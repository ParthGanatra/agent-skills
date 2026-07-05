#!/usr/bin/env bash
# Fetch YouTube video metadata + English transcript, cleaned.
# Subtitles: prefers MANUAL (human-written) captions, falls back to AUTO-generated.
# Writes to ~/.cache/yt-summary/latest.txt with format:
#   <id>|<title>|<channel>|<upload_date>|<duration_seconds>|<url>
#   ---CHAPTERS---
#   <chapters JSON array: [{"start_time","end_time","title"}, ...]  or  "NA" if none>
#   ---TRANSCRIPT---
#   <cleaned transcript text>
# Also prints the same content to stdout for piping.
#
# Usage: fetch-transcript.sh <youtube-url>
# Env:   BROWSER (default: chrome) — browser (optionally browser:profile, e.g.
#          "chrome:Default") to pull cookies from on first run / refresh.
#        YTDLP   — path to a yt-dlp binary to force (skips the managed one below).
#
# Cookies are cached at ~/.cache/yt-summary/cookies.txt (netscape format) to avoid
# keychain prompts on every run. If the cached cookies fail auth, the script
# automatically refreshes them from $BROWSER (triggers one keychain prompt).
#
# yt-dlp: YouTube now gates the player response behind checks that a stale yt-dlp
# fails ("Sign in to confirm you're not a bot" / "No title found in player
# responses"). Homebrew/pip copies drift out of date fast, so this script keeps a
# fresh standalone binary at ~/.cache/yt-summary/yt-dlp and auto-refreshes it when
# it's older than 30 days, falling back to a system yt-dlp only if that fails.

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

TMPDIR_=$(mktemp -d -t yt-summary.XXXXXX)
trap 'rm -rf "$TMPDIR_"' EXIT

# Resolve a yt-dlp binary into $YTDLP, preferring a fresh standalone binary in the
# cache. A stale yt-dlp is the #1 cause of spurious "not a bot" failures.
ensure_ytdlp() {
  if [[ -n "${YTDLP:-}" && -x "${YTDLP:-}" ]]; then return; fi
  local bin="$CACHE_DIR/yt-dlp"
  # Reuse the cached standalone binary if it's fresh (<30 days old).
  if [[ -x "$bin" && -z "$(find "$bin" -mtime +30 2>/dev/null)" ]]; then
    YTDLP="$bin"; return
  fi
  # (Re)download a fresh standalone binary for this platform.
  local url=""
  case "$(uname -s)" in
    Darwin) url="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" ;;
    Linux)  url="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux" ;;
  esac
  if [[ -n "$url" ]] && command -v curl >/dev/null 2>&1; then
    echo "info: refreshing yt-dlp standalone binary ($bin)" >&2
    if curl -fsSL "$url" -o "$bin.tmp" && chmod +x "$bin.tmp"; then
      mv "$bin.tmp" "$bin"; YTDLP="$bin"; return
    fi
    rm -f "$bin.tmp"
    echo "warn: could not download fresh yt-dlp; falling back" >&2
  fi
  # Fallbacks: a stale cached binary, then a system yt-dlp.
  if [[ -x "$bin" ]]; then YTDLP="$bin"; return; fi
  if command -v yt-dlp >/dev/null 2>&1; then YTDLP="$(command -v yt-dlp)"; return; fi
  echo "error: yt-dlp not available and could not be downloaded (need curl + network)" >&2
  exit 1
}
ensure_ytdlp

refresh_cookies() {
  echo "info: refreshing cookies from $BROWSER (keychain may prompt)" >&2
  local attempt
  for attempt in 1 2; do
    if "$YTDLP" --cookies-from-browser "$BROWSER" --cookies "$COOKIES" \
        --skip-download --no-simulate --print id "$URL" \
        >/dev/null 2>"$TMPDIR_/refresh.err"; then
      return 0
    fi
    # Hard-fail only when cookie *extraction* broke (keychain / browser DB /
    # permissions). A bot-check on the validation fetch is transient — if the
    # cookie jar was still written, keep it; the real fetch usually gets through.
    if grep -qiE "could not copy|unable to|permission|no such|database|could not find" "$TMPDIR_/refresh.err"; then
      echo "error: cookie refresh failed:" >&2
      cat "$TMPDIR_/refresh.err" >&2
      return 1
    fi
    if [[ -s "$COOKIES" ]]; then
      echo "warn: cookie validation fetch failed (likely a transient bot-check); using extracted cookies" >&2
      return 0
    fi
  done
  echo "error: cookie refresh failed:" >&2
  cat "$TMPDIR_/refresh.err" >&2
  return 1
}

