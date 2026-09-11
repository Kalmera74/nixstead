from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from .commands import (
    SetupError,
    ensure_owned_directory,
    prepare_runtime,
    require,
    run,
    run_as_root,
)
from .model import HostConfig
from .registry import Registry
from .render import render_consumer_flake, render_host
from .ui import Cancelled, UI
from .validation import host_name
from .wizard import run_wizard


DEFAULT_NIXSTEAD_URL = "github:Kalmera74/nixstead"


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        prog="nixstead setup wizard",
        description="Create and switch to a NixOS host configuration.",
    )
    result.add_argument("target", nargs="?", help="existing flake target to switch")
    mode = result.add_mutually_exclusive_group()
    mode.add_argument(
        "--output",
        type=Path,
        help="create a standalone consumer flake in a new directory",
    )
    mode.add_argument(
        "--repo-local",
        action="store_true",
        help="create hosts/<name> inside a Nixstead source checkout",
    )
    result.add_argument(
        "--nixstead-url",
        default=DEFAULT_NIXSTEAD_URL,
        help="Nixstead flake URL written by --output",
    )
    result.add_argument(
        "-i",
        "--interactive",
        "--new-host",
        action="store_true",
        dest="new_host",
        help="create a new host interactively",
    )
    result.add_argument(
        "--hardware-config", help="hardware configuration source for a new host"
    )
    result.add_argument(
        "--state-version",
        help="original system.stateVersion (YY.MM); required when automatic detection is unavailable",
    )
    result.add_argument(
        "--configuration",
        help="installed configuration file to inspect instead of /etc/nixos/configuration.nix",
    )
    result.add_argument(
        "--generate-only",
        action="store_true",
        help="create and validate without switching",
    )
    result.add_argument(
        "--skip-healthcheck",
        action="store_true",
        help="skip the pre-switch healthcheck",
    )
    return result


def read_system_state_version(
    explicit: str | None = None,
    configuration: Path = Path("/etc/nixos/configuration.nix"),
) -> str:
    if explicit is not None:
        if not re.fullmatch(r"[0-9]{2}\.(0[1-9]|1[0-2])", explicit):
            raise SetupError(
                "--state-version must be the original NixOS state version, e.g. 24.11"
            )
        return explicit
    path = configuration
    fallback = "Pass --state-version with the original system.stateVersion from your existing configuration; do not use the current release version."
    if not path.is_file():
        raise SetupError(
            f"cannot read the installed NixOS configuration: {path}. {fallback}"
        )
    # This is a convenience detector, not a Nix evaluator. Ambiguous or imported
    # assignments need an explicit value; never silently pick a commented value.
    content = re.sub(r"/\*.*?\*/|#[^\n]*", "", path.read_text(), flags=re.DOTALL)
    matches = re.findall(
        r'system\.stateVersion\s*=\s*"([0-9]{2}\.(?:0[1-9]|1[0-2]))"', content
    )
    if len(matches) != 1:
        raise SetupError(
            f"cannot detect one literal system.stateVersion in {path}. {fallback}"
        )
    return matches[0]


def copy_hardware(host: HostConfig, destination: Path) -> None:
    source = (
        Path(host.hardware_source)
        if host.hardware_source
        else Path("/etc/nixos/hardware-configuration.nix")
    )
    if source.is_file():
        shutil.copyfile(source, destination)
        print(f"==> Copied hardware configuration from {source}")
        return
    require("nixos-generate-config")
    print(
        "==> /etc/nixos/hardware-configuration.nix was not found; generating hardware configuration"
    )
    result = run_as_root(
        ["nixos-generate-config", "--show-hardware-config"], capture=True
    )
    destination.write_text(result.stdout)


def validate_hardware(path: Path) -> None:
    content = path.read_text()
    match = re.search(r'nixpkgs\.hostPlatform[^\"]*"([^\"]+)"', content)
    if not match or match.group(1) not in {"x86_64-linux", "aarch64-linux"}:
        raise SetupError(
            f"hardware configuration does not declare a supported nixpkgs.hostPlatform: {path}"
        )
    print(f"==> Hardware platform: {match.group(1)}")


def write_host(host: HostConfig, registry: Registry) -> None:
    host.host_directory.parent.mkdir(parents=True, exist_ok=True)
    if host.host_directory.exists():
        raise SetupError(f"host already exists: {host.host_directory}")
    staging = Path(
        tempfile.mkdtemp(prefix=f".{host.host_name}.setup.", dir=str(host.repo_root))
    )
    try:
        (staging / "default.nix").write_text(render_host(host, registry))
        (staging / "container-images.nix").write_text("{}\n")
        copy_hardware(host, staging / "hardware-configuration.nix")
        validate_hardware(staging / "hardware-configuration.nix")
        staging.rename(host.host_directory)
        host.new_host_directory = host.host_directory
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    print(f"==> Created host: {host.host_directory}")
    print(
        f"==> Hardware configuration: {host.host_directory / 'hardware-configuration.nix'}"
    )


