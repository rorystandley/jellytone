#!/bin/sh
set -eu

repo_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

branch=$(git branch --show-current)
head=$(git rev-parse --short HEAD)
expected=$(awk -F'`' '/^- Last reconciled commit:/ { print $2; exit }' docs/NEXT_WORK.md)

echo "Repository: $repo_root"
echo "Branch: ${branch:-detached}"
echo "HEAD: $head"

if [ -n "$(git status --porcelain)" ]; then
  echo "Worktree: DIRTY — reconcile in-flight work before selecting a new slice"
else
  echo "Worktree: clean"
fi

if [ -n "$expected" ] && [ "$head" != "$expected" ]; then
  echo "Routing: STALE — NEXT_WORK.md expects $expected; reconcile it with $head"
else
  echo "Routing: reconciled with HEAD"
fi

echo
git status --short --branch
echo
sed -n '1,120p' docs/NEXT_WORK.md
