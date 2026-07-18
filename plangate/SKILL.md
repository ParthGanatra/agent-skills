---
name: plangate
description: >-
  Use for any non-trivial task with 2+ open decisions/tradeoffs OR multiple
  implementation steps — instead of deliberating one question at a time in chat,
  write a structured plan to a file and let the user review it inline in vim with
  `> Q:` / `> A:` blockquote markers, then revise until agreed before touching any code. Triggers on
  feature planning, design/architecture decisions, refactors, or multi-step work.
  Auto-propose it when a task hits the 2+-decisions bar; the user can opt out by
  saying "just answer". Do NOT use for a single simple question.
---

# PlanGate — terminal-native plan-review loop

Batch the decisions into a reviewable plan file instead of forcing the user through
one-by-one chat. The user reviews in vim; their `:w` is the signal; you resolve and
revise; no code until it's agreed. Full background & prior art: see the repo README.

**Review markers (the contract).** Everything the user reviews is markdown blockquotes:
- `> Q:` — a question / decision / anything needing the user's input. **Whenever you write a
  `> Q:` line, put an empty `> A:` line directly under it** so the user jumps in and types the
  answer with no marker typing (their vim has `]a` to jump to the next empty `> A:` and start typing).
- `> A:` — the answer. The user fills the empty slot; you fill it when *replying* to a `> Q:` the
  user raised.
- **An open item = an empty `> A:` slot** (`^\s*> A:\s*$`), plus any `> Q:` the user added with no
  `> A:` under it. The loop is done when every `> Q:` has a non-empty `> A:` beneath it.
- Blockquotes keep the plan valid markdown (renders fine in Obsidian/GitHub) and — with the bundled
  vim reading setup (see README) — highlight `> Q:` vs `> A:`, with `]q`/`[q` to page between open questions.

Helper scripts live beside this file:
- `open-plan.sh <file>` — open/focus the plan in a right-side vim pane (its own pane; never hijacks the user's working vim).
- `wait-save.sh <file> [max_s]` — block until the user saves; run it in the BACKGROUND so their `:w` re-invokes you.
- `nudge-reload.sh` — after you edit the plan, refresh the user's vim (`:checktime` + autoread) to show your `> A:` answers.
- `prune-plans.sh <plans-dir> [days]` — delete plan files untouched for N days (default 7). Run it once per plan, at step 2.

## When to fire
- 2+ open decisions/tradeoffs, or multiple implementation steps → propose the loop.
- One simple/single-answer question → just answer, no plan.
- If the user says "just answer" / "skip the plan" → drop the loop for that task.

## Loop

1. **Scope it.** Feature comes from the `/plangate <description>` argument if given, else infer it
   from the conversation and confirm your one-line summary before writing.

2. **Pick the path, then prune.** In a git repo → `.plans/<slug>.md` at the repo root; otherwise
   `~/.plans/<slug>.md`. `<slug>` is a short kebab-case name. **First time** you create a
   plan in a git repo, add `.plans/` to its `.gitignore` (and mention it).
   Then run `prune-plans.sh <plans-dir>` before writing the new plan — it deletes plans
   untouched for 7 days (finished or abandoned; an in-review plan's mtime is bumped by every
   `:w`, so it survives). Mention anything it pruned. Override with `PLAN_RETENTION_DAYS`.

3. **Write the plan — a design doc *and* a decision surface, with decisions up front.**
   The reader asked for this plan minutes ago and reviews it fresh — they already know the goal,
   so don't re-explain the ask or pad with background. Spend words on what they can't already
   know: the **decisions**, the **open questions**, and non-obvious design findings.
   - **Order:** `Goal (≤3 lines) → Decisions → Open questions → Approach → Steps → Risks / unknowns`.
     Keep a terse Goal on top for orientation, then hit the decisions immediately — don't bury them
     under a long exposition. Approach / Steps / Risks still carry the full design below.
   - **Context budget:** restating what the user asked for = cut. A background fact earns its place
     only if it's non-obvious *and* bears on a decision — put it inside that decision block, not a
     standalone exposition section. Findings that shape the whole design can live in Approach.
   - Open the file with a short header telling the user how to review (markers below).
   - Pose every real choice as a **decision block** (the checkbox / "input" pattern):
     ```
     ### Decision: <title>
     - [ ] Option A — one-line tradeoff
     - [ ] Option B — one-line tradeoff
     > Q: pick one (check the box) or comment. Recommend A because…
     > A:
     ```
     Options are one-line tradeoffs, not paragraphs; always give a recommendation and leave the
     empty `> A:` line so the user jumps straight to typing.
   - Genuinely leave decisions open — don't pre-resolve to avoid review.

4. **Open it:** run `open-plan.sh <path>`.

5. **Wait for review:** launch `wait-save.sh <path>` in the BACKGROUND. The user's `:w` will
   fire it and re-invoke you. (Typing "reviewed" is a manual fallback.)

6. **Resolve (each round).** On the save signal, re-read the file and find open items —
   `grep -nE '^\s*> A:\s*$'` (empty answer slots) plus any `> Q:` the user added with no `> A:` below:
   - The user's `> A:` text answers your questions; their `> Q:` lines are new comments/instructions
     (`> Q: DELETE …` = cut that scope, `> Q: REPLACE: …` = proposed change). Apply ticked `[x]` decisions.
   - Revise the plan inline. **Fill every `> A:` you owe** (answering a user `> Q:`), and for anything
     still needing the user, add a fresh `> Q:` + empty `> A:` pair. Leave the user's answered
     `> Q:`/`> A:` exchanges in place as the record.
   - Run `nudge-reload.sh` so their vim shows your changes.
   - **Post a short chat summary of what changed** — inline edits are invisible in chat.
   - Re-launch `wait-save.sh` in the background for the next round. Repeat until no empty `> A:`
     slots remain, every `> Q:` has an answer, and no decisions are unticked.

7. **Gate.** Do NOT write code or make implementation edits until BOTH: no open items (every
   `> Q:` has a non-empty `> A:`, no empty slots) AND the user explicitly approves (e.g. "approved",
   "go build it", "lgtm").
   If the user wants to bypass planning for a quick change, honor "just answer".

8. **Build.** Once gated through, implement against the agreed plan.

## Notes
- The `> Q:` / `> A:` markers and decision blocks are the whole contract — keep them consistent,
  and always pair a `> Q:` with an empty `> A:` beneath it.
- The save-signal means the user has no unsaved changes at resolve time, so `nudge-reload.sh`
  refreshes safely; `:checktime` won't clobber if they've started editing again.
- If `wait-save.sh` reports `TIMEOUT`, the review is just still open — re-launch it or check in.
- **Portability:** the scripts are best in tmux + vim/nvim on macOS or Linux. Outside tmux, `open-plan.sh`
  prints the path for you to open manually and `nudge-reload.sh` is a silent no-op; `wait-save.sh` is
  plain mtime-polling and works in any editor that writes to disk.