def write_consumer_flake(
    host: HostConfig, registry: Registry, nixstead_url: str
) -> None:
    output_directory = host.repo_root
    if output_directory.exists():
        raise SetupError(f"standalone output already exists: {output_directory}")
    output_directory.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(
        tempfile.mkdtemp(
            prefix=f".{output_directory.name}.setup.",
            dir=str(output_directory.parent),
        )
    )
    try:
        (staging / "configuration.nix").write_text(
            render_host(host, registry, standalone=True)
        )
        (staging / "flake.nix").write_text(render_consumer_flake(host, nixstead_url))
        (staging / "container-images.nix").write_text("{}\n")
        copy_hardware(host, staging / "hardware-configuration.nix")
        validate_hardware(staging / "hardware-configuration.nix")
        run(
            [
                "nix",
                "--extra-experimental-features",
                "nix-command flakes",
                "flake",
                "lock",
                f"path:{staging}",
            ]
        )
        staging.rename(output_directory)
        host.host_directory = output_directory
        host.new_host_directory = output_directory
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    print(f"==> Created standalone consumer flake: {output_directory}")
    print(f"==> Nixstead input: {nixstead_url} (pinned in flake.lock)")
    print(
        f"==> Hardware configuration: {output_directory / 'hardware-configuration.nix'}"
    )


def preserve_recovery(host: HostConfig) -> None:
    if not host.new_host_directory.is_dir():
        return
    recovery_parent = host.repo_root.parent if host.standalone else host.repo_root
    recovery = recovery_parent / f".{host.host_name}.setup-recovery.{os.getpid()}"
    while recovery.exists():
        recovery = Path(f"{recovery}x")
    host.new_host_directory.rename(recovery)
    print(
        f"==> Preserved the generated host after setup stopped: {recovery}",
        file=sys.stderr,
    )
    original = "standalone output path" if host.standalone else "hosts/<host> path"
    print(
        f"==> The original {original} is free, so setup can be retried.",
        file=sys.stderr,
    )


def framework_script(framework_root: Path, environment_name: str, name: str) -> Path:
    configured = os.environ.get(environment_name)
    return Path(configured) if configured else framework_root / "scripts" / name


def selected_secrets(host: HostConfig, registry: Registry) -> list[str]:
    values: set[str] = set()
    for service in registry.services:
        if host.service_flags.get(service.variable, False):
            values.update(service.secrets)
    return sorted(values)


def offer_secrets(host: HostConfig, registry: Registry, framework_root: Path) -> None:
    secrets = selected_secrets(host, registry)
    if not secrets:
        return
    ensure_owned_directory(host.user_files_directory, host.user_uid)
    sops_helper = framework_script(
        framework_root, "NIXSTEAD_SOPS_HELPER", "configure-sops-host.sh"
    )
    credential_helper = framework_script(
        framework_root,
        "NIXSTEAD_CREDENTIAL_HELPER",
        "generate-credential-files.sh",
    )
    env = dict(
        os.environ,
        NIXSTEAD_HOST=host.host_name,
        NIXSTEAD_REPOSITORY_ROOT=str(host.repo_root),
        NIXSTEAD_SECRETS_DIR=str(host.secrets_dir),
    )
    run(
        [
            str(sops_helper),
            "--age-key-file",
            str(host.user_sops_age_key_file),
            host.host_name,
        ],
        env=env,
    )
    encrypted = host.secrets_dir / f"{host.host_name}.yaml"
    missing = []
    for name in secrets:
        try:
            run(
                ["sops", "decrypt", "--extract", f'["{name}"]', str(encrypted)],
                capture=True,
            )
        except subprocess.CalledProcessError:
            missing.append(name)
    if not missing:
        return
    print(
        f"Missing encrypted secret branches for enabled services: {' '.join(missing)}"
    )
    ui = UI()
    if not ui.yes_no(
        "Generate bootstrap credentials and integration placeholders now", True
    ):
        print("==> Secrets were not generated; the healthcheck may refuse the rebuild.")
        return
    post_install_domains = {"homepage", "swaparr"}
    for name in (item for item in missing if item not in post_install_domains):
        run([str(credential_helper), name], env=env)
    for name in (item for item in missing if item in post_install_domains):
        run([str(credential_helper), "--bootstrap", name], env=env)
    if "homepage" in secrets:
        print(
            "==> Managed media credentials will be enrolled in SOPS and delivered automatically during activation."
        )
        print(
            f"==> After activation, run: nixstead --host {host.host_name} credentials configure homepage"
        )
        print(
            "==> The Homepage helper is only needed for unmanaged application widgets."
        )


