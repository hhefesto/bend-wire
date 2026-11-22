#!/usr/bin/env bash
# ./mkmutant.sh FILE MUTANT 'SED': writes probe/mutants/MUTANT.patch, the
# diff that the sed expression makes to FILE (it must change it)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
file=$1 mut=$2 expr=$3
t=$(mktemp -d)
mkdir -p "$t/a/$(dirname "$file")" "$t/b/$(dirname "$file")"
cp "$here/$file" "$t/a/$file"; sed -e "$expr" "$here/$file" > "$t/b/$file"
mkdir -p "$here/probe/mutants"
if (cd "$t" && diff -u "a/$file" "b/$file") > "$here/probe/mutants/$mut.patch"; then
  echo "$mut: the sed changed nothing"; rm "$here/probe/mutants/$mut.patch"; rm -rf "$t"; exit 1
fi
rm -rf "$t"
