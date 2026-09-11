from __future__ import annotations

import json
import os
import subprocess
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path

from ..commands import SetupError, output
from ..model import HostConfig, NasConfig, NasDisk, NasParityDisk
from ..ui import UI
from ..validation import absolute_path, fs_type, mount_options, nas_disk_name


def _validated_form(
    ui: UI,
    title: str,
    fields: Sequence[tuple[str, str, str, str]],
    validators: Sequence[tuple[str, Callable[[str], bool], str]],
) -> dict[str, str]:
    current = list(fields)
    while True:
        values = ui.form(title, current)
        for key, validator, message in validators:
            if not validator(values[key]):
                ui.error(message.format(value=values[key] or "<empty>"))
                current = [
                    (field_key, label, values.get(field_key, default), help_text)
                    for field_key, label, default, help_text in current
                ]
                break
        else:
            return values


@dataclass(frozen=True)
class DiskCandidate:
    """A real, currently visible block disk offered by the NAS wizard."""

    path: str
    stable_path: str
    size_bytes: int
    uuid_values: tuple[str, ...]
    free_bytes: int | None
    filesystems: tuple[str, ...]
    mountpoints: tuple[str, ...]
    model: str
    has_partitions: bool

    @property
    def key(self) -> str:
        return self.stable_path or self.path

    @property
    def label(self) -> str:
        uuid = ", ".join(self.uuid_values) if self.uuid_values else "none"
        filesystem = (
            ", ".join(self.filesystems) if self.filesystems else "unformatted/unknown"
        )
        free = (
            _human_bytes(self.free_bytes) if self.free_bytes is not None else "unknown"
        )
        partitions = "yes" if self.has_partitions else "no"
        model = self.model or "unknown model"
        return (
            f"{self.key} | kernel {self.path}; model {model}; "
            f"size {_human_bytes(self.size_bytes)}; free {free}; UUID {uuid}; "
            f"filesystem {filesystem}; partitions {partitions}"
        )


def discover_disks() -> list[DiskCandidate]:
    """Discover whole disks without probing or changing their contents."""

    try:
        raw = output(
            [
                "lsblk",
                "--json",
                "--bytes",
                "--paths",
                "--tree",
                "--output",
                "PATH,TYPE,SIZE,FSTYPE,UUID,MOUNTPOINT,FSAVAIL,MODEL",
            ]
        )
        devices = json.loads(raw).get("blockdevices", [])
    except (OSError, ValueError, TypeError, subprocess.CalledProcessError) as error:
        raise SetupError("could not inspect block devices with lsblk") from error

    candidates: list[DiskCandidate] = []
    for device in devices:
        if device.get("type") != "disk":
            continue
        path = str(device.get("path") or "")
        if not path or path.startswith("/dev/zram") or device.get("fstype") == "swap":
            continue
        children = [
            child for child in device.get("children", []) if isinstance(child, dict)
        ]
        records = [device, *children]
        if any(record.get("mountpoint") == "[SWAP]" for record in records):
            continue
        size_bytes = _integer(device.get("size"))
        free_bytes = _free_bytes(records)
        if (
            free_bytes is None
            and not children
            and not device.get("fstype")
            and not device.get("mountpoint")
        ):
            free_bytes = size_bytes
        candidates.append(
            DiskCandidate(
                path=path,
                stable_path=_stable_path(path),
                size_bytes=size_bytes,
                uuid_values=tuple(
                    _unique_text(record.get("uuid") for record in records)
                ),
                free_bytes=free_bytes,
                filesystems=tuple(
                    _unique_text(record.get("fstype") for record in records)
                ),
                mountpoints=tuple(
                    _unique_text(record.get("mountpoint") for record in records)
                ),
                model=str(device.get("model") or "").strip(),
                has_partitions=bool(children),
            )
        )
    return candidates


