#!/usr/bin/env bash
# Prints what is needed to verify CR findings against the PR branch: real base/head, local worktree,
# commits, diff stat, the diff of the flagged files, and the PR body.
# usage: pr-context.sh <pr-number> [--repo owner/name] [-- <flagged-file>...]
set -euo pipefail

pr=""; repo=""; files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --) shift; files=("$@"); break ;;
    *) pr="$1"; shift ;;
  esac
done
[ -n "$pr" ] || { echo "usage: $0 <pr-number> [--repo owner/name] [-- <flagged-file>...]" >&2; exit 2; }

repo="${repo:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
read -r base head sha < <(gh pr view "$pr" --repo "$repo" --json baseRefName,headRefName,headRefOid \
  --jq '"\(.baseRefName) \(.headRefName) \(.headRefOid[0:7])"')

# stacked PRs base on a feature branch, never assume master
git fetch -q origin "$base"

worktree="$(git worktree list --porcelain | awk -v b="refs/heads/$head" '/^worktree /{w=$2} $0=="branch "b{print w}')"
if [ -n "$worktree" ]; then
  cd "$worktree"
  headref=HEAD
  local_sha="$(git rev-parse --short=7 HEAD)"
  [ "$local_sha" = "$sha" ] || echo "WARNING: worktree HEAD $local_sha differs from PR head $sha" >&2
else
  # pull/N/head survives branch deletion and works for fork PRs
  git fetch -q origin "pull/$pr/head"
  headref="$(git rev-parse FETCH_HEAD)"
fi

echo "PR #$pr $repo  base=$base  head=$head@$sha"
echo "worktree: ${worktree:-none, read files with: git show $sha:<path>}"
echo; echo "== commits =="; git log --oneline "origin/$base..$headref"
echo; echo "== diff stat =="; git diff --stat "origin/$base...$headref"
if [ ${#files[@]} -gt 0 ]; then
  echo; echo "== diff of flagged files =="; git diff "origin/$base...$headref" -- "${files[@]}"
fi
echo; echo "== PR body =="; gh pr view "$pr" --repo "$repo" --json body --jq .body
