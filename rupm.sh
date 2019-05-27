#!/usr/bin/env sh
#rupm - relocatable user package manager


set -a
ARCH="${ARCH:-$(uname -m)}"
OS="${OS:-$(uname -s)}"
if [ "$OS" = Darwin ]; then
    XDG_CONFIG_HOME="${XDG_CONFIG_HOME-$HOME/Library/Application Support}"
    XDG_DATA_HOME="${XDG_DATA_HOME-$HOME/Library/Local/share}"
    XDG_CACHE_HOME="${XDG_CACHE_HOME-$HOME/Library/Caches}"
    MACOS_LIBRARY="${MACOS_LIBRARY-$HOME/Library}"
    PREFIX="${PREFIX-$HOME/Library/Local}"
else
    XDG_CONFIG_HOME="${XDG_CONFIG_HOME-$HOME/.config}"
    XDG_DATA_HOME="${XDG_DATA_HOME-$HOME/.local/share}"
    XDG_CACHE_HOME="${XDG_CACHE_HOME-$HOME/.cache}"
    PREFIX="${PREFIX-$HOME/.local}"
fi
BINDIR="${BINDIR-$PREFIX/bin}"
LIBDIR="${LIBDIR-$PREFIX/lib}"
MANDIR="${MANDIR-$XDG_DATA_HOME/man}"

RUPM_PKGINFO="${RUPM_PKGINFO-$XDG_DATA_HOME/rupm/pkginfo}"
RUPM_PRVINFO="${RUPM_PRVINFO-$XDG_DATA_HOME/rupm/prv}"
set +a

RUPM_PACKAGES="${RUPM_PACKAGES-$XDG_CACHE_HOME/rupm/packages}"
IDENTREGEX='[A-Za-z-]*.[A-Za-z0-9_.]*_[A-Za-z0-9_]*-[A-Za-z0-9_-]*'
IDENTPRINT='%s.%s_%s-%s'

verbosity="0"

trace() { [ "$verbosity" -ge "3" ] && printf '%s\n' "$*" >&2; true;}
debug() { [ "$verbosity" -ge "2" ] && printf '%s\n' "$*" >&2; true;}
info() { [ "$verbosity" -ge "1" ] && printf '%s\n' "$*" >&2; true;}
warn() { [ "$verbosity" -ge "0" ] && printf '%s\n' "$*" >&2; true;}
err() { [ "$verbosity" -ge "-1" ] && printf '%s\n' "$*" >&2; true;}
die() { [ "$verbosity" -ge "-2" ] && printf '%s\n' "$*" >&2; exit 1; }

foreach() {
    func="$1"; shift;
    for i in "$@"; do
        $func "$i"
    done
}

#POSIX xargs does not handle newline-separated files
fargs() {
    while IFS= read -r line; do set -- "$@" "$line"; done
    "$@"
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

url_clean() { #1: url
    echo "$1" | sed 's|://|_|;s|/|_|;'
}

prv_meta() { #1: prv, 2?: metafile
    echo "$RUPM_PRVINFO/$(url_clean "$1")${2:+/$2}"
}

prv_meta_f() { #1: prv, 2?: metafile
    [ -f "$(prv_meta "$@")" ] || die "repo $1 missing info${2:+ ($2)}"
    prv_meta "$@"
}

prv_cache() { #1: prv, 2?: file
    mkdir -p "$XDG_CACHE_HOME/$(url_clean "$1")"
    echo "$XDG_CACHE_HOME/$(url_clean "$1")${2:+/$2}"
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
    [ "$verbosity" -ge "1" ] || curlopts="-s"
    case "$2" in
    get)
        set -- "$@" "$(pkg_choose "$1" "$3")" #4: ident
        set -- "$@" "$1$4.tar" #5: pkg_uri
        set -- "$@" "$(prv_cache "$1" "$4.tar")" #6: cached_pkg
        curl -N $curlopts --progress-bar --fail "$5" -o "$6" \
            && debug "$3 downloaded from $1" \
            && mkdir -p "$RUPM_PACKAGES/$3" \
            && tar -C"$RUPM_PACKAGES/$3" -xf"$6"
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
    set -- "$(echo "$1" | sed 's|^ssh://||')" "$2" "$3"

    case "$2" in
    get)
        set -- "$@" "$(pkg_choose "ssh://$1" "$3")" #4: ident
        set -- "$@" "$1$4.tar" #5: pkg_uri
        set -- "$@" "$(prv_cache "$1" "$4.tar")" #6: cached_pkg
        scp "$5" "$6" \
            && debug "$3 downloaded from $1" \
            && mkdir -p "$RUPM_PACKAGES/$3" \
            && tar -C"$RUPM_PACKAGES/$3" -xf"$6"
        ;;
    put)
        set -- "$@" "$(pkg_mkident "$3")" #4: ident
        set -- "$@" "$1$4.tar" #5: pkg_uri
        set -- "$@" "$(prv_cache "$1" "$4.tar")" #6: cached_pkg
        sort "$(pkg_meta_f "$3" filelist)" \
            | (cd "$RUPM_PACKAGES/$3"; fargs tar -cf "$6") \
            && chmod 0644 "$6" \
            && scp "$6" "$5" \
            && rm -r "$RUPM_PACKAGES/$3" \
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
        [ -d "$(path_transform "$file")" ] && file="$file/."
        cp_f "$(path_transform "$file")" "$RUPM_PACKAGES/$1/$file" "$1/$file"
    done
}

pkg_edit() { #1: name
    set -- "$1" "$(pkg_meta "$1")" #2: pkgmeta
    mkdir -p "$2"
    (
        cd "$2"
        [ -e "filelist" ] || echo "\$RUPM_PKGINFO/$1" >"filelist"
        "$EDITOR" "filelist"
        [ -n "$(sed '/^\$RUPM_PKGINFO\/'"$1"'$/d' filelist)" ] || rm "filelist"
    )
    rmdir "$2" 2>/dev/null || true
}

pkg_remove() { #1: name
    sed 's|/\.$||' <"$(pkg_meta_f "$1" filelist)" \
        | path_transform \
        | fargs rm -r \
        || die "$name could not be deleted."
}

cd "$HOME"
tasks=""
pkgs=""
while getopts vquESyPR opt; do
    case $opt in
    v) verbosity="$(($verbosity + 1))" ;;
    q) verbosity="$(($verbosity - 1))" ;;
    u) pkgs="$(ls -1 "$RUPM_PKGINFO")" ;;
    E) tasks="$tasks pkg_edit" ;;
    S) tasks="$tasks pkg_get pkg_install" ;;
    y) tasks="$tasks prv_sync" ;;
    P) tasks="$tasks pkg_assemble pkg_put" ;;
    R) tasks="$tasks pkg_remove" ;;
    esac
done
shift "$(($OPTIND - 1))"
pkgs="$pkgs $*"
for task in $tasks; do
    if echo "$task" | grep -q '^pkg'; then
        trace "running task $task"
        foreach $task $pkgs
    else
        $task
    fi
done
