#!/usr/bin/env sh
#rupm - relocatable user package manager
RUPM_PACKAGES="${RUPM_PACKAGES:-${XDG_DATA_HOME:-$HOME/.local/share}/rupm/packages}"
RUPM_RECIPES="${RUPM_RECIPES:-${XDG_CONFIG_HOME:-$HOME/.config}/rupm/recipes}"
RUPM_EXTENSION="${RUPM_EXTENSION:-tar}"

workingdir="$HOME"
arch="${ARCH:-$(uname -m)}"
verbosity="0"
ext="$RUPM_EXTENSION"

trace() { [ "$verbosity" -ge "3" ] && printf '%s\n' "$*" >&2; }
debug() { [ "$verbosity" -ge "2" ] && printf '%s\n' "$*" >&2; }
info() { [ "$verbosity" -ge "1" ] && printf '%s\n' "$*" >&2; }
warn() { [ "$verbosity" -ge "0" ] && printf '%s\n' "$*" >&2; }
err() { [ "$verbosity" -ge "-1" ] && printf '%s\n' "$*" >&2; }
die() { [ "$verbosity" -ge "-2" ] && printf '%s\n' "$*" >&2; exit 1; }

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

    debug "$name uploading to $remotepkg"
    scp "$pkg" "$remotepkg" || die "Could not upload package(s) to repo."
}

pkg_download() {
    name="$1"
    pkg="$(pkg_localfile "$name")"
    
    mkdir -p "$RUPM_PACKAGES"
    info "$name downloading."
    for repo in $RUPM_MIRRORLIST; do
        url="$(pkg_remotefile "$repo" "$name")"
        [ "$verbosity" -ge "3" ] || curlopts="-s"
        if curl -N $curlopts -\# --fail "$url" > "$pkg"; then
            debug "$name downloaded from $url"
            return 0;
        fi
    done
    warn "$name could not be downloaded."
    false
}

pkg_get() {
    name="$1"
    pkg="$(pkg_localfile "$name")"
    
    if pkg_download "$name"; then
        echo "$pkg"
    elif [ -f "$pkg" ]; then
        warn "$name will be installed using a cached package."
        echo "$pkg"
    else
        err "$name is not available."
    fi
}

pkg_install() {
    name="$1"
    
    if pkg_get "$name" >/dev/null; then
        debug "$name is installing"
        tarxenv < "$(pkg_localfile "$name")"
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
        err "$name could not be assembled into a package."
    fi
)

pkg_clean() {
    name="$1"

    info "$name is removed from cache."
    rm -f "$(pkg_localfile "$name")"
    rmdir --ignore-fail-on-non-empty "$RUPM_PACKAGES"
}

tasks=""
while getopts vqC:cSAP opt; do
    case $opt in
    v) verbosity="$(($verbosity + 1))" ;;
    q) verbosity="$(($verbosity - 1))" ;;
    C) workingdir="$OPTARG"; info "Creating packages from $workingdir" ;;
    c) tasks="$tasks pkg_clean" ;;
    S) tasks="$tasks pkg_install" ;;
    A) tasks="$tasks pkg_assemble" ;;
    P) tasks="$tasks pkg_push" ;;
    esac
done
shift "$(($OPTIND - 1))"
for task in $tasks; do
    foreach $task "$@"
done

