#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: nixstead media rom-import [options] <batocera-roms-root> <romm-roms-root>

Copies ROMs from Batocera system folders into corresponding RomM folders.
Only mapped/existing RomM platforms are copied by default.

Arguments:
  <batocera-roms-root>  Source Batocera roms root (example: /userdata/roms)
  <romm-roms-root>      Destination RomM roms root (example: /mnt/public/Roms/roms)

Options:
  --dry-run             Show what would be copied without writing
  --overwrite           Overwrite existing files in destination
  --allow-unknown       Copy unmapped platforms using original folder name
  --create-missing-dirs Create destination platform folders if missing
  -h, --help            Show this help message

Real copy mode shows rsync transfer progress by default.

Notes:
  - Folder names are mapped where Batocera and RomM differ (e.g. gamecube -> ngc).
  - By default, only platforms that map to existing RomM folders are copied.
  - Use --allow-unknown to copy unmapped platforms with original names.
  - Use --create-missing-dirs to allow creating missing destination folders.
  - Text/document metadata files are skipped by default (*.txt, *.md, *.markdown, *.nfo, *.diz, *.rtf, *.xml, *.xm).
  - Image/video assets are skipped by default (jpg/jpeg/png/gif/webp/bmp/tif/tiff/svg/mp4/mkv/avi/mov/wmv/webm/m4v/mpg/mpeg).
  - Folders containing only excluded files are pruned and not created in destination.
EOF
}

require_cmd() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    printf 'Error: required command not found: %s\n' "${command_name}" >&2
    exit 1
  fi
}

normalize_platform_name() {
  local platform_name="$1"
  printf '%s' "${platform_name}" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]'
}

declare -A romm_platform_by_normalized_name=()

