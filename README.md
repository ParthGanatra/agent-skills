# agent-skills

Agent skills for Claude Code, by [@ParthGanatra](https://github.com/ParthGanatra).

## Skills

### [`youtube-summary`](./youtube-summary)

Turn a YouTube video into a **structured note** — not a raw transcript dump, but a
real summary (TL;DR, key takeaways, read-more links, open questions), with the
video's own chapters used as the section structure when it has them. Works out of
the box (prints the note right in the conversation); point it at an **Obsidian
vault** to save it there instead.

Its distinctive feature: **opt-in slide extraction.** For slide-heavy talks, it
downloads the video, detects unique slides via crop-aware change detection,
transcribes their content (diagrams, code, charts) by vision, and **embeds the
key slides inline** in the note next to the prose. This also rescues summaries
when the auto-caption transcript is truncated — the slides carry the rest.

- Transcript + metadata + chapters via `yt-dlp`, with a cookie cache so YouTube
  auth/bot-checks only prompt once.
- Slides via `ffmpeg` (scene/`mpdecimate` change detection on a clean slide crop).
- Vault location is **configurable** — nothing is hardcoded.

**Requires:** `yt-dlp`, and (for slides) `ffmpeg` + `ffprobe`. macOS-oriented
(uses the `open obsidian://` URI and `--cookies-from-browser`).

## Install

Via the [skills.sh](https://www.skills.sh) CLI:

```bash
npx skills add ParthGanatra/agent-skills/youtube-summary
```

Or manually — copy the skill folder into your Claude Code skills directory:

```bash
git clone https://github.com/ParthGanatra/agent-skills
cp -r agent-skills/youtube-summary ~/.claude/skills/
```

## Configure (optional, for `youtube-summary`)

Works out of the box: with no config, the note is **printed in the conversation**
(no file written). If you ask for slides, it saves the note + images to the
current directory instead, since the images need to live on disk.

To save into your **Obsidian vault** instead (and embed slides as `![[wikilinks]]`),
tell the skill where the vault is:

```bash
mkdir -p ~/.config/youtube-summary
cp ~/.claude/skills/youtube-summary/config.example.sh ~/.config/youtube-summary/config.sh
$EDITOR ~/.config/youtube-summary/config.sh   # set vault name, path, notes subfolder
```

(Env vars `OBSIDIAN_VAULT_NAME` / `OBSIDIAN_VAULT_PATH` / `NOTES_SUBFOLDER`
override the file for one-off runs.)

## Use

In Claude Code:

- `/youtube-summary <url>` — or just paste a URL and ask for a summary.
- Add *"this one has slides"* / *"include the slides"* to trigger slide extraction
  for that specific video (it's off by default — slides mean a full video download).

## License

[MIT](./LICENSE)
