#!/usr/bin/env bash
# Shared database policy handling for backup, restore and archive verification.
# registry_json is supplied by the calling registry-aware script.
# shellcheck disable=SC2154
set -euo pipefail

database_field() {
  jq -r --arg service "$1" --arg field "$2" '.[$service].backup[$field] // ""' <<<"${registry_json}"
}

validate_service_rdb() {
  local service="$1" source_dir="$2" rdb_file rdb_checker
  rdb_file="$(jq -r --arg service "${service}" '.[$service].backup.rdb.file // empty' <<<"${registry_json}")"
  [[ -n "${rdb_file}" ]] || return 0
  rdb_checker="$(jq -r --arg service "${service}" '.[$service].backup.rdb.checker // empty' <<<"${registry_json}")"
  [[ "${rdb_file}" != */* && -s "${source_dir}/${rdb_file}" && -x "${rdb_checker}" ]] || {
    echo "Incomplete RDB backup or unavailable checker for ${service}; nothing restored." >&2
    return 1
  }
  "${rdb_checker}" "${source_dir}/${rdb_file}" >/dev/null 2>&1 || {
    echo "Invalid RDB backup for ${service}; nothing restored." >&2
    return 1
  }
}

validate_service_state_files() {
  local service="$1" source_dir="$2" validator mode relative required_strings
  validator="${NIXSTEAD_STATE_FILE_VALIDATOR:-$(dirname "${BASH_SOURCE[0]}")/validate-state-file.py}"
  command -v python3 >/dev/null 2>&1 || {
    echo "Missing required command: python3" >&2
    return 1
  }
  [[ -f "${validator}" ]] || {
    echo "Missing state-file validator; nothing changed." >&2
    return 1
  }
  while IFS=$'\t' read -r mode relative required_strings; do
    [[ -n "${mode}" && -n "${relative}" ]] || continue
    [[ "${relative}" != /* && "${relative}" != ".." && "${relative}" != ../* && "${relative}" != */../* && "${relative}" != */.. ]] || {
      echo "Invalid recovery state path for ${service}; nothing changed." >&2
      return 1
    }
    python3 "${validator}" "${mode}" "${source_dir}/${relative}" --required-strings-json "${required_strings:-[]}" || {
      echo "Invalid ${mode} recovery state for ${service}; nothing changed." >&2
      return 1
    }
  done < <(jq -r --arg service "${service}" '
    (.[$service].backup.requiredJsonFiles // [] | .[] | ["json", ., "[]"]),
    (.[$service].backup.requiredSQLiteFiles // [] | .[] | ["sqlite", ., "[]"]),
    (.[$service].backup.requiredJsonStrings // [] | .[] | ["json", .file, (.keys | tojson)])
    | @tsv
  ' <<<"${registry_json}")
}

validate_service_mongodb_directory() {
  local service="$1" source_dir="$2" policy validator
  policy="$(jq -c --arg service "${service}" '.[$service].backup.mongodbDirectoryCheck // empty' <<<"${registry_json}")"
  [[ -n "${policy}" ]] || return 0
  validator="${NIXSTEAD_MONGODB_DIRECTORY_VALIDATOR:-$(dirname "${BASH_SOURCE[0]}")/validate-mongodb-directory.py}"
  command -v python3 >/dev/null 2>&1 && [[ -f "${validator}" ]] || {
    echo "Missing MongoDB recovery validator; nothing changed." >&2
    return 1
  }
  python3 "${validator}" "${source_dir}" <<<"${policy}"
}

validate_database_policy() {
  local service="$1" policy format database
  policy="$(database_field "${service}" database)"
  format="$(database_field "${service}" databaseFormat)"
  database="$(database_field "${service}" databaseName)"
  case "${policy}" in
    "") return 0 ;;
    postgresql) ;;
    elasticsearch-container)
      [[ -n "$(database_field "${service}" databaseContainer)" ]] || {
        echo "Missing Elasticsearch container for ${service}." >&2
        return 1
      }
      ;;
    mariadb-container | postgresql-container)
      [[ -n "$(database_field "${service}" databaseContainer)" && -n "$(database_field "${service}" databaseName)" ]] || {
        echo "Incomplete database policy for ${service}." >&2
        return 1
      }
      ;;
    *)
      echo "Unsupported database backup policy for ${service}: ${policy}" >&2
      return 1
      ;;
  esac
  case "${format}" in
    "" | plain) ;;
    custom)
      [[ "${policy}" == postgresql && -n "${database}" ]] || {
        echo "Custom database dumps require a named native PostgreSQL database for ${service}." >&2
        return 1
      }
      ;;
    *)
      echo "Unsupported database dump format for ${service}: ${format}" >&2
      return 1
      ;;
  esac
  [[ -n "$(database_field "${service}" databaseUnit)" ]] || {
    echo "Missing databaseUnit for ${service}." >&2
    return 1
  }
}

