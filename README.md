# cr-reply

An agent skill that answers code-review threads on a GitHub PR for you, without ever posting something you didn't approve. For those who prefer to be the meat in the loop.

The agent fetches the open review threads, checks each finding against the actual branch, drafts a short reply per thread in your voice, shows you every draft in a form where you can **post**, **skip**, or **replace it with your own text**, and then posts only the approved ones. Every posted reply ends with a footer that says who really typed it:

```markdown
Good catch, will fix. initCode() is being invoked twice in a recursive function. Silly me!

<sub>Posted by Cursor on behalf of @your-login</sub>
```

Works with Cursor and Claude Code (anything that loads `SKILL.md` folders). The scripts are plain bash on top of `gh`.

## How it works

```
  fetch-threads.sh          open CR threads (+ reply_to, thread)
         |
         v
  pr-context.sh             real base, worktree, diff of flagged files
         |
         v
  fix first?  --yes-->      change code -> Fixed in <sha>
         | no
         v
  draft                     your voice (will-fix or Fixed in)
         |
         v
  form                      post / skip / Other (your text)
         |
         +-- Other -------> corrections.md  (later folds into voice)
         |
         v
  reply.sh                  footer + post
                            --promise (will-fix) / --resolve (opt-in)
         |
         v
  report                    runs.log + URLs + open promises
```