def healthcheck(host: HostConfig, skip: bool, framework_root: Path) -> str:
    if skip:
        return "skipped"
    script = framework_script(
        framework_root, "NIXSTEAD_HEALTHCHECK_SCRIPT", "healthcheck.sh"
    )
    print(f"==> Running pre-switch healthcheck for {host.target_name}")
    env = dict(
        os.environ,
        NIXSTEAD_REPOSITORY_ROOT=str(host.repo_root),
        NIXSTEAD_SECRETS_DIR=str(host.secrets_dir),
    )
    result = run(
        [str(script), host.target_name, str(host.secrets_dir)], check=False, env=env
    )
    if result.returncode == 0:
        return "passed"
    return "failed"


def switch(host: HostConfig, secrets_override: bool) -> None:
    args = [
        "nixos-rebuild",
        "switch",
        "--option",
        "experimental-features",
        "nix-command flakes",
    ]
    if secrets_override:
        args.append("--impure")
    args += ["--flake", f"path:{host.repo_root}#{host.target_name}"]
    env = dict(os.environ)
    if secrets_override:
        env["NIXSTEAD_SECRETS_DIR"] = str(host.secrets_dir)
    run_as_root(args, env=env)


def set_new_user_password(host: HostConfig, ui: UI) -> None:
    if host.user_existed_before:
        return
    if host.ssh.key_mode == "none":
        print(
            f"==> Password-only SSH was selected; set a login password for {host.user_name}."
        )
        run_as_root(["passwd", host.user_name])
    elif ui.yes_no(f"Set a login password for {host.user_name} now", True):
        run_as_root(["passwd", host.user_name])
    else:
        print(f"Remember to run: sudo passwd {host.user_name}")


def run_application(arguments: list[str]) -> int:
    args = parser().parse_args(arguments)
    framework_root = find_framework_root()
    if args.output and args.target:
        raise SetupError("--output creates a new host and cannot be used with a target")
    standalone = args.output is not None
    repo_root = args.output.expanduser().resolve() if args.output else find_repo_root()
    configured_secrets_dir = os.environ.get("NIXSTEAD_SECRETS_DIR") or os.environ.get(
        "NIXCONFIG_SECRETS_DIR"
    )
    secrets_override = bool(configured_secrets_dir)
    secrets_dir = Path(configured_secrets_dir or repo_root / "secrets")
    create_host = args.new_host or not args.target
    if create_host and not standalone and not is_framework_root(repo_root):
        raise SetupError(
            "creating a host outside a Nixstead checkout requires --output <directory>"
        )
    if args.repo_local and not is_framework_root(repo_root):
        raise SetupError("--repo-local requires a Nixstead source checkout")
    if standalone and repo_root.exists():
        raise SetupError(f"standalone output already exists: {repo_root}")
    if args.target and args.new_host:
        raise SetupError("choose either a new interactive host or an existing target")
    if args.target and args.generate_only:
        raise SetupError(
            "--generate-only creates a new host and cannot be used with an existing target"
        )
    if args.hardware_config and not create_host:
        raise SetupError("--hardware-config is only valid when creating a new host")
    if (args.state_version or args.configuration) and not create_host:
        raise SetupError(
            "--state-version and --configuration are only valid when creating a new host"
        )
    state_version = ""
    if create_host:
        state_version = read_system_state_version(
            args.state_version,
            Path(args.configuration or "/etc/nixos/configuration.nix"),
        )
        print(f"==> Preserving system.stateVersion = {state_version}")
    if args.hardware_config and not Path(args.hardware_config).is_file():
        raise SetupError(f"hardware configuration not found: {args.hardware_config}")
    if os.geteuid() == 0 and os.environ.get("SUDO_USER") and create_host:
        raise SetupError("run setup as your normal user, not through sudo")
    require("nix")
    healthcheck_script = framework_script(
        framework_root, "NIXSTEAD_HEALTHCHECK_SCRIPT", "healthcheck.sh"
    )
    credential_helper = framework_script(
        framework_root,
        "NIXSTEAD_CREDENTIAL_HELPER",
        "generate-credential-files.sh",
    )
    sops_helper = framework_script(
        framework_root, "NIXSTEAD_SOPS_HELPER", "configure-sops-host.sh"
    )
    if not args.skip_healthcheck and not os.access(healthcheck_script, os.X_OK):
        raise SetupError(
            f"healthcheck script is missing or not executable: {healthcheck_script}"
        )
    if create_host and not os.access(credential_helper, os.X_OK):
        raise SetupError(
            f"credential helper is missing or not executable: {credential_helper}"
        )
    if create_host and not os.access(sops_helper, os.X_OK):
        raise SetupError(f"SOPS helper is missing or not executable: {sops_helper}")
    prepare_runtime(framework_root, create_host or not args.skip_healthcheck)
    registry = Registry(framework_root)
    registry.load()
    ui = UI()
    if create_host:
        host = run_wizard(
            repo_root,
            secrets_dir,
            registry,
            ui,
            args.hardware_config or "",
            generate_only=args.generate_only,
            skip_healthcheck=args.skip_healthcheck,
            standalone=standalone,
        )
        try:
            host.system_state_version = state_version
            host.target_name = host.host_name
            if standalone:
                write_consumer_flake(host, registry, args.nixstead_url)
            else:
                write_host(host, registry)
            secrets_dir.mkdir(parents=True, exist_ok=True)
            offer_secrets(host, registry, framework_root)
        except Exception:
            preserve_recovery(host)
            raise
    else:
        if not host_name(args.target or ""):
            raise SetupError(f"invalid flake target: {args.target}")
        host = HostConfig(
            repo_root=repo_root,
            secrets_dir=secrets_dir,
            host_name=args.target,
            target_name=args.target,
        )
    result = healthcheck(host, args.skip_healthcheck, framework_root)
    if result == "failed":
        try:
            continue_anyway = create_host and ui.yes_no(
                "Healthcheck failed. Continue anyway", False
            )
        except Cancelled:
            if create_host:
                preserve_recovery(host)
            raise
        if continue_anyway:
            print("==> Continuing despite healthcheck failure.")
        else:
            if create_host:
                preserve_recovery(host)
            raise SetupError("aborting before rebuild")
    print(f"==> Rebuild target: path:{repo_root}#{host.target_name}")
    if args.generate_only:
        print(
            f"==> Host generation and validation completed; --generate-only skipped the switch ({result})."
        )
        return 0
    try:
        switch(host, secrets_override)
    except Exception:
        if create_host:
            preserve_recovery(host)
        raise
    if create_host:
        set_new_user_password(host, ui)
        if host.service_flags.get("ENABLE_HOMEPAGE", False):
            print(
                "==> After completing each application's initial setup, populate dashboard integrations with:"
            )
            print(
                f"    nixstead --host {host.host_name} credentials configure homepage"
            )
            print(
                "    Managed media credentials are enrolled and delivered automatically."
            )
    return 0