database_dump_path() {
  local service="$1" directory="$2" extension=sql
  if [[ "$(database_field "${service}" database)" == elasticsearch-container ]]; then
    extension=tar
  elif [[ "$(database_field "${service}" databaseFormat)" == custom ]]; then
    extension=dump
  fi
  printf '%s/%s.%s\n' "${directory}" "${service}" "${extension}"
}

elasticsearch_snapshot() {
  local helper="${NIXSTEAD_ELASTICSEARCH_SNAPSHOT:-$(dirname "${BASH_SOURCE[0]}")/elasticsearch-snapshot.py}"
  command -v python3 >/dev/null 2>&1 || {
    echo "Missing required command: python3" >&2
    return 1
  }
  python3 "${helper}" "$@"
}

validate_mariadb_dump() {
  local service="$1" artifact="$2" database last_line
  local database_names=()
  mapfile -t database_names < <(jq -r --arg service "${service}" '.[$service].backup | .databaseNames // [.databaseName] | .[] // empty' <<<"${registry_json}")
  [[ "${#database_names[@]}" -gt 0 ]] || {
    echo "Missing MariaDB database names for ${service}; nothing restored." >&2
    return 1
  }
  for database in "${database_names[@]}"; do
    [[ -n "${database}" && "${database}" != *$'\n'* && "${database}" != *'`'* ]] || {
      echo "Invalid MariaDB database name for ${service}; nothing restored." >&2
      return 1
    }
    if ! grep -Fqx -- "-- Current Database: \`${database}\`" "${artifact}" ||
      ! grep -Fqx -- "USE \`${database}\`;" "${artifact}"; then
      echo "Incomplete MariaDB dump for ${service}: missing ${database}; nothing restored." >&2
      return 1
    fi
  done
  last_line="$(sed '/^[[:space:]]*$/d' "${artifact}" | tail -n 1)"
  [[ "${last_line}" == "-- Dump completed on "* ]] || {
    echo "Truncated MariaDB dump for ${service}; nothing restored." >&2
    return 1
  }
}

validate_database_dump() {
  local service="$1" source_root="$2" artifact format
  validate_database_policy "${service}" || return 1
  [[ -n "$(database_field "${service}" database)" ]] || return 0
  artifact="$(database_dump_path "${service}" "${source_root}/database-dumps")"
  [[ -s "${artifact}" ]] || {
    echo "Incomplete backup: ${service} requires its own populated database-dumps/${artifact##*/}." >&2
    return 1
  }
  format="$(database_field "${service}" databaseFormat)"
  case "$(database_field "${service}" database)" in
    elasticsearch-container) elasticsearch_snapshot validate --archive "${artifact}" ;;
    mariadb-container) validate_mariadb_dump "${service}" "${artifact}" ;;
    postgresql)
      if [[ "${format}" == custom ]]; then
        command -v pg_restore >/dev/null 2>&1 || {
          echo "Missing required command: pg_restore" >&2
          return 1
        }
        # Render the entire archive without connecting to a database. Listing
        # only its table of contents can miss a truncated/corrupt data section.
        pg_restore --file=/dev/null "${artifact}" >/dev/null 2>&1 || {
          echo "Invalid PostgreSQL custom dump for ${service}; nothing restored." >&2
          return 1
        }
      fi
      ;;
  esac
}

