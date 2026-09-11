import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from suite_catalogue import CATEGORIES, render, validate
from select_checks import (
    canary_checks,
    changed_paths,
    matches,
    select,
    service_checks,
    shard_checks,
)


def catalogue_fixture():
    services = {
        name: {
            "name": name.title(),
            "local": True,
            "stateful": True,
            "support": "limited",
            "suite": f"tests/services/{name}/default.nix",
            "paths": [f"modules/services/dev/{name}.nix"],
            "limitations": ["No upgrades."],
            "coverage": {
                category: {"status": "missing", "checks": []} for category in CATEGORIES
            },
        }
        for name in ["alpha", "beta", "unported"]
    }
    checks = {
        "public-module-api": {
            "tier": "fast",
            "services": list(services),
            "paths": [],
            "detail": "Shared API.",
        },
        "service-alpha-runtime": {
            "tier": "runtime",
            "services": ["alpha"],
            "paths": ["tests/services/alpha/"],
            "quick": True,
            "weight": 3,
            "detail": "Runtime operation.",
        },
        "service-beta-recovery": {
            "tier": "runtime",
            "services": ["beta"],
            "paths": ["tests/services/beta/"],
            "detail": "Recovery operation.",
        },
    }
    for name, service in services.items():
        service["coverage"]["configuration"] = {
            "status": "shared",
            "checks": ["public-module-api"],
        }
        service["relatedChecks"] = [
            key for key, check in checks.items() if name in check["services"]
        ]
    services["alpha"]["coverage"]["runtime"] = {
        "status": "scenario",
        "checks": ["service-alpha-runtime"],
    }
    return {
        "schemaVersion": 1,
        "categories": list(CATEGORIES),
        "services": services,
        "checks": checks,
    }


