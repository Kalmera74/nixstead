from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from typing import Mapping, Sequence


class SetupError(RuntimeError):
    pass


def exists(command: str) -> bool:
    return shutil.which(command) is not None


def require(command: str) -> None:
    if not exists(command):
        raise SetupError(f"required command not found: {command}")


def run(
    args: Sequence[str],
    *,
    check: bool = True,
    capture: bool = False,
    input_text: str | None = None,
    env: Mapping[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(args),
        check=check,
        text=True,
        input=input_text,
        capture_output=capture,
        env=dict(env) if env is not None else None,
    )


def output(args: Sequence[str], *, env: Mapping[str, str] | None = None) -> str:
    return run(args, capture=True, env=env).stdout.strip()


def prepare_runtime(repo_root: Path, require_secret_tools: bool = True) -> None:
    required = ["age-keygen", "python3", "sops", "ssh-to-age"]
    missing_secret_tools = any(not exists(command) for command in required)
    if missing_secret_tools and not require_secret_tools:
        return
    if not missing_secret_tools:
        return
    require("nix")
    print("==> Preparing the pinned setup and secret-management runtime...")
    try:
        runtime = output(
            [
                "nix",
                "build",
                "--extra-experimental-features",
                "nix-command flakes",
                "--no-link",
                "--print-out-paths",
                f"path:{repo_root}#setup-runtime",
            ]
        )
    except subprocess.CalledProcessError as error:
        if missing_secret_tools and require_secret_tools:
            raise SetupError("required SOPS tools could not be prepared") from error
        return
    os.environ["PATH"] = f"{runtime}/bin:{os.environ.get('PATH', '')}"
    for command in required:
        require(command)


def sudo_prefix() -> list[str]:
    return [] if os.geteuid() == 0 else ["sudo"]


def run_as_root(
    args: Sequence[str], **kwargs: object
) -> subprocess.CompletedProcess[str]:
    return run([*sudo_prefix(), *args], **kwargs)  # type: ignore[arg-type]


def ensure_owned_directory(path: Path, uid: int) -> None:
    if os.geteuid() == uid:
        path.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(path, 0o700)
    else:
        run_as_root(["install", "-d", "-m", "0700", "-o", str(uid), str(path)])
