#!/usr/bin/env bash
# Extract slide images from a YouTube video for slide-aware summaries.
# OPT-IN: only run this when the user asks for slides to be included.
#
# Two-phase workflow (the video is downloaded once and cached):
#
#   1. PROBE — inspect the layout so you can pick crop rectangles:
#        fetch-slides.sh <url> --probe
#      Dumps ~6 evenly-spaced sample frames to <cache>/probe/ and prints paths.
#      Read those frames to find (a) the slide region and (b) a clean interior
#      sub-region with no speaker PiP / animated background (used for change
#      detection). ffmpeg crop syntax is W:H:X:Y (width:height:x-offset:y-offset).
#
#   2. EXTRACT — detect slide changes and save full slides + contact sheets:
#        fetch-slides.sh <url> --detect-crop W:H:X:Y --save-crop W:H:X:Y
#      --detect-crop : tight interior region used ONLY to detect changes
#                      (omit = full frame; but PiP/animation cause false changes)
#      --save-crop   : region saved as the slide image (omit = full frame)
#      Optional: --gap N (collapse changes closer than N s; default 4)
#                --fps N (detection sample rate; default 1)
#                --thresh "hi:lo:frac" (mpdecimate; default 640:256:0.2)
#
# Outputs (under ~/.cache/yt-summary/slides/<id>/):
#   final/slide_NN_tSSSS.jpg  — one image per unique slide (NN=index, SSSS=secs)
#   sheets/sheet_NN.jpg       — 2x3 contact sheets for fast triage
#   manifest.txt              — "<index> <seconds> <filename>" per slide
# The manifest path is printed to stdout on success.
#
# Usage:   fetch-slides.sh <youtube-url> (--probe | --detect-crop ... --save-crop ...)
# Env:     BROWSER (default: chrome) — browser to pull cookies from on refresh
# Cookies: shared with fetch-transcript.sh at ~/.cache/yt-summary/cookies.txt

set -euo pipefail

URL="${1:-}"
if [[ -z "$URL" ]]; then
  echo "usage: $0 <youtube-url> (--probe | --detect-crop W:H:X:Y --save-crop W:H:X:Y)" >&2
  exit 1
fi
shift

MODE=""
DETECT_CROP=""
SAVE_CROP=""
GAP=4
FPS=1
THRESH="640:256:0.2"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --probe)       MODE="probe"; shift ;;
    --detect-crop) DETECT_CROP="$2"; MODE="extract"; shift 2 ;;
    --save-crop)   SAVE_CROP="$2"; MODE="extract"; shift 2 ;;
    --gap)         GAP="$2"; shift 2 ;;
    --fps)         FPS="$2"; shift 2 ;;
    --thresh)      THRESH="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "error: pass --probe, or --detect-crop/--save-crop to extract" >&2
  exit 1
fi

for bin in yt-dlp ffmpeg ffprobe; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: $bin not installed (brew install $bin)" >&2; exit 1; }
done

BROWSER="${BROWSER:-chrome}"
CACHE_DIR="$HOME/.cache/yt-summary"
COOKIES="$CACHE_DIR/cookies.txt"
mkdir -p "$CACHE_DIR"

# Resolve the video id (also refreshes cookies if needed).
get_id() {
  yt-dlp --cookies "$COOKIES" --skip-download --print id "$URL" 2>/dev/null
}
if [[ ! -s "$COOKIES" ]]; then
  echo "info: refreshing cookies from $BROWSER (keychain may prompt)" >&2
  yt-dlp --cookies-from-browser "$BROWSER" --cookies "$COOKIES" --skip-download --print id "$URL" >/dev/null 2>&1 || true
fi
VID="$(get_id || true)"
if [[ -z "$VID" ]]; then
  echo "info: id lookup failed, refreshing cookies from $BROWSER" >&2
  yt-dlp --cookies-from-browser "$BROWSER" --cookies "$COOKIES" --skip-download --print id "$URL" >/dev/null 2>&1
  VID="$(get_id)"
fi
[[ -n "$VID" ]] || { echo "error: could not resolve video id" >&2; exit 1; }

WORK="$CACHE_DIR/slides/$VID"
mkdir -p "$WORK"
VIDEO="$WORK/video1080.mp4"

