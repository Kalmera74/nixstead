"""Textual widgets used by the interactive setup wizard.

The wizard itself remains synchronous and typed-state driven. Each prompt is a
small Textual application that returns a value when the user submits it. This
keeps feature flows straightforward while giving every interactive control the
same keyboard, resize, and terminal handling.
"""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from typing import Any

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.widgets import (
    Button,
    Footer,
    Header,
    Input,
    Label,
    OptionList,
    SelectionList,
    Static,
)


CSS = """
Screen {
    align: center middle;
}

#body {
    width: 94%;
    height: 92%;
    padding: 1 2;
}

#context {
    color: $text-muted;
    height: auto;
}

#title {
    color: $accent;
    text-style: bold;
    height: auto;
    margin-bottom: 1;
}

#help {
    color: $text-muted;
    height: auto;
    margin-bottom: 1;
}

#error {
    color: $error;
    height: auto;
    margin-bottom: 1;
}

Input {
    width: 100%;
}

OptionList, SelectionList, #review {
    width: 100%;
    height: 1fr;
    border: round $accent;
    padding: 1;
}

#form {
    width: 100%;
    height: 1fr;
    padding: 0 1;
}

.field-label {
    color: $accent;
    height: auto;
    margin-top: 1;
}

.field-help {
    color: $text-muted;
    height: auto;
}

#actions {
    width: 100%;
    height: auto;
    align: center middle;
    margin-top: 1;
}

#actions Button {
    margin: 0 1;
}

"""


def run(application: App[object]) -> object:
    """Run one prompt app and return the value supplied to ``App.exit``."""

    return application.run()


class _BaseApp(App[object]):
    CSS = CSS
    TITLE = "Nixstead setup"
    ENABLE_COMMAND_PALETTE = False
    BINDINGS = [Binding("escape", "cancel", "Cancel", show=True)]

    def __init__(
        self, context: str, title: str, help_text: str, error: str = ""
    ) -> None:
        super().__init__()
        self.context = context
        self.prompt_title = title
        self.help_text = help_text
        self.error_text = error

    def compose(self) -> ComposeResult:
        yield Header(show_clock=False)
        with Vertical(id="body"):
            if self.context:
                yield Label(self.context, id="context")
            yield Label(self.prompt_title, id="title")
            if self.help_text:
                yield Label(self.help_text, id="help")
            if self.error_text:
                yield Label(f"Error: {self.error_text}", id="error")
            yield from self.body_widgets()
        yield Footer()

    def body_widgets(self) -> Iterable[Any]:
        return ()

    def action_cancel(self) -> None:
        self.exit(None)


class InputApp(_BaseApp):
    def __init__(
        self, context: str, title: str, default: str, help_text: str, error: str = ""
    ) -> None:
        super().__init__(context, title, help_text, error)
        self.default = default

    def body_widgets(self) -> Iterable[Any]:
        yield Input(value=self.default, placeholder=self.default, id="input")

    def on_mount(self) -> None:
        self.query_one("#input", Input).focus()

    def on_input_submitted(self, event: Input.Submitted) -> None:
        self.exit(event.value.strip() or self.default)


@dataclass(frozen=True)
class FormResult:
    values: dict[str, str]


class FormApp(_BaseApp):
    """A single-page form whose inputs are traversed with Tab or Shift+Tab."""

    BINDINGS = [
        Binding("left", "previous", "Previous", show=False),
        Binding("right", "next", "Next", show=False),
        Binding("escape", "cancel", "Cancel", show=True),
    ]

    def __init__(
        self,
        context: str,
        title: str,
        fields: Sequence[tuple[str, str, str, str]],
        error: str = "",
        *,
        previous: bool = False,
    ) -> None:
        super().__init__(
            context,
            title,
            "Tab / Shift+Tab move between fields. Enter continues. Escape cancels.",
            error,
        )
        self.fields = list(fields)
        self.allow_previous = previous

    def body_widgets(self) -> Iterable[Any]:
        with VerticalScroll(id="form"):
            for key, label, default, help_text in self.fields:
                yield Label(label, classes="field-label")
                if help_text:
                    yield Label(help_text, classes="field-help")
                yield Input(value=default, placeholder=default, id=f"field-{key}")
        with Horizontal(id="actions"):
            if self.allow_previous:
                yield Button("Previous", id="previous")
            yield Button("Continue", id="continue", variant="primary")

    def on_mount(self) -> None:
        inputs = self.query(Input)
        if inputs:
            inputs[0].focus()

    def _values(self) -> dict[str, str]:
        inputs = list(self.query(Input))
        return {
            key: input_widget.value.strip()
            for (key, *_), input_widget in zip(self.fields, inputs)
        }

    def _continue(self) -> None:
        self.exit(FormResult(self._values()))

    def on_input_submitted(self, event: Input.Submitted) -> None:
        inputs = list(self.query(Input))
        try:
            index = inputs.index(event.input)
        except ValueError:
            self._continue()
            return
        if index + 1 < len(inputs):
            inputs[index + 1].focus()
        else:
            self._continue()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "continue":
            self._continue()
        elif event.button.id == "previous" and self.allow_previous:
            self.exit(("navigation", "previous"))

    def action_previous(self) -> None:
        if self.allow_previous:
            self.exit(("navigation", "previous"))

    def action_next(self) -> None:
        self._continue()


