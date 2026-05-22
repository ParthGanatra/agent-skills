#!/usr/bin/env bash
# Fetch YouTube video metadata + auto-caption transcript, cleaned.
# Writes to ~/.cache/yt-summary/latest.txt with format:
#   <id>|<title>|<channel>|<upload_date>|<duration_seconds>|<url>
#   ---CHAPTERS---
#   <chapters JSON array: [{"start_time","end_time","title"}, ...]  or  "NA" if none>
#   ---TRANSCRIPT---
#   <cleaned transcript text>
# Also prints the same content to stdout for piping.
#
# Usage: fetch-transcript.sh <youtube-url>
# Env:   BROWSER (default: chrome) — browser to pull cookies from on first run / refresh
#
# Cookies are cached at ~/.cache/yt-summary/cookies.txt (netscape format) to avoid
# keychain prompts on every run. If the cached cookies fail auth, the script
# automatically refreshes them from $BROWSER (triggers one keychain prompt).

set -euo pipefail

URL="${1:-}"
if [[ -z "$URL" ]]; then
  echo "usage: $0 <youtube-url>" >&2
  exit 1
fi

BROWSER="${BROWSER:-chrome}"
CACHE_DIR="$HOME/.cache/yt-summary"
COOKIES="$CACHE_DIR/cookies.txt"
OUTPUT="$CACHE_DIR/latest.txt"
mkdir -p "$CACHE_DIR"

if ! command -v yt-dlp >/dev/null 2>&1; then
  echo "error: yt-dlp not installed. brew install yt-dlp" >&2
  exit 1
fi

TMPDIR_=$(mktemp -d -t yt-summary.XXXXXX)
trap 'rm -rf "$TMPDIR_"' EXIT

refresh_cookies() {
  echo "info: refreshing cookies from $BROWSER (keychain may prompt)" >&2
  yt-dlp --cookies-from-browser "$BROWSER" --cookies "$COOKIES" \
    --skip-download --no-simulate --print id "$URL" \
    >/dev/null 2>"$TMPDIR_/refresh.err" || {
      echo "error: cookie refresh failed:" >&2
      cat "$TMPDIR_/refresh.err" >&2
      return 1
    }
}

run_yt_dlp() {
  yt-dlp \
    --cookies "$COOKIES" \
    --skip-download \
    --no-simulate \
    --write-auto-sub \
    --sub-lang en \
    --sub-format vtt \
    -o "$TMPDIR_/yt.%(ext)s" \
    --print "%(id)s|%(title)s|%(channel)s|%(upload_date)s|%(duration)s|%(webpage_url)s" \
    --print "%(chapters)j" \
    "$URL" >"$TMPDIR_/meta.txt" 2>"$TMPDIR_/yt.err"
}

# Ensure we have a cookies file; refresh if missing
if [[ ! -s "$COOKIES" ]]; then
  refresh_cookies
fi

# Try with cached cookies; if it fails with an auth error, refresh and retry once
if ! run_yt_dlp; then
  if grep -qi -e "sign in" -e "confirm you" -e "not a bot" "$TMPDIR_/yt.err"; then
    refresh_cookies
    run_yt_dlp || { cat "$TMPDIR_/yt.err" >&2; exit 1; }
  else
    cat "$TMPDIR_/yt.err" >&2
    exit 1
  fi
fi

if [[ ! -s "$TMPDIR_/meta.txt" ]]; then
  echo "error: yt-dlp succeeded but produced no metadata" >&2
  cat "$TMPDIR_/yt.err" >&2
  exit 1
fi

VTT=$(ls "$TMPDIR_"/yt.en.vtt 2>/dev/null | head -1 || true)
if [[ -z "$VTT" ]]; then
  echo "error: no English captions found (auto or manual). Video may have captions disabled or in another language." >&2
  exit 1
fi

# Build the output: header + chapters + cleaned transcript.
# meta.txt is two lines: line 1 = pipe-delimited header, line 2 = chapters JSON
# (a JSON array of {start_time,end_time,title}, or "null" if the video has none).
{
  sed -n '1p' "$TMPDIR_/meta.txt"
  echo "---CHAPTERS---"
  sed -n '2p' "$TMPDIR_/meta.txt"
  echo "---TRANSCRIPT---"
  # Strip VTT formatting:
  #   - skip header lines (WEBVTT, Kind:, Language:, blank)
  #   - skip timestamp lines (contain -->)
  #   - strip inline <c>...</c> and <00:00:00.000> tags
  #   - dedupe consecutive identical lines (auto-captions repeat heavily)
  awk '
    /^WEBVTT|^Kind:|^Language:|^$/ { next }
    /-->/ { next }
    { print }
  ' "$VTT" \
    | sed -E 's/<[^>]*>//g' \
    | awk '!seen[$0]++'
} | tee "$OUTPUT"