def configure(host: HostConfig, ui: UI) -> bool:
    while True:
        ui.header(
            "NAS storage configuration",
            "Select real disks first, then assign parity and mergerfs purposes. No disks are formatted.",
        )
        candidates = discover_disks()
        if not candidates or not any(
            not candidate.has_partitions and not candidate.mountpoints
            for candidate in candidates
        ):
            ui.pager(
                "No eligible non-swap disks were found. NAS needs at least one unpartitioned, "
                "unmounted data disk before it can be enabled.\n\n"
                + (
                    "\n".join(f"  {candidate.label}" for candidate in candidates)
                    if candidates
                    else "No block disks were detected."
                )
            )
            if ui.yes_no("Disable NAS and continue with the rest of setup", True):
                host.nas.enabled = False
                host.nas.configured = False
                return False
            raise SetupError(
                "no eligible non-swap block disks were found for NAS configuration"
            )

        selected = {candidate.key: False for candidate in candidates}
        ui.checklist(
            "Select every disk to include in this NAS",
            [(candidate.key, candidate.label) for candidate in candidates],
            selected,
        )
        chosen = [candidate for candidate in candidates if selected[candidate.key]]
        if not chosen:
            ui.error("Select at least one disk for the NAS.")
            continue
        unsafe = [
            candidate
            for candidate in chosen
            if candidate.has_partitions or candidate.mountpoints
        ]
        if unsafe:
            details = "; ".join(
                f"{candidate.key} (partitions={candidate.has_partitions}, mounted={','.join(candidate.mountpoints) or 'none'})"
                for candidate in unsafe
            )
            ui.error(f"Select unpartitioned, unmounted disks only; review: {details}")
            continue

        parity_wanted = ui.yes_no(
            "Use one or more of the selected disks for SnapRAID parity",
            bool(host.nas.parity),
        )
        parity_candidates: list[DiskCandidate] = []
        if parity_wanted:
            if len(chosen) < 2:
                ui.error(
                    "Parity requires at least two selected disks: one parity disk and one data disk."
                )
                continue
            parity_selected = {candidate.key: False for candidate in chosen}
            ui.checklist(
                "Select parity disk(s) from the disks you just selected",
                [(candidate.key, candidate.label) for candidate in chosen],
                parity_selected,
            )
            parity_candidates = [
                candidate for candidate in chosen if parity_selected[candidate.key]
            ]
            if not parity_candidates:
                ui.error(
                    "Select at least one parity disk, or answer No to the parity question."
                )
                continue
            if len(parity_candidates) == len(chosen):
                ui.error("At least one selected disk must remain for mergerfs data.")
                continue

        data_candidates = [
            candidate for candidate in chosen if candidate not in parity_candidates
        ]
        if not data_candidates:
            ui.error("At least one selected disk must remain for mergerfs data.")
            continue

        nas = host.nas
        values = _validated_form(
            ui,
            "NAS pool",
            [
                (
                    "tank_mount",
                    "Merged NAS tank mount point",
                    nas.tank_mount,
                    "Used by mergerfs and Samba.",
                )
            ],
            [("tank_mount", absolute_path, "Invalid NAS tank mount point: {value}")],
        )
        nas.tank_mount = values["tank_mount"]
        nas.mergerfs = ui.yes_no(
            "Enable mergerfs pooling for the data disks", nas.mergerfs
        )
        nas.snapraid = bool(parity_candidates)
        nas.samba = ui.yes_no(
            "Enable Samba (authenticated shares must be selected explicitly in the host configuration)",
            nas.samba,
        )

        nas.data = []
        mount_points: set[str] = set()
        data_names: set[str] = set()
        for index, candidate in enumerate(data_candidates, start=1):
            while True:
                filesystem_default = (
                    candidate.filesystems[0] if candidate.filesystems else "ext4"
                )
                values = _validated_form(
                    ui,
                    f"Data disk {index}",
                    [
                        (
                            "name",
                            f"SnapRAID name for data disk {index}",
                            f"data{index}",
                            "Use a short unique name such as data1.",
                        ),
                        (
                            "filesystem",
                            f"Filesystem type for data disk {index}",
                            filesystem_default,
                            "Use the filesystem already present; setup never formats disks.",
                        ),
                        (
                            "options",
                            f"Mount options for data disk {index} (comma-separated)",
                            "nofail",
                            "Use nofail so a missing disk does not prevent boot.",
                        ),
                        (
                            "mount",
                            f"Mount point for data disk {index}",
                            f"/mnt/data{index}",
                            "Use a unique absolute mount point under /mnt.",
                        ),
                    ],
                    [
                        ("name", nas_disk_name, "Invalid SnapRAID name: {value}"),
                        ("filesystem", fs_type, "Invalid filesystem type: {value}"),
                        ("options", mount_options, "Invalid mount options: {value}"),
                        ("mount", absolute_path, "Invalid mount point: {value}"),
                    ],
                )
                name = values["name"]
                filesystem = values["filesystem"]
                options = values["options"]
                mount = values["mount"]
                if name in data_names:
                    ui.error(f"The SnapRAID name {name} is already in use.")
                    continue
                if mount == "/" or mount in mount_points:
                    ui.error(
                        f"The mount point {mount} is already in use by a NAS disk."
                        if mount in mount_points
                        else "The root mount point cannot be reused by a NAS disk."
                    )
                    continue
                data_names.add(name)
                mount_points.add(mount)
                break
            nas.data.append(
                NasDisk(
                    name=name,
                    device=candidate.key,
                    mount_point=mount,
                    fs_type=filesystem,
                    options=_split_options(options),
                )
            )

        nas.parity = []
        for index, candidate in enumerate(parity_candidates, start=1):
            filesystem_default = (
                candidate.filesystems[0] if candidate.filesystems else "ext4"
            )
            values = _validated_form(
                ui,
                f"Parity disk {index}",
                [
                    (
                        "filesystem",
                        f"Filesystem type for parity disk {index}",
                        filesystem_default,
                        "Use the filesystem already present; setup never formats disks.",
                    ),
                    (
                        "options",
                        f"Mount options for parity disk {index} (comma-separated)",
                        "nofail",
                        "Use nofail so a missing disk does not prevent boot.",
                    ),
                    (
                        "mount",
                        f"Mount point for parity disk {index}",
                        f"/mnt/parity{index}",
                        "Use a unique absolute mount point under /mnt.",
                    ),
                ],
                [
                    ("filesystem", fs_type, "Invalid filesystem type: {value}"),
                    ("options", mount_options, "Invalid mount options: {value}"),
                    ("mount", absolute_path, "Invalid mount point: {value}"),
                ],
            )
            filesystem = values["filesystem"]
            options = values["options"]
            mount = values["mount"]
            if mount == "/" or mount in mount_points:
                ui.error(
                    f"The mount point {mount} is already in use by a NAS disk."
                    if mount in mount_points
                    else "The root mount point cannot be reused by a NAS disk."
                )
                continue
            mount_points.add(mount)
            nas.parity.append(
                NasParityDisk(
                    device=candidate.key,
                    mount_point=mount,
                    fs_type=filesystem,
                    options=_split_options(options),
                )
            )

        show(nas, chosen)
        if ui.yes_no("Save this disk layout and enable the NAS stack", False):
            nas.enabled = True
            nas.configured = True
            return True
        ui.error("NAS configuration was not saved; select and assign the disks again.")


