#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: nixstead media transcode [options] <input_dir> [output_dir]

Converts video files under <input_dir> to an efficient codec with quality/size
controls for reduced storage usage.

IMPORTANT:
  Use either --codec OR --codec-profile (not both).

Options:
  -c, --codec <av1|hevc>       Explicit codec choice (balanced defaults)
  -p, --codec-profile <name>   Profile choice: quality|balance|size
  -g, --gpu                    Use NVIDIA GPU encoder (NVENC)
  -f, --faster                 Shorthand for --faster-level 1
  -l, --faster-level <1|2|3>   Faster encode level (higher = faster, larger files)
  -r, --replace                Replace original with converted file on success
  -i, --interactive            Prompt for encoding settings and stream selection
  -k, --check                  Validate existing converted output only (no conversion)
  -s, --strict-check           In check mode, run full decode scan and frame counting
  -n, --dry-run                Show planned actions without converting/replacing
  -h, --help                   Show this help text

Codec profile defaults (AV1):
  quality                      AV1 CRF 24, preset 3 (best quality)
  balance                      AV1 CRF 30, preset 4 (default)
  size                         AV1 CRF 36, preset 6 (smallest size)

Codec defaults (when using --codec):
  av1                          CRF 30, preset 4
  hevc                         CRF 23, preset slow

GPU mode notes:
  - Uses NVENC encoders: av1_nvenc or hevc_nvenc
  - Uses VBR quality mode with CQ value (mapped from CRF)
  - Requires ffmpeg built with NVENC and a supported NVIDIA GPU

General defaults:
  - If neither option is set, --codec-profile balance is used.
  - Container: MKV
  - Audio: Opus 96k
  - Output naming: <name>.<codec>.mkv

Faster levels preset mapping:
  AV1:  level 1 -> preset 6, level 2 -> preset 8, level 3 -> preset 10
  HEVC: level 1 -> preset medium, level 2 -> preset fast, level 3 -> preset faster

Environment overrides:
  VIDEO_CODEC=av1|hevc
  VIDEO_PROFILE=quality|balance|size
  VIDEO_CRF=<number>
  VIDEO_PRESET=<value>
  AUDIO_BITRATE=<value>        (default: 96k)

Examples:
  nixstead media transcode /media/videos
  nixstead media transcode --codec av1 /media/videos
  nixstead media transcode -c hevc -n /media/videos
  nixstead media transcode --codec-profile quality /media/videos
  nixstead media transcode -p size -r /media/videos
  nixstead media transcode -g -c av1 /media/videos
  nixstead media transcode -i /media/videos
  nixstead media transcode --check /media/videos
EOF
}

require_cmd() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    printf 'Error: required command not found: %s\n' "${command_name}" >&2
    exit 1
  fi
}

is_video_file() {
  local file_name_lower
  file_name_lower="${1,,}"
  case "${file_name_lower}" in
    *.mp4 | *.mkv | *.mov | *.avi | *.wmv | *.flv | *.webm | *.m4v | *.ts | *.mts | *.m2ts | *.mpg | *.mpeg)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

prompt_with_default() {
  local label="$1"
  local default_value="$2"
  local input

  read -rp "${label} [${default_value}]: " input
  if [[ -z "${input}" ]]; then
    printf '%s' "${default_value}"
  else
    printf '%s' "${input}"
  fi
}

show_streams() {
  local file_path="$1"
  local stream_type="$2"

  ffprobe \
    -v error \
    -select_streams "${stream_type}" \
    -show_entries stream=index,codec_name,channels,channel_layout:stream_tags=language,title \
    -of csv=p=0 \
    "${file_path}" || true
}

