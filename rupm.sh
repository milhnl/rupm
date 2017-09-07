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

trace() { [ "$verbosity" -ge "3" ] && printf '%s\n' "$*" >&2; true;}
debug() { [ "$verbosity" -ge "2" ] && printf '%s\n' "$*" >&2; true;}
info() { [ "$verbosity" -ge "1" ] && printf '%s\n' "$*" >&2; true;}
warn() { [ "$verbosity" -ge "0" ] && printf '%s\n' "$*" >&2; true;}
err() { [ "$verbosity" -ge "-1" ] && printf '%s\n' "$*" >&2; true;}
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
    echo "$RUPM_PKGINFO/$1/$2"
}

pkg_meta_f() { #1: name, 2: metafile
    [ -f "$(pkg_meta "$1" "$2")" ] || die "$1 missing info ($2)"
    pkg_meta "$1" "$2"
}

pkg_remotefile() { #1: remote template, 2: name
    name="$2" #Needed by the template
    echo "$(eval "echo $1")"
}

prv_http() { #1: uri, 2: verb, 3: name
    [ "$2" = "get" ] || return 1
    tmp="$(tmp_get)"
    
    set -- "$(pkg_remotefile "$1" "$3")" "$2" "$3"
    debug "$3 trying $1"
    [ "$verbosity" -ge "1" ] || curlopts="-s"
    curl -N $curlopts --progress-bar --fail "$1" -o "$tmp" \
        && debug "$3 downloaded from $1" \
        && mkdir -p "$RUPM_PACKAGES/$3" \
        && tar -C"$RUPM_PACKAGES/$3" -xf"$tmp"
}

prv_ssh() { #1: uri, 2: verb, 3: name
    tmp="$(tmp_get)"

    set -- "$(pkg_remotefile "$1" "$3" | sed 's|^ssh://||')" "$2" "$3"
    case "$2" in
    get)
        scp "$1" "$tmp" \
            && debug "$3 downloaded from $1" \
            && mkdir -p "$RUPM_PACKAGES/$3" \
            && tar -C"$RUPM_PACKAGES/$3" -xf"$tmp"
        ;;
    put)
        sort "$(pkg_meta_f "$3" filelist)" \
            | (cd "$RUPM_PACKAGES/$3"; xargs -xd '\n' tar -cf "$tmp") \
            && chmod 0644 "$tmp" \
            && scp "$tmp" "$1" \
            && rm -r "$tmp" "$RUPM_PACKAGES/$3" \
            && debug "$3 pushed to $1"
        ;;
    esac
}

pkg_do() { #1: verb, 2: name
    for provider in $RUPM_MIRRORLIST; do
        case $provider in
        https://*|http://*) prv_http $provider "$1" "$2" && return ;;
        ssh://*) prv_ssh $provider "$1" "$2" && return ;;
        *) die "$1 provider $provider not supported" ;;
        esac
    done
    false
}

pkg_get() { pkg_do get "$1" || die "$1 could not be found"; }
pkg_put() { pkg_do put "$1" || die "$1 could not be pushed"; }

pkg_install() { #1: name
    debug "$1 is installing"
    pkgdir="$RUPM_PACKAGES/$1"

    for envkey in "$pkgdir"/* "$pkgdir"/.[!.]* "$pkgdir"/..?* ; do
        [ -e "$envkey" ] || continue
        fsfile="$(path_transform "$(basename "$envkey")")"
        [ -d "$envkey" ] && envkey="$envkey/."
        trace "$envkey -> $fsfile"
        cp -a "$envkey" "$fsfile" || \
            die "$1 member ${envkey#$pkgdir/} failed."
    done

    rm -rf "$pkgdir"
}

pkg_assemble() { #1: name
    exec 9<"$(pkg_meta_f "$1" filelist)"
    while IFS= read -r file <&9; do
        fsfile="$(path_transform "$file")"
        mkdir -p "$RUPM_PACKAGES/$1/$(dirname "$file")"
        trace "$fsfile -> $RUPM_PACKAGES/$1/$file"
        cp -a "$fsfile" "$RUPM_PACKAGES/$1/$file" \
            || die "$1 member $file failed"
    done
}

pkg_remove() { #1: name
    sed 's|/\.$||' <"$(pkg_meta_f "$1" filelist)" \
        | path_transform \
        | xargs -d'\n' rm -r \
        || die "$name could not be deleted."
}

tasks=""
while getopts vqC:SPR opt; do
    case $opt in
    v) verbosity="$(($verbosity + 1))" ;;
    q) verbosity="$(($verbosity - 1))" ;;
    C) workingdir="$OPTARG"; info "Creating packages from $workingdir" ;;
    S) tasks="$tasks pkg_get pkg_install" ;;
    P) tasks="$tasks pkg_assemble pkg_put" ;;
    R) tasks="$tasks pkg_remove" ;;
    esac
done
cd "$workingdir"
shift "$(($OPTIND - 1))"
for task in $tasks; do
    foreach $task "$@"
done

