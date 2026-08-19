#!/usr/bin/env bash
# NovaMine launcher for Linux and macOS.
#
# Installs PHP on first run if it isn't there, enables PHP's JIT compiler when the
# build supports it, then starts the server. Safe to run repeatedly - everything it
# does is idempotent, and setup problems never stop the server from starting.
#
# Undo the JIT settings:  ./start.sh --revert-jit

set -uo pipefail
cd "$(dirname "$0")" || exit 1

SERVER_ROOT="$(pwd)"
PHP_DIR="$SERVER_ROOT/bin/php"
PHP_BIN="$PHP_DIR/bin/php"
MARKER="$PHP_DIR/.novamine-setup"
PMMP_TAG="pm5-latest"

green() { printf '\033[32m  %s\033[0m\n' "$1"; }
warn()  { printf '\033[33m  %s\033[0m\n' "$1"; }
info()  { printf '  %s\n' "$1"; }

find_php() {
    if [ -x "$PHP_BIN" ]; then echo "$PHP_BIN"; return 0; fi
    if [ -x "$PHP_DIR/php" ]; then echo "$PHP_DIR/php"; return 0; fi
    command -v php 2>/dev/null && return 0
    return 1
}

php_ini_path() {
    local php="$1"
    # The bundled build keeps php.ini next to the binary; fall back to what PHP reports.
    if [ -f "$PHP_DIR/bin/php.ini" ]; then echo "$PHP_DIR/bin/php.ini"; return; fi
    local reported
    reported="$("$php" -r 'echo php_ini_loaded_file() ?: "";' 2>/dev/null)"
    [ -n "$reported" ] && echo "$reported" || echo "$PHP_DIR/bin/php.ini"
}

# ------------------------------------------------------------------- revert
if [ "${1:-}" = "--revert-jit" ]; then
    php="$(find_php)" || { warn "No PHP found."; exit 1; }
    ini="$(php_ini_path "$php")"
    if [ -f "$ini" ]; then
        sed -i.bak '/^[[:space:]]*opcache\.jit/d; /^[[:space:]]*;[[:space:]]*\[NovaMine\]/d' "$ini" 2>/dev/null \
            || sed -i '' '/^[[:space:]]*opcache\.jit/d; /^[[:space:]]*;[[:space:]]*\[NovaMine\]/d' "$ini"
        green "Removed the JIT settings from $ini"
    fi
    rm -f "$MARKER"
    info "Done."
    exit 0
fi

# --------------------------------------------------- 1. make sure PHP exists
if ! find_php >/dev/null 2>&1; then
    printf '\n\033[36mPHP not found - installing it into bin/php ...\033[0m\n'
    case "$(uname -s)" in
        Linux)  asset="PHP-8.2-Linux-x86_64-PM5.tar.gz" ;;
        Darwin) if [ "$(uname -m)" = "arm64" ]; then asset="PHP-8.2-MacOS-arm64-PM5.tar.gz"; else asset="PHP-8.2-MacOS-x86_64-PM5.tar.gz"; fi ;;
        *)      warn "Unsupported OS $(uname -s) - install PHP manually."; exit 1 ;;
    esac

    url="https://github.com/pmmp/PHP-Binaries/releases/download/$PMMP_TAG/$asset"
    tmp="$(mktemp -d)"
    ok=1
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$tmp/php.tar.gz" || ok=0
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$url" -O "$tmp/php.tar.gz" || ok=0
    else
        warn "Neither curl nor wget is available."; ok=0
    fi

    if [ "$ok" -eq 1 ]; then
        mkdir -p "$SERVER_ROOT/bin"
        # The tarball contains bin/php/..., so unpack at the server root.
        tar -xzf "$tmp/php.tar.gz" -C "$SERVER_ROOT" || ok=0
    fi
    rm -rf "$tmp"

    if [ "$ok" -ne 1 ] || ! find_php >/dev/null 2>&1; then
        warn "Could not install PHP automatically."
        warn "Download it from https://github.com/pmmp/PHP-Binaries/releases ($PMMP_TAG)"
        warn "and unpack it so that bin/php/bin/php exists."
        exit 1
    fi
    green "installed PHP $("$(find_php)" -r 'echo PHP_VERSION;' 2>/dev/null)"
fi

PHP="$(find_php)"

# ------------------------------------------------------------- 2. enable JIT
# Only touches php.ini, and only when this build actually has JIT compiled in.
# Unlike Windows there is no official drop-in OPcache to swap in, so if the build
# lacks JIT we simply carry on - the server runs fine either way.
if [ ! -f "$MARKER" ]; then
    has_jit="$("$PHP" -r "echo isset(opcache_get_status(false)['jit']) ? 'yes' : 'no';" 2>/dev/null || echo no)"
    if [ "$has_jit" = "yes" ]; then
        ini="$(php_ini_path "$PHP")"
        mkdir -p "$(dirname "$ini")"
        [ -f "$ini" ] || : > "$ini"
        if ! grep -qE '^[[:space:]]*opcache\.jit[[:space:]]*=' "$ini" 2>/dev/null; then
            {
                echo ""
                echo "; [NovaMine] tracing JIT: profiles hot loops at runtime and compiles the paths"
                echo "; [NovaMine] that actually run - the right fit for a long-lived server process."
                echo "; [NovaMine] Undo with:  ./start.sh --revert-jit"
                echo "opcache.jit=tracing"
                echo "opcache.jit_buffer_size=128M"
            } >> "$ini"
        fi
        state="$("$PHP" -r '$s=opcache_get_status(false); echo ($s["jit"]["on"] ?? false) ? "on" : "off";' 2>/dev/null || echo off)"
        if [ "$state" = "on" ]; then green "JIT enabled"; else warn "JIT could not be enabled - the server will still run."; fi
    else
        info "This PHP build has no JIT support - continuing without it."
    fi
    printf 'NovaMine setup completed %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" > "$MARKER"
fi

# ---------------------------------------------------------------- 3. run it
if   [ -f "NovaMine.phar" ];       then PHAR="NovaMine.phar"
elif [ -f "PocketMine-MP.phar" ];  then PHAR="PocketMine-MP.phar"
else warn "NovaMine.phar not found next to this script."; exit 1
fi

while true; do
    printf '\nType "run" to start the server, or "exit" to quit.\n> '
    read -r input || exit 0
    case "$input" in
        run|RUN|Run) "$PHP" "$PHAR" "$@" || echo "Server crashed or stopped." ;;
        exit|EXIT|Exit) exit 0 ;;
        *) echo "Invalid input." ;;
    esac
done