build_interactive_maps() {
  local file_path="$1"

  selected_audio_map_args=()
  selected_subtitle_map_args=()

  printf '\n[INFO] Stream selection for: %s\n' "${file_path}"

  local audio_streams
  audio_streams="$(show_streams "${file_path}" "a")"
  if [[ -n "${audio_streams}" ]]; then
    echo "Available audio streams:"
    echo "${audio_streams}" | nl -w2 -s'. '
    local audio_input
    audio_input="$(prompt_with_default "Select audio stream indexes (comma-separated or 'all')" "all")"

    if [[ "${audio_input}" == "all" ]]; then
      selected_audio_map_args+=("-map" "0:a?")
    elif [[ -n "${audio_input}" ]]; then
      IFS=',' read -r -a audio_indexes <<<"${audio_input}"
      for audio_index in "${audio_indexes[@]}"; do
        audio_index="${audio_index//[[:space:]]/}"
        if [[ -n "${audio_index}" ]]; then
          selected_audio_map_args+=("-map" "0:${audio_index}")
        fi
      done
    fi
  else
    selected_audio_map_args+=("-map" "0:a?")
  fi

  local subtitle_streams
  subtitle_streams="$(show_streams "${file_path}" "s")"
  if [[ -n "${subtitle_streams}" ]]; then
    echo "Available subtitle streams:"
    echo "${subtitle_streams}" | nl -w2 -s'. '
    local subtitle_input
    subtitle_input="$(prompt_with_default "Select subtitle stream indexes (comma-separated, 'all', or 'none')" "all")"

    if [[ "${subtitle_input}" == "all" ]]; then
      selected_subtitle_map_args+=("-map" "0:s?")
    elif [[ "${subtitle_input}" == "none" ]]; then
      :
    elif [[ -n "${subtitle_input}" ]]; then
      IFS=',' read -r -a subtitle_indexes <<<"${subtitle_input}"
      for subtitle_index in "${subtitle_indexes[@]}"; do
        subtitle_index="${subtitle_index//[[:space:]]/}"
        if [[ -n "${subtitle_index}" ]]; then
          selected_subtitle_map_args+=("-map" "0:${subtitle_index}")
        fi
      done
    fi
  else
    selected_subtitle_map_args+=("-map" "0:s?")
  fi
}

set_profile_defaults() {
  local profile="$1"

  case "${profile}" in
    quality | guqality)
      codec="av1"
      video_encoder="libsvtav1"
      video_crf_default="24"
      video_preset_default="3"
      encoder_extra_args=("-svtav1-params" "tune=0")
      ;;
    balance)
      codec="av1"
      video_encoder="libsvtav1"
      video_crf_default="30"
      video_preset_default="4"
      encoder_extra_args=("-svtav1-params" "tune=0")
      ;;
    size)
      codec="av1"
      video_encoder="libsvtav1"
      video_crf_default="36"
      video_preset_default="6"
      encoder_extra_args=("-svtav1-params" "tune=0")
      ;;
    *)
      printf 'Error: unsupported codec profile: %s\n' "${profile}" >&2
      printf 'Use one of: quality, balance, size\n' >&2
      exit 1
      ;;
  esac
}

set_codec_defaults() {
  local codec_value="$1"

  case "${codec_value}" in
    av1)
      codec="av1"
      video_encoder="libsvtav1"
      video_crf_default="30"
      video_preset_default="4"
      encoder_extra_args=("-svtav1-params" "tune=0")
      ;;
    hevc)
      codec="hevc"
      video_encoder="libx265"
      video_crf_default="23"
      video_preset_default="slow"
      encoder_extra_args=()
      ;;
    *)
      printf 'Error: unsupported codec: %s (use av1 or hevc)\n' "${codec_value}" >&2
      exit 1
      ;;
  esac
}

get_duration_seconds_ffmpeg() {
  local file_path="$1"
  local duration_hms

  duration_hms="$(ffmpeg -nostdin -i "${file_path}" 2>&1 | awk '/Duration:/ { gsub(",", "", $2); print $2; exit }' || true)"

  if [[ -z "${duration_hms}" || "${duration_hms}" == "N/A" ]]; then
    return 1
  fi

  awk -F: -v hms="${duration_hms}" 'BEGIN {
    split(hms, t, ":");
    if (length(t) != 3) {
      exit 1
    }
    printf "%.3f", (t[1] * 3600) + (t[2] * 60) + t[3]
  }'
}