1. **Account check.** `gh api user` must be the account you post from on that repo. The login is pinned for the rest of the run.
2. **Fetch.** Unresolved review threads where you are not the last replier, plus human-written review summaries and PR comments. Open will-fix promises from prior runs are listed first. Bot badges, CI comments and linkbacks are filtered out.
3. **Verify.** The agent diffs the PR against its *real* base (stacked PRs don't base on `main`), finds your local worktree for the branch, reads the whole function around each flagged line, and follows every `file:line` the reviewer cites. Each finding gets classified: valid and unfixed, already fixed (which sha), pre-existing, overclaim, or duplicate of another thread.
4. **Fix first (optional).** For valid unfixed findings, the agent asks which to fix in code before drafting, so those replies can say `Fixed in <sha>` instead of `will fix`.
5. **Draft.** 1–2 sentences per thread, disposition first, in your voice once you've built one (see [Your voice](#your-voice)).
6. **Approve.** A chat message with the verified facts and the drafts, then a form with one question per thread: *Post as drafted*, *Skip*, or *Other* to type the exact text you want posted.
7. **Post.** One API call per approved reply, footer appended at post time, URL reported back. Will-fix replies are recorded; `Fixed in` replies can optionally resolve the thread.
8. **Learn.** Edits via *Other* are appended to your corrections file and periodically folded into your voice.

## Requirements

- [`gh`](https://cli.github.com/) authenticated against the GitHub host of the repo
- `jq` and `git`
- An agent with a structured question tool (Cursor `AskQuestion`, Claude Code `AskUserQuestion`). Without one the agent asks in chat and waits for a per-item answer.

## Install

Clone it anywhere, then put (or symlink) the folder where your agent discovers skills:

```bash
git clone <this repo> ~/Code/cr-reply
```

| Agent | Personal (all repos) | Project (this repo only) |
| --- | --- | --- |
| Cursor | `ln -s ~/Code/cr-reply ~/.cursor/skills/cr-reply` | `ln -s ~/Code/cr-reply .cursor/skills/cr-reply` |
| Claude Code | `ln -s ~/Code/cr-reply ~/.claude/skills/cr-reply` | `ln -s ~/Code/cr-reply .claude/skills/cr-reply` |
| [Ruler](https://github.com/intellectronica/ruler) repos | | copy to `.ruler/skills/cr-reply/` and run `npx ruler apply` |

Copy instead of symlink if you want to commit it into a repo. The scripts are referenced relative to the skill folder, so any location works.

## Usage

Just ask, in the repo the PR belongs to:

- "reply to the CR comments on #9900"
- "answer thejarx's review on PR 1234"
- "respond to the cursor[bot] findings on this PR"
- "reply and resolve the fixed ones on #9900"
- "anything new on #4567?"
- `/cr-reply 1234` in Cursor

The agent stops at the form. Pick an option per thread:

- **Post as drafted**: posts that draft, plus the footer.
- **Skip**: nothing is posted for that thread.
- **Other**: type the reply you want. It is posted verbatim (plus the footer); the agent does not polish it. If what you type reads like an instruction ("shorter", "mention the follow-up ticket"), the agent redrafts that one item and asks again.

Cancelling the form posts nothing.

### What the footer says

`<sub>Posted by <agent> on behalf of @<login></sub>`

- `<login>` is the account `gh` is authenticated as at post time, never a guess.
- `<agent>` is detected: `Cursor` when `CURSOR_AGENT` is set, `Claude Code` when `CLAUDECODE` is set, else `an AI agent`. Override with `--via "Name"` on `reply.sh`.

## What it remembers

All under `${CR_REPLY_HOME:-~/.config/cr-reply}` (override the dir with the env var; useful for tests):

| File | Written by | Holds |
| --- | --- | --- |
| `voice.md` | voice build / fold | your reply voice |
| `corrections.md` | *Other* edits | draft vs what you said |
| `will-fix.log` | `reply.sh --promise` | open will-fix promises |
| `runs.log` | Report step | posted / edited / skipped counts |

Delete a file to reset that piece of state. Nothing here is committed to a repo.

## Your voice

The default register is deliberately neutral, so out of the box the drafts won't sound like you. Let an agent build your voice from your own past replies instead:

```bash
# from any repo in your org; or --repo owner/name, --limit 80 for more material
bash ~/Code/cr-reply/scripts/gather-voice.sh --org acme > /tmp/voice-corpus.md
```

Then tell your agent: "build my cr-reply voice from /tmp/voice-corpus.md" (or just "build my cr-reply voice", the skill runs the gather step itself). It fills [`voice-template.md`](voice-template.md) with what it actually finds in your replies: how you open and close, how you agree, defer and push back, how long you go, your reply shapes in your own words, verbatim examples, and the things you never do. It saves the result to `~/.config/cr-reply/voice.md`, and from then on every draft follows it. Read the file once and delete whatever isn't you.

**More examples, richer voice.** The corpus pairs each of your replies with the comment it answered, so the agent learns _when_ you say "will fix" and when you push back, not just your vocabulary. A dozen replies capture punctuation and openers; many more, across different situations, capture the shapes. The script tells you how much it found; under ~15, widen the scope (`--org`, `--limit`) before building. Re-run when your style drifts.

**Learns from edits.** Every time you replace a draft via *Other*, the agent appends the reviewer ask, the draft, and what you said to `corrections.md`. After three new corrections (and once `voice.md` exists), it folds them in: new Real example under the matching situation, adjusted Reply-shapes row when the shape itself changed, Hard avoid when the same thing was stripped twice. A rising edit rate in `runs.log` is the signal to rebuild from scratch.

Already have a writing-voice rule for your agent? The skill uses it whenever no `voice.md` exists (and will not edit that rule; migrate into `voice.md` if you want folding).

The corpus is your own comments, fetched with your `gh` token into `/tmp`. Nothing leaves your machine.

## Customizing

The skill carries no personal data; it reads yours from files and rules you own.

- **Account.** If you keep several GitHub accounts in `gh`, add a rule to your agent that names the one to use for a given org (for example "on repos under the `acme` org always post as `@you`"). The skill verifies it first and passes it as `--as` on every post, so a mid-run `gh auth switch` can't post as someone else.
- **Voice.** `~/.config/cr-reply/voice.md`, built as above; or an existing personal voice rule; or the neutral default in `SKILL.md`.
- **Footer.** Agent name via `--via`. The footer itself is not optional; it is the point.
- **Bots.** Top-level bot posts are hidden by default. Inline bot threads (greptile, cursor[bot], claude) are shown, since those are real findings. `--from "cursor[bot]"` restricts to one author.

## Scripts

All scripts take `--repo owner/name`; without it they use the repo of the current directory.

### `scripts/fetch-threads.sh <pr> [--from LOGIN] [--all] [--since ISO]`

One GraphQL call. Prints review threads with `reply_to=<root comment id>` and `thread=<graphql id>`, resolved/outdated markers, and the full comment bodies; then human-written review summaries `[R*]` and conversation comments `[C*]` (bodies clipped at 600 chars, with URLs).

- default: unresolved threads where you are not the last replier
- `--from LOGIN`: only items by that author (also unhides that bot's top-level posts)
- `--all`: include resolved threads and the ones you already answered
- `--since ISO`: only items whose last activity is after the timestamp (e.g. `2026-10-28T12:20:00Z`)

### `scripts/pr-context.sh <pr> [-- <file>...]`

Resolves base and head from GitHub, fetches the base, finds the local worktree for the head branch (or fetches `pull/<n>/head`, which also works for merged PRs with deleted branches and for forks), warns if the worktree HEAD differs from the PR head, then prints commits, diff stat, the diff of the given files, and the PR body.

### `scripts/reply.sh <pr> <reply_to|pr> [--as LOGIN] [--via AGENT] [--promise TEXT] [--resolve THREAD_ID] [--dry-run] < body.md`

Reads the body from stdin, appends the footer, posts. `reply_to` is the thread's root comment id from `fetch-threads.sh`; the literal `pr` posts a PR conversation comment instead (for `[R*]` / `[C*]` items). `--as` aborts if the active account is not `LOGIN`. `--promise` appends a will-fix ledger line after a real post. `--resolve` resolves the review thread after a real post (opt-in; use the `thread=` id). `--dry-run` prints the endpoint, body, and would-append / would-resolve lines, and posts nothing.

```bash
printf 'Fixed in 3bf24bd.' | scripts/reply.sh 8877 4400401494 --as your-login --promise "guard on null config" --resolve PRRT_kwDO… --dry-run
```

### `scripts/gather-voice.sh [--org NAME | --repo owner/name] [--login LOGIN] [--limit N]`

Searches the newest `N` PRs (default 40, max 100) you commented on in the scope (default: the current repo's org) and prints a markdown corpus: every review reply of yours under the comment it answered (clipped), plus your PR conversation comments, verbatim. Ends with a count so you know whether there is enough material. Feed it to `voice-template.md`; see [Your voice](#your-voice).

## Safety

- Nothing is posted without a per-thread **Post** in the form (or your own text via Other).
- Replies only by default. Resolving a thread is opt-in (`--resolve`), per reply, and only for `Fixed in` replies when you asked. The skill never edits or deletes comments, approves, or requests changes.
- The footer is always appended, from the live login, so a reply can't be mistaken for one you typed yourself.
- `--as` makes a wrong-account post (which GitHub won't let you delete) fail before it happens.

## Limits

- GitHub only.
- Fetches the first 100 review threads and 50 comments per thread; no pagination. Add `pageInfo` cursors in `fetch-threads.sh` if a PR ever overflows.
- The agent does the judgment (is the finding valid, what is the fix); the scripts only make the fetch, the diff and the post deterministic.

## Ideas

Not built yet. Roughly in the order they can be done.

- **Voice learns from skip-and-answer.** When you skip a thread in the form and later answer it yourself on GitHub, harvest that reply on the next run (`fetch-threads.sh --all` already sees it) and fold it into `corrections.md` the same way *Other* edits are folded.
- **Will-fix auto-check.** Detect that an open promise landed (commit touching the file, or a later `Fixed in` by you) and clear the ledger line without a manual reply.
- **Duplicate findings.** Detect two bots flagging the same file and line range and pre-pair them, instead of relying on the agent to notice.
- **Pagination.** Lift the 100 threads / 50 comments per thread ceiling with `pageInfo` cursors.
- **Other forges.** GitLab MRs via `glab` have the same shape (threads, root note id, footer). The scripts are the only GitHub-specific part.
- **MEAT IS THE LOOP.** Gather all scripts and build a CLI for this with a dashboard and other cool stuff in a TUI. (yet another wrapper)