def find_repo_root() -> Path:
    configured = os.environ.get("NIXSTEAD_REPO_ROOT") or os.environ.get(
        "NIXSTEAD_REPOSITORY_ROOT"
    )
    if configured:
        return Path(configured).resolve()
    for candidate in [Path.cwd(), *Path.cwd().parents]:
        if (candidate / "flake.nix").is_file():
            return candidate
    raise SetupError(
        "could not find a configuration flake; run from one or pass --output <directory>"
    )


def is_framework_root(path: Path) -> bool:
    return (
        (path / "flake.nix").is_file()
        and (path / "modules/services/registry.nix").is_file()
        and (path / "setup").is_dir()
    )


def find_framework_root() -> Path:
    configured = os.environ.get("NIXSTEAD_FRAMEWORK_ROOT")
    if configured:
        root = Path(configured).resolve()
        if is_framework_root(root):
            return root
        raise SetupError(f"NIXSTEAD_FRAMEWORK_ROOT is not Nixstead source: {root}")
    candidates = [
        Path.cwd(),
        *Path.cwd().parents,
        Path(__file__).resolve().parent.parent,
    ]
    for candidate in candidates:
        if is_framework_root(candidate):
            return candidate
    raise SetupError("could not locate the packaged Nixstead framework source")


def main(arguments: list[str] | None = None) -> int:
    try:
        return run_application(arguments if arguments is not None else sys.argv[1:])
    except Cancelled:
        print("==> Setup cancelled before making changes.")
        return 0
    except (
        SetupError,
        OSError,
        RuntimeError,
        subprocess.CalledProcessError,
        KeyboardInterrupt,
    ) as error:
        if isinstance(error, subprocess.CalledProcessError):
            command = (
                error.cmd
                if isinstance(error.cmd, str)
                else " ".join(str(part) for part in error.cmd)
            )
            detail = f"command failed ({error.returncode}): {command}"
            if error.stderr:
                detail += f"\n{error.stderr.strip()}"
            error = SetupError(detail)
        print(f"Error: {error}", file=sys.stderr)
        return 1