truncate_cell() {
  local value="$1"
  local width="$2"

  if ((${#value} > width)); then
    printf '%s…' "${value:0:width-1}"
  else
    printf '%s' "${value}"
  fi
}

format_size_human() {
  local bytes="$1"
  awk -v b="${bytes}" 'BEGIN {
    split("B KiB MiB GiB TiB", units, " ")
    i = 1
    while (b >= 1024 && i < 5) {
      b = b / 1024
      i++
    }
    printf "%.2f %s", b, units[i]
  }'
}

get_video_codec() {
  local file_path="$1"
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${file_path}" 2>/dev/null | head -n 1 || true
}

get_video_frame_count() {
  local file_path="$1"
  local strict_mode="${2:-false}"
  local frame_count

  if [[ "${strict_mode}" == "true" ]]; then
    frame_count="$(ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames,nb_frames -of default=noprint_wrappers=1:nokey=1 "${file_path}" 2>/dev/null | awk 'NF && $1 != "N/A" { print $1; exit }' || true)"
  else
    frame_count="$(ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames -of default=noprint_wrappers=1:nokey=1 "${file_path}" 2>/dev/null | awk 'NF && $1 != "N/A" { print $1; exit }' || true)"
  fi

  if [[ -n "${frame_count}" ]]; then
    printf '%s' "${frame_count}"
  else
    printf '%s' "n/a"
  fi
}

get_audio_tracks_list() {
  local file_path="$1"
  local tracks

  tracks="$(ffprobe -v error -select_streams a -show_entries stream=index,codec_name:stream_tags=language,title -of csv=p=0 "${file_path}" 2>/dev/null | awk -F',' 'BEGIN { OFS="" }
    {
      idx=$1
      codec=$2
      lang=($3==""?"und":$3)
      title=$4
      item="#" idx " " codec " (" lang
      if (title != "") {
        item=item ", " title
      }
      item=item ")"
      list = (list == "" ? item : list "; " item)
    }
    END {
      if (list == "") print "none"
      else print list
    }' || true)"

  printf '%s' "${tracks:-none}"
}

get_subtitle_tracks_list() {
  local file_path="$1"
  local tracks

  tracks="$(ffprobe -v error -select_streams s -show_entries stream=index,codec_name:stream_tags=language,title -of csv=p=0 "${file_path}" 2>/dev/null | awk -F',' 'BEGIN { OFS="" }
    {
      idx=$1
      codec=$2
      lang=($3==""?"und":$3)
      title=$4
      item="#" idx " " codec " (" lang
      if (title != "") {
        item=item ", " title
      }
      item=item ")"
      list = (list == "" ? item : list "; " item)
    }
    END {
      if (list == "") print "none"
      else print list
    }' || true)"

  printf '%s' "${tracks:-none}"
}

get_file_size_display() {
  local file_path="$1"
  local file_size_bytes

  file_size_bytes="$(stat -c '%s' "${file_path}" 2>/dev/null || true)"
  if [[ -z "${file_size_bytes}" ]]; then
    printf '%s' "n/a"
    return
  fi

  printf '%s (%s)' "${file_size_bytes}" "$(format_size_human "${file_size_bytes}")"
}

print_comparison_row() {
  local label="$1"
  local source_value="$2"
  local target_value="$3"

  printf '| %-20s | %-58s | %-58s |\n' \
    "$(truncate_cell "${label}" 20)" \
    "$(truncate_cell "${source_value}" 58)" \
    "$(truncate_cell "${target_value}" 58)"
}

validate_conversion_output() {
  local source_path="$1"
  local target_path="$2"
  local strict_mode="${3:-false}"
  local source_duration
  local target_duration
  local duration_delta="n/a"
  local source_codec
  local target_codec
  local source_frames
  local target_frames
  local source_size
  local target_size
  local source_audio_tracks
  local target_audio_tracks
  local source_subtitle_tracks
  local target_subtitle_tracks
  local status="OK"
  local reasons=()

  source_duration="$(get_duration_seconds_ffmpeg "${source_path}" || true)"
  target_duration="$(get_duration_seconds_ffmpeg "${target_path}" || true)"

  source_codec="$(get_video_codec "${source_path}")"
  target_codec="$(get_video_codec "${target_path}")"
  source_frames="$(get_video_frame_count "${source_path}" "${strict_mode}")"
  target_frames="$(get_video_frame_count "${target_path}" "${strict_mode}")"
  source_size="$(get_file_size_display "${source_path}")"
  target_size="$(get_file_size_display "${target_path}")"
  source_audio_tracks="$(get_audio_tracks_list "${source_path}")"
  target_audio_tracks="$(get_audio_tracks_list "${target_path}")"
  source_subtitle_tracks="$(get_subtitle_tracks_list "${source_path}")"
  target_subtitle_tracks="$(get_subtitle_tracks_list "${target_path}")"

  if [[ -z "${target_duration}" ]]; then
    target_duration="n/a"
    status="FAIL"
    reasons+=("Missing converted duration metadata")
  elif [[ -n "${source_duration}" ]]; then
    duration_delta="$(awk -v source="${source_duration}" -v target="${target_duration}" 'BEGIN { d=source-target; if (d<0) d=-d; printf "%.3f", d }')"
    if ! awk -v delta="${duration_delta}" 'BEGIN { exit !(delta <= 2.0) }'; then
      status="FAIL"
      reasons+=("Duration mismatch (>2.0s)")
    fi
  fi

  if ! ffmpeg -nostdin -v error -xerror -i "${target_path}" -map 0:v:0 -frames:v 1 -f null - >/dev/null 2>&1; then
    status="FAIL"
    reasons+=("No decodable video stream")
  fi

  if [[ "${strict_mode}" == "true" ]]; then
    if ! ffmpeg -nostdin -v error -xerror -i "${target_path}" -map 0 -f null - >/dev/null 2>&1; then
      status="FAIL"
      reasons+=("Decode fault detected")
    fi
  fi

  local compare_table_sep="|----------------------|------------------------------------------------------------|------------------------------------------------------------|"
  printf '%s\n' "${compare_table_sep}"
  printf '| %-20s | %-58s | %-58s |\n' "Field" "Original" "Converted"
  printf '%s\n' "${compare_table_sep}"
  print_comparison_row "Path" "${source_path}" "${target_path}"
  print_comparison_row "Duration (s)" "${source_duration:-n/a}" "${target_duration:-n/a}"
  print_comparison_row "Duration delta (s)" "-" "${duration_delta}"
  print_comparison_row "Frame count" "${source_frames}" "${target_frames}"
  print_comparison_row "File size" "${source_size}" "${target_size}"
  print_comparison_row "Video codec" "${source_codec:-n/a}" "${target_codec:-n/a}"
  print_comparison_row "Audio tracks" "${source_audio_tracks}" "${target_audio_tracks}"
  print_comparison_row "Subtitle tracks" "${source_subtitle_tracks}" "${target_subtitle_tracks}"
  print_comparison_row "Status" "-" "${status}"

  if [[ "${status}" == "FAIL" ]]; then
    print_comparison_row "Issues" "-" "${reasons[*]}"
  fi

  printf '%s\n' "${compare_table_sep}"

  if [[ "${status}" == "OK" ]]; then
    return 0
  fi

  return 1
}

codec_arg=""
profile_arg=""
replace_mode=false
dry_run=false
interactive_mode=false
check_mode=false
strict_check=false
use_gpu=false
faster_mode=false
faster_level=""
positional_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c | --codec)
      if [[ $# -lt 2 ]]; then
        printf 'Error: --codec requires a value\n' >&2
        exit 1
      fi
      codec_arg="$2"
      shift
      ;;
    -p | --codec-profile)
      if [[ $# -lt 2 ]]; then
        printf 'Error: --codec-profile requires a value\n' >&2
        exit 1
      fi
      profile_arg="$2"
      shift
      ;;
    -r | --replace)
      replace_mode=true
      ;;
    -i | --interactive)
      interactive_mode=true
      ;;
    -k | --check)
      check_mode=true
      ;;
    -s | --strict-check)
      strict_check=true
      ;;
    -n | --dry-run)
      dry_run=true
      ;;
    -g | --gpu)
      use_gpu=true
      ;;
    -f | --faster)
      faster_mode=true
      ;;
    -l | --faster-level)
      if [[ $# -lt 2 ]]; then
        printf 'Error: --faster-level requires a value (1, 2, or 3)\n' >&2
        exit 1
      fi
      faster_level="$2"
      faster_mode=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        positional_args+=("$1")
        shift
      done
      break
      ;;
    -*)
      printf 'Error: unknown option: %s\n\n' "$1" >&2
      usage
      exit 1
      ;;
    *)
      positional_args+=("$1")
      ;;
  esac
  shift