build_romm_platform_index() {
  local romm_platform_dir
  for romm_platform_dir in "${romm_root}"/*; do
    [[ -d "${romm_platform_dir}" ]] || continue

    local romm_platform_name
    local normalized_platform_name

    romm_platform_name="$(basename "${romm_platform_dir}")"
    normalized_platform_name="$(normalize_platform_name "${romm_platform_name}")"

    if [[ -z "${normalized_platform_name}" ]]; then
      continue
    fi

    if [[ -n "${romm_platform_by_normalized_name[${normalized_platform_name}]:-}" ]]; then
      romm_platform_by_normalized_name["${normalized_platform_name}"]="__AMBIGUOUS__"
      continue
    fi

    romm_platform_by_normalized_name["${normalized_platform_name}"]="${romm_platform_name}"
  done
}

resolve_romm_platform() {
  local batocera_platform="$1"

  case "${batocera_platform}" in
    adam) echo "colecoadam" ;;
    advision) echo "adventure-vision" ;;
    amiga500 | amiga1200) echo "amiga" ;;
    amigacd32) echo "amiga-cd32" ;;
    amigacdtv) echo "commodore-cdtv" ;;
    amstradcpc) echo "acpc" ;;
    apfm1000) echo "apf" ;;
    apple2) echo "appleii" ;;
    apple2gs) echo "apple-iigs" ;;
    arcadia) echo "arcadia-2001" ;;
    archimedes) echo "acorn-archimedes" ;;
    atarist) echo "atari-st" ;;
    astrocde) echo "astrocade" ;;
    bbc) echo "bbcmicro" ;;
    channelf) echo "fairchild-channel-f" ;;
    coco) echo "trs-80-color-computer" ;;
    commanderx16) echo "commander-x16" ;;
    cplus4) echo "c-plus-4" ;;
    crvision) echo "creativision" ;;
    dreamcast) echo "dc" ;;
    fm7) echo "fm-7" ;;
    fmtowns) echo "fm-towns" ;;
    gameandwatch) echo "g-and-w" ;;
    gamecom) echo "game-dot-com" ;;
    gamecube) echo "ngc" ;;
    gx4000) echo "amstrad-gx4000" ;;
    jaguarcd) echo "atari-jaguar-cd" ;;
    lcdgames) echo "handheld-electronic-lcd" ;;
    macintosh) echo "mac" ;;
    mastersystem) echo "sms" ;;
    megacd) echo "segacd" ;;
    megadrive) echo "genesis" ;;
    megaduck) echo "mega-duck-slash-cougar-boy" ;;
    msx1) echo "msx" ;;
    msx2+) echo "msx2plus" ;;
    msxturbor) echo "msx-turbo" ;;
    n64dd) echo "64dd" ;;
    neogeocd) echo "neo-geo-cd" ;;
    ngp) echo "neo-geo-pocket" ;;
    ngpc) echo "neo-geo-pocket-color" ;;
    o2em) echo "odyssey-2" ;;
    oricatmos) echo "atmos" ;;
    pc88) echo "pc-8800-series" ;;
    pc98) echo "pc-9800-series" ;;
    pcengine) echo "tg16" ;;
    pcenginecd | turbografxcd) echo "turbografx-cd" ;;
    pcfx) echo "pc-fx" ;;
    pet) echo "cpet" ;;
    plugnplay) echo "plug-and-play" ;;
    pokemini) echo "pokemon-mini" ;;
    ps1 | psx) echo "psx" ;;
    samcoupe) echo "sam-coupe" ;;
    snes-msu1) echo "snes" ;;
    sufami) echo "sufami-turbo" ;;
    supracan) echo "super-acan" ;;
    thomson) echo "thomson-mo5" ;;
    tic80) echo "tic-80" ;;
    ti99) echo "ti-99" ;;
    tutor) echo "tomy-tutor" ;;
    vc4000) echo "vc-4000" ;;
    videopacplus) echo "videopac-g7400" ;;
    wasm4) echo "wasm-4" ;;
    windows) echo "win" ;;
    wswan) echo "wonderswan" ;;
    wswanc) echo "wonderswan-color" ;;
    xegs) echo "atari-xegs" ;;
    zxspectrum) echo "zxs" ;;
    fbneo | mame) echo "arcade" ;;
    *)
      local normalized_batocera_platform
      local normalized_match

      normalized_batocera_platform="$(normalize_platform_name "${batocera_platform}")"
      normalized_match="${romm_platform_by_normalized_name[${normalized_batocera_platform}]:-}"

      if [[ -n "${normalized_match}" && "${normalized_match}" != "__AMBIGUOUS__" ]]; then
        echo "${normalized_match}"
      else
        echo ""
      fi
      ;;
  esac
}

dry_run=false
overwrite=false
allow_unknown=false
create_missing_dirs=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=true
      shift
      ;;
    --overwrite)
      overwrite=true
      shift
      ;;
    --allow-unknown)
      allow_unknown=true
      shift
      ;;
    --create-missing-dirs)
      create_missing_dirs=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      printf 'Error: unknown option: %s\n' "$1" >&2
      usage
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -ne 2 ]]; then
  usage
  exit 1
fi

batocera_root="$1"
romm_root="$2"

if [[ ! -d "${batocera_root}" ]]; then
  printf 'Error: Batocera root not found: %s\n' "${batocera_root}" >&2
  exit 1
fi

if [[ ! -d "${romm_root}" ]]; then
  printf 'Error: RomM root not found: %s\n' "${romm_root}" >&2
  exit 1
fi

build_romm_platform_index

require_cmd rsync

print_dry_run_summary() {
  local platform_name="$1"
  local mapped_platform_name="$2"
  local rsync_output="$3"

  local new_files=0
  local updated_files=0
  local new_directories=0
  local updated_directories=0
  local other_changes=0

  local examples_limit=8
  local examples_count=0
  local examples=""

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue

    if [[ "${line}" == "created directory "* ]]; then
      new_directories=$((new_directories + 1))
      continue
    fi

    if [[ "${line}" != *"|"* ]]; then
      continue
    fi

    local itemized_change="${line%%|*}"
    local change_path="${line#*|}"

    [[ "${change_path}" == "./" ]] && continue

    case "${itemized_change}" in
      ">f+++++++++")
        new_files=$((new_files + 1))
        ;;
      ">f"*)
        updated_files=$((updated_files + 1))
        ;;
      "cd+++++++++")
        new_directories=$((new_directories + 1))
        ;;
      ".d"* | "cd"*)
        updated_directories=$((updated_directories + 1))
        ;;
      *)
        other_changes=$((other_changes + 1))
        ;;
    esac

    if [[ ${examples_count} -lt ${examples_limit} ]]; then
      examples+=$(printf '    - %s\n' "${change_path}")
      examples_count=$((examples_count + 1))
    fi
  done <<<"${rsync_output}"

  local total_changes=$((new_files + updated_files + new_directories + updated_directories + other_changes))

  if [[ ${total_changes} -eq 0 ]]; then
    printf '  No changes planned for %s -> %s\n' "${platform_name}" "${mapped_platform_name}"
    return
  fi

  printf '  Planned changes for %s -> %s:\n' "${platform_name}" "${mapped_platform_name}"
  printf '    - New files: %d\n' "${new_files}"
  printf '    - Updated files: %d\n' "${updated_files}"
  printf '    - New directories: %d\n' "${new_directories}"
  printf '    - Updated directories: %d\n' "${updated_directories}"

  if [[ ${other_changes} -gt 0 ]]; then
    printf '    - Other changes: %d\n' "${other_changes}"
  fi

  if [[ -n "${examples}" ]]; then
    printf '    - Example paths:\n%s' "${examples}"
  fi
}

rsync_options=(
  --archive
  --human-readable
  --prune-empty-dirs
  --exclude='*.[Tt][Xx][Tt]'
  --exclude='*.[Mm][Dd]'
  --exclude='*.[Mm][Aa][Rr][Kk][Dd][Oo][Ww][Nn]'
  --exclude='*.[Nn][Ff][Oo]'
  --exclude='*.[Dd][Ii][Zz]'
  --exclude='*.[Rr][Tt][Ff]'
  --exclude='*.[Xx][Mm][Ll]'
  --exclude='*.[Xx][Mm]'
  --exclude='*.[Jj][Pp][Gg]'
  --exclude='*.[Jj][Pp][Ee][Gg]'
  --exclude='*.[Pp][Nn][Gg]'
  --exclude='*.[Gg][Ii][Ff]'
  --exclude='*.[Ww][Ee][Bb][Pp]'
  --exclude='*.[Bb][Mm][Pp]'
  --exclude='*.[Tt][Ii][Ff]'
  --exclude='*.[Tt][Ii][Ff][Ff]'
  --exclude='*.[Ss][Vv][Gg]'
  --exclude='*.[Mm][Pp]4'
  --exclude='*.[Mm][Kk][Vv]'
  --exclude='*.[Aa][Vv][Ii]'
  --exclude='*.[Mm][Oo][Vv]'
  --exclude='*.[Ww][Mm][Vv]'
  --exclude='*.[Ww][Ee][Bb][Mm]'
  --exclude='*.[Mm]4[Vv]'
  --exclude='*.[Mm][Pp][Gg]'
  --exclude='*.[Mm][Pp][Ee][Gg]'
)

if [[ "${dry_run}" == true ]]; then
  rsync_options+=(
    --dry-run
    --itemize-changes
    "--out-format=%i|%n%L"
  )
else
  rsync_options+=(--info=progress2)
fi

if [[ "${overwrite}" == false ]]; then
  rsync_options+=(--ignore-existing)
fi

platform_count=0
copied_count=0
skipped_unmapped_count=0
skipped_missing_target_count=0

for source_platform_dir in "${batocera_root}"/*; do
  [[ -d "${source_platform_dir}" ]] || continue

  source_platform="$(basename "${source_platform_dir}")"
  target_platform="$(resolve_romm_platform "${source_platform}")"

  if [[ -z "${target_platform}" ]]; then
    if [[ "${allow_unknown}" == true ]]; then
      target_platform="${source_platform}"
    else
      platform_count=$((platform_count + 1))
      skipped_unmapped_count=$((skipped_unmapped_count + 1))
      printf '[%d] %s -> skipped (no RomM mapping; use --allow-unknown)\n' "${platform_count}" "${source_platform}"
      continue
    fi
  fi

  target_platform_dir="${romm_root}/${target_platform}"

  if [[ ! -d "${target_platform_dir}" && "${create_missing_dirs}" != true ]]; then
    platform_count=$((platform_count + 1))
    skipped_missing_target_count=$((skipped_missing_target_count + 1))
    printf '[%d] %s -> %s (skipped: destination missing; use --create-missing-dirs)\n' "${platform_count}" "${source_platform}" "${target_platform}"
    continue
  fi

  platform_count=$((platform_count + 1))

  rsync_platform_options=("${rsync_options[@]}")
  if [[ ! -d "${target_platform_dir}" && "${create_missing_dirs}" == true ]]; then
    rsync_platform_options+=(--mkpath)
  fi

  if [[ "${dry_run}" == true ]]; then
    printf '[%d] %s -> %s\n' "${platform_count}" "${source_platform}" "${target_platform}"
    rsync_output="$(rsync "${rsync_platform_options[@]}" "${source_platform_dir}/" "${target_platform_dir}/")"
    print_dry_run_summary "${source_platform}" "${target_platform}" "${rsync_output}"
  else
    rsync "${rsync_platform_options[@]}" "${source_platform_dir}/" "${target_platform_dir}/" 2>&1 | tr '\r' '\n' | while IFS= read -r rsync_progress_line; do
      [[ -n "${rsync_progress_line}" ]] || continue

      if [[ "${rsync_progress_line}" =~ ^[[:space:]]*([0-9,]+)[[:space:]]+([0-9]+)%[[:space:]]+([^[:space:]]+)[[:space:]]+([0-9:]+) ]]; then
        copied_amount="${BASH_REMATCH[1]}"
        progress_percent="${BASH_REMATCH[2]}"
        transfer_speed="${BASH_REMATCH[3]}"
        transfer_duration="${BASH_REMATCH[4]}"

        copied_amount_numeric="${copied_amount//,/}"
        total_amount="?"

        if [[ "${copied_amount_numeric}" =~ ^[0-9]+$ ]] && ((progress_percent > 0)); then
          total_amount="$((copied_amount_numeric * 100 / progress_percent))"
        fi

        printf '\r[%d] %s -> %s [PROGRESS] %s/%s %s%% %s %s' \
          "${platform_count}" "${source_platform}" "${target_platform}" \
          "${copied_amount}" "${total_amount}" "${progress_percent}" "${transfer_speed}" "${transfer_duration}"
      fi
    done
    printf '\n'
  fi

  copied_count=$((copied_count + 1))
done

if [[ "${dry_run}" == true ]]; then
  printf 'Done (dry-run). Reviewed %d platform folder(s).\n' "${copied_count}"
else
  printf 'Done. Copied %d platform folder(s).\n' "${copied_count}"
fi

printf 'Skipped %d unmapped platform(s).\n' "${skipped_unmapped_count}"
printf 'Skipped %d platform(s) due to missing destination folder.\n' "${skipped_missing_target_count}"
