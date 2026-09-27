#!/bin/sh
# Writes a build's release notes: what changed since the last build, in the words the changes were described in, and a
# few things worth trying on the phone.
#
#   scripts/release-notes.sh <this build's commit>
#
# "The last build" is the newest build-N tag in this commit's history. The changes are the commit subjects since then,
# with the "feat(powder):" style prefixes taken off. The things to try are the first lines of the bullet points in those
# commits' descriptions, newest first, three at most. Needs the whole history, so the checkout must fetch it.
set -eu

HEAD_COMMIT="${1:-HEAD}"
PREVIOUS=$(git describe --tags --match 'build-*' --abbrev=0 "$HEAD_COMMIT^" 2>/dev/null || true)
if [ -n "$PREVIOUS" ]; then
  RANGE="$PREVIOUS..$HEAD_COMMIT"
  echo "## What changed since $PREVIOUS"
else
  RANGE="$HEAD_COMMIT~10..$HEAD_COMMIT"
  echo "## The latest changes"
fi
echo

# Subjects, newest first, merges left out, prefixes such as "feat(powder): " removed and the first letter made capital.
git log --no-merges --format='%s' "$RANGE" |
  sed -E 's/^[a-z]+(\([^)]*\))?!?: //' |
  awk '{ print "- " toupper(substr($0, 1, 1)) substr($0, 2) }'

TRY=$(git log --no-merges --format='%b%x00' "$RANGE" |
  awk 'BEGIN { RS = "\0" }
       {
         n = split($0, lines, "\n")
         for (i = 1; i <= n; i++) {
           if (lines[i] ~ /^- /) {
             item = substr(lines[i], 3)
             # A point wrapped over several lines is joined back together.
             while (i + 1 <= n && lines[i + 1] ~ /^  [^ -]/) { i++; sub(/^ +/, "", lines[i]); item = item " " lines[i] }
             print "- " item
           }
         }
       }' | head -n 3)

if [ -n "$TRY" ]; then
  echo
  echo "## Worth trying on the phone"
  echo
  echo "$TRY"
fi