done

set -- "${positional_args[@]}"

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

if [[ -n "${codec_arg}" && -n "${profile_arg}" ]]; then
  printf 'Error: use either --codec or --codec-profile, not both\n' >&2
  exit 1
fi

if [[ -n "${codec_arg}" && -n "${VIDEO_PROFILE:-}" ]]; then
  printf 'Error: --codec conflicts with VIDEO_PROFILE\n' >&2
  exit 1
fi

if [[ -n "${profile_arg}" && -n "${VIDEO_CODEC:-}" ]]; then
  printf 'Error: --codec-profile conflicts with VIDEO_CODEC\n' >&2
  exit 1
fi

if [[ -z "${codec_arg}" && -z "${profile_arg}" && -n "${VIDEO_CODEC:-}" && -n "${VIDEO_PROFILE:-}" ]]; then
  printf 'Error: VIDEO_CODEC and VIDEO_PROFILE are both set; use only one\n' >&2
  exit 1
fi

if [[ "${strict_check}" == "true" && "${check_mode}" != "true" ]]; then
  printf 'Error: --strict-check requires --check\n' >&2
  exit 1
fi

require_cmd ffmpeg
require_cmd ffprobe
require_cmd find
require_cmd realpath
require_cmd mktemp

input_dir="$1"
if [[ ! -d "${input_dir}" ]]; then
  printf 'Error: input directory not found: %s\n' "${input_dir}" >&2
  exit 1
