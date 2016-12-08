#!/usr/bin/env sh
#jtar - Move files into a JSON-file defined tar structure
#Needs jshon

if [ "$#" -lt 1 ]; then
    echo "Usage: `basename "$0"` STRUCTURE_JSON_FILE [TAR_OPTIONS]" >&2
    exit 1;
elif [ "$#" -lt 2 ]; then
    set -- "$1" "-cO"
fi
set -e
structurefile="$1"; shift
if [ ! -e "$structurefile" ]; then
    echo "Error: '$structurefile' not found" >&2
    exit 1
fi
targetfile="$(mktemp)"
exec 9< "$targetfile"
pkgdir="$(mktemp -d)"

#Get the keys (target directories/env variables) from the json file
jshon -k < "$structurefile" >"$targetfile"

while IFS= read -r target <&9; do
    #Make sure there is something to copy to
    mkdir -p "$(dirname "$pkgdir/$target")"
    #Get the value type
    type="$(jshon -e "$target" -t < "$structurefile")"
    case "$type" in
    "array")
        mkdir -p "$pkgdir/$target"
        for i in $(seq 0 "$(($(jshon -e "$target" -l < "$structurefile") - 1))"); do
            source="$(jshon -e "$target" -e "$i" -u < "$structurefile")"
            cp -a "$source" -t "$pkgdir/$target"
        done
        ;;
    "string")
        source="$(jshon -e "$target" -u < "$structurefile")"
        cp -a "$source" "$pkgdir/$target"
        ;;
    *)
        echo "Unknown value type: '$type' in package description." >&2
        exit 1
        ;;
    esac
done
exec 9<&-
(
cd "$pkgdir"
xargs tar "$@" < "$targetfile"
)
rm -rf "$pkgdir" "$targetfile"
