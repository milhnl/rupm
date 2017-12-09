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
export RUPM_PRVINFO="${RUPM_PRVINFO:-$XDG_DATA_HOME/rupm/prv}"
RUPM_PACKAGES="${RUPM_PACKAGES:-$XDG_CACHE_HOME/rupm/packages}"
IDENTREGEX='[A-Za-z-]*.[A-Za-z0-9_.]*_[A-Za-z0-9_]*-[A-Za-z0-9_-]*'
IDENTPRINT='%s.%s_%s-%s'

ARCH="${ARCH:-$(uname -m)}"
OS="${OS:-$(uname -s)}"
verbosity="0"
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

cp_f() { #1: source, 2: dest, 3: name (optional)
    trace "${3:-1} -> $2"
    mkdir -p "$(dirname "$2")"
    cp -a "$1" "$2" || die "${3:-1} copy failed."
}

path_transform() { #$1: path to transform, or use stdin
    ([ $# -ne 0 ] && echo "$1" || cat) \
        | awk 'BEGIN {OFS = FS = "/"} {
            target = ENVIRON[substr($1, 2)]
            $1 = target != "" ? target : $1
            print
        }'
}

realbase() { #1: path
    basename "$(echo "$1" | sed 's:/.$::')"
}

prv_meta() { #1: prv, 2?: metafile
    echo "$RUPM_PRVINFO/$(echo "$1" | sed 's|://|_|;s|/|_|;')${2:+/$2}"
}

prv_meta_f() { #1: prv, 2?: metafile
    [ -f "$(prv_meta "$@")" ] || die "repo $1 missing info${2:+ ($2)}"
    prv_meta "$@"
}

pkg_meta() { #1: name, 2?: metafile
    echo "$RUPM_PKGINFO/$1${2:+/$2}"
}

pkg_meta_f() { #1: name, 2?: metafile
    [ -f "$(pkg_meta "$@")" ] || die "$1 missing info${2:+ ($2)}"
    pkg_meta "$@"
}

pkg_meta_r() { #1: name, 2: metafile
    cat "$(pkg_meta "$@")"
}

pkg_choose() { #1: prv, 2: name
    grep "^$2" <"$(prv_meta_f "$1" packages)" | tail -n1
}

pkg_mkident() { #1: name
    printf "$IDENTPRINT" "$1" \
        "$(pkg_meta_r "$1" version).$(pkg_meta_r "$1" revision)" \
        "$(pkg_meta_r "$1" arch)" \
        "$(pkg_meta_r "$1" os)"
}

prv_handler_http() { #1: uri, 2: verb, 3: name
    tmp="$(tmp_get)"
    
    [ "$verbosity" -ge "1" ] || curlopts="-s"
    case "$2" in
    get)
        set -- "$1$(pkg_choose "$1" "$3").tar" "$2" "$3"
        curl -N $curlopts --progress-bar --fail "$1" -o "$tmp" \
            && debug "$3 downloaded from $1" \
            && mkdir -p "$RUPM_PACKAGES/$3" \
            && tar -C"$RUPM_PACKAGES/$3" -xf"$tmp"
        ;;
    put) return 1 ;;
    list)
        curl -Ns --fail "$1" \
            | sed 's/<[^>]*>//g' \
            | sed -n 's/\('"$IDENTREGEX"'\).*/\1/p' | sort | uniq
        ;;
    esac
}

