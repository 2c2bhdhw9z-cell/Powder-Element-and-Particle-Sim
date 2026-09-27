#!/bin/sh
# Gives every file under native/ the time it last changed in the history, so a build kept from an earlier run of the
# checks is reused for everything that has not changed since.
#
# ## Why this is needed
#
# Swift decides what to compile again by each file's modification time. A fresh checkout stamps every file with the
# moment it was checked out, so a kept build looked out of date in every file and was thrown away: measured, a kept
# build was reused completely when the files kept their times (nothing compiled) and not at all when they did not
# (every file compiled). The file's identity on disk does not matter; only its time.
#
# ## Why some changed files are stamped "now" instead
#
# Two different versions of a file can carry the same time to the second — a change amended moments after it was
# made. A kept build would then think the second was already compiled. So a file that differs from the version the
# kept build was made from (named in .build/crucible-built-from.txt), but whose last change has the same time as it
# had then, is stamped with the present moment, which no kept build can have seen. A kept build with no record of
# what it was made from has every file stamped "now": a full build, but never a wrong one.
#
# Run from anywhere inside the repository. Needs the whole history (a checkout with fetch-depth 0).
set -eu
cd "$(git rev-parse --show-toplevel)"

stamp() { # stamp <seconds since 1970> <file>
  if touch -d "@$1" "$2" 2>/dev/null; then return; fi
  # macOS's touch takes a calendar time rather than a count of seconds.
  touch -t "$(date -r "$1" +%Y%m%d%H%M.%S)" "$2"
}

# Newest first, so the first time a file is named is the last time it changed.
git log --format='format:%ct' --name-only --no-renames -- native |
  awk 'NF == 1 && $0 ~ /^[0-9]+$/ { t = $0; next } NF > 0 && !($0 in seen) { seen[$0] = 1; print t " " $0 }' |
  while read -r when file; do
    # A file named in the history may since have been deleted.
    if [ -f "$file" ]; then stamp "$when" "$file"; fi
  done

record="native/.build/crucible-built-from.txt"
now=$(date +%s)
if [ ! -d native/.build ]; then
  echo "No kept build: everything will be compiled."
elif [ -f "$record" ] && built_from=$(cat "$record") && git cat-file -e "$built_from^{commit}" 2>/dev/null; then
  changed=0
  newline='
'
  IFS=$newline
  for file in $(git diff --name-only "$built_from" HEAD -- native); do
    if [ ! -f "$file" ]; then continue; fi
    changed=$((changed + 1))
    then_time=$(git log -1 --format=%ct "$built_from" -- "$file")
    now_time=$(git log -1 --format=%ct HEAD -- "$file")
    if [ "$then_time" = "$now_time" ]; then stamp "$now" "$file"; fi
  done
  unset IFS
  echo "Kept build from $(git rev-parse --short "$built_from"): $changed files have changed since."
else
  git ls-files native | while read -r file; do if [ -f "$file" ]; then stamp "$now" "$file"; fi; done
  echo "A kept build with no record of what it was made from: everything will be compiled."
fi

# What the build about to be made is made from, for the next run.
mkdir -p native/.build
git rev-parse HEAD > "$record"
