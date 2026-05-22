---
name: youtube-summary
description: Summarize a YouTube video into a structured Obsidian note. Use when the user shares a YouTube URL and asks for a summary, takeaways, or notes — or invokes `/youtube-summary <url>`. Fetches the transcript via yt-dlp, writes the note into the user's configured Obsidian vault, and opens it in Obsidian. Optionally extracts and embeds slides on request.
---

# youtube-summary

Turn a YouTube video into a structured note in the user's Obsidian vault.

## When to use
- User pastes a YouTube URL and asks for a summary / takeaways / notes
- User invokes `/youtube-summary <url>`
- User says something like "write this up", "save this video", etc. with a YouTube link

By default, summaries are built from the **transcript only**. If the user says the
video has important **slides** (or asks to "include the slides", "the slides
matter", a slide-heavy conference talk, etc.), also run the **opt-in slide flow**
in the section below. Do **not** extract slides unless the user asks for this
video specifically — it downloads the full video (~hundreds of MB) and is slow.

## Configuration (one-time)

The target vault is **not** hardcoded — resolve it at runtime:

```bash
~/.claude/skills/youtube-summary/resolve-config.sh
```

It prints `VAULT_NAME`, `VAULT_PATH`, `NOTES_SUBFOLDER`, and `NOTES_DIR` (the
absolute notes folder). Use those values everywhere below — this doc writes
`$NOTES_DIR`, `$VAULT_NAME`, etc. as placeholders for what the resolver returns.

If the resolver exits non-zero (unconfigured), it prints setup instructions.
Help the user create `~/.config/youtube-summary/config.sh` (template:
`config.example.sh` next to this SKILL.md): ask for their Obsidian vault name,
its absolute path, and the notes subfolder, then write the file and re-run the
resolver. Env vars `OBSIDIAN_VAULT_NAME` / `OBSIDIAN_VAULT_PATH` /
`NOTES_SUBFOLDER` override the file for one-off runs.

- Filename: `<video title>.md` (sanitize: replace `/` with `-`, strip leading/trailing whitespace, no quotes)

## Procedure

### 0. Resolve config
Run `resolve-config.sh` (above) and note `NOTES_DIR`, `VAULT_NAME`, and
`NOTES_SUBFOLDER` for the steps below.

### 1. Fetch transcript + metadata
Run the helper script next to this SKILL.md:

```bash
~/.claude/skills/youtube-summary/fetch-transcript.sh "<url>"
```

It writes the output to `~/.cache/yt-summary/latest.txt` (and also prints to stdout). Format:
- Line 1: `ID|TITLE|CHANNEL|UPLOAD_DATE|DURATION_SECONDS|URL`
- `---CHAPTERS---`
- A chapters JSON array (`[{"start_time","end_time","title"}, ...]`) or `NA` if the video has no chapters
- `---TRANSCRIPT---`
- Rest: cleaned transcript text

Cookies are cached at `~/.cache/yt-summary/cookies.txt` so the macOS Keychain only prompts on first run or when cookies expire. If YouTube auth fails, the script auto-refreshes from `$BROWSER` (default `chrome`). Override with `BROWSER=safari ~/.claude/skills/youtube-summary/fetch-transcript.sh "<url>"` if Chrome isn't your primary browser.

### 2. Read the transcript
Use the Read tool on `~/.cache/yt-summary/latest.txt` (already allowlisted — no permission prompt). The transcript is auto-captioned so expect typos — fix obvious ones in the summary using context (e.g. "Cloud Code" → "Claude Code", "JGC" → "ZGC", brand/product names, technical terms).

**Chapters:** if the `---CHAPTERS---` section is a JSON array (not `NA`), use the chapter titles (in order) as the **section structure** for the "Key takeaways" headings — they're the author's own outline. Map transcript content into each chapter's `[start_time, end_time)` window, and (for slide videos) align slides by their timestamp too. If chapters are `NA`, fall back to inferring 3-6 topical headings yourself.

### 3. Write the note
Create the file at `$NOTES_DIR/<title>.md` (create `$NOTES_DIR` if it doesn't exist) using this template:

```markdown
---
title: <video title>
speaker: <speaker name if identifiable from transcript, else omit>
channel: <channel>
url: <url>
published: <YYYY-MM-DD from upload_date>
duration: <Hh Mm Ss or Mm Ss>
watched: <today's date YYYY-MM-DD>
tags:
  - youtube
  - <topic tags inferred from content, 2-5 tags>
---

# <title>

## TL;DR
<2-3 sentences. The actual thesis of the talk, not generic platitudes.>

## Key takeaways

### <topical heading 1>
- <specific, concrete points — name the libraries, versions, numbers, trade-offs>
- <not vague — "they use ZGC" is bad; "Generational ZGC is now default; G1 had ~1.5s pauses causing IPC timeouts → retries" is good>

### <topical heading 2>
- ...

(Headings = the video's chapter titles when it has them; otherwise 3-6 topical headings you infer from the talk structure.)

## Read more / related

- **<resource name>** — <one-line why it matters>: <url>
- ... (5-12 items: official docs, JEPs, blog posts the speaker referenced, related Obsidian notes via [[wikilinks]])

## Open questions / things to dig into
- <thing the speaker glossed over that the user might want to explore>
- <POC ideas, things to try in our own stack>
```

### 4. Open in Obsidian
Use the configured vault name and notes subfolder (URL-encode the path):
```bash
open "obsidian://open?vault=$VAULT_NAME&file=$NOTES_SUBFOLDER/<title>.md"
```
Or, if the Obsidian CLI is installed and enabled, `obsidian open path="$NOTES_SUBFOLDER/<title>.md"`.

## Slide-aware summaries (opt-in)

Only when the user asks to include slides for a specific video. Slides capture
diagrams, code, charts, and bullet text the speaker shows but never says — and
they're a safety net when the auto-caption transcript is truncated.

Prereqs: `ffmpeg` + `ffprobe` (e.g. `brew install ffmpeg`). The helper reuses the
same cookie cache as `fetch-transcript.sh`.

### S1. Probe the layout
```bash
~/.claude/skills/youtube-summary/fetch-slides.sh "<url>" --probe
```
Downloads a 1080p copy (cached) and dumps ~6 sample frames to
`~/.cache/yt-summary/slides/<id>/probe/`. **Read those frames** with the Read
tool to determine the recording's layout, then choose two crop rectangles
(ffmpeg `W:H:X:Y` = width:height:x-offset:y-offset):
- **`--detect-crop`**: a *tight interior* slide sub-region with no speaker
  picture-in-picture and no animated background. Used only for change detection;
  a moving speaker or animated border makes every frame look "changed".
- **`--save-crop`**: the full slide region to save as the image (exclude the
  speaker PiP and any fiery/animated chrome, but keep the whole slide).

If slides fill the frame edge-to-edge with no PiP/animation, you can omit the
crops (defaults to full frame).

### S2. Extract slides + contact sheets
```bash
~/.claude/skills/youtube-summary/fetch-slides.sh "<url>" \
  --detect-crop W:H:X:Y --save-crop W:H:X:Y
```
Writes one image per unique slide to `final/`, 2x3 contact sheets to `sheets/`,
and `manifest.txt` (`<index> <seconds> <filename>`). Tune with `--gap N`
(collapse changes < N s apart; default 4), `--fps N`, `--thresh hi:lo:frac`.

### S3. Read sheets, then curate
Read the `sheets/sheet_*.jpg` contact sheets (6 slides each, row-major) to
transcribe content and map the deck. Many slides are incremental builds of the
same slide — pick the **settled/most-complete** version of each. Aim to embed
the genuinely informative slides (diagrams, charts, unique code), not every
build. Read individual `final/` images at full resolution when code/diagrams
need precise transcription.

### S4. Copy chosen slides into the vault + embed
Copy the curated slides into a sibling folder of the note, renaming to unique,
descriptive names (prefix with a short video slug so filenames stay unique
vault-wide):
```
$NOTES_DIR/<slug>-slides/<slug>-NN-description.jpg
```
Embed inline at the relevant point in the note with `![[<slug>-NN-description.jpg]]`
(Obsidian resolves by filename). Put the slide image next to its transcription —
e.g. the diagram image followed by a short prose description, or the code-slide
image followed by the same code in a fenced block.

### S5. Cleanup
Delete the cached `video1080.mp4` (and any `slides_out`/`detect`/`probe` scratch)
when done — keep `final/` and `sheets/` only if useful. The video is the large
artifact.

Note in the front-matter or a callout that slides were merged in, and if the
transcript was truncated say which sections came from slides only.

## Style rules for the summary

- **Be specific, not generic.** Concrete library names, version numbers, latency numbers, JEP numbers. If the speaker says "we saw lower errors", quantify if they did; if not, say "significantly" not "much".
- **Capture the *interesting* parts.** What's the non-obvious insight, the counter-intuitive trade-off, the gotcha? Skip filler ("they have many users", "they use microservices") unless it's load-bearing.
- **Fix auto-caption errors.** Watch for: product names ("Cloud Code" → "Claude Code"), acronyms ("JGC" → "ZGC"), homophones ("there/their"), hallucinated punctuation.
- **Read more links must be real.** Only include URLs you're confident exist — official docs, JEPs, well-known project pages. If the speaker referenced a blog post you can't verify the URL for, write the search query instead: `search "Spring One Paul Bakker testing" on YouTube`.
- **Use `[[wikilinks]]`** to seed connections to existing or future notes in the vault.
- **One-line YAML tags** — lowercase, kebab-case, 2-5 topic tags beyond the always-present `youtube`.

## Notes
- All paths come from `resolve-config.sh` (env vars or `~/.config/youtube-summary/config.sh`). Nothing vault-specific is hardcoded in this skill — keep it that way so it stays publishable.
- On macOS the filesystem is case-insensitive, so match the casing of `NOTES_SUBFOLDER` to the user's existing folder to avoid creating a near-duplicate.
- Opening via the `obsidian://` URI works without extra setup. The `obsidian open` CLI alternative requires the Obsidian CLI enabled (Settings → General → CLI) with the `obsidian` binary on `$PATH`.
