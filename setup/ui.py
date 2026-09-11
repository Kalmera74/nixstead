from __future__ import annotations

import os
import shutil
from typing import Callable, Sequence


class Cancelled(Exception):
    pass


class SectionBack(Exception):
    pass


class UI:
    def __init__(self) -> None:
        self.tty = (
            os.isatty(0) and os.isatty(1) and os.environ.get("TERM", "dumb") != "dumb"
        )
        self.textual_available = self.tty and self._has_textual()
        self.context = ""
        self.input_error = ""
        self.section_title = ""
        self.section_subtitle = ""
        self.section_previous_allowed = False

    @staticmethod
    def _has_textual() -> bool:
        try:
            import textual  # noqa: F401
        except ImportError:
            return False
        return True

    @property
    def textual(self) -> bool:
        return self.tty and self.textual_available

    def _run_textual(self, application: object) -> object:
        try:
            from . import textual_ui
        except ImportError:
            self.textual_available = False
            raise RuntimeError("Textual is unavailable in the setup environment")
        return textual_ui.run(application)

    @staticmethod
    def _unwrap_textual_navigation(result: object) -> object:
        if result is None:
            raise Cancelled
        if isinstance(result, tuple) and len(result) == 2 and result[0] == "navigation":
            if result[1] == "previous":
                raise SectionBack
            raise Cancelled
        return result

    def clear(self) -> None:
        if self.textual:
            return
        if self.tty:
            print("\033[2J\033[H", end="")

    def header(self, title: str, subtitle: str = "") -> None:
        if self.textual:
            self.section_title = title
            self.section_subtitle = subtitle
            return
        self.clear()
        print("\n┌──────────────────────────────────────────────────────────────┐")
        if self.context:
            print(f"  {self.context}")
        print(f"  {title}")
        if subtitle:
            print(f"  {subtitle}")
        if self.input_error:
            print(f"  ! {self.input_error}", file=os.sys.stderr)
            self.input_error = ""
        print("└──────────────────────────────────────────────────────────────┘\n")

    def error(self, message: str) -> None:
        if self.tty:
            self.input_error = message
        else:
            print(f"Error: {message}", file=os.sys.stderr)

    def pager(self, text: str) -> None:
        if self.textual:
            from . import textual_ui

            result = self._run_textual(
                textual_ui.ReviewApp(self.context, "Review", text)
            )
            if result is None:
                raise Cancelled
            return
        print(text)

    def ask(self, label: str, default: str = "", help_text: str = "") -> str:
        if self.textual:
            error = self.input_error
            self.input_error = ""
            from . import textual_ui

            result = self._run_textual(
                textual_ui.InputApp(self.context, label, default, help_text, error)
            )
            if result is None:
                raise Cancelled
            return str(result)
        if self.input_error:
            print(f"Error: {self.input_error}", file=os.sys.stderr)
            self.input_error = ""
        if help_text:
            print(help_text)
        suffix = f" [{default}]" if default else ""
        try:
            value = input(f"{label}{suffix}: ").strip()
        except EOFError as error:
            raise Cancelled from error
        return value or default

    def form(
        self, title: str, fields: Sequence[tuple[str, str, str, str]]
    ) -> dict[str, str]:
        """Collect related text values on one page in the Textual interface."""

        if self.textual:
            error = self.input_error
            self.input_error = ""
            from . import textual_ui

            result = self._run_textual(
                textual_ui.FormApp(
                    self.context,
                    title,
                    fields,
                    error,
                    previous=self.section_previous_allowed,
                )
            )
            result = self._unwrap_textual_navigation(result)
            return dict(result.values)
        return {
            key: self.ask(label, default, help_text)
            for key, label, default, help_text in fields
        }

    def required(self, label: str, default: str = "", help_text: str = "") -> str:
        while True:
            value = self.ask(label, default, help_text)
            if value:
                return value
            self.error("A value is required.")

    def validated(
        self,
        label: str,
        default: str,
        validator: Callable[[str], bool],
        help_text: str = "",
    ) -> str:
        while True:
            value = self.ask(label, default, help_text)
            if validator(value):
                return value
            self.error(f"Invalid value: {value or '<empty>'}")

    def yes_no(self, label: str, default: bool = False) -> bool:
        if self.textual:
            error = self.input_error
            self.input_error = ""
            from . import textual_ui

            result = self._run_textual(
                textual_ui.OptionApp(
                    self.context,
                    label,
                    ["Yes", "No"],
                    0 if default else 1,
                    error,
                    previous=self.section_previous_allowed,
                ),
            )
            result = self._unwrap_textual_navigation(result)
            return int(result) == 0
        suffix = "Y/n" if default else "y/N"
        while True:
            try:
                value = input(f"{label} [{suffix}]: ").strip().lower()
            except EOFError as error:
                raise Cancelled from error
            if not value:
                return default
            if value in {"y", "yes"}:
                return True
            if value in {"n", "no"}:
                return False
            self.error("Please answer yes or no.")

    def select(self, label: str, choices: Sequence[str], default: int = 0) -> int:
        if self.textual:
            rendered = []
            for choice in choices:
                if "|" in choice:
                    name, description = choice.split("|", 1)
                    rendered.append(f"{name.strip()} — {description.strip()}")
                else:
                    rendered.append(choice)
            error = self.input_error
            self.input_error = ""
            from . import textual_ui

            result = self._run_textual(
                textual_ui.OptionApp(
                    self.context,
                    label,
                    rendered,
                    default,
                    error,
                    previous=self.section_previous_allowed,
                )
            )
            result = self._unwrap_textual_navigation(result)
            return int(result)
        return self._select_numbered(label, choices, default)

    def _select_numbered(
        self, label: str, choices: Sequence[str], default: int = 0
    ) -> int:
        if self.tty:
            index = default
            while True:
                self.header(label, "Use ↑/↓ to move, Enter to select, or q to cancel.")
                for position, choice in enumerate(choices):
                    if "|" in choice:
                        name, description = choice.split("|", 1)
                    else:
                        name, description = choice, ""
                    marker = "›" if position == index else " "
                    suffix = f"  {description}" if description else ""
                    print(f"  {marker} {name}{suffix}")
                pressed = self._read_key()
                if pressed in ("\x1b[A", "k"):
                    index = (index - 1) % len(choices)
                elif pressed in ("\x1b[B", "j"):
                    index = (index + 1) % len(choices)
                elif pressed in ("", "\n", "\r"):
                    self.clear()
                    return index
                elif pressed.lower() == "q":
                    raise Cancelled
        print(f"\n{label}")
        for index, choice in enumerate(choices, start=1):
            print(f"  {index}. {choice}")
        while True:
            answer = self.ask("Choice", str(default + 1))
            if answer.isdigit() and 1 <= int(answer) <= len(choices):
                return int(answer) - 1
            self.error("Choose one of the listed numbers.")

    def checklist(
        self, label: str, items: Sequence[tuple[str, str]], selected: dict[str, bool]
    ) -> None:
        if self.textual:
            error = self.input_error
            self.input_error = ""
            from . import textual_ui

            result = self._run_textual(
                textual_ui.ChecklistApp(
                    self.context,
                    label,
                    items,
                    selected,
                    error,
                    previous=self.section_previous_allowed,
                )
            )
            result = self._unwrap_textual_navigation(result)
            chosen = set(result)
            for key, _ in items:
                selected[key] = key in chosen
            return
        self.header(
            label,
            "Use ↑/↓, Space, and Enter when an interactive terminal is available.",
        )
        if self.tty:
            index = 0
            while True:
                self.header(
                    label,
                    "Use ↑/↓ to move, Space to toggle, Enter to continue, or q to cancel.",
                )
                for position, (key, text) in enumerate(items):
                    marker = "[✓]" if selected.get(key, False) else "[ ]"
                    prefix = "› " if position == index else "  "
                    print(f"{prefix}{marker} {text}")
                pressed = self._read_key()
                if pressed in ("\x1b[A", "k"):
                    index = (index - 1) % len(items)
                elif pressed in ("\x1b[B", "j"):
                    index = (index + 1) % len(items)
                elif pressed == " ":
                    key, _ = items[index]
                    selected[key] = not selected.get(key, False)
                elif pressed in ("", "\n", "\r"):
                    self.clear()
                    return
                elif pressed.lower() == "q":
                    raise Cancelled

        for key, text in items:
            selected[key] = self.yes_no(text, selected.get(key, False))

    def _read_key(self) -> str:
        import sys
        import termios
        import tty

        fd = sys.stdin.fileno()
        old = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            value = os.read(fd, 1).decode(errors="ignore")
            if value == "\x1b":
                value += os.read(fd, 2).decode(errors="ignore")
            return value
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)

    def section_navigation(self, name: str, allow_back: bool = True) -> str:
        if self.textual:
            from . import textual_ui

            result = self._run_textual(
                textual_ui.NavigationApp(
                    self.context,
                    f"{name} complete",
                    previous=allow_back,
                    show_cancel=False,
                )
            )
            if result == "previous":
                return "back"
            if result == "next":
                return "next"
            raise Cancelled
        choices = ["Next|Save these choices and open the next section"]
        if allow_back:
            choices.insert(
                1, "Previous|Save these choices and return to the previous section"
            )
        selected = self.select(f"{name} complete", choices, 0)
        if selected == 0:
            return "next"
        if allow_back and selected == 1:
            return "back"
        raise Cancelled

    def review_navigation(self) -> str:
        if self.textual:
            from . import textual_ui

            result = self._run_textual(
                textual_ui.NavigationApp(
                    self.context,
                    "Ready to apply this configuration?",
                    previous=True,
                    next_label="Apply",
                    show_cancel=False,
                ),
            )
            if result == "previous":
                return "back"
            if result == "next":
                return "apply"
            raise Cancelled
        selected = self.select(
            "Ready to apply this configuration?",
            [
                "Apply configuration|Generate the host and continue",
                "Previous|Return to primary-user privileges",
            ],
            0,
        )
        return ["apply", "back"][selected]

    def show_device(self, device: str) -> None:
        if shutil.which("lsblk") and os.path.exists(device):
            os.system(f"lsblk -dn -o NAME,SIZE,TYPE,MODEL -- {shlex_quote(device)}")
        elif not os.path.exists(device):
            print(f"Warning: device path does not currently exist: {device}")


def shlex_quote(value: str) -> str:
    import shlex

    return shlex.quote(value)
