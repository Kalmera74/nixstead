"""Behavioral checks for the retained media-library tools."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class HardlinkToolTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.reference = self.root / "reference"
        self.candidate = self.root / "candidate"
        self.reference.mkdir()
        self.candidate.mkdir()

    def run_tool(self, *arguments):
        return subprocess.run(
            ["bash", str(ROOT / "scripts/hardlinks.sh"), *arguments],
            text=True,
            capture_output=True,
            timeout=10,
        )

    def test_compare_reports_only_files_without_reference_hardlinks(self):
        original = self.reference / "original.mkv"
        original.write_text("shared")
        linked = self.candidate / "linked.mkv"
        os.link(original, linked)
        independent = self.candidate / "independent.mkv"
        independent.write_text("different")

        result = self.run_tool("compare", str(self.reference), str(self.candidate))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(independent))

    def test_same_file_finds_every_link_in_the_selected_tree(self):
        original = self.reference / "original.mkv"
        original.write_text("shared")
        linked = self.candidate / "linked.mkv"
        os.link(original, linked)

        result = self.run_tool("same-file", str(self.root), str(original))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(set(result.stdout.splitlines()), {str(original), str(linked)})


class TranscodeReplacementTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.videos = self.root / "videos"
        self.videos.mkdir()
        self.source = self.videos / "movie.mp4"
        self.source.write_text("source")

        ffmpeg = self.bin / "ffmpeg"
        ffmpeg.write_text(
            f"#!{shutil.which('bash')}\n"
            "set -euo pipefail\n"
            "is_conversion=false\n"
            'for argument in "$@"; do\n'
            '  [[ "$argument" == -stats ]] && is_conversion=true\n'
            "done\n"
            'if [[ "$is_conversion" == true ]]; then\n'
            "  for output; do :; done\n"
            '  printf converted >"$output"\n'
            "else\n"
            "  printf '  Duration: 00:00:10.000, start: 0.000000\\n' >&2\n"
            "fi\n"
        )
        ffmpeg.chmod(0o755)

        ffprobe = self.bin / "ffprobe"
        ffprobe.write_text(f"#!{shutil.which('bash')}\nprintf 'h264\\n'\n")
        ffprobe.chmod(0o755)

    def test_replace_removes_a_source_with_a_different_extension(self):
        result = subprocess.run(
            [
                "bash",
                str(ROOT / "scripts/convert-videos-efficiently.sh"),
                "--codec",
                "hevc",
                "--replace",
                str(self.videos),
            ],
            env=dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}"),
            text=True,
            capture_output=True,
            timeout=10,
        )

        target = self.videos / "movie.mkv"
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.source.exists())
        self.assertEqual(target.read_text(), "converted")


if __name__ == "__main__":
    unittest.main()
