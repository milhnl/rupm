#!/usr/bin/env sh
#rupm - relocatable user package manager

#Default values for used environment variables
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export PREFIX="${PREFIX:-$HOME/.local}"
export BINDIR="${BINDIR:-$PREFIX/bin}"
export LIBDIR="${LIBDIR:-$PREFIX/lib}"
export MANDIR="${MANDIR:-$XDG_DATA_HOME/man}"

export RUPM_PKGINFO="${RUPM_PKGINFO:-$XDG_DATA_HOME/rupm/pkginfo}"
RUPM_PACKAGES="${RUPM_PACKAGES:-$XDG_CACHE_HOME/rupm/packages}"
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

tmp_get() { #1: Optional -d flag for directory
    file="$(mktemp "$@")"
    tmps="$file $tmps"
    echo "$file"
}

tmp_cleanup() {
    rm -rf $tmps #This is just asking for trouble. Let's see
}

path_transform() { #$1: path to transform, or use stdin
    ([ $# -ne 0 ] && echo "$1" || cat) \
        | awk 'BEGIN {OFS = FS = "/"} {
            target = ENVIRON[substr($1, 2)]
            $1 = target != "" ? target : $1
            print
        }'
}

pkg_meta() { #1: name, 2: metafile
    name="$1"
    metafile="$2"
    echo "$RUPM_PKGINFO/$name/$metafile"
}

pkg_remotefile() {
    type="$1"
    name="$2"
    echo "$(eval "echo $type")"
}

pkg_push() {
    name="$1"
    pkg="$RUPM_PACKAGES/$name"
    remotepkg="$(pkg_remotefile "$RUPM_SSHPUSH" "$name")"

    debug "$name uploading to $remotepkg"
    scp "$pkg" "$remotepkg" || die "$name could not be uploaded to repo."
}

pkg_download() {
    name="$1"
    pkg="$RUPM_PACKAGES/$name"
    tmp="$(tmp_get)"
    
    info "$name downloading."
    for repo in $RUPM_MIRRORLIST; do
        url="$(pkg_remotefile "$repo" "$name")"
        [ "$verbosity" -ge "3" ] || curlopts="-s"
        curl -N $curlopts --progress-bar --fail "$url" -o "$tmp" && break
    done
    if [ -f "$tmp" ]; then
        debug "$name downloaded from $url"
        mkdir -p "$pkg"
        tar -C"$pkg" -xf"$tmp"
    else
        warn "$name could not be downloaded."
        false
    fi
}

pkg_get() {
    name="$1"
    pkg="$RUPM_PACKAGES/$name"

    pkg_download "$name" \
        || ( [ -f "$pkg" ] \
            && warn "$name will be installed using a cached package." ) \
        || die "$name is not available.";
}

pkg_install() {
    name="$1"
    
    debug "$name is installing"
    pkgdir="$RUPM_PACKAGES/$name"

    for envkey in "$pkgdir"/* "$pkgdir"/.[!.]* "$pkgdir"/..?* ; do
        [ -e "$envkey" ] || continue
        fsfile="$(path_transform "$(basename "$envkey")")"
        [ -d "$envkey" ] && envkey="$envkey/."
        trace "$envkey -> $fsfile"
        cp -a "$envkey" "$fsfile" || \
            die "$name member ${envkey#$pkgdir/} failed."
    done

    rm -rf "$pkgdir"
}

pkg_assemble() {
    name="$1"

    filelist="$(pkg_meta "$name" filelist)"
    tmppkgdir="$(tmp_get -d)"
    [ -f "$filelist" ] || die "$name has no filelist."
    exec 9<"$filelist"
    while IFS= read -r file <&9; do
        fsfile="$(path_transform "$file")"
        mkdir -p "$tmppkgdir/$(dirname "$file")"
        trace "$fsfile -> $tmppkgdir/$file"
        cp -a "$fsfile" "$tmppkgdir/$file" \
            || die "$name could not be assembled"
    done
    info "$name is packaged."
    oldpwd="$(pwd)"; cd "$tmppkgdir"
    mkdir -p "$RUPM_PACKAGES"
    sort "$filelist" \
        | xargs -x -d '\n' tar -cf "$RUPM_PACKAGES/$name" \
        || die "$name could not be assembled."
    rm -rf "$tmppkgdir"
    cd "$oldpwd"
}

pkg_remove() {
    name="$1"

    filelist="$(pkg_meta "$name" filelist)"
    [ -f "$filelist" ] || die "$name has no filelist."
    sed 's|/\.$||' <"$filelist" \
        | path_transform \
        | xargs -d'\n' rm -r \
        || die "$name could not be deleted."
}

pkg_clean() {
    name="$1"

    rm "$RUPM_PACKAGES/$name" 2>/dev/null&&info "$name cleaned from cache."
    rmdir --ignore-fail-on-non-empty "$RUPM_PACKAGES" 2>/dev/null || true
}

tasks=""
while getopts vqC:cSAPR opt; do
    case $opt in
    v) verbosity="$(($verbosity + 1))" ;;
    q) verbosity="$(($verbosity - 1))" ;;
    C) workingdir="$OPTARG"; info "Creating packages from $workingdir" ;;
    c) tasks="$tasks pkg_clean" ;;
    S) tasks="$tasks pkg_get pkg_install" ;;
    A) tasks="$tasks pkg_assemble" ;;
    P) tasks="$tasks pkg_push" ;;
    R) tasks="$tasks pkg_remove" ;;
    esac
done
cd "$workingdir"
shift "$(($OPTIND - 1))"
for task in $tasks; do
    foreach $task "$@"
done