class OptionApp(_BaseApp):
    BINDINGS = [
        Binding("left", "previous", "Previous", show=False),
        Binding("right", "next", "Next", show=False),
        Binding("enter", "next", "Continue", show=False),
        Binding("escape", "cancel", "Cancel", show=True),
    ]

    def __init__(
        self,
        context: str,
        title: str,
        choices: Sequence[str],
        default: int,
        error: str = "",
        *,
        previous: bool = False,
    ) -> None:
        super().__init__(
            context, title, "Use ↑/↓ and Enter to choose. Escape cancels.", error
        )
        self.choices = list(choices)
        self.default = max(0, min(default, len(self.choices) - 1))
        self.allow_previous = previous

    def body_widgets(self) -> Iterable[Any]:
        yield OptionList(*self.choices, id="choices", markup=False)
        with Horizontal(id="actions"):
            if self.allow_previous:
                yield Button("Previous", id="previous")
            yield Button("Continue", id="next", variant="primary")

    def on_mount(self) -> None:
        choices = self.query_one("#choices", OptionList)
        choices.highlighted = self.default
        choices.focus()

    def _selected_index(self) -> int:
        choices = self.query_one("#choices", OptionList)
        return choices.highlighted

    def _next(self) -> None:
        self.exit(self._selected_index())

    def on_option_list_option_selected(self, event: OptionList.OptionSelected) -> None:
        self.exit(event.option_index)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "previous" and self.allow_previous:
            self.exit(("navigation", "previous"))
        elif event.button.id == "next":
            self._next()

    def action_previous(self) -> None:
        if self.allow_previous:
            self.exit(("navigation", "previous"))

    def action_next(self) -> None:
        self._next()


class FinishableSelectionList(SelectionList[str]):
    """SelectionList where Enter submits instead of selecting one item."""

    BINDINGS = [
        Binding("down", "cursor_down", "Down", show=False),
        Binding("end", "last", "Last", show=False),
        Binding("home", "first", "First", show=False),
        Binding("pagedown", "page_down", "Page Down", show=False),
        Binding("pageup", "page_up", "Page Up", show=False),
        Binding("space", "select", "Toggle", show=False),
        Binding("up", "cursor_up", "Up", show=False),
        Binding("enter", "submit_selection", "Continue", show=False),
    ]

    def action_submit_selection(self) -> None:
        self.app.exit(list(self.selected))


class ChecklistApp(_BaseApp):
    def __init__(
        self,
        context: str,
        title: str,
        items: Sequence[tuple[str, str]],
        selected: dict[str, bool],
        error: str = "",
        *,
        previous: bool = False,
    ) -> None:
        super().__init__(
            context,
            title,
            "Use ↑/↓ to move, Space to toggle, and Enter to continue. Escape cancels.",
            error,
        )
        self.items = list(items)
        self.initial = selected.copy()
        self.allow_previous = previous

    def body_widgets(self) -> Iterable[Any]:
        values = [
            (label, key, self.initial.get(key, False)) for key, label in self.items
        ]
        yield FinishableSelectionList(*values, id="choices")
        with Horizontal(id="actions"):
            if self.allow_previous:
                yield Button("Previous", id="previous")
            yield Button("Continue", id="next", variant="primary")

    def on_mount(self) -> None:
        self.query_one("#choices", FinishableSelectionList).focus()

    def _selected(self) -> list[str]:
        return list(self.query_one("#choices", FinishableSelectionList).selected)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "next":
            self.exit(self._selected())
        elif event.button.id == "previous" and self.allow_previous:
            self.exit(("navigation", "previous"))

    def action_previous(self) -> None:
        if self.allow_previous:
            self.exit(("navigation", "previous"))

    def action_next(self) -> None:
        self.exit(self._selected())


class ReviewApp(_BaseApp):
    BINDINGS = [
        Binding("escape", "cancel", "Cancel", show=True),
        Binding("enter", "continue", "Continue", show=True),
    ]

    def __init__(self, context: str, title: str, text: str) -> None:
        super().__init__(context, title, "Press Enter to continue or Escape to cancel.")
        self.review_text = text

    def body_widgets(self) -> Iterable[Any]:
        yield Static(self.review_text, id="review")

    def action_continue(self) -> None:
        self.exit(True)


class NavigationApp(_BaseApp):
    """Bottom-button navigation for completed wizard sections."""

    BINDINGS = [
        Binding("escape", "cancel", "Cancel", show=True),
        Binding("left", "previous", "Previous", show=False),
        Binding("right", "next", "Next", show=False),
        Binding("enter", "next", "Next", show=False),
    ]

    def __init__(
        self,
        context: str,
        title: str,
        *,
        previous: bool,
        next_label: str = "Next",
        show_cancel: bool = True,
    ) -> None:
        super().__init__(context, title, "Choose what to do next.")
        self.has_previous = previous
        self.next_label = next_label
        self.show_cancel = show_cancel

    def body_widgets(self) -> Iterable[Any]:
        with Horizontal(id="actions"):
            if self.has_previous:
                yield Button("Previous", id="previous")
            yield Button(self.next_label, id="next", variant="primary")
            if self.show_cancel:
                yield Button("Cancel", id="cancel")

    def on_mount(self) -> None:
        self.query_one("#next", Button).focus()

    def action_previous(self) -> None:
        if self.has_previous:
            self.exit("previous")

    def action_next(self) -> None:
        self.exit("next")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        self.exit(event.button.id)
