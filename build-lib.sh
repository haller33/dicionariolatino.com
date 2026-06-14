#!/usr/bin/env bash
set -e

mkdir -p bin lib

# Try to find Lua development files using pkg-config
if command -v pkg-config >/dev/null 2>&1; then
    # Try common Lua versions
    for luaver in lua5.1 lua5.2 lua-5.2 lua5.3 lua-5.3 lua5.4 lua-5.4 lua; do
        if pkg-config --exists "$luaver" 2>/dev/null; then
            CFLAGS=$(pkg-config --cflags "$luaver")
            LIBS=$(pkg-config --libs "$luaver")
            echo "Using pkg-config for $luaver"
            break
        fi
    done
else
    if [ -f /data/data/com.termux/files/usr/include/lua5.1/lua.h ]; then
        CFLAGS="-I/data/data/com.termux/files/usr/include/lua5.1"
        LIBS="-llua5.1"
        # Fallback to common include/library paths
        if [ -f /usr/include/lua5.2/lua.h ]; then
            CFLAGS="-I/usr/include/lua5.2"
            LIBS="-llua5.2"
        elif [ -f /usr/include/lua5.3/lua.h ]; then
            CFLAGS="-I/usr/include/lua5.3"
            LIBS="-llua5.3"
        elif [ -f /usr/include/lua5.4/lua.h ]; then
            CFLAGS="-I/usr/include/lua5.4"
            LIBS="-llua5.4"
        else
            CFLAGS="-I/usr/include/lua"
            LIBS="-llua"
        fi
    fi
fi

OUTPUT_DIR='./bin/fuzzy.so'
INPUT_FILE='./lib/fuzzy.c'

echo "Compiling fuzzy.so with CFLAGS=$CFLAGS LIBS=$LIBS"
clang -pedantic -shared -O3 -fPIC -o $OUTPUT_DIR $INPUT_FILE $CFLAGS $LIBS

echo "Build successful. Library: ${OUTPUT_DIR}"
