# agent-skills

Agent skills for Claude Code, by [@ParthGanatra](https://github.com/ParthGanatra).

## Skills

### [`plangate`](./plangate)

A **terminal-native plan-review loop.** Instead of your agent dumping a wall-of-text
plan into the chat (and you skimming it and saying "looks fine"), PlanGate writes the
plan to a file and lets you **review it inline in vim** — you answer questions and leave
comments right in the document, your `:w` re-invokes the agent to revise, and **no code
gets written until every question is answered and you approve.**

![PlanGate demo — answer a plan's questions inline in vim, `:w`, and the agent resolves them.](./assets/plangate-demo.gif)

Its distinctive angle: it never leaves the terminal. The whole review happens in your
editor — **your `:w` *is* the "reviewed" signal** (a background watcher re-invokes the
agent), the agent nudges vim to reload its answers, and there's a **hard gate** before
implementation. No browser round-trip, no separate UI, no MCP server.

- Everything the reviewer touches is a markdown blockquote: `> Q:` (a question, needs
  you) with an empty `> A:` under it (you type the answer — `]a` jumps you there).
- Decisions are checkbox blocks with a recommendation; you tick your pick or comment.
- Plans live in `.plans/<slug>.md` (auto-gitignored) and age-prune themselves.
- Bundled **vim reading setup** highlights `> Q:`/`> A:` and adds `]q`/`[q`/`]a` nav
  (see [PlanGate setup](#plangate-setup-vim-reading) — optional, colorscheme-agnostic).

**Requires:** tmux + vim/nvim for the full loop (macOS or Linux). Degrades gracefully
outside tmux — see [notes](#plangate-notes).

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
npx skills add ParthGanatra/agent-skills/plangate
npx skills add ParthGanatra/agent-skills/youtube-summary
```

Or manually — copy the skill folder into your Claude Code skills directory:

```bash
git clone https://github.com/ParthGanatra/agent-skills
cp -r agent-skills/plangate ~/.claude/skills/
cp -r agent-skills/youtube-summary ~/.claude/skills/
```

<a name="plangate-setup-vim-reading"></a>
## PlanGate setup (vim reading)

PlanGate works without any vim config — but the bundled reading setup makes the review
pane much nicer: it highlights `> Q:` (needs you) vs `> A:` (answered), soft-wraps prose,
and adds navigation (`]q`/`[q` between open questions, `]a` to jump to the next empty
answer and start typing). Colors link to your colorscheme's standard groups, so it adapts
to whatever theme you use. Copy the two files:

```bash
# vim
mkdir -p ~/.vim/after/ftplugin ~/.vim/after/syntax
cp ~/.claude/skills/plangate/vim/after/ftplugin/markdown.vim ~/.vim/after/ftplugin/
cp ~/.claude/skills/plangate/vim/after/syntax/markdown.vim   ~/.vim/after/syntax/

# neovim
mkdir -p ~/.config/nvim/after/ftplugin ~/.config/nvim/after/syntax
cp ~/.claude/skills/plangate/vim/after/ftplugin/markdown.vim ~/.config/nvim/after/ftplugin/
cp ~/.claude/skills/plangate/vim/after/syntax/markdown.vim   ~/.config/nvim/after/syntax/
```

These apply to **all** markdown you edit (the plan file is just markdown). To revert,
delete the two files.

<a name="plangate-notes"></a>
### PlanGate notes

- **Best in tmux + vim/nvim** on macOS or Linux. Outside tmux, the skill prints the plan
  path for you to open yourself and skips the auto-reload; the save-watcher is plain
  mtime-polling and works with any editor that writes to disk.
- Trigger it with `/plangate <description>`, or just let it auto-propose when a task has
  2+ open decisions or multiple steps. Say *"just answer"* to skip the loop for a task.

## Prior art & credits

PlanGate is a terminal-native distillation of ideas from three projects — full credit to
them. We adapted rather than adopted for one reason: we wanted the review to stay **in the
terminal (tmux + vim)**, with no browser round-trip.

- **[Lavish](https://github.com/kunchenguid/lavish-axi)** (Kun Chen) — opens agent-generated
  artifacts in a local browser to annotate and send feedback back to the agent. PlanGate keeps
  that annotate-and-return-to-agent loop but does it inline in vim instead of a browser.
- **[Huon Wilson's inline-feedback workflow](https://huonw.github.io/blog/2026/02/ai-plan/)** —
  splat `COMMENT:` lines into the plan, reject, and have the agent re-read and revise. PlanGate
  formalizes this into the `> Q:` / `> A:` blockquote contract with a `:w`-driven re-invoke.
- **[Plannotator](https://github.com/backnotprop/plannotator)** (backnotprop) — a browser-based
  review surface with annotation verbs and an approve/deny gate. PlanGate borrows the annotation
  verbs and the hard gate-before-code, minus the browser UI.

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