# Download once (1080p — needed for legible code/diagrams), cache for reuse.
if [[ ! -s "$VIDEO" ]]; then
  echo "info: downloading 1080p video (cached for reuse)..." >&2
  yt-dlp --cookies "$COOKIES" \
    -f "bestvideo[height<=1080][ext=mp4]/bestvideo[height<=1080]/best[height<=1080]" \
    -o "$VIDEO" "$URL" >&2
else
  echo "info: reusing cached video at $VIDEO" >&2
fi

DUR="$(ffprobe -v error -select_streams v:0 -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO" 2>/dev/null || echo 0)"
DUR="${DUR%.*}"

if [[ "$MODE" == "probe" ]]; then
  rm -rf "$WORK/probe" && mkdir -p "$WORK/probe"
  echo "info: dumping sample frames (duration ${DUR}s)..." >&2
  for frac in 5 20 35 50 70 90; do
    t=$(( DUR * frac / 100 ))
    ffmpeg -hide_banner -ss "$t" -i "$VIDEO" -frames:v 1 -q:v 2 "$WORK/probe/probe_t${t}.jpg" -y 2>/dev/null
  done
  echo "PROBE FRAMES (read these to choose --detect-crop and --save-crop):"
  ls -1 "$WORK"/probe/*.jpg
  exit 0
fi

# --- extract mode ---
[[ -n "$SAVE_CROP" ]] || SAVE_CROP="${DETECT_CROP}"   # fall back to detect crop if save not given
DET_FILTER="fps=${FPS},mpdecimate=hi=${THRESH%%:*}:lo=$(echo "$THRESH" | cut -d: -f2):frac=${THRESH##*:},showinfo"
[[ -n "$DETECT_CROP" ]] && DET_FILTER="crop=${DETECT_CROP},${DET_FILTER}"

echo "info: detecting slide changes..." >&2
LOG="$WORK/detect_log.txt"
ffmpeg -hide_banner -i "$VIDEO" -vf "$DET_FILTER" -vsync vfr -f null - 2>"$LOG"

# collapse near-adjacent changes: keep the last timestamp of each cluster (settled slide)
# (read loop instead of mapfile — macOS ships bash 3.2, which has no mapfile)
TS=()
while IFS= read -r _line; do
  [[ -n "$_line" ]] && TS+=("$_line")
done < <(grep -oE 'pts_time:[0-9.]+' "$LOG" | sed 's/pts_time://;s/\..*//')
COLLAPSED=()
if [[ ${#TS[@]} -gt 0 ]]; then
  last="${TS[0]}"
  for ((i=1; i<${#TS[@]}; i++)); do
    if (( TS[i] - last > GAP )); then COLLAPSED+=("$last"); fi
    last="${TS[i]}"
  done
  COLLAPSED+=("$last")
fi
echo "info: ${#COLLAPSED[@]} unique slides detected" >&2

rm -rf "$WORK/final" "$WORK/sheets" && mkdir -p "$WORK/final" "$WORK/sheets"
: > "$WORK/manifest.txt"
SAVE_FILTER=""
[[ -n "$SAVE_CROP" ]] && SAVE_FILTER="-vf crop=${SAVE_CROP}"
idx=0
for t in "${COLLAPSED[@]}"; do
  idx=$((idx+1))
  fn=$(printf "slide_%02d_t%04d.jpg" "$idx" "$t")
  ffmpeg -hide_banner -ss "$t" -i "$VIDEO" -frames:v 1 $SAVE_FILTER -q:v 2 "$WORK/final/$fn" -y 2>/dev/null
  printf "%d %d %s\n" "$idx" "$t" "$fn" >> "$WORK/manifest.txt"
done

# contact sheets: 2 cols x 3 rows, scaled for legibility
ffmpeg -hide_banner -pattern_type glob -i "$WORK/final/slide_*.jpg" \
  -vf "scale=820:-1,tile=2x3:padding=8:margin=8:color=0x222222" \
  -q:v 3 "$WORK/sheets/sheet_%02d.jpg" 2>/dev/null || true

echo "SLIDES: $WORK/final/ ($(ls "$WORK"/final/*.jpg 2>/dev/null | wc -l | tr -d ' ') images)"
echo "SHEETS: $WORK/sheets/"
echo "MANIFEST: $WORK/manifest.txt"