# YouTube's bot-check is applied per-request and per-player-client, so rotating
# through a few clients dramatically improves the odds when one gets flagged.
# Override with YT_CLIENTS="a b c" if a particular client works best for you.
read -r -a YT_CLIENTS <<< "${YT_CLIENTS:-default tv web_safari mweb ios}"

# One yt-dlp attempt for a given player client + subtitle mode
# ($2 = --write-subs for manual/human captions, or --write-auto-subs for
# auto-generated). Always prints metadata + chapters; writes yt.en*.vtt if the
# requested subtitles exist. Returns yt-dlp's exit code.
_ytdlp_attempt() {
  local client="$1" submode="$2"
  "$YTDLP" \
    --cookies "$COOKIES" \
    --extractor-args "youtube:player_client=$client" \
    --extractor-retries 2 \
    --socket-timeout 20 \
    --skip-download \
    --no-simulate \
    "$submode" \
    --sub-langs "en.*,en" \
    --sub-format vtt \
    -o "$TMPDIR_/yt.%(ext)s" \
    --print "%(id)s|%(title)s|%(channel)s|%(upload_date)s|%(duration)s|%(webpage_url)s" \
    --print "%(chapters)j" \
    "$URL" >"$TMPDIR_/meta.txt" 2>"$TMPDIR_/yt.err"
}

_have_vtt() { ls "$TMPDIR_"/yt.en*.vtt >/dev/null 2>&1; }

# Rotate clients; for each working client PREFER MANUAL (human-written) English
# subtitles, falling back to AUTO-generated ones. Manual captions are cleaner (no
# ASR typos) and some channels (e.g. 3Blue1Brown) ship manual subs with no
# auto-captions at all. Returns 0 once metadata is fetched; the caller validates
# that a subtitle file actually landed.
run_yt_dlp() {
  local client
  for client in "${YT_CLIENTS[@]}"; do
    rm -f "$TMPDIR_"/yt.en*.vtt "$TMPDIR_/meta.txt" 2>/dev/null || true
    # Pass 1: manual/human subtitles. A bot-check here -> try the next client.
    _ytdlp_attempt "$client" --write-subs || continue
    [[ -s "$TMPDIR_/meta.txt" ]] || continue
    _have_vtt && return 0                      # got manual subs — preferred
    # Pass 2: same client, auto-generated subtitles as fallback.
    _ytdlp_attempt "$client" --write-auto-subs || true
    return 0                                   # meta good; subs are auto or absent
  done
  return 1
}

# Ensure we have a cookies file; refresh if missing
if [[ ! -s "$COOKIES" ]]; then
  refresh_cookies
fi

# If YouTube is hard-blocking (bot-check survives cookies + client rotation +
# retries), the escalation is a PO-token provider. Print how to enable it.
botcheck_hint() {
  cat >&2 <<'HINT'

hint: YouTube is demanding a PO token (bot-check survived valid cookies + client
      rotation). This usually clears on its own after a while (often self-inflicted
      by too many requests in a short window). For a permanent fix install a PO
      token provider — see:
      https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide
HINT
}

# Try with cached cookies; if it fails with an auth error, refresh and retry once
if ! run_yt_dlp; then
  if grep -qi -e "sign in" -e "confirm you" -e "not a bot" "$TMPDIR_/yt.err"; then
    refresh_cookies
    run_yt_dlp || { cat "$TMPDIR_/yt.err" >&2; botcheck_hint; exit 1; }
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

# Prefer the plain `en` file (manual subs land here) but accept regional variants
# like en-US / en-GB from the "en.*" match.
VTT=$(ls "$TMPDIR_"/yt.en.vtt 2>/dev/null | head -1 || true)
[[ -z "$VTT" ]] && VTT=$(ls "$TMPDIR_"/yt.en*.vtt 2>/dev/null | head -1 || true)
if [[ -z "$VTT" ]]; then
  echo "error: no English captions found (manual or auto). Video may have captions disabled or in another language." >&2
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
