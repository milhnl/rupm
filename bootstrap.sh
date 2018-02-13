#!/usr/bin/env sh
RUPM_MIRRORLIST="${RUPM_MIRRORLIST:-http://repo.milh.nl/}"

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export PREFIX="${PREFIX:-$HOME/.local}"
export RUPM_PKGINFO="${RUPM_PKGINFO:-$XDG_DATA_HOME/rupm/pkginfo}"

rupm() {
    echo "Installing rupm..."
    pkg="${RUPM_PACKAGES:-$XDG_CACHE_HOME/rupm/packages}"
    mkdir -p "$pkg"
    pkg="$pkg/rupm.tar"
    for repo in $RUPM_MIRRORLIST; do
        case "$repo" in
        https://*|http://*)
            curl "$repo$(curl --progress-bar --fail "$repo"\
                | sed 's/<[^>]*>//g' \
                | sed -n 's/\([A-Za-z0-9_.-]*.tar\).*/\1/p'\
                | grep '^rupm' \
                | sort -t. -k1,1 -k2,2n -k3,3n -k4,4n -k5,5n -k6,6n -k7,7n\
                | tail -n1)" -o "$pkg" && break
            ;;
        ssh://*)
            scp "(ssh "$(echo "$repo" | sed 's/.*:\(.*\):.*/\1/')" \
                -C "cd '$(echo "$repo"|sed 's/.*:.*:/')'; ls -1" \
                | grep '^rupm' \
                | sort -t. -k1,1 -k2,2n -k3,3n -k4,4n -k5,5n -k6,6n -k7,7n\
                | tail -n1)" "$pkg" && break
            ;;
        esac
    done
    [ -s "$pkg" ] || { echo "Could not download rupm." >&2; return 1; }
    pkgdir="$(mktemp -d)"
    tar -C "$pkgdir" -xf "$pkg" || return 1
    mkdir -p "$RUPM_PKGINFO"
    for envkey in "$pkgdir"/* "$pkgdir"/.[!.]* "$pkgdir"/..?* ; do
        [ -e "$envkey" ] || continue
        fsfile="`printenv $(basename "$envkey"|sed 's/[^A-Za-z0-9\_]//g')`"
        [ -d "$envkey" ] && envkey="$envkey/."
        cp -a "$envkey" "$fsfile" || return 1
    done
    rm -rf "$pkgdir" "$pkg"
}
rupm