fi

if ! input_dir="$(realpath "${input_dir}")"; then
  printf 'Error: failed to resolve input directory path: %s\n' "$1" >&2
  exit 1
fi

selection_source=""
selected_profile=""

if [[ -n "${codec_arg}" ]]; then
  selection_source="codec"
  set_codec_defaults "${codec_arg}"
elif [[ -n "${profile_arg}" ]]; then
  selection_source="profile"
  selected_profile="${profile_arg}"
  set_profile_defaults "${selected_profile}"
elif [[ -n "${VIDEO_CODEC:-}" ]]; then
  selection_source="codec"
  set_codec_defaults "${VIDEO_CODEC}"
elif [[ -n "${VIDEO_PROFILE:-}" ]]; then
  selection_source="profile"
  selected_profile="${VIDEO_PROFILE}"
  set_profile_defaults "${selected_profile}"
else
  selection_source="profile"
  selected_profile="balance"
  set_profile_defaults "${selected_profile}"
fi

video_crf="${VIDEO_CRF:-${video_crf_default}}"
video_preset="${VIDEO_PRESET:-${video_preset_default}}"
audio_bitrate="${AUDIO_BITRATE:-96k}"

if [[ "${interactive_mode}" == "true" ]]; then
  echo "==> Interactive encoding setup"

  if [[ -z "${codec_arg}" && -z "${profile_arg}" && -z "${VIDEO_CODEC:-}" && -z "${VIDEO_PROFILE:-}" ]]; then
    codec_choice="$(prompt_with_default "Codec (av1/hevc)" "${codec}")"
    set_codec_defaults "${codec_choice}"
    codec="${codec_choice}"
    selection_source="codec"
    selected_profile=""
  fi

  gpu_input="$(prompt_with_default "Use GPU mode (yes/no)" "$([[ "${use_gpu}" == "true" ]] && echo yes || echo no)")"
  if [[ "${gpu_input}" == "yes" ]]; then
    use_gpu=true
  else
    use_gpu=false
  fi

  replace_input="$(prompt_with_default "Replace original files after success (yes/no)" "$([[ "${replace_mode}" == "true" ]] && echo yes || echo no)")"
  if [[ "${replace_input}" == "yes" ]]; then
    replace_mode=true
  else
    replace_mode=false
  fi

  faster_input="$(prompt_with_default "Use faster mode (yes/no)" "$([[ "${faster_mode}" == "true" ]] && echo yes || echo no)")"
  if [[ "${faster_input}" == "yes" ]]; then
    faster_mode=true
    faster_level="$(prompt_with_default "Faster level (1/2/3)" "${faster_level:-1}")"
  else
    faster_mode=false
    faster_level=""
  fi

  video_crf="$(prompt_with_default "Quality value (CRF/CQ)" "${video_crf}")"
  audio_bitrate="$(prompt_with_default "Audio bitrate" "${audio_bitrate}")"
