"""Independent deterministic bytes for native mergerfs/SnapRAID evidence."""

import hashlib
from pathlib import Path
import sys


POOL = Path("/srv/pool")
EXPECTED = {
    "recover deleted.bin": bytes(range(256)) * 2048,
    "recover corrupt.bin": bytes(reversed(range(256))) * 2048,
    "unrelated.bin": b"Unaffected parity-protected content\n" * 1024,
}


def verify():
    for name, data in EXPECTED.items():
        assert (POOL / name).read_bytes() == data, name
    assert (POOL / "consumer.txt").read_bytes() == b"Managed consumer bytes\n"


action = sys.argv[1]
if action == "populate":
    for name, data in EXPECTED.items():
        (POOL / name).write_bytes(data)
    (POOL / "temporary.txt").write_text("created")
    (POOL / "temporary.txt").write_text("updated")
    assert (POOL / "temporary.txt").read_text() == "updated"
    (POOL / "temporary.txt").unlink()
    assert not (POOL / "temporary.txt").exists()
elif action == "verify":
    verify()
elif action == "delete":
    (POOL / "recover deleted.bin").unlink()
    assert not (POOL / "recover deleted.bin").exists()
    assert (POOL / "recover corrupt.bin").read_bytes() == EXPECTED[
        "recover corrupt.bin"
    ]
    assert (POOL / "unrelated.bin").read_bytes() == EXPECTED["unrelated.bin"]
elif action == "corrupt":
    # Apply each fault separately: single parity cannot repair overlapping
    # blocks lost on two different data disks at the same time.
    with (POOL / "recover corrupt.bin").open("r+b") as output:
        output.seek(1000)
        output.write(b"damaged parity-protected bytes")
    assert (POOL / "recover deleted.bin").read_bytes() == EXPECTED[
        "recover deleted.bin"
    ]
    assert (
        hashlib.sha256((POOL / "recover corrupt.bin").read_bytes()).digest()
        != hashlib.sha256(EXPECTED["recover corrupt.bin"]).digest()
    )
    assert (POOL / "unrelated.bin").read_bytes() == EXPECTED["unrelated.bin"]
else:
    raise SystemExit("Unknown NAS fixture action")
