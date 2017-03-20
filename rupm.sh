#!/usr/bin/env sh
#rupm - relocatable user package manager
RUPM_PACKAGES="${RUPM_PACKAGES:-${XDG_DATA_HOME:-$HOME/.local/share}/rupm/packages}"
RUPM_RECIPES="${RUPM_RECIPES:-${XDG_CONFIG_HOME:-$HOME/.config}/rupm/recipes}"
RUPM_EXTENSION="${RUPM_EXTENSION:-tar}"

workingdir="$HOME"
arch="${ARCH:-$(uname -m)}"
verbose="0"
ext="$RUPM_EXTENSION"

vecho() {
    [ "${verbose:-0}" = "0" ] || echo "$@" >&2
}

foreach() {
    func="$1"; shift;
    for i in "$@"; do
        $func "$i"
    done
}

pkg_localfile() {
    echo "$RUPM_PACKAGES/$1.$ext"
}

pkg_remotefile() {
    type="$1"
    name="$2"
    echo "$(eval "echo $type")"
}

pkg_push() {
    name="$1"
    pkg="$(pkg_localfile "$name")"
    remotepkg="$(pkg_remotefile "$RUPM_SSHPUSH" "$name")"

    vecho "Pushing $pkg to $remotepkg"
    if ! scp "$pkg" "$remotepkg"; then
        echo "Could not upload packages to repo." >&2
        exit
    fi
}

pkg_download() {
    name="$1"
    pkg="$(pkg_localfile "$name")"
    
    mkdir -p "$RUPM_PACKAGES"
    for repo in $RUPM_MIRRORLIST; do
        url="$(pkg_remotefile "$repo" "$name")"
        [ "${verbose:-0}" = "0" ] && curlopts="-s"
        if curl -N $curlopts -# --fail "$url" > "$pkg"; then
            vecho "Downloaded $url"
            return;
        fi
    done
    echo "Could not download $url" >&2
    false
}

pkg_get() {
    name="$1"
    pkg="$(pkg_localfile "$name")"
    
    if [ -f "$pkg" ]; then
        echo "$pkg"
    elif pkg_download "$name"; then
        echo "$pkg"
    else
        echo "Error: Could not download $1." >&2
        exit 1
    fi
}

pkg_install() {
    name="$1"
    
    if pkg_get "$name" >/dev/null; then
        vecho "Installing $name"
        tarxenv < "$(pkg_get "$name")"
    fi
}

pkg_assemble() (
    tmpfile="$(mktemp)"
    cd "$workingdir"
    if jtar "$RUPM_RECIPES/$1.json" > "$tmpfile"; then
        chmod +r "$tmpfile"
        mkdir -p "$RUPM_PACKAGES"
        mv "$tmpfile" "$RUPM_PACKAGES/$1.$RUPM_EXTENSION"
    else
        echo "Error: could not create package for $1." >&2
    fi
)

while getopts SC:APvc opt; do
    case $opt in
    v)
        verbose="1"
        ;;
    c)
        vecho "Removing package files from cache"
        rm -rf "$RUPM_PACKAGES"
        ;;
    S)
        shift "$(($OPTIND - 1))"
        foreach pkg_install "$@"
        ;;
    C)
        workingdir="$OPTARG"
        vecho "Creating packages from $workingdir"
        ;;
    A)
        shift "$(($OPTIND - 1))"
        foreach pkg_assemble "$@"
        ;;
    P)
        shift "$(($OPTIND - 1))"
        foreach pkg_push "$@"
        ;;
    esac
done

