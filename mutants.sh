#!/usr/bin/env bash
# ./mutants.sh: this library's laws must catch each mistake in its
# probe/mutants/: every patch there breaks the library on purpose, one
# mistake at a time (patch -p1 from here), and PROOF.bend must fail on each.
# bend on PATH, and the libraries it imports beside this one (../bend-NAME/);
# the copies are made in a temporary directory and removed.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
name=$(basename "$here")
t=$(mktemp -d)
for d in "$(dirname "$here")"/bend-*; do
  [ -d "$d" ] && [ "$d" != "$here" ] && ln -s "$d" "$t/"
done
bad=0
for p in "$here"/probe/mutants/*.patch; do
  n=$(basename "$p" .patch)
  rm -rf "${t:?}/$name"; cp -r "$here" "$t/$name"
  if ! (cd "$t/$name" && patch -s -p1 < "$p"); then echo "$n: the patch no longer applies"; bad=1
  elif (cd "$t/$name" && bend PROOF.bend 2>&1) | grep -q 'SOME PROOFS FAIL'; then echo "$n: caught"
  else echo "$n: NOT CAUGHT"; bad=1; fi
done
rm -rf "$t"
exit $bad
