"""Exercise the shell database adapter through its process boundary."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

LIBRARY = Path(__file__).resolve().parents[1] / "scripts/lib/service-databases.sh"


@unittest.skipUnless(shutil.which("jq"), "jq required")
class DatabasePolicyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "calls"
        self.registry = {
            "romm": {
                "backup": {
                    "database": "mariadb-container",
                    "databaseName": "romm",
                    "databaseContainer": "romm-db",
                    "databaseUnit": "docker-romm-db.service",
                }
            },
            "immich": {
                "backup": {
                    "database": "postgresql",
                    "databaseName": "immich",
                    "databaseUnit": "postgresql.service",
                }
            },
        }
        self.stub(
            "docker",
            'printf "%s\\n" "$*" >> "$CALLS"\ncase "$*" in *mariadb-dump*) printf "CREATE DATABASE romm;\\n";; *"exec -i"*) cat > "$IMPORTED";; esac\n',
        )
        self.stub(
            "runuser",
            'printf "%s\\n" "$*" >> "$CALLS"\ncase "$*" in *pg_dump*) printf "CREATE DATABASE immich;\\n";; *pg_restore*|*psql*) cat > "$IMPORTED";; esac\n',
        )
        self.stub(
            "pg_restore",
            'printf "%s\\n" "$*" >> "$CALLS"\n[[ "$1" == --file=/dev/null ]]\n[[ "$(cat "${@: -1}")" == "CREATE DATABASE immich;" ]]\n',
        )
        self.stub("systemctl", 'printf "%s\\n" "$*" >> "$CALLS"\n')
        self.snapshot_helper = self.root / "snapshot.py"
        self.snapshot_helper.write_text(
            "import json, os, sys\n"
            "from pathlib import Path\n"
            "args = sys.argv[1:]\n"
            "with Path(os.environ['CALLS']).open('a') as log:\n"
            "    log.write(json.dumps(args) + '\\n')\n"
            "if args[0] == 'backup':\n"
            "    Path(args[args.index('--output') + 1]).write_bytes(b'snapshot fixture')\n"
            "elif args[0] == 'validate':\n"
            "    sys.exit(0 if Path(args[-1]).read_bytes() == b'snapshot fixture' else 23)\n"
            "elif args[0] == 'restore':\n"
            "    Path(os.environ['IMPORTED']).write_bytes(Path(args[-1]).read_bytes())\n"
        )

    def stub(self, name, body):
        script = self.bin / name
        script.write_text(f"#!{shutil.which('bash')}\nset -euo pipefail\n" + body)
        script.chmod(0o755)

    def run_adapter(self, command):
        return subprocess.run(
            ["bash", "-c", 'source "$LIBRARY"; ' + command],
            env=dict(
                os.environ,
                PATH=f"{self.bin}:{os.environ['PATH']}",
                LIBRARY=str(LIBRARY),
                registry_json=json.dumps(self.registry),
                ROOT=str(self.root),
                CALLS=str(self.log),
                IMPORTED=str(self.root / "imported"),
                NIXSTEAD_ELASTICSEARCH_SNAPSHOT=str(self.snapshot_helper),
            ),
            text=True,
            capture_output=True,
        )

    def test_mariadb_dump_uses_container_credentials_and_private_output(self):
        result = self.run_adapter(
            'validate_database_policy romm; dump_service_database romm "$ROOT/romm.sql"'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "romm.sql").stat().st_mode & 0o777, 0o600)
        self.assertIn("CREATE DATABASE romm", (self.root / "romm.sql").read_text())
        self.assertIn("exec romm-db sh -c", self.log.read_text())
        self.assertIn("--single-transaction", self.log.read_text())

    def test_postgresql_dump_is_scoped_to_immich(self):
        result = self.run_adapter('dump_service_database immich "$ROOT/immich.sql"')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--dbname immich", self.log.read_text())
        self.assertNotIn("pg_dumpall", self.log.read_text())

    def test_native_postgresql_dump_and_restore_use_configured_port(self):
        self.registry["immich"]["backup"]["databasePort"] = 25432
        result = self.run_adapter(
            'export PGPORT=15432; dump_service_database immich "$ROOT/immich.sql"; '
            'restore_service_database immich "$ROOT"'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.log.read_text()
        self.assertIn("pg_dump --port 25432", calls)
        self.assertIn("psql --port 25432", calls)
        self.assertNotIn("--port 15432", calls)

    def test_native_postgresql_custom_dump_is_validated_and_restored(self):
        self.registry["immich"]["backup"]["databaseFormat"] = "custom"
        result = self.run_adapter(
            'artifact=$(database_dump_path immich "$ROOT"); '
            'dump_service_database immich "$artifact"; '
            'mkdir "$ROOT/database-dumps"; '
            'cp "$artifact" "$ROOT/database-dumps/immich.dump"; '
            'validate_database_dump immich "$ROOT"; '
            'restore_service_database immich "$ROOT"'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.log.read_text()
        self.assertIn("--format=custom", calls)
        self.assertIn("--file=/dev/null", calls)
        self.assertIn("pg_restore --port 5432", calls)
        self.assertIn("--exit-on-error", calls)
        self.assertEqual(
            (self.root / "imported").read_text(), "CREATE DATABASE immich;\n"
        )

    def test_corrupt_custom_postgresql_dump_is_refused_before_database_start(self):
        self.registry["immich"]["backup"]["databaseFormat"] = "custom"
        (self.root / "database-dumps").mkdir()
        (self.root / "database-dumps/immich.dump").write_text("truncated")
        result = self.run_adapter('validate_database_dump immich "$ROOT"')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid PostgreSQL custom dump", result.stderr)
        self.assertNotIn("start postgresql.service", self.log.read_text())

    def test_custom_postgresql_dump_requires_named_database(self):
        self.registry["immich"]["backup"]["databaseFormat"] = "custom"
        self.registry["immich"]["backup"].pop("databaseName")
        result = self.run_adapter("validate_database_policy immich")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("named native PostgreSQL", result.stderr)

    def test_unknown_database_engine_fails_closed(self):
        self.registry["romm"]["backup"]["database"] = "unknown-engine"
        result = self.run_adapter("validate_database_policy romm")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unsupported", result.stderr)
        self.assertFalse(self.log.exists())

    def test_other_services_sql_does_not_satisfy_missing_dump(self):
        (self.root / "database-dumps").mkdir()
        (self.root / "database-dumps/romm.sql").write_text("CREATE DATABASE romm;")
        result = self.run_adapter('validate_database_dump immich "$ROOT"')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("immich.sql", result.stderr)

    def test_empty_dump_is_rejected(self):
        self.stub("docker", "exit 0\n")
        result = self.run_adapter('dump_service_database romm "$ROOT/romm.sql"')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Empty database dump", result.stderr)

    def seafile_policy(self):
        self.registry["seafile"] = {
            "backup": {
                "database": "mariadb-container",
                "databaseName": "seafile_db",
                "databaseNames": ["ccnet_db", "seafile_db", "seahub_db"],
                "databaseContainer": "seafile-db",
                "databaseUnit": "docker-seafile-db.service",
            }
        }

    def write_mariadb_dump(self, databases, *, completed=True):
        dumps = self.root / "database-dumps"
        dumps.mkdir(exist_ok=True)
        lines = ["-- MariaDB dump 10.19"]
        for database in databases:
            lines.extend(
                [
                    f"-- Current Database: `{database}`",
                    f"CREATE DATABASE IF NOT EXISTS `{database}`;",
                    f"USE `{database}`;",
                    "CREATE TABLE fixture (id int);",
                ]
            )
        if completed:
            lines.append("-- Dump completed on 2026-09-09 19:00:00")
        (dumps / "seafile.sql").write_text("\n".join(lines) + "\n")

    def test_mariadb_multi_database_dump_requires_every_named_database(self):
        self.seafile_policy()
        self.write_mariadb_dump(["ccnet_db", "seafile_db", "seahub_db"])
        result = self.run_adapter('validate_database_dump seafile "$ROOT"')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.log.exists())

    def test_mariadb_multi_database_dump_refuses_missing_member_before_start(self):
        self.seafile_policy()
        self.write_mariadb_dump(["ccnet_db", "seahub_db"])
        result = self.run_adapter('validate_database_dump seafile "$ROOT"')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing seafile_db", result.stderr)
        self.assertFalse(self.log.exists())

    def test_mariadb_dump_requires_native_completion_boundary(self):
        self.seafile_policy()
        self.write_mariadb_dump(
            ["ccnet_db", "seafile_db", "seahub_db"], completed=False
        )
        result = self.run_adapter('validate_database_dump seafile "$ROOT"')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Truncated MariaDB dump", result.stderr)
        self.assertFalse(self.log.exists())

    def test_dump_command_failure_propagates(self):
        self.stub("docker", "exit 42\n")
        result = self.run_adapter('dump_service_database romm "$ROOT/romm.sql"')
        self.assertEqual(result.returncode, 42)

    def test_restore_routes_each_engine_and_reads_private_dump_via_stdin(self):
        for service in ["romm", "immich"]:
            with self.subTest(service=service):
                (self.root / f"{service}.sql").write_text(f"CREATE DATABASE {service};")
                result = self.run_adapter(f'restore_service_database {service} "$ROOT"')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    (self.root / "imported").read_text(), f"CREATE DATABASE {service};"
                )
        calls = self.log.read_text()
        self.assertIn("exec -i romm-db", calls)
        self.assertIn("ON_ERROR_STOP=1", calls)
        self.assertNotIn("--file", calls)

    def test_container_postgresql_uses_declared_database_and_engine(self):
        self.registry["links"] = {
            "backup": {
                "database": "postgresql-container",
                "databaseName": "linkwarden",
                "databaseContainer": "linkwarden-db",
                "databaseUnit": "docker-linkwarden-db.service",
            }
        }
        self.stub(
            "docker",
            'printf "%s\\n" "$*" >> "$CALLS"\ncase "$*" in *pg_dump*) printf "CREATE DATABASE linkwarden;\\n";; *"exec -i"*) cat > "$IMPORTED";; esac\n',
        )
        result = self.run_adapter(
            'validate_database_policy links; dump_service_database links "$ROOT/links.sql"; restore_service_database links "$ROOT"'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "CREATE DATABASE linkwarden", (self.root / "imported").read_text()
        )
        self.assertIn("exec -i linkwarden-db", self.log.read_text())
        self.assertIn("ON_ERROR_STOP=1", self.log.read_text())

    def test_import_failure_is_not_reported_as_success(self):
        (self.root / "immich.sql").write_text("invalid SQL")
        self.stub("runuser", "exit 3\n")
        result = self.run_adapter('restore_service_database immich "$ROOT"')
        self.assertEqual(result.returncode, 3)
        self.assertNotIn("Imported", result.stdout)

    def elasticsearch_policy(self):
        self.registry["tubearchivist"] = {
            "backup": {
                "database": "elasticsearch-container",
                "databaseContainer": "tubearchivist-es",
                "databaseUnit": "docker-tubearchivist-es.service",
            }
        }

    def rdb_policy(self):
        self.stub(
            "rdb-checker",
            'printf "%s\\n" "$1" >> "$CALLS"\n'
            '[[ "$(cat "$1")" == "valid native snapshot" ]]\n',
        )
        self.registry["redis"] = {
            "backup": {
                "rdb": {
                    "file": "custom snapshot.rdb",
                    "checker": str(self.bin / "rdb-checker"),
                }
            }
        }

    def test_rdb_validation_uses_selected_checker_and_exact_filename(self):
        self.rdb_policy()
        source = self.root / "custom snapshot.rdb"
        source.write_text("valid native snapshot")
        result = self.run_adapter('validate_service_rdb redis "$ROOT"')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), str(source) + "\n")

    def test_missing_rdb_refused_without_running_checker(self):
        self.rdb_policy()
        result = self.run_adapter('validate_service_rdb redis "$ROOT"')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("nothing restored", result.stderr)
        self.assertFalse(self.log.exists())

    def test_corrupt_rdb_rejected_without_changing_input(self):
        self.rdb_policy()
        source = self.root / "custom snapshot.rdb"
        source.write_text("truncated")
        result = self.run_adapter('validate_service_rdb redis "$ROOT"')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid RDB", result.stderr)
        self.assertEqual(source.read_text(), "truncated")

    def test_rdb_path_cannot_escape_archive_slot(self):
        self.rdb_policy()
        self.registry["redis"]["backup"]["rdb"]["file"] = "../outside.rdb"
        result = self.run_adapter('validate_service_rdb redis "$ROOT"')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.log.exists())

    def test_elasticsearch_snapshot_roundtrip_uses_distinct_artifact_and_adapter(self):
        self.elasticsearch_policy()
        result = self.run_adapter(
            "validate_database_policy tubearchivist; "
            'mkdir "$ROOT/database-dumps"; '
            'artifact=$(database_dump_path tubearchivist "$ROOT/database-dumps"); '
            'dump_service_database tubearchivist "$artifact"; '
            'validate_database_dump tubearchivist "$ROOT"; '
            'restore_service_database tubearchivist "$ROOT/database-dumps"'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        archive = self.root / "database-dumps/tubearchivist.tar"
        self.assertEqual(archive.stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.root / "imported").read_bytes(), b"snapshot fixture")
        self.assertIn('"--container", "tubearchivist-es"', self.log.read_text())
        self.assertIn("start docker-tubearchivist-es.service", self.log.read_text())
        self.assertNotIn("pg_dump", self.log.read_text())

    def test_corrupt_snapshot_is_refused_before_database_start(self):
        self.elasticsearch_policy()
        (self.root / "tubearchivist.tar").write_bytes(b"truncated snapshot")
        result = self.run_adapter('restore_service_database tubearchivist "$ROOT"')
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertNotIn("start ", self.log.read_text())
        self.assertFalse((self.root / "imported").exists())

    def test_sql_file_cannot_stand_in_for_missing_elasticsearch_snapshot(self):
        self.elasticsearch_policy()
        (self.root / "database-dumps").mkdir()
        (self.root / "database-dumps/tubearchivist.sql").write_text("not a snapshot")
        result = self.run_adapter('validate_database_dump tubearchivist "$ROOT"')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("tubearchivist.tar", result.stderr)
        self.assertFalse(self.log.exists())
