#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

VAST_DIR=$PWD
TARGET_DIR=$VAST_DIR/lib
CC=$(lib/find_gcc_compiler.sh)

# Simple test that only checks if zlib can be compiled and linked
test_zlib_compile() {
    local ZLIB_LINK="$1"
    local TEST_ID="zlibtest_$$_$(date +%s)_$RANDOM"
    local TEST_C_FILE="${TEST_ID}.c"
    local TEST_EXE_FILE="${TEST_ID}"
    
    # Create a simple test program
    echo '#include <zlib.h>
int main() { compress(0,0,0,0); return 0; }' > "$TEST_C_FILE"

    # Try to compile and link
    $CC -o "$TEST_EXE_FILE" "$TEST_C_FILE" $ZLIB_LINK &>/dev/null
    local RESULT=$?
    
    # Clean up
    rm -f "$TEST_C_FILE" "$TEST_EXE_FILE" 2>/dev/null
    
    return $RESULT
}

# Test bundled zlib if available
if [ -f "$TARGET_DIR/libz.a" ]; then
    if test_zlib_compile "$TARGET_DIR/libz.a"; then
        echo "$TARGET_DIR/libz.a"
        exit 0
    fi
fi

# Test system zlib
if test_zlib_compile "-lz"; then
    echo "-lz"
    exit 0
fi

# If we get here, neither option worked
echo "ERROR: No working zlib library found!" >&2
exit 1
