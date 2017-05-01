#!/usr/bin/env sh
#rupm - relocatable user package manager

#Default values for used environment variables
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export PREFIX="${PREFIX:-$HOME/.local}"
export BINDIR="${BINDIR:-$HOME/.local/bin}"
export LIBDIR="${LIBDIR:-$HOME/.local/lib}"
export MANDIR="${MANDIR:-$HOME/.local/share/man}"

export RUPM_PKGINFO="${RUPM_PKGINFO:-$XDG_DATA_HOME/rupm/pkginfo}"
RUPM_PACKAGES="${RUPM_PACKAGES:-$XDG_DATA_HOME/rupm/packages}"
RUPM_EXTENSION="${RUPM_EXTENSION:-tar}"

workingdir="$HOME"
arch="${ARCH:-$(uname -m)}"
verbosity="0"
ext="$RUPM_EXTENSION"
tmps=""

trace() { [ "$verbosity" -ge "3" ] && printf '%s\n' "$*" >&2; }
debug() { [ "$verbosity" -ge "2" ] && printf '%s\n' "$*" >&2; }
info() { [ "$verbosity" -ge "1" ] && printf '%s\n' "$*" >&2; }
warn() { [ "$verbosity" -ge "0" ] && printf '%s\n' "$*" >&2; }
err() { [ "$verbosity" -ge "-1" ] && printf '%s\n' "$*" >&2; }
die() { [ "$verbosity" -ge "-2" ] && printf '%s\n' "$*" >&2;
    tmp_cleanup; exit 1; }

foreach() {
    func="$1"; shift;
    for i in "$@"; do
        $func "$i"
    done
}

tmp_getdir() {
    dir="$(mktemp -d)"
    tmps="$dir $tmps"
    echo "$dir"
}

tmp_cleanup() {
    rm -rf $tmps #This is just asking for trouble. Let's see
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
    scp "$pkg" "$remotepkg" || die "$name could not be uploaded to repo."
}

pkg_download() {
    name="$1"
    pkg="$(pkg_localfile "$name")"
    
    mkdir -p "$RUPM_PACKAGES"
    info "$name downloading."
    for repo in $RUPM_MIRRORLIST; do
        url="$(pkg_remotefile "$repo" "$name")"
        [ "$verbosity" -ge "3" ] || curlopts="-s"
        if curl -N $curlopts --progress-bar --fail "$url" -o "$pkg"; then
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

    pkg_download "$name" \
        || ( [ -f "$pkg" ] \
            && warn "$name will be installed using a cached package." ) \
        || die "$name is not available.";
}

pkg_install() {
    name="$1"
    
    debug "$name is installing"
    tarxenv < "$(pkg_localfile "$name")"
}

pkg_assemble() {
    name="$1"
    filelist="$RUPM_PKGINFO/$name/filelist"
    
    tmppkgdir="$(tmp_getdir)"
    [ -f "$filelist" ] || die "$name has no filelist."
    exec 9<"$filelist"
    while IFS= read -r file <&9; do
        keyname="$(echo "$file"|sed 's|^\$\([A-Za-z0-9_]*\).*|\1|')"
        keypath="$(echo "$file"|sed 's|^\$[^/]*/\(.*\)|\1|')"
        target="$(printenv "$keyname")"
        mkdir -p "$tmppkgdir/$(dirname "$file")"
        cp -a "${target:+$target/}$keypath" "$tmppkgdir/$file" \
            || die "$name could not be assembled"
    done
    info "$name is packaged."
    pushd "$tmppkgdir" >/dev/null
    mkdir -p "$RUPM_PACKAGES"
    sort "$filelist" \
        | xargs -x -d '\n' tar -cf "$(pkg_localfile "$name")" \
        || die "$name could not be assembled."
    rm -rf "$tmppkgdir"
    popd >/dev/null
}

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
    S) tasks="$tasks pkg_get pkg_install" ;;
    A) tasks="$tasks pkg_assemble" ;;
    P) tasks="$tasks pkg_push" ;;
    esac
done
cd "$workingdir"
shift "$(($OPTIND - 1))"
for task in $tasks; do
    foreach $task "$@"
done