def _stable_path(path: str) -> str:
    by_id = Path("/dev/disk/by-id")
    if not by_id.is_dir():
        return path
    real_path = os.path.realpath(path)
    matches = []
    try:
        for link in by_id.iterdir():
            if "-part" in link.name or not link.is_symlink():
                continue
            if os.path.realpath(link) == real_path:
                matches.append(link)
    except OSError:
        return path
    if not matches:
        return path
    matches.sort(key=lambda link: (0 if link.name.startswith("wwn-") else 1, link.name))
    return str(matches[0])


def _integer(value: object) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def _free_bytes(records: list[dict[str, object]]) -> int | None:
    values = [
        _integer(record.get("fsavail"))
        for record in records
        if record.get("fsavail") not in (None, "")
    ]
    return sum(values) if values else None


def _unique_text(values: object) -> list[str]:
    result: list[str] = []
    for value in values if not isinstance(values, str) else [values]:
        text = str(value or "").strip()
        if text and text not in result:
            result.append(text)
    return result


def _human_bytes(value: int | None) -> str:
    if value is None:
        return "unknown"
    units = ("B", "KiB", "MiB", "GiB", "TiB", "PiB")
    amount = float(value)
    for unit in units:
        if abs(amount) < 1024 or unit == units[-1]:
            return f"{amount:.1f} {unit}" if unit != "B" else f"{int(amount)} B"
        amount /= 1024
    return f"{value} B"


def _split_options(value: str) -> list[str]:
    return [item for item in value.split(",") if item]


def show(nas: NasConfig, chosen: list[DiskCandidate]) -> None:
    print(
        f"\nNAS layout: tank={nas.tank_mount}, mergerfs={nas.mergerfs}, "
        f"snapraid={nas.snapraid}, samba={nas.samba}"
    )
    print("  selected disks:")
    for candidate in chosen:
        print(f"    {candidate.label}")
    for disk in nas.data:
        print(
            f"  mergerfs data {disk.name}: {disk.device} -> {disk.mount_point} ({disk.fs_type}; {','.join(disk.options) or 'none'})"
        )
    for disk in nas.parity:
        print(
            f"  parity: {disk.device} -> {disk.mount_point} ({disk.fs_type}; {','.join(disk.options) or 'none'})"
        )
