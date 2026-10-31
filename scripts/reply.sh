#!/usr/bin/env bash
# Posts one PR reply with a "Posted by <agent> on behalf of @login" footer. Body comes from stdin.
# usage: reply.sh <pr-number> <reply_to|pr> [--repo owner/name] [--as LOGIN] [--via AGENT]
#               [--promise TEXT] [--resolve THREAD_ID] [--dry-run] < body.md
#   reply_to     root comment id of a review thread (the reply_to= value from fetch-threads.sh)
#   pr           post a PR conversation comment instead (for [R*] / [C*] items)
#   --as         abort unless the active gh account is LOGIN (the account verified before drafting)
#   --via        agent name for the footer; detected from CURSOR_AGENT / CLAUDECODE when omitted
#   --promise    after a real post, append the promise to will-fix.log (will-fix replies)
#   --resolve    after a real post, resolve the review thread (Fixed-in replies only; opt-in)
#   --dry-run    print target + final body (+ would-append / would-resolve), post nothing
# State dir: ${CR_REPLY_HOME:-$HOME/.config/cr-reply}
set -euo pipefail

pr=""; target=""; repo=""; as=""; via=""; promise=""; resolve=""; dry=false
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --as) as="$2"; shift 2 ;;
    --via) via="$2"; shift 2 ;;
    --promise) promise="$2"; shift 2 ;;
    --resolve) resolve="$2"; shift 2 ;;
    --dry-run) dry=true; shift ;;
    *) if [ -z "$pr" ]; then pr="$1"; else target="$1"; fi; shift ;;
  esac
done
[ -n "$pr" ] && [ -n "$target" ] || {
  echo "usage: $0 <pr-number> <reply_to|pr> [--repo owner/name] [--as LOGIN] [--via AGENT] [--promise TEXT] [--resolve THREAD_ID] [--dry-run] < body.md" >&2
  exit 2
}

home="${CR_REPLY_HOME:-$HOME/.config/cr-reply}"
repo="${repo:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
me="$(gh api user --jq .login)"
if [ -n "$as" ] && [ "$me" != "$as" ]; then
  echo "active gh account is @$me, expected @$as. Run: gh auth switch --user $as" >&2
  exit 1
fi

if [ -z "$via" ]; then
  if [ -n "${CURSOR_AGENT:-}" ]; then via="Cursor"
  elif [ -n "${CLAUDECODE:-}" ]; then via="Claude Code"
  else via="an AI agent"
  fi
fi

body="$(cat)"
[ -n "$body" ] || { echo "empty body on stdin" >&2; exit 2; }
body="$body"$'\n\n'"<sub>Posted by $via on behalf of @$me</sub>"

if [ "$target" = "pr" ]; then
  endpoint="repos/$repo/issues/$pr/comments"
else
  endpoint="repos/$repo/pulls/$pr/comments/$target/replies"
fi

ledger_line=""
if [ -n "$promise" ]; then
  ledger_line="$(date -u +%Y-%m-%dT%H:%M:%SZ)"$'\t'"$repo#$pr"$'\t'"$target"$'\t'"URL"$'\t'"$promise"
fi

if [ "$dry" = true ]; then
  printf 'DRY RUN  POST %s\n---\n%s\n' "$endpoint" "$body"
  if [ -n "$promise" ]; then
    printf 'would append to %s/will-fix.log:\n%s\n' "$home" "${ledger_line/URL/<url>}"
  fi
  if [ -n "$resolve" ]; then
    printf 'would resolve %s\n' "$resolve"
  fi
  exit 0
fi

url="$(gh api -X POST "$endpoint" -f body="$body" --jq .html_url)"
printf '%s\n' "$url"

if [ -n "$promise" ]; then
  mkdir -p "$home"
  printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"$'\t'"$repo#$pr"$'\t'"$target"$'\t'"$url"$'\t'"$promise" >>"$home/will-fix.log"
fi

if [ -n "$resolve" ]; then
  resolved="$(gh api graphql -f id="$resolve" -f query='
    mutation($id: ID!) {
      resolveReviewThread(input: {threadId: $id}) { thread { isResolved } }
    }' --jq '.data.resolveReviewThread.thread.isResolved')"
  printf 'resolved=%s\n' "$resolved"
fi
