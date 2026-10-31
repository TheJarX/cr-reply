#!/usr/bin/env bash
# Collects the user's own PR review replies and PR comments, each paired with the comment it answered,
# as a corpus for building their voice file (see voice-template.md).
# usage: gather-voice.sh [--org NAME | --repo owner/name] [--login LOGIN] [--limit N] > corpus.md
#   default scope: the org of the current repo; --limit = PRs to scan, newest first (max 100, default 40)
set -euo pipefail

scope=""; login=""; limit=40
while [ $# -gt 0 ]; do
  case "$1" in
    --org) scope="org:$2"; shift 2 ;;
    --repo) scope="repo:$2"; shift 2 ;;
    --login) login="$2"; shift 2 ;;
    --limit) limit="$2"; shift 2 ;;
    *) echo "usage: $0 [--org NAME | --repo owner/name] [--login LOGIN] [--limit N]" >&2; exit 2 ;;
  esac
done

login="${login:-$(gh api user --jq .login)}"
scope="${scope:-org:$(gh repo view --json owner --jq .owner.login)}"

gh api graphql -F q="is:pr commenter:$login $scope sort:updated-desc" -F n="$limit" -f query='
query($q: String!, $n: Int!) {
  search(query: $q, type: ISSUE, first: $n) {
    nodes {
      ... on PullRequest {
        number title url
        reviewThreads(first: 50) { nodes { comments(first: 20) { nodes { author { login } body } } } }
        comments(first: 100) { nodes { author { login } body } }
      }
    }
  }
}' | jq -r --arg me "$login" --arg scope "$scope" --arg date "$(date +%Y-%m-%d)" '
  def who: .author.login // "ghost";
  def clip($n): if length > $n then .[0:$n] + " […]" else . end;
  def quote: gsub("\n"; "\n> ");
  def replies($c): range(0; $c | length) as $i
    | select($c[$i] | who == $me)
    | { context: (if $i > 0 then $c[$i - 1] else null end), reply: $c[$i] };

  [ .data.search.nodes[]
    | select(.number != null)
    | { pr: { number, title, url },
        threads: [ .reviewThreads.nodes[] | replies(.comments.nodes) ],
        comments: [ .comments.nodes[] | select(who == $me) ] }
    | select((.threads | length) + (.comments | length) > 0)
  ] as $prs
  | ($prs | map((.threads | length) + (.comments | length)) | add // 0) as $total
  | "# Voice corpus for @\($me): \($total) replies across \($prs | length) PRs (\($scope)), fetched \($date)",
    "",
    "Each `>` block is what the other person wrote (clipped). The text after it is @\($me), verbatim.",
    ($prs[]
      | "\n## PR #\(.pr.number) \(.pr.title)\n\(.pr.url)",
        (.threads[]
          | (if .context then "\n> @\(.context | who): \(.context.body | clip(300) | quote)"
             else "\n> (as reviewer, opened the thread)" end),
            "\n\(.reply.body | clip(1200))"),
        (.comments[] | "\n> (PR conversation)\n\n\(.body | clip(1200))")),
    "\n---\n\($total) replies. Under ~15 is a thin voice; widen the scope with --limit or --org and re-run."
'
