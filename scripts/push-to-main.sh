#!/bin/sh
# Pushes the work to the project's main line, safely, even if somebody else has pushed since.
#
# ## Why this is in the repository
#
# It used to live outside it, in a scratch folder on one machine. That was fine while one conversation was doing the
# work and useless the moment two were: a second conversation gets its own copy of the repository and would not have
# the script at all, so it would push blind — and a blind push either fails with a message nobody reads or, worse,
# somebody reaches for `--force` and a morning's work stops existing.
#
# ## What it does
#
#   1. Finds out what the main line is called *now*. It has been renamed several times, and a branch called `main` was
#      deleted on purpose — so the name is looked up every time rather than written down anywhere.
#   2. Fetches, and if the main line has moved on, replays this work on top of it. That is what lets two conversations
#      work at once: neither has to wait for the other, and neither can overwrite the other.
#   3. If replaying hits a conflict, it stops, puts everything back exactly as it was, and says which files disagree.
#      It never guesses at a merge and never force-pushes.
#
# Run it from anywhere inside the repository.

set -eu

cd "$(git rev-parse --show-toplevel)"
REPO=$(git remote get-url origin | sed -E 's#.*/github/##; s#.*github.com[:/]##; s#\.git$##')

# Nothing half-finished. Pushing with work uncommitted is how a conversation loses track of what it has actually sent.
if [ -n "$(git status --porcelain)" ]; then
  echo "There is work here that has not been committed yet:"
  git status --short
  echo
  echo "Commit it first. Nothing has been pushed."
  exit 2
fi

DEFAULT=$(gh api "repos/$REPO" --jq .default_branch)
echo "The main line is called: $DEFAULT"

git fetch -q --prune origin
TIP=$(git rev-parse "origin/$DEFAULT")

if ! git merge-base --is-ancestor "$TIP" HEAD; then
  echo
  echo "The main line has moved on since this work started:"
  git log --format='  %h %an | %s' "HEAD..$TIP"
  echo
  echo "Replaying this work on top of it."
  # Where to come back to if this goes wrong.
  WAS=$(git rev-parse HEAD)
  if ! git rebase "$TIP" >/dev/null 2>&1; then
    git rebase --abort >/dev/null 2>&1 || true
    git reset -q --hard "$WAS"
    echo
    echo "IT WOULD NOT REPLAY CLEANLY. Nothing has been changed or pushed."
    echo "These files are the disagreement:"
    git diff --name-only "$TIP...$WAS" | sed 's/^/  /'
    echo
    echo "Somebody has to decide what the right answer is in those files. Look at both versions, write the one that"
    echo "is right, commit that, and run this again."
    exit 3
  fi
  echo "Replayed. Now:"
  git log --oneline "$TIP..HEAD" | sed 's/^/  /'
fi

git push origin "HEAD:refs/heads/$DEFAULT" 2>&1 \
  | grep -v '^remote: *$' | grep -v 'pull request' | tail -3
echo
git log --oneline -1