prv_handler_ssh() { #1: uri, 2: verb, 3: name
    tmp="$(tmp_get)"
    set -- "$(echo "$1" | sed 's|^ssh://||')" "$2" "$3"

    case "$2" in
    get)
        set -- "$1$(pkg_choose "$1" "$3").tar" "$2" "$3"
        scp "$1" "$tmp" \
            && debug "$3 downloaded from $1" \
            && mkdir -p "$RUPM_PACKAGES/$3" \
            && tar -C"$RUPM_PACKAGES/$3" -xf"$tmp"
        ;;
    put)
        set -- "$1$(pkg_mkident "$3").tar" "$2" "$3"
        sort "$(pkg_meta_f "$3" filelist)" \
            | (cd "$RUPM_PACKAGES/$3"; xargs -xd '\n' tar -cf "$tmp") \
            && chmod 0644 "$tmp" \
            && scp "$tmp" "$1" \
            && rm -r "$tmp" "$RUPM_PACKAGES/$3" \
            && debug "$3 pushed to $1"
        ;;
    list)
        ssh "$(echo "$1" | sed 's|:.*||')" \
            -C "cd '$(echo "$1"|sed 's|^.*:||')'; ls -1" | sed 's/.tar$//'
        ;;
    esac
}

prv_do() { #1: provider, prv_args...
    trace "${3:+$3 }$2 $1"
    case "$1" in
    https://*|http://*) prv_handler_http "$@" ;;
    ssh://*) prv_handler_ssh "$@" ;;
    *) die "provider $1 not supported" ;;
    esac
}

pkg_do() { #prv_args...
    for prv in $RUPM_MIRRORLIST; do
        prv_do "$prv" "$@" && return
    done
    false
}

pkg_get() { pkg_do get "$1" || die "$1 could not be found"; }
pkg_put() { pkg_do put "$1" || die "$1 could not be pushed"; }

prv_sync() {
    for prv in $RUPM_MIRRORLIST; do
        mkdir -p "$(prv_meta "$prv")"
        prv_do "$prv" list \
            | sort -t. -k1,1 -k2,2n -k3,3n -k4,4n -k5,5n -k6,6n -k7,7n \
            >"$(prv_meta "$prv" packages)";
    done;
}

pkg_install() { #1: name
    debug "$1 is installing"
    for envkey in "$RUPM_PACKAGES/$1"/* "$RUPM_PACKAGES/$1"/.[!.]* \
            "$RUPM_PACKAGES/$1"/..?* ; do
        [ -e "$envkey" ] || continue
        [ -d "$envkey" ] && envkey="$envkey/."
        cp_f "$envkey" "$(path_transform "$(realbase "$envkey")")" \
            "${envkey#$RUPM_PACKAGES/}"
    done
    rm -rf "$RUPM_PACKAGES/$1"
}

pkg_assemble() { #1: name
    if [ -f "$(pkg_meta "$1" revision)" ]; then
        expr 1 + "$(pkg_meta_r "$1" revision)" \
            >"$(pkg_meta "$1" revision)"
    else
        echo "0" >"$(pkg_meta "$1" revision)"
    fi
    [ -f "$(pkg_meta "$1" version)" ] || echo "0" >"$(pkg_meta "$1" version)"
    [ -f "$(pkg_meta "$1" arch)" ] || echo "$ARCH" >"$(pkg_meta "$1" arch)"
    [ -f "$(pkg_meta "$1" os)" ] || echo "$OS" >"$(pkg_meta "$1" os)"
    exec 9<"$(pkg_meta_f "$1" filelist)"
    while IFS= read -r file <&9; do
        cp_f "$(path_transform "$file")" "$RUPM_PACKAGES/$1/$file" "$1/$file"
    done
}

pkg_remove() { #1: name
    sed 's|/\.$||' <"$(pkg_meta_f "$1" filelist)" \
        | path_transform \
        | xargs -d'\n' rm -r \
        || die "$name could not be deleted."
}

cd "$HOME"
tasks=""
while getopts vqSyPR opt; do
    case $opt in
    v) verbosity="$(($verbosity + 1))" ;;
    q) verbosity="$(($verbosity - 1))" ;;
    S) tasks="$tasks pkg_get pkg_install" ;;
    y) tasks="$tasks prv_sync" ;;
    P) tasks="$tasks pkg_assemble pkg_put" ;;
    R) tasks="$tasks pkg_remove" ;;
    esac
done
shift "$(($OPTIND - 1))"
for task in $tasks; do
    if echo "$task" | grep -q '^pkg'; then
        trace "running task $task"
        foreach $task "$@"
    else
        $task
    fi
done
