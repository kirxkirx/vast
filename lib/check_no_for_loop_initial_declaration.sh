#!/usr/bin/env bash
#
# Check that no C source file declares a variable in the initialization part of
# a 'for' loop, like 'for (int i = 0; ...)'. That is C99: gcc 4.1 on the reference
# system (Scientific Linux 5.6) compiles C as gnu89 by default and rejects it.
# The script is run by GNUmakefile from the VaST root directory and scans all .c
# files below it. Every finding is printed. The exit code is 1 (which stops 'make')
# if any finding is not one of the known exceptions listed in is_allowed_exception().

# 'for (int i', 'for( size_t *p', but not 'for (interval = 0'
FOR_LOOP_DECLARATION_REGEX='for[[:space:]]*\([[:space:]]*(int|size_t)[[:space:]*]'

# Known exceptions: bundled third-party files that are NOT compiled as part of VaST
# (cfitsio builds its iter_* utilities only when configured with BUILD_ITER, and the
# zlib examples are never built). The version number of the bundled library is
# matched with '*' so that an upgrade of the library does not break this check.
function is_allowed_exception {
 case "$1" in
  ./src/cfitsio-*/utilities/iter_image.c|./src/cfitsio-*/utilities/iter_var.c|./src/zlib-*/examples/enough.c)
   return 0
   ;;
 esac
 return 1
}

FOUND_NOT_ALLOWED=0

# 'find -exec ... {} +' runs grep on many files at once: one grep per file takes
# seconds on the ~1900 .c files of VaST and the bundled libraries.
# (The old version of this script set its failure flag inside a 'find | while' pipeline,
# i.e. in a subshell, so it always exited with 0.)
FINDINGS=$(find . -type f -name '*.c' -exec grep -E -H -n "$FOR_LOOP_DECLARATION_REGEX" {} + 2>/dev/null | sort)

if [ -n "$FINDINGS" ];then
 while IFS= read -r FINDING ;do
  # grep -H -n prints file:line:text
  FINDING_FILE="${FINDING%%:*}"
  if is_allowed_exception "$FINDING_FILE" ;then
   echo "$FINDING   <-- allowed exception (a bundled file that VaST does not compile)"
  else
   echo "$FINDING"
   FOUND_NOT_ALLOWED=1
  fi
 done <<< "$FINDINGS"
fi

if [ $FOUND_NOT_ALLOWED -ne 0 ];then
 echo "ERROR: 'for' loop initial declaration(s) found (the lines above not marked as an allowed exception).
Declare the loop variable at the start of the function instead: VaST must compile with gcc 4.1 (C89/gnu89)." 1>&2
 exit 1
fi

exit 0