fi

if [[ "${use_gpu}" == "true" ]]; then
  if [[ "${codec}" == "av1" ]]; then
    video_encoder="av1_nvenc"
    if ! ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "av1_nvenc"; then
      printf 'Error: --gpu requested but ffmpeg av1_nvenc encoder is unavailable\n' >&2
      exit 1
    fi
  else
    video_encoder="hevc_nvenc"
    if ! ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "hevc_nvenc"; then
      printf 'Error: --gpu requested but ffmpeg hevc_nvenc encoder is unavailable\n' >&2
      exit 1
    fi
  fi

  if [[ -z "${VIDEO_PRESET:-}" ]]; then
    video_preset="p6"
  fi
fi

if [[ "${faster_mode}" == "true" && -z "${VIDEO_PRESET:-}" ]]; then
  if [[ -z "${faster_level}" ]]; then
    faster_level="1"
  fi

  case "${faster_level}" in
    1)
      if [[ "${use_gpu}" == "true" ]]; then
        video_preset="p5"
      elif [[ "${codec}" == "av1" ]]; then
        video_preset="6"
      else
        video_preset="medium"
      fi
      ;;
    2)
      if [[ "${use_gpu}" == "true" ]]; then
        video_preset="p4"
      elif [[ "${codec}" == "av1" ]]; then
        video_preset="8"
      else
        video_preset="fast"
      fi
      ;;
    3)
      if [[ "${use_gpu}" == "true" ]]; then
        video_preset="p3"
      elif [[ "${codec}" == "av1" ]]; then
        video_preset="10"
      else
        video_preset="faster"
      fi
      ;;
    *)
      printf 'Error: invalid --faster-level: %s (use 1, 2, or 3)\n' "${faster_level}" >&2
      exit 1
      ;;
  esac
fi

replace_temp_dir=""
cleanup_replace_temp() {
  if [[ -n "${replace_temp_dir}" && -d "${replace_temp_dir}" ]]; then
    rm -rf -- "${replace_temp_dir}"
  fi
}