dump_service_database() {
  local service="$1" destination="$2" policy database container port format
  policy="$(database_field "${service}" database)"
  database="$(database_field "${service}" databaseName)"
  port="$(database_field "${service}" databasePort)"
  format="$(database_field "${service}" databaseFormat)"
  case "${policy}" in
    "") return 0 ;;
    elasticsearch-container)
      elasticsearch_snapshot backup --container "$(database_field "${service}" databaseContainer)" --output "${destination}"
      ;;
    postgresql)
      if [[ -n "${database}" ]]; then
        if [[ "${format}" == custom ]]; then
          runuser -u postgres -- pg_dump --port "${port:-${PGPORT:-5432}}" --format=custom --clean --if-exists --create --dbname "${database}" >"${destination}"
        else
          runuser -u postgres -- pg_dump --port "${port:-${PGPORT:-5432}}" --clean --if-exists --create --dbname "${database}" >"${destination}"
        fi
      else
        # The restore connection is the bootstrap postgres role; it cannot
        # drop itself. Keep its ALTER statements and recreate all other roles.
        runuser -u postgres -- pg_dumpall --port "${port:-${PGPORT:-5432}}" --clean --if-exists | sed '/^DROP ROLE IF EXISTS postgres;$/d; /^CREATE ROLE postgres;$/d' >"${destination}"
      fi
      ;;
    mariadb-container)
      container="$(database_field "${service}" databaseContainer)"
      # The password is read inside the container, never passed in host argv.
      local database_names=()
      mapfile -t database_names < <(jq -r --arg service "${service}" '.[$service].backup | .databaseNames // [.databaseName] | .[]' <<<"${registry_json}")
      docker exec "${container}" sh -c 'export MYSQL_PWD="${MARIADB_ROOT_PASSWORD:-$MYSQL_ROOT_PASSWORD}"; exec mariadb-dump --user=root --single-transaction --routines --events --triggers --add-drop-database --databases "$@"' sh "${database_names[@]}" >"${destination}"
      ;;
    postgresql-container)
      container="$(database_field "${service}" databaseContainer)"
      docker exec "${container}" sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec pg_dump --username="$POSTGRES_USER" --clean --if-exists --create --dbname "$1"' sh "${database}" >"${destination}"
      ;;
  esac
  [[ -s "${destination}" ]] || {
    echo "Empty database dump for ${service}." >&2
    return 1
  }
  chmod 0600 "${destination}"
}

restore_service_database() {
  local service="$1" source_root="$2" policy container artifact port format
  policy="$(database_field "${service}" database)"
  port="$(database_field "${service}" databasePort)"
  format="$(database_field "${service}" databaseFormat)"
  [[ -n "${policy}" ]] || return 0
  artifact="$(database_dump_path "${service}" "${source_root}")"
  # Snapshot validation must precede even starting the target engine. The
  # top-level restore also validates every service before modifying any files.
  if [[ "${policy}" == elasticsearch-container ]]; then
    elasticsearch_snapshot validate --archive "${artifact}"
  fi
  systemctl start "$(database_field "${service}" databaseUnit)"
  case "${policy}" in
    elasticsearch-container)
      elasticsearch_snapshot restore --container "$(database_field "${service}" databaseContainer)" --archive "${artifact}"
      ;;
    postgresql)
      # Feed stdin: scratch directories are deliberately inaccessible to postgres.
      if [[ "${format}" == custom ]]; then
        runuser -u postgres -- pg_restore --port "${port:-${PGPORT:-5432}}" --clean --if-exists --create --exit-on-error --dbname postgres <"${artifact}"
      else
        runuser -u postgres -- psql --port "${port:-${PGPORT:-5432}}" --set ON_ERROR_STOP=1 --dbname postgres <"${artifact}"
      fi
      ;;
    mariadb-container)
      container="$(database_field "${service}" databaseContainer)"
      local ready=false
      for ((attempt = 0; attempt < 60; attempt++)); do
        if docker exec "${container}" sh -c 'export MYSQL_PWD="${MARIADB_ROOT_PASSWORD:-$MYSQL_ROOT_PASSWORD}"; exec mariadb --protocol=tcp --host=127.0.0.1 --user=root --execute "SELECT 1"' >/dev/null 2>&1; then
          ready=true
          break
        fi
        sleep 1
      done
      [[ "${ready}" == true ]] || {
        echo "Database is not ready for ${service}." >&2
        return 1
      }
      docker exec -i "${container}" sh -c 'export MYSQL_PWD="${MARIADB_ROOT_PASSWORD:-$MYSQL_ROOT_PASSWORD}"; exec mariadb --user=root' <"${source_root}/${service}.sql"
      ;;
    postgresql-container)
      container="$(database_field "${service}" databaseContainer)"
      local ready=false
      for ((attempt = 0; attempt < 60; attempt++)); do
        if docker exec "${container}" sh -c 'exec pg_isready --host=127.0.0.1 --username="$POSTGRES_USER" --dbname postgres' >/dev/null 2>&1; then
          ready=true
          break
        fi
        sleep 1
      done
      [[ "${ready}" == true ]] || {
        echo "Database is not ready for ${service}." >&2
        return 1
      }
      docker exec -i "${container}" sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql --username="$POSTGRES_USER" --set ON_ERROR_STOP=1 --dbname postgres' <"${source_root}/${service}.sql"
      ;;
  esac
  echo "Imported ${policy} dump for ${service}."
}