class CoverageContractTests(unittest.TestCase):
    def setUp(self):
        self.catalogue = catalogue_fixture()

    def test_missing_coverage_is_visible_and_does_not_prevent_available_checks(self):
        validate(self.catalogue, list(self.catalogue["checks"]))
        report = render(self.catalogue)
        self.assertIn(
            "| [Alpha](#alpha) | shared | scenario | missing | missing | missing | missing |",
            report,
        )

    def test_unavailable_flake_check_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "unavailable"):
            validate(self.catalogue, ["public-module-api"])

    def test_architecture_exclusion_does_not_hide_a_missing_supported_check(self):
        self.catalogue["checks"]["service-alpha-runtime"]["systems"] = ["x86_64-linux"]
        available = set(self.catalogue["checks"]) - {"service-alpha-runtime"}
        validate(self.catalogue, available, "aarch64-linux")
        with self.assertRaisesRegex(ValueError, "unavailable"):
            validate(self.catalogue, available, "x86_64-linux")

    def test_empty_or_unknown_architecture_cannot_hide_a_declared_check(self):
        for systems in [
            None,
            [],
            ["unknown-linux"],
            "x86_64-linux",
            ["x86_64-linux"] * 2,
        ]:
            with self.subTest(systems=systems):
                self.catalogue["checks"]["service-alpha-runtime"]["systems"] = systems
                with self.assertRaisesRegex(ValueError, "architectures"):
                    validate(self.catalogue)

    def test_execution_key_must_be_nonempty_text(self):
        for key in [None, "", [], 42]:
            with self.subTest(key=key):
                self.catalogue["checks"]["service-alpha-runtime"]["executionKey"] = key
                with self.assertRaisesRegex(ValueError, "execution key"):
                    validate(self.catalogue)

    def test_quick_marker_must_be_boolean(self):
        for quick in [None, "yes", 1, []]:
            with self.subTest(quick=quick):
                self.catalogue["checks"]["service-alpha-runtime"]["quick"] = quick
                with self.assertRaisesRegex(ValueError, "quick-check marker"):
                    validate(self.catalogue)

    def test_weight_must_be_a_positive_integer(self):
        for weight in [0, -1, 1.5, "2", True]:
            with self.subTest(weight=weight):
                self.catalogue["checks"]["service-alpha-runtime"]["weight"] = weight
                with self.assertRaisesRegex(ValueError, "check weight"):
                    validate(self.catalogue)

    def test_full_support_requires_real_recovery_evidence(self):
        service = self.catalogue["services"]["alpha"]
        service["support"] = "full"
        for category in CATEGORIES:
            service["coverage"][category] = {
                "status": "scenario",
                "checks": ["service-alpha-runtime"],
            }
        for status in ["missing", "shared", "not-applicable"]:
            with self.subTest(status=status):
                service["coverage"]["recovery"] = {
                    "status": status,
                    "checks": ["public-module-api"] if status == "shared" else [],
                    "reason": "No fixture yet",
                }
                with self.assertRaisesRegex(ValueError, "lacks required"):
                    validate(self.catalogue)

    def test_stateful_recovery_does_not_repeat_startup_in_a_second_vm(self):
        runtime = self.catalogue["checks"]["service-alpha-runtime"]
        self.catalogue["checks"]["service-alpha-recovery"] = {
            **runtime,
            "detail": "Combined startup and clean restore.",
        }
        service = self.catalogue["services"]["alpha"]
        service["stateful"] = True
        service["relatedChecks"].append("service-alpha-recovery")
        service["coverage"]["recovery"] = {
            "status": "scenario",
            "checks": ["service-alpha-recovery"],
        }
        with self.assertRaisesRegex(ValueError, "Redundant stateful runtime VM"):
            validate(self.catalogue)

    def test_claimed_coverage_cannot_have_empty_or_foreign_evidence(self):
        for refs in [[], ["nonexistent"], ["service-beta-recovery"]]:
            with self.subTest(refs=refs):
                self.catalogue["services"]["alpha"]["coverage"]["runtime"]["checks"] = (
                    refs
                )
                with self.assertRaises(ValueError):
                    validate(self.catalogue)

    def test_unknown_service_in_a_check_is_rejected(self):
        self.catalogue["checks"]["service-beta-recovery"]["services"].append("typo")
        with self.assertRaisesRegex(ValueError, "Unknown service"):
            validate(self.catalogue)

    def test_not_applicable_requires_an_explicit_reason(self):
        self.catalogue["services"]["alpha"]["coverage"]["upgrade"] = {
            "status": "not-applicable",
            "checks": [],
        }
        with self.assertRaisesRegex(ValueError, "requires a reason"):
            validate(self.catalogue)

    def test_stateless_service_can_explain_recovery_without_a_meaningless_test(self):
        service = self.catalogue["services"]["alpha"]
        service["support"] = "full"
        service["stateful"] = False
        for category in ["configuration", "runtime", "failure"]:
            service["coverage"][category] = {
                "status": "scenario",
                "checks": ["service-alpha-runtime"],
            }
        service["coverage"]["recovery"] = {
            "status": "not-applicable",
            "checks": [],
            "reason": "Stateless proxy with no local data.",
        }
        validate(self.catalogue)
        self.assertIn(
            "recovery: not applicable. Stateless proxy with no local data.",
            render(self.catalogue),
        )

    def test_omitted_service_link_is_rejected(self):
        self.catalogue["services"]["alpha"]["relatedChecks"].remove(
            "service-alpha-runtime"
        )
        with self.assertRaisesRegex(ValueError, "Incomplete related"):
            validate(self.catalogue)

    def test_drift_check_fails_for_stale_report(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "catalogue.json").write_text(json.dumps(self.catalogue))
            (root / "report.md").write_text("old report")
            result = subprocess.run(
                [
                    "python",
                    str(Path(__file__).with_name("suite_catalogue.py")),
                    str(root / "catalogue.json"),
                    str(root / "report.md"),
                    "--check",
                ],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("stale", result.stderr)


class AffectedCheckTests(unittest.TestCase):
    def setUp(self):
        self.catalogue = catalogue_fixture()
        self.all = ["service-alpha-runtime", "service-beta-recovery"]

    def test_module_change_selects_its_service(self):
        self.assertEqual(
            select(self.catalogue, ["modules/services/dev/alpha.nix"]),
            ["service-alpha-runtime"],
        )

    def test_service_fixture_change_selects_its_service(self):
        self.assertEqual(
            select(self.catalogue, ["tests/services/beta/credentials.json"]),
            ["service-beta-recovery"],
        )

    def test_shared_and_unknown_changes_expand_to_all(self):
        for path in [
            "flake.lock",
            "tests/lib/service_scenario.py",
            "tests/select_checks.py",
            "modules/services/registry/dev.nix",
            "scripts/restore-service-configs.sh",
            "modules/new-module.nix",
            ".github/workflows/checks.yml",
            "tests/services/deleted/config.nix",
        ]:
            with self.subTest(path=path):
                self.assertEqual(select(self.catalogue, [path]), self.all)

    def test_quick_shared_changes_use_canaries(self):
        self.assertEqual(
            select(self.catalogue, ["flake.lock"], quick=True),
            ["service-alpha-runtime"],
        )

    def test_quick_direct_changes_keep_the_affected_heavy_check(self):
        self.assertEqual(
            select(
                self.catalogue,
                ["modules/services/dev/beta.nix"],
                quick=True,
            ),
            ["service-beta-recovery"],
        )

    def test_canaries_and_service_scope_are_explicit(self):
        self.assertEqual(
            canary_checks(self.catalogue, "x86_64-linux"),
            {"service-alpha-runtime"},
        )
        self.assertEqual(
            service_checks(self.catalogue, "beta"),
            ["service-beta-recovery"],
        )
        with self.assertRaisesRegex(ValueError, "Unknown service"):
            service_checks(self.catalogue, "typo")

    def test_weighted_shards_are_deterministic_and_complete(self):
        checks = copy.deepcopy(self.catalogue["checks"])
        checks["service-gamma-runtime"] = {
            **checks["service-beta-recovery"],
            "weight": 2,
        }
        checks["service-delta-runtime"] = {
            **checks["service-beta-recovery"],
            "weight": 1,
        }
        self.catalogue["checks"] = checks
        selected = [
            "service-alpha-runtime",
            "service-beta-recovery",
            "service-gamma-runtime",
            "service-delta-runtime",
        ]
        shards = shard_checks(self.catalogue, selected, 2)
        self.assertEqual(shards, shard_checks(self.catalogue, reversed(selected), 2))
        self.assertEqual(
            sorted(check for shard in shards for check in shard["checks"]),
            sorted(selected),
        )
        self.assertNotEqual(
            next(
                shard["shard"]
                for shard in shards
                if "service-alpha-runtime" in shard["checks"]
            ),
            next(
                shard["shard"]
                for shard in shards
                if "service-gamma-runtime" in shard["checks"]
            ),
        )

    def test_shard_count_must_be_positive(self):
        with self.assertRaisesRegex(ValueError, "positive"):
            shard_checks(self.catalogue, self.all, 0)

    def test_owned_service_without_runtime_does_not_start_unrelated_jobs(self):
        self.assertEqual(
            select(self.catalogue, ["modules/services/dev/unported.nix"]), []
        )

    def test_shared_owner_without_runtime_does_not_expand_other_owners(self):
        for service in ["alpha", "unported"]:
            self.catalogue["services"][service]["paths"].append(
                "modules/services/dev/shared.nix"
            )
        self.assertEqual(
            select(self.catalogue, ["modules/services/dev/shared.nix"]),
            ["service-alpha-runtime"],
        )

    def test_architecture_selection_keeps_only_available_runtime(self):
        self.catalogue["checks"]["service-beta-recovery"]["systems"] = ["x86_64-linux"]
        for path, expected in [
            ("flake.lock", ["service-alpha-runtime"]),
            ("tests/services/beta/node.nix", []),
        ]:
            with self.subTest(path=path):
                self.assertEqual(
                    select(self.catalogue, [path], "aarch64-linux"), expected
                )
        self.assertEqual(select(self.catalogue, ["flake.lock"]), self.all)

    def test_docs_only_or_empty_changes_need_no_runtime(self):
        self.assertEqual(
            select(self.catalogue, ["docs/validation.md", "README.md"]), []
        )
        self.assertEqual(select(self.catalogue, []), [])

    def test_file_matching_does_not_hide_unknown_siblings(self):
        self.assertFalse(
            matches(
                "modules/services/dev/alpha.nix.old", "modules/services/dev/alpha.nix"
            )
        )
        self.assertFalse(
            matches("tests/services/alpha-extra/a.py", "tests/services/alpha/")
        )
        self.assertEqual(
            select(self.catalogue, ["modules/services/dev/alpha.nix.old"]), self.all
        )

    def test_selection_is_deduplicated_and_order_independent(self):
        paths = ["modules/services/dev/alpha.nix", "tests/services/beta/node.nix"]
        self.assertEqual(select(self.catalogue, paths + paths), self.all)
        self.assertEqual(select(self.catalogue, reversed(paths)), self.all)

    def test_shared_vm_is_selected_once_after_service_ownership(self):
        for name in ["service-alpha-runtime", "service-beta-recovery"]:
            self.catalogue["checks"][name]["executionKey"] = "tests/shared-smoke.nix"
        before = copy.deepcopy(self.catalogue)
        paths = ["tests/services/beta/node.nix", "modules/services/dev/alpha.nix"]
        self.assertEqual(select(self.catalogue, paths), ["service-alpha-runtime"])
        self.assertEqual(
            select(self.catalogue, reversed(paths)),
            ["service-alpha-runtime"],
        )
        # An affected beta still selects its actual alias; global lexical
        # grouping must not discard its ownership before selecting checks.
        self.assertEqual(
            select(self.catalogue, ["tests/services/beta/node.nix"]),
            ["service-beta-recovery"],
        )
        self.assertEqual(self.catalogue, before)

    def test_shared_vm_deduplication_respects_architecture(self):
        for name in ["service-alpha-runtime", "service-beta-recovery"]:
            self.catalogue["checks"][name]["executionKey"] = "tests/shared-smoke.nix"
        self.catalogue["checks"]["service-alpha-runtime"]["systems"] = ["x86_64-linux"]
        self.assertEqual(
            select(self.catalogue, ["flake.lock"], "aarch64-linux"),
            ["service-beta-recovery"],
        )

    def test_edit_to_shared_service_fixture_selects_one_execution(self):
        for name in ["service-alpha-runtime", "service-beta-recovery"]:
            self.catalogue["checks"][name]["paths"].append(
                "tests/services/alpha/shared-smoke.nix"
            )
            self.catalogue["checks"][name]["executionKey"] = "tests/shared-smoke.nix"
        self.assertEqual(
            select(self.catalogue, ["tests/services/alpha/shared-smoke.nix"]),
            ["service-alpha-runtime"],
        )

    def test_all_cli_deduplicates_shared_vm_aliases(self):
        for name in ["service-alpha-runtime", "service-beta-recovery"]:
            self.catalogue["checks"][name]["executionKey"] = "tests/shared-smoke.nix"
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "catalogue.json"
            source.write_text(json.dumps(self.catalogue))
            result = subprocess.check_output(
                [
                    "python",
                    str(Path(__file__).with_name("select_checks.py")),
                    str(source),
                    "--all",
                ],
                text=True,
            )
        self.assertEqual(json.loads(result), {"check": ["service-alpha-runtime"]})

    def test_cli_emits_canaries_and_sharded_full_runs(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "catalogue.json"
            source.write_text(json.dumps(self.catalogue))
            command = [
                "python",
                str(Path(__file__).with_name("select_checks.py")),
                str(source),
            ]
            canaries = json.loads(
                subprocess.check_output(command + ["--canaries"], text=True)
            )
            shards = json.loads(
                subprocess.check_output(command + ["--all", "--shards", "2"], text=True)
            )
        self.assertEqual(canaries, {"check": ["service-alpha-runtime"]})
        self.assertEqual(len(shards["include"]), 2)
        self.assertEqual(
            sorted(check for shard in shards["include"] for check in shard["checks"]),
            self.all,
        )

    def test_git_comparison_preserves_both_sides_of_renames_and_spaces(self):
        # --no-renames presents removed and added files separately, including
        # moved files leaving a previously owned service directory.
        with patch(
            "select_checks.subprocess.check_output",
            side_effect=[
                "a" * 40 + "\n",
                "b" * 40 + "\n",
                b"modules/services/dev/alpha.nix\0docs/moved file.md\0",
            ],
        ) as git:
            paths = changed_paths("main", "HEAD")
        self.assertIn("--no-renames", git.call_args.args[0])
        self.assertIn("--end-of-options", git.call_args_list[0].args[0])
        self.assertEqual(select(self.catalogue, paths), ["service-alpha-runtime"])

    def test_malformed_catalogue_fails_instead_of_skipping_checks(self):
        invalid = copy.deepcopy(self.catalogue)
        invalid["services"]["alpha"]["relatedChecks"] = []
        with self.assertRaises(ValueError):
            select(invalid, ["README.md"])


if __name__ == "__main__":
    unittest.main()
