from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path

from .commands import SetupError, output


@dataclass
class Service:
    service_id: str
    option_path: str
    group: str
    label: str
    preset_controlled: bool
    requires_lan: bool
    suggest_docker: bool
    presets: list[str] = field(default_factory=list)
    secrets: list[str] = field(default_factory=list)
    inputs: list[dict] = field(default_factory=list)
    requires_services: list[str] = field(default_factory=list)

    support: str = "Evaluation only; application restore unverified"
    requirements: str = "See the service guide for storage and resource requirements"

    @property
    def selection_label(self) -> str:
        return f"{self.label} — {self.support}. {self.requirements}"

    @property
    def variable(self) -> str:
        return "ENABLE_" + self.service_id.upper().replace("-", "_")


class Registry:
    def __init__(self, repo_root: Path) -> None:
        self.repo_root = repo_root
        self.services: list[Service] = []

    def load(self) -> None:
        expression = r"""
let
  registry = import (builtins.getEnv "SERVICE_REGISTRY_PATH");
  ids = builtins.filter (id: registry.${id}.setup != null) (builtins.attrNames registry);
  sorted = builtins.sort (left: right: registry.${left}.setup.order < registry.${right}.setup.order) ids;
  render = id:
    let entry = registry.${id}; setup = entry.setup; optionPath = setup.optionPath or entry.enablePath;
    in builtins.concatStringsSep "|" [ id ("nixstead.services." + builtins.concatStringsSep "." optionPath)
      setup.group (setup.label or entry.name) (if setup.presetControlled then "true" else "false")
      (if setup.requiresLan then "true" else "false") (if setup.suggestDocker or false then "true" else "false")
      (builtins.concatStringsSep "," setup.presets) (builtins.concatStringsSep "," entry.secrets)
      (builtins.toJSON { inputs = setup.inputs or []; requiresServices = setup.requiresServices or []; support = setup.support or "Evaluation only"; requirements = setup.requirements or "Explicit host configuration required"; }) ];
in builtins.concatStringsSep "\n" (map render sorted)
"""
        env = dict(
            os.environ,
            SERVICE_REGISTRY_PATH=str(self.repo_root / "modules/services/registry.nix"),
        )
        try:
            raw = output(
                [
                    "nix",
                    "--extra-experimental-features",
                    "nix-command flakes",
                    "eval",
                    "--raw",
                    "--impure",
                    "--expr",
                    expression,
                ],
                env=env,
            )
        except Exception as error:
            raise SetupError(
                "could not load setup metadata from the service registry"
            ) from error
        self.services = []
        for line in raw.splitlines():
            if not line:
                continue
            parts = line.split("|", 9)
            if len(parts) != 10:
                raise SetupError(f"invalid service registry row: {line}")
            metadata = json.loads(parts[9])
            self.services.append(
                Service(
                    parts[0],
                    parts[1],
                    parts[2],
                    parts[3],
                    parts[4] == "true",
                    parts[5] == "true",
                    parts[6] == "true",
                    [x for x in parts[7].split(",") if x],
                    [x for x in parts[8].split(",") if x],
                    metadata["inputs"],
                    metadata["requiresServices"],
                    metadata["support"],
                    metadata["requirements"],
                )
            )

    def by_variable(self, variable: str) -> Service:
        return next(
            service for service in self.services if service.variable == variable
        )

    def groups(self, group: str) -> list[Service]:
        return [service for service in self.services if service.group == group]

    def apply_preset(self, state: dict[str, bool], preset: str) -> None:
        for service in self.services:
            if service.preset_controlled:
                state[service.variable] = (
                    preset in service.presets if preset != "custom" else False
                )

    def requires_lan(self, state: dict[str, bool]) -> bool:
        return any(
            state.get(service.variable, False) and service.requires_lan
            for service in self.services
        )
