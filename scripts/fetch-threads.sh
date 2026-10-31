#!/usr/bin/env bash
# Lists review threads, review summaries and conversation comments on a PR that still need a reply.
# usage: fetch-threads.sh <pr-number> [--repo owner/name] [--from LOGIN] [--all] [--since ISO]
#   --from LOGIN  only threads/comments started by that reviewer (e.g. witoszekdev, "cursor[bot]")
#   --all         include resolved threads and threads where the active account replied last
#   --since ISO   only items whose last activity is after the ISO timestamp (e.g. 2026-10-28T12:20:00Z)
set -euo pipefail

pr=""; repo=""; from=""; all=false; since=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --from) from="$2"; shift 2 ;;
    --all) all=true; shift ;;
    --since) since="$2"; shift 2 ;;
    *) pr="$1"; shift ;;
  esac
done
[ -n "$pr" ] || { echo "usage: $0 <pr-number> [--repo owner/name] [--from LOGIN] [--all] [--since ISO]" >&2; exit 2; }

repo="${repo:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
owner="${repo%%/*}"; name="${repo##*/}"
me="$(gh api user --jq .login)"

# ponytail: first:100 threads / 50 comments per thread, no pagination; fine for any PR we review, add pageInfo cursors if one ever overflows
gh api graphql -F owner="$owner" -F name="$name" -F number="$pr" -f query='
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      title url headRefOid
      reviewThreads(first: 100) {
        nodes {
          id isResolved isOutdated path line originalLine
          comments(first: 50) { nodes { databaseId body createdAt author { login } } }
        }
      }
      reviews(first: 50) { nodes { state body url submittedAt author { login __typename } } }
      comments(first: 100) { nodes { body url createdAt author { login __typename } } }
    }
  }
}' | jq -r --arg me "$me" --arg from "$from" --argjson all "$all" --arg since "$since" '
  def who: .author.login // "ghost";
  def indent: gsub("\n"; "\n    ");
  def clip: if length > 600 then .[0:600] + " […]" else . end;
  def mine: (who) == $me;
  def wanted: $from == "" or (who) == $from;
  # top-level bot posts (CI badges, linkbacks, auto-reviews) are noise unless --from names the bot
  def human: $from != "" or .author.__typename != "Bot";
  def after: $since == "" or . > $since;

  .data.repository.pullRequest as $pr
  | ($pr.reviewThreads.nodes
      | map(select($all or (.isResolved | not)))
      | map(select(.comments.nodes[0] | wanted))
      | map(select($all or (.comments.nodes[-1] | mine | not)))
      | map(select(.comments.nodes[-1].createdAt | after))
    ) as $threads
  | ($pr.reviews.nodes | map(select(.body != "" and (mine | not) and wanted and human and (.submittedAt | after)))) as $reviews
  | ($pr.comments.nodes | map(select((mine | not) and wanted and human and (.createdAt | after)))) as $comments
  | "PR #\($pr.url | split("/")[-1]) \($pr.title)\n\($pr.url)  head=\($pr.headRefOid[0:7])  me=@\($me)\(if $since != "" then "  since=\($since)" else "" end)",
    "\n== Review threads needing a reply: \($threads | length) ==",
    ($threads | to_entries[]
      | "\n[T\(.key + 1)] \(.value.path):\(.value.line // .value.originalLine // "?")  reply_to=\(.value.comments.nodes[0].databaseId)  thread=\(.value.id)\(if .value.isResolved then "  (resolved)" else "" end)\(if .value.isOutdated then "  (outdated)" else "" end)",
        (.value.comments.nodes[] | "  @\(who) \(.createdAt[0:16] | sub("T"; " "))\n    \(.body | indent)")
    ),
    "\n== Review summaries: \($reviews | length) ==  (reply with target `pr`)",
    ($reviews | to_entries[]
      | "\n[R\(.key + 1)] @\(.value | who) \(.value.state) \(.value.submittedAt[0:10])  \(.value.url)\n    \(.value.body | clip | indent)"
    ),
    "\n== Conversation comments: \($comments | length) ==  (reply with target `pr`)",
    ($comments | to_entries[]
      | "\n[C\(.key + 1)] @\(.value | who) \(.value.createdAt[0:10])  \(.value.url)\n    \(.value.body | clip | indent)"
    )
'
