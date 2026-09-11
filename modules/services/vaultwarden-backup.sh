#!/usr/bin/env bash
set -euo pipefail
umask 077

for command_name in sqlite3 mktemp cp cmp mv rm; do
  command -v "${command_name}" >/dev/null || {
    echo "Missing required command: ${command_name}" >&2
    exit 1
  }
done

: "${DATA_FOLDER:?DATA_FOLDER is required}"
: "${BACKUP_FOLDER:?BACKUP_FOLDER is required}"
[[ -d "${BACKUP_FOLDER}" ]] || {
  echo "Backup directory is unavailable: ${BACKUP_FOLDER}" >&2
  exit 1
}
if [[ ! -d "${DATA_FOLDER}" ]]; then
  echo "Vaultwarden has not created its data directory; skipping initial backup."
  exit 0
fi
[[ -s "${DATA_FOLDER}/db.sqlite3" ]] || {
  echo "Vaultwarden database is missing or empty; refusing to replace the backup." >&2
  exit 1
}

staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/vaultwarden-backup.XXXXXXXX")"
destination_tmp=""
cleanup() {
  rm -rf -- "${staging_dir}"
  if [[ -n "${destination_tmp}" ]]; then
    rm -f -- "${destination_tmp}"
  fi
}
trap cleanup EXIT

# SQLite's backup API snapshots a live database, including its WAL. Keep its
# destination on local storage: network shares need only support copying files.
(
  cd "${staging_dir}"
  sqlite3 -bail "${DATA_FOLDER}/db.sqlite3" ".timeout 30000" '.backup db.sqlite3'
)
[[ -s "${staging_dir}/db.sqlite3" ]]
# Make the snapshot self-contained for readers that cannot create WAL sidecars.
[[ "$(sqlite3 "${staging_dir}/db.sqlite3" 'PRAGMA journal_mode=DELETE;')" == "delete" ]]
[[ "$(sqlite3 -readonly "${staging_dir}/db.sqlite3" 'PRAGMA integrity_check;')" == "ok" ]] || {
  echo "Vaultwarden backup failed SQLite integrity validation." >&2
  exit 1
}

# Preserve attachments, sends, keys and config, excluding the live SQLite files.
shopt -s nullglob dotglob
for source_path in "${DATA_FOLDER}"/*; do
  [[ "${source_path##*/}" == db.* ]] && continue
  cp -R -- "${source_path}" "${BACKUP_FOLDER}/"
done

# Never truncate the last database backup on a failed copy. Check the copied
# bytes without opening SQLite on the share, then rename within that directory.
destination_tmp="$(mktemp "${BACKUP_FOLDER}/.db.sqlite3.XXXXXXXX")"
cp -- "${staging_dir}/db.sqlite3" "${destination_tmp}"
cmp -- "${staging_dir}/db.sqlite3" "${destination_tmp}"
mv -fT -- "${destination_tmp}" "${BACKUP_FOLDER}/db.sqlite3"
destination_tmp=""
echo "Vaultwarden database backup validated and published."
