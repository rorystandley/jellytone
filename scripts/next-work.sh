#!/bin/sh
set -eu

repo_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

branch=$(git branch --show-current)
head=$(git rev-parse --short HEAD)
head_commit=$(git rev-parse HEAD)
queue_commit=$(git log -1 --format=%H -- docs/NEXT_WORK.md)
queue_status=$(git status --porcelain -- docs/NEXT_WORK.md)

echo "Repository: $repo_root"
echo "Branch: ${branch:-detached}"
echo "HEAD: $head"

if [ -n "$(git status --porcelain)" ]; then
  echo "Worktree: DIRTY — reconcile in-flight work before selecting a new slice"
else
  echo "Worktree: clean"
fi

if [ -n "$queue_status" ]; then
  echo "Routing: IN-FLIGHT — NEXT_WORK.md has uncommitted routing changes"
elif [ -n "$queue_commit" ] && [ "$head_commit" = "$queue_commit" ]; then
  echo "Routing: reconciled with HEAD"
else
  queue_short=$(git rev-parse --short "$queue_commit")
  echo "Routing: STALE — commits landed after NEXT_WORK.md was last updated at $queue_short"
fi

echo
git status --short --branch
echo
sed -n '1,120p' docs/NEXT_WORK.md
