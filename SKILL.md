---
name: cr-reply
description: >-
  Fetch the open code-review (CR) threads on a GitHub PR, verify each finding
  against the branch, draft a reply per thread in the user's voice, let the user
  approve, edit, or skip every draft through a structured question form, then
  post the approved ones with a "Posted by <agent> on behalf of @login" footer.
  Use when the user asks to reply to / answer / respond to review comments, CR
  comments, a reviewer's or bot's threads on a PR, to post review replies on
  their behalf, or to build or refresh their reply voice from their own past PR
  comments.
---

# CR reply

Posts nothing until the user picks **Post** for a specific draft in the question form. That selection is the explicit approval; no other message counts.

Scripts live in `scripts/` next to this file. `<skill-dir>` below is the directory that contains this `SKILL.md`. Run the scripts, don't reimplement them. Any personal rules the user has about GitHub account, writing voice, or disclaimers apply on top of this skill.

State lives in `${CR_REPLY_HOME:-$HOME/.config/cr-reply}`: `voice.md`, `corrections.md`, `will-fix.log`, `runs.log`.

## Workflow

### 1. Account

`gh api user --jq .login` and confirm it is the account the user posts from on this repo (their personal rules or the repo's conventions may name one; several accounts can be logged into `gh`). If not, `gh auth switch --user <login>` and re-check. Keep that login: every `reply.sh` call passes it as `--as <login>` so a switch in between cannot post as someone else.

### 2. Fetch

State home: `home="${CR_REPLY_HOME:-$HOME/.config/cr-reply}"`.

First list open will-fix promises for this PR:

```bash
grep -F "${repo}#${pr}" "$home/will-fix.log" 2>/dev/null || true
```

Show them in chat before the threads (so the user sees what they already promised).

```bash
bash <skill-dir>/scripts/fetch-threads.sh <pr> [--repo owner/name] [--from LOGIN] [--all] [--since ISO]
```

- Default: unresolved review threads where the active account is not the last replier, plus human-authored review summaries `[R*]` and conversation comments `[C*]`.
- `--from LOGIN` when the user names a reviewer or bot (`someone`, `cursor[bot]`). Only this unhides top-level bot posts.
- `--all` to include resolved threads and threads the active account already answered.
- `--since <iso>` when the user asks what's new, or on a repeat run: use the timestamp of the last `runs.log` line for this PR. A default first run still shows everything unanswered.

Each thread line carries `reply_to=<id>` and `thread=<id>`; `[R*]`/`[C*]` items use target `pr`. Pass `thread=` to `reply.sh --resolve` when resolving.

### 3. Verify every finding against the branch

```bash
bash <skill-dir>/scripts/pr-context.sh <pr> -- <every file flagged in step 2>
```

Prints the real base (stacked PRs don't base on the default branch), the local worktree or a `git show <sha>:<path>` fallback, the commits (shas for `Fixed in …`), the diff stat, the diff of the flagged files (introduced here vs pre-existing), and the PR body (claims the PR makes). Then, per thread:

- read the whole function around the flagged line, not just the line
- follow every `file:line` the reviewer cites; bot findings carry a "Why this was flagged" block with the exact references to check
- classify: valid and unfixed → will-fix shape and name the fix in one clause · already fixed → `Fixed in <sha>` · not in the diff → `Not introduced in this PR…` · overclaim → push back + disposition · same root cause flagged twice (two bots) → full answer once, one-line cross-reference on the other

Never guess. If a claim can't be confirmed from the code, say so in the reply or skip the thread.

### 4. Fix first

If any finding is valid and unfixed, ask once before drafting — multi-select question tool (or chat equivalent):

- `title` = `PR #<n> fix before reply?`
- `prompt` = `Which findings should be fixed in code before drafting replies?`
- one option per finding: `T1: <fix in one clause>`
- plus `none` → "None, reply will-fix for all"

For each picked finding: make the change per the repo's rules, run the smallest relevant check, and commit only if the user's / repo's commit rules allow it. If the agent may not commit, hand over the diff and wait for the user's commit. Then `git rev-parse --short HEAD` and draft `Fixed in <sha>.` (+ one sentence). Note in the final report if the commit is not pushed yet.

Unpicked valid findings get will-fix drafts.

### 5. Draft

Voice, first match wins: `$home/voice.md` if it exists (see "Building a voice" below) → a personal writing-voice rule the user already has → the default register: 1–2 sentences, plain language, contractions are fine, lead with the disposition, read like a teammate and not like a review bot, no throat-clearing ("Thanks for the thorough review…"). No footer in drafts.

| Situation | Shape |
| --- | --- |
| Fixed | `Fixed in <sha>.` + one sentence on what changed |
| Taking the suggestion | `Good catch, will fix.` + the fix in one clause |
| Agree, out of scope | what stays in this PR + where the rest goes (follow-up, ticket) |
| Pre-existing | `Not introduced in this PR` + whether it gets a separate look |
| Disagree, leaving it | `Fair point, but …` + the reason in one sentence + `Not taking this one here.` |
| Clarify | the question, plainly + current behavior in one sentence |
| Duplicate finding | `Same root cause as <other thread>, fixing it there.` |

"Reply to every CR" means will-fix replies are wanted for valid unfixed findings (unless step 4 already fixed them); otherwise skip those and list them at the end.

### 6. Approve / edit

First a chat message, so the user can judge each draft without re-reading the code: per item, one line of verified facts (what the code does, which claim holds or doesn't), then the draft as a blockquote, labelled `[T1]`-style.

Then ask with the agent's structured question tool (Cursor `AskQuestion`, Claude Code `AskUserQuestion`); without one, ask in chat with the same numbered items and wait for an explicit per-item answer. One form per ~8 items:

- `title` = `PR #<n> CR replies (pick Other to replace a draft with your own text)`
- one question per item, `id` = the label (`T1`, `R2`, …), single choice
- `prompt` = `[T1] <file>:<line> · @<reviewer> (<severity if any>): <one-line gist of their ask>` + blank line + the full draft
- `options` = `post` → "Post as drafted", `skip` → "Skip"
- "Other" is the edit channel. The user's text replaces the draft verbatim; do not polish it.
- Only if the Other text clearly reads as an instruction rather than a reply ("shorter", "mention the follow-up ticket", a question to you), redraft that item and re-ask it alone.
- A cancelled form posts nothing; ask what should change instead of re-sending it as is.

### 7. Post

One call per approved item; the script appends the footer using the live login and the detected agent (`CURSOR_AGENT` → Cursor, `CLAUDECODE` → Claude Code, otherwise pass `--via "<agent name>"`):

```bash
bash <skill-dir>/scripts/reply.sh <pr> <reply_to|pr> --as <login> [--repo owner/name] [--promise "<clause>"] [--resolve <thread>] <<'EOF'
<approved body, no footer>
EOF
```

- Will-fix replies: pass `--promise "<the one-clause fix>"` so the ledger records it.
- `--resolve <thread>` only when the user asked to resolve, and only on `Fixed in` replies. Never resolve by default.
- When posting a `Fixed in` reply whose `reply_to` has an open line in `will-fix.log`, delete that line (promise kept).

Footer shape: `<sub>Posted by <agent> on behalf of @<login></sub>`. Use `--dry-run` to preview the exact body when in doubt. Quote the heredoc (`<<'EOF'`) so backticks survive.

### 8. Learn

For every item answered via *Other*, append to `$home/corrections.md`:

```markdown
## <repo>#<pr> [T3] <file>:<line> · @<reviewer> · <YYYY-MM-DD>
> <reviewer's ask, clipped>

Draft:
<draft>

Said:
<user text verbatim>
```

Fold when 3+ entries sit after the last `<!-- folded … -->` marker and `$home/voice.md` exists:

1. Add the user's text as a Real example under the matching situation (replace the oldest of that situation when it already has 2).
2. Change the Reply-shapes row when the shape itself differs.
3. Add a Hard avoid when the same thing was removed in 2+ corrections.
4. Append `<!-- folded <YYYY-MM-DD> -->` after the folded entries.

Never edit a personal voice rule. If that is the voice in use, suggest migrating it into `$home/voice.md` once corrections pile up. With no voice at all, corrections seed the next build.

### 9. Report

Append one line to `$home/runs.log`:

```text
<utc>	<repo>#<pr>	posted=<n>	edited=<n>	skipped=<n>
```

If over the last five lines for any PR `edited >= posted`, suggest a voice rebuild.

Then list: posted replies with URLs, skipped items, promises recorded, voice changes made, and any unpushed `Fixed in` commits.

## Building a voice

When the user asks to build or refresh their voice (or when drafting without one and they want their own):

1. Gather their past replies, each paired with the comment it answered:

   ```bash
   bash <skill-dir>/scripts/gather-voice.sh [--org NAME | --repo owner/name] [--limit 40] > /tmp/voice-corpus.md
   ```

   Default scope is the org of the current repo. Read the whole corpus. Also read `$home/corrections.md` when it exists and treat each Said block as an extra reply sample.
2. Fill `<skill-dir>/voice-template.md` from the corpus only: openers and closers they actually type, how they agree, defer, push back and own mistakes, length by situation, reply shapes in their own words, 8–15 verbatim examples spread across situations, and hard avoids (what the corpus never does that drafts tend to add). Keep their grammar and idioms; discard entries that are tool output posted from their account.
3. Save it to `$home/voice.md`, summarize what you inferred in chat, and ask them to cut anything that isn't them.

More replies in the corpus means a richer, less generic voice. If the script reports under ~15, say so and offer `--limit` / `--org` before building. Suggest a rebuild when their replies start to drift from the file, or when runs.log shows a rising edit rate.

## Never

- Post anything that was not approved in the form, including "small" fixes to an approved body.
- Put the footer in drafts; the script adds it at post time.
- Resolve threads unless the user asked, and then only with a `Fixed in` reply. Never edit or delete existing comments, approve, or request changes.
- Post from an unverified account; a wrong-account comment cannot be deleted.