if [[ "${replace_mode}" == "true" ]]; then
  if [[ $# -eq 2 ]]; then
    printf 'Error: output_dir argument is not allowed with --replace\n' >&2
    exit 1
  fi

  if [[ "${dry_run}" == "true" ]]; then
    output_root="${input_dir}/.converted_${codec}_tmp.XXXXXX"
  else
    replace_temp_dir="$(mktemp -d --tmpdir="${input_dir}" ".converted_${codec}_tmp.XXXXXX")"
    output_root="${replace_temp_dir}"
    trap cleanup_replace_temp EXIT
  fi
else
  if [[ $# -eq 2 ]]; then
    output_root="$2"
  else
    output_root="${input_dir}/converted_${codec}"
  fi
fi

if [[ "${dry_run}" != "true" ]]; then
  mkdir -p "${output_root}"
  if ! output_root="$(realpath "${output_root}")"; then
    printf 'Error: failed to resolve output directory path: %s\n' "${output_root}" >&2
    exit 1
  fi
fi

planned=0
processed=0
checked=0
skipped=0
failed=0

if [[ "${check_mode}" != "true" ]]; then
  settings_table_sep="|------------------|----------------------------------------------------------------------|"
  printf '%s\n' "${settings_table_sep}"
  printf '| %-16s | %-68s |\n' "Setting" "Value"
  printf '%s\n' "${settings_table_sep}"
  printf '| %-16s | %-68s |\n' "Input directory" "${input_dir}"
  printf '| %-16s | %-68s |\n' "Output directory" "${output_root}"
  printf '| %-16s | %-68s |\n' "Selection" "${selection_source}${selected_profile:+ (${selected_profile})}"
  printf '| %-16s | %-68s |\n' "Codec" "${codec} (${video_encoder})"
  printf '| %-16s | %-68s |\n' "GPU mode" "${use_gpu}"
  printf '| %-16s | %-68s |\n' "CRF/CQ" "${video_crf}, Preset: ${video_preset}, Audio: ${audio_bitrate}"
  printf '| %-16s | %-68s |\n' "Replace original" "${replace_mode}"
  printf '| %-16s | %-68s |\n' "Check mode" "${check_mode}"
  printf '| %-16s | %-68s |\n' "Strict check" "${strict_check}"
  printf '| %-16s | %-68s |\n' "Dry run" "${dry_run}"
  printf '| %-16s | %-68s |\n' "Interactive mode" "${interactive_mode}"
  printf '| %-16s | %-68s |\n' "Faster mode" "${faster_mode}"
  printf '| %-16s | %-68s |\n' "Faster level" "${faster_level:-0}"
  printf '%s\n' "${settings_table_sep}"
fi

while IFS= read -r -d '' source_path; do
  if [[ "${source_path}" == "${output_root}/"* ]]; then
    continue
  fi

  if ! is_video_file "${source_path}"; then
    continue
  fi

  relative_path="${source_path#"${input_dir}"/}"
  relative_dir="$(dirname "${relative_path}")"
  base_name_no_ext="$(basename "${relative_path%.*}")"

  if [[ "${replace_mode}" == "true" ]]; then
    target_path="${output_root}/${relative_dir}/${base_name_no_ext}.mkv"
    final_path="${source_path%.*}.mkv"
  else
    target_path="${output_root}/${relative_dir}/${base_name_no_ext}.${codec}.mkv"
    final_path="${target_path}"
  fi

  if [[ "${replace_mode}" == "true" && "${source_path}" != "${final_path}" && -e "${final_path}" ]]; then
    echo "[FAIL] Replacement destination already exists: ${final_path}" >&2
    failed=$((failed + 1))
    continue
  fi

  if [[ "${dry_run}" != "true" ]]; then
    mkdir -p "$(dirname "${target_path}")"
  fi

  if [[ -f "${target_path}" ]]; then
    if [[ "${check_mode}" == "true" ]]; then
      if validate_conversion_output "${source_path}" "${target_path}" "${strict_check}"; then
        checked=$((checked + 1))
      else
        failed=$((failed + 1))
      fi
    else
      echo "[SKIP] Output exists: ${target_path}"
      skipped=$((skipped + 1))
    fi
    continue
  fi

  if [[ "${check_mode}" == "true" ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  planned=$((planned + 1))

  if [[ "${dry_run}" == "true" ]]; then
    echo "[PLAN] Convert: ${source_path} -> ${target_path}"
    if [[ "${replace_mode}" == "true" ]]; then
      echo "[PLAN] Replace original with converted: ${final_path}"
      echo "[PLAN] Delete original after success: ${source_path}"
    fi
    continue
  fi

  echo "[RUN ] ${source_path}"

  ffmpeg_base_args=(
    -hide_banner
    -loglevel error
    -stats
    -i "${source_path}"
    -map 0:v:0
  )

  if [[ "${interactive_mode}" == "true" ]]; then
    build_interactive_maps "${source_path}"
    if [[ "${#selected_audio_map_args[@]}" -gt 0 ]]; then
      ffmpeg_base_args+=("${selected_audio_map_args[@]}")
    else
      ffmpeg_base_args+=("-map" "0:a?")
    fi

    if [[ "${#selected_subtitle_map_args[@]}" -gt 0 ]]; then
      ffmpeg_base_args+=("${selected_subtitle_map_args[@]}")
    fi
  else
    ffmpeg_base_args+=("-map" "0:a?" "-map" "0:s?")
  fi

  ffmpeg_base_args+=(
    -map_metadata 0
  )

  if [[ "${use_gpu}" == "true" ]]; then
    ffmpeg_base_args+=(
      -c:v "${video_encoder}"
      -preset "${video_preset}"
      -rc vbr
      -cq "${video_crf}"
      -b:v 0
      -pix_fmt p010le
    )
  else
    ffmpeg_base_args+=(
      -c:v "${video_encoder}"
      -preset "${video_preset}"
      -crf "${video_crf}"
      -pix_fmt yuv420p10le
      "${encoder_extra_args[@]}"
    )
  fi

  conversion_succeeded=false

  if ffmpeg -nostdin "${ffmpeg_base_args[@]}" \
    -c:a libopus \
    -b:a "${audio_bitrate}" \
    -mapping_family 1 \
    -c:s copy \
    "${target_path}"; then
    conversion_succeeded=true
  else
    rm -f "${target_path}"
    echo "[WARN] Opus surround mapping failed, retrying with stereo downmix: ${source_path}"

    if ffmpeg -nostdin "${ffmpeg_base_args[@]}" \
      -c:a libopus \
      -b:a "${audio_bitrate}" \
      -ac 2 \
      -c:s copy \
      "${target_path}"; then
      conversion_succeeded=true
      echo "[WARN] Used stereo fallback for audio: ${source_path}"
    else
      rm -f "${target_path}"
      echo "[WARN] Opus fallback failed, retrying with original audio copy: ${source_path}"

      if ffmpeg -nostdin "${ffmpeg_base_args[@]}" \
        -c:a copy \
        -c:s copy \
        "${target_path}"; then
        conversion_succeeded=true
        echo "[WARN] Copied original audio stream(s): ${source_path}"
      fi
    fi
  fi

  if [[ "${conversion_succeeded}" == "true" ]]; then
    if validate_conversion_output "${source_path}" "${target_path}" false; then
      echo "[CHK ] Validation passed: ${target_path}"
    else
      failed=$((failed + 1))
      rm -f -- "${target_path}"
      echo "[FAIL] Validation failed: ${source_path}"
      continue
    fi

    if [[ "${replace_mode}" == "true" ]]; then
      mv -f -- "${target_path}" "${final_path}"
      if [[ "${source_path}" != "${final_path}" ]]; then
        rm -f -- "${source_path}"
      fi
      echo "[REP ] ${source_path} -> ${final_path}"
    else
      echo "[ OK ] ${target_path}"
    fi

    processed=$((processed + 1))
  else
    failed=$((failed + 1))
    rm -f "${target_path}"
    echo "[FAIL] ${source_path}"
  fi
done < <(find "${input_dir}" -type f -print0)

if [[ "${replace_mode}" == "true" && -n "${replace_temp_dir}" ]]; then
  cleanup_replace_temp
  trap - EXIT
  echo "[CLEAN] Removed temporary output directory: ${replace_temp_dir}"
fi

if [[ "${check_mode}" != "true" ]]; then
  summary_table_sep="|-----------|-------|"
  printf '%s\n' "${summary_table_sep}"
  printf '| %-9s | %-5s |\n' "Metric" "Count"
  printf '%s\n' "${summary_table_sep}"
  printf '| %-9s | %-5s |\n' "Planned" "${planned}"
  printf '| %-9s | %-5s |\n' "Converted" "${processed}"
  printf '| %-9s | %-5s |\n' "Checked" "${checked}"
  printf '| %-9s | %-5s |\n' "Skipped" "${skipped}"
  printf '| %-9s | %-5s |\n' "Failed" "${failed}"
  printf '%s\n' "${summary_table_sep}"
fi

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
