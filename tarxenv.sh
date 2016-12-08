#!/usr/bin/env sh
#tarxenv - extract a tar archive with top level env vars
#TODO: add fail checks like unknown env var
set -e

pkgdir="$(mktemp -d)"
dirlist="$(mktemp)"

tar -C "$pkgdir" -x #<stdin

find "$pkgdir" -maxdepth 1 -mindepth 1 -print0 > "$dirlist"

exec 9< "$dirlist"
while IFS= read -rd '' envdir <&9; do
    #Do some basic sanitiation (try opening $(rm -rf .))
    var="$(basename "$envdir" | sed 's/[^A-Za-z0-9\_]//g')"
    #Make cp copy the *contents* instead of the whole dir
    if [ -d "$envdir" ]; then
        envdir="$envdir/."
    fi
    actualplace="$(printenv $var)"
    cp -a "$envdir" "$actualplace"
done; exec 9<&-

rm -rf "$pkgdir" "$dirlist"
