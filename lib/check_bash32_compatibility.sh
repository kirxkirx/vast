#!/usr/bin/env bash
#
# Check that the VaST shell scripts work with bash 3.2 - the /bin/bash of macOS.
#
# Usage: lib/check_bash32_compatibility.sh PATH_TO_BASH_3.2
#
# PATH_TO_BASH_3.2 is anything that runs bash 3.2 when given bash arguments:
# /bin/bash on macOS, a bash-3.2.57 binary built from the GNU source, or a wrapper
# script running the official bash:3.2 Docker image (see build_and_test_ubuntu.yml).
#
# Every tracked shell script outside src/ (*.sh files and files starting with
# a bash or sh shebang line) is checked in three ways:
#  - 'bash -n' with bash 3.2. This finds the constructs that bash 3.2 cannot parse,
#    like a case statement inside $( ) that made macOS /bin/bash abort test_vast.sh.
#    Note that bash 3.2 only matches the parentheses of $( ), backticks and <( ) and
#    parses their body when the script runs it, so 'bash -n' does not find other
#    bash 4+ syntax inside them (the lint below covers the common cases).
#  - 'bash -n' with the bash running this script (5.2 on ubuntu-latest). Since bash 5.2
#    it also parses the bodies of $( ) and <( ), so it finds ordinary syntax errors there.
#  - A lint for bash 4+ features that bash 3.2 parses but then fails on at run time,
#    or runs differently without any error message. A lint finding on a line that is
#    known to be safe (for example, guarded by a BASH_VERSINFO check) may be silenced
#    by ending that line with a comment containing 'bash32-ok' and the reason.
#
# Exit code: 0 - all checks passed, 1 - some check failed, 2 - cannot run the checks.
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

if [ -z "$1" ];then
 echo "Usage: $0 PATH_TO_BASH_3.2" >&2
 exit 2
fi
BASH32="$1"
# Make a relative path to the bash 3.2 binary absolute before changing the directory
case "$BASH32" in
 /*) ;;
 */*) BASH32="$PWD/$BASH32" ;;
esac

# Go to the VaST root directory (this script is in lib/)
cd "$(dirname "$0")/.." || exit 2

# Make sure we really got bash 3.x: the checks would pass silently with any newer bash
# shellcheck disable=SC2016
BASH32_VERSION=$("$BASH32" -c 'echo "$BASH_VERSION"' 2>/dev/null)
case "$BASH32_VERSION" in
 3.*) ;;
 "")
  echo "ERROR: cannot run '$BASH32'" >&2
  exit 2
  ;;
 *)
  echo "ERROR: '$BASH32' is bash $BASH32_VERSION, not bash 3.x" >&2
  exit 2
  ;;
esac

# List the shell scripts to check
list_shell_scripts() {
 if command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null ;then
  git -c core.quotepath=off ls-files
 else
  # Not a git working copy (a release archive, or a container without git)
  find . \( -path ./.git -o -path ./src \) -prune -o -type f -print | sed 's:^\./::'
 fi | grep -v '^src/' | sort | while IFS= read -r FILE_TO_CHECK ;do
  # Skip tracked files that were deleted from the working copy, and symlinks
  # (their targets are checked anyway)
  if [ ! -f "$FILE_TO_CHECK" ] || [ -L "$FILE_TO_CHECK" ];then
   continue
  fi
  case "$FILE_TO_CHECK" in
   *.sh)
    echo "$FILE_TO_CHECK"
    continue
    ;;
  esac
  head -n 1 "$FILE_TO_CHECK" 2>/dev/null | grep -qE '^#![[:space:]]*(/usr/bin/env[[:space:]]+)?(/usr/local/bin/|/usr/bin/|/bin/)?(ba)?sh([[:space:]]|$)'
  if [ $? -eq 0 ];then
   echo "$FILE_TO_CHECK"
  fi
 done
}

FILELIST=$(list_shell_scripts)
if [ -z "$FILELIST" ];then
 echo "ERROR: found no shell scripts to check in $PWD" >&2
 exit 2
fi
# Put the file names into the positional parameters (they contain no newlines)
OLD_IFS="$IFS"
IFS='
'
set -f
# shellcheck disable=SC2086
set -- $FILELIST
set +f
IFS="$OLD_IFS"
echo "Checking $# shell scripts in $PWD"

CHECK_FAILED=0

# 'bash -n' with bash 3.2 - a single bash 3.2 process runs the loop, so that a Docker
# wrapper starts only one container. It prints the names of the files it cannot parse;
# the syntax error messages themselves go to stderr.
# shellcheck disable=SC2016
BASH32_FAILED_FILES=$("$BASH32" -c '"$BASH" -c : </dev/null || exit 3 ;for F in "$@" ;do "$BASH" -n -- "$F" </dev/null || echo "$F" ;done ;exit 0' check_bash32 "$@")
if [ $? -ne 0 ];then
 echo "ERROR: could not run the syntax check with '$BASH32'" >&2
 exit 2
fi
if [ -n "$BASH32_FAILED_FILES" ];then
 CHECK_FAILED=1
 echo "$BASH32_FAILED_FILES" | while IFS= read -r FILE_TO_CHECK ;do
  echo "FAILED: bash $BASH32_VERSION cannot parse $FILE_TO_CHECK (see the syntax error above)"
  if [ "$GITHUB_ACTIONS" = "true" ];then
   echo "::error file=$FILE_TO_CHECK::bash $BASH32_VERSION (macOS /bin/bash) cannot parse this script"
  fi
 done
 echo "bash $BASH32_VERSION syntax check: FAILED"
else
 echo "bash $BASH32_VERSION syntax check: PASSED"
fi

# 'bash -n' with the bash running this script
CURRENT_BASH_FAILED=0
for FILE_TO_CHECK in "$@" ;do
 "$BASH" -n -- "$FILE_TO_CHECK" </dev/null
 if [ $? -ne 0 ];then
  CURRENT_BASH_FAILED=1
  echo "FAILED: bash $BASH_VERSION cannot parse $FILE_TO_CHECK (see the syntax error above)"
  if [ "$GITHUB_ACTIONS" = "true" ];then
   echo "::error file=$FILE_TO_CHECK::bash $BASH_VERSION cannot parse this script"
  fi
 fi
done
if [ $CURRENT_BASH_FAILED -ne 0 ];then
 CHECK_FAILED=1
 echo "bash $BASH_VERSION syntax check: FAILED"
else
 echo "bash $BASH_VERSION syntax check: PASSED"
fi

# The lint for bash 4+ features. Only POSIX awk features are used, so any awk works
# (gawk, mawk, BSD awk on macOS, busybox awk). Comment lines and trailing comments
# are ignored. The single quote character is passed in as SQ.
# shellcheck disable=SC2016
BASH4_LINT_AWK_PROGRAM='
function report(rule, message) {
 nfound++
 print FILENAME ":" FNR ": " rule ": " message
 print "    " substr($0, 1, 200)
 if (GHA == "true")
  print "::error file=" FILENAME ",line=" FNR "::" rule ": " message
}
# Quote state at position pos of the line s: 0 - unquoted, 1 - in "...", 2 - in single quotes.
# A whole ${...} is skipped, so that the quotes inside it do not count.
function quote_state(s, pos,    i, c, inq, depth) {
 inq = 0
 for (i = 1; i < pos; i++) {
  c = substr(s, i, 1)
  if (inq == 2) {
   if (c == SQ)
    inq = 0
   continue
  }
  if (c == "\\") {
   i++
   continue
  }
  if (c == "$" && substr(s, i + 1, 1) == "{") {
   depth = 0
   for (i = i + 1; i < pos; i++) {
    c = substr(s, i, 1)
    if (c == "{")
     depth++
    else if (c == "}") {
     depth--
     if (depth == 0)
      break
    }
   }
   continue
  }
  if (c == "\"") {
   inq = (inq == 1) ? 0 : 1
   continue
  }
  if (c == SQ && inq == 0)
   inq = 2
 }
 return inq
}
# ${VAR/pattern/replacement} and ${VAR//pattern/replacement}:
# - bash 3.2 ends the pattern at a quoted slash: ${VAR//"a/b"/c} does not replace "a/b";
# - inside double quotes bash 3.2 keeps the quotes of a quoted replacement:
#   "${VAR/a/"b"}" gives "b" with the quote characters around it.
function check_pattern_substitution(s,    rest, off, start, n, i, c, q, bad_pattern, quoted_replacement, depth) {
 n = length(s)
 off = 0
 rest = s
 while (match(rest, /\$\{([A-Za-z_][A-Za-z_0-9]*|[0-9]+|[@*])(\[[^]]*\])?\//)) {
  start = off + RSTART
  i = off + RSTART + RLENGTH
  off = i - 1
  rest = substr(s, i)
  c = substr(s, i, 1)
  if (c == "/" || c == "#" || c == "%")
   i++
  # Walk through the pattern
  q = ""
  bad_pattern = 0
  for (; i <= n; i++) {
   c = substr(s, i, 1)
   if (q == "") {
    if (c == "\\") {
     i++
     continue
    }
    if (c == "\"" || c == SQ) {
     q = c
     continue
    }
    if (c == "/" || c == "}")
     break
   } else {
    if (c == q) {
     q = ""
     continue
    }
    if (q == "\"" && c == "\\") {
     i++
     continue
    }
    if (c == "/")
     bad_pattern = 1
   }
  }
  if (bad_pattern)
   report("BASH32_QUOTED_SLASH_IN_PATTERN", "bash 3.2 ends the ${VAR/pattern/...} pattern at a quoted slash - use a backslash-escaped slash (\\/) or sed")
  if (c != "/")
   continue
  # Walk through the replacement
  quoted_replacement = 0
  depth = 0
  for (i++; i <= n; i++) {
   c = substr(s, i, 1)
   if (c == "\\") {
    i++
    continue
   }
   if (c == "\"" || c == SQ)
    quoted_replacement = 1
   if (c == "{")
    depth++
   if (c == "}") {
    if (depth == 0)
     break
    depth--
   }
  }
  if (quoted_replacement && quote_state(s, start) == 1)
   report("BASH32_QUOTED_REPLACEMENT_IN_DOUBLE_QUOTES", "inside double quotes bash 3.2 keeps the quote characters of a quoted ${VAR/pattern/replacement} replacement")
 }
}
FNR == 1 {
 in_dq_comsub = 0
}
{
 line = $0
 # Skip comment lines (including the shebang line) and the lines marked as safe
 if (line ~ /^[[:space:]]*#/)
  next
 if (index(line, "bash32-ok") > 0)
  next
 # Remove a trailing comment (roughly: a # after a whitespace)
 sub(/[[:space:]]#.*$/, "", line)

 if (line ~ /(^|[;&|({`[:space:]])(declare|local|typeset|readonly)[[:space:]]+(-[A-Za-z]*[[:space:]]+)*-[A-Za-z]*[AglunI]/)
  report("BASH4_DECLARE_OPTION", "declare/local options -A -g -l -u -n -I are not in bash 3.2 (associative arrays, global, case-converting, nameref)")
 if (line ~ /(^|[;&|({`[:space:]])local[[:space:]]+-([[:space:];]|$)/)
  report("BASH4_LOCAL_DASH", "local - is not in bash 3.2")
 if (line ~ /(^|[;&|({`]|then|do|else)[[:space:]]*(mapfile|readarray|coproc)([[:space:]]|$)/)
  report("BASH4_BUILTIN", "mapfile, readarray and coproc are not in bash 3.2")
 if (line ~ /\$\{([A-Za-z_][A-Za-z_0-9]*|[0-9]+|[@*])(\[[^]]*\])?(\^|,)/)
  report("BASH4_CASE_MODIFICATION", "the case-modifying expansions (^ ^^ , ,,) are a fatal bad substitution in bash 3.2 - use tr")
 if (line ~ /\$\{([A-Za-z_][A-Za-z_0-9]*|[0-9]+|[@*])(\[[^]]*\])?@[QEPAaUuLKk]\}/)
  report("BASH4_TRANSFORMATION", "the @ transformations (@Q @E @P @A @a @U @u @L @K) are a fatal bad substitution in bash 3.2")
 if (line ~ /\$\{?(EPOCHSECONDS|EPOCHREALTIME|BASHPID|SRANDOM|BASH_ARGV0)([^A-Za-z0-9_]|$)/)
  report("BASH4_VARIABLE", "EPOCHSECONDS, EPOCHREALTIME, BASHPID, SRANDOM and BASH_ARGV0 are empty in bash 3.2")
 if (line ~ /(^|[;&|({`[:space:]])wait[[:space:]]+-[A-Za-z]*[nfp]/)
  report("BASH4_WAIT_OPTION", "wait -n/-f/-p are not in bash 3.2 (wait returns 2 at once)")
 if (line ~ /(^|[;&|({`[:space:]])read[[:space:]]+([^&;|]*[[:space:]])?-[A-Za-z]*[Ni][A-Za-z]*([[:space:]]|$)/)
  report("BASH4_READ_OPTION", "bash 3.2 has no -N and -i options for read")
 if (line ~ /(^|[;&|({`[:space:]])read[[:space:]]+([^&;|]*[[:space:]])?-[A-Za-z]*t[[:space:]]*[0-9]*\.[0-9]/)
  report("BASH4_READ_OPTION", "bash 3.2 read -t accepts only a whole number of seconds")
 if (line ~ /\{[A-Za-z_][A-Za-z_0-9]*\}[<>]/)
  report("BASH4_NAMED_FD", "the named file descriptor redirection ({VAR} followed by > or <) is not in bash 3.2")
 if (line ~ /shopt[[:space:]]+(-[A-Za-z]+[[:space:]]+)*(autocd|checkjobs|compat32|compat4[0-4]|compat5[0-9]|complete_fullquote|direxpand|dirspell|globasciiranges|globskipdots|globstar|inherit_errexit|lastpipe|localvar_inherit|localvar_unset|assoc_expand_once|array_expand_once|noexpand_translation|patsub_replacement|progcomp_alias|varredir_close)([^A-Za-z0-9_]|$)/)
  report("BASH4_SHOPT", "this shopt option is not in bash 3.2")
 if (line ~ /\$\{[A-Za-z_][A-Za-z_0-9]*\[[[:space:]]*-[[:space:]]*[0-9]/ || line ~ /(^|[;&|({`[:space:]])[A-Za-z_][A-Za-z_0-9]*\[-[0-9]+\]\+?=/)
  report("BASH4_NEGATIVE_SUBSCRIPT", "negative array subscripts are a bad array subscript in bash 3.2")
 if (line ~ /\$\{([A-Za-z_][A-Za-z_0-9]*|[0-9]+|[@*])(\[[^]]*\])?:[^}:]*:[[:space:]]*-[[:space:]]*[0-9]/)
  report("BASH4_NEGATIVE_LENGTH", "a negative substring length is a fatal error in bash 3.2 (substring expression < 0)")
 if (line ~ /printf[[:space:]].*%-?[0-9]*\([^)]*\)T/)
  report("BASH4_PRINTF_TIME", "the printf time format is not in bash 3.2 - use date")
 if (line ~ /\{-?[0-9]+\.\.-?[0-9]+\.\.-?[0-9]+\}/ || line ~ /\{[A-Za-z]\.\.[A-Za-z]\.\.-?[0-9]+\}/)
  report("BASH4_BRACE_STEP", "bash 3.2 does not expand a brace sequence with a step, it leaves it as is")
 if (line ~ /\{-?0[0-9]+\.\.-?[0-9]+\}/ || line ~ /\{-?[0-9]+\.\.-?0[0-9]+\}/)
  report("BASH4_BRACE_ZERO_PADDING", "bash 3.2 does not zero-pad a brace sequence with leading zeros")
 if (line ~ /(^|[;&|(!{[:space:]])(\[\[?|test)[[:space:]]+(![[:space:]]+)?-[vR][[:space:]]/)
  report("BASH4_TEST_V", "the -v and -R test operators are not in bash 3.2 (a syntax error in double brackets, always false in single brackets)")
 # These do not parse in bash 3.2, but bash -n misses them inside $( ), backticks and <( )
 # (HTML character entities like &nbsp; are removed first)
 tokens = line
 gsub(/&[A-Za-z]+;/, "", tokens)
 gsub(/&#[0-9]+;/, "", tokens)
 if (tokens ~ /\|[&]/)
  report("BASH4_PIPE_STDERR", "|" "& is not in bash 3.2 - use 2>&1 and a pipe")
 if (tokens ~ /&[>][>]/)
  report("BASH4_APPEND_BOTH", "&" ">> is not in bash 3.2 - use >>file 2>&1")
 if (tokens ~ /;;?&([[:space:]]|$)/)
  report("BASH4_CASE_FALLTHROUGH", "the case terminators ;" "& and ;;" "& are not in bash 3.2")
 # bash 3.2 ends $( ) at the ) of a case pattern. Outside double quotes bash -n catches this,
 # but "$( case ... )" silently runs a truncated command.
 if (in_dq_comsub) {
  if (line ~ /^[[:space:]]*\)/ || index(line, ")\"") > 0)
   in_dq_comsub = 0
  else if (line ~ /(^|[;&|({`[:space:]])case[[:space:]]+[^[:space:]]+[[:space:]]+in([[:space:]]|$)/)
   report("BASH32_CASE_IN_QUOTED_COMSUB", "bash 3.2 cannot parse a case statement inside \"$( )\" - move it to a function or use grep")
 }
 rest = line
 off = 0
 while (match(rest, /\$\(/)) {
  pos = off + RSTART
  off = pos + 1
  rest = substr(line, off + 1)
  # Skip $(( arithmetic and the $( ) outside double quotes
  if (substr(rest, 1, 1) == "(" || quote_state(line, pos) != 1)
   continue
  if (rest ~ /^[[:space:]]*$/)
   in_dq_comsub = 1
  else if (rest ~ /^([^)]*[;&|({`]|[^)]*[[:space:]](then|do|else)[[:space:]])?[[:space:]]*case[[:space:]]+[^[:space:]]+[[:space:]]+in([[:space:]]|$)/)
   report("BASH32_CASE_IN_QUOTED_COMSUB", "bash 3.2 cannot parse a case statement inside \"$( )\" - move it to a function or use grep")
 }
 # The VAST_PATH clean-up line used in many VaST scripts has a quoted slash in the pattern,
 # so it does nothing in bash 3.2. That is harmless: the path works with a double slash.
 while ((k = index(line, VAST_PATH_IDIOM)) > 0)
  line = substr(line, 1, k - 1) "VAST_PATH" substr(line, k + length(VAST_PATH_IDIOM))
 if (index(line, "${") > 0)
  check_pattern_substitution(line)
}
END {
 if (nfound > 0)
  exit 1
 exit 0
}
'
SQ="'"
# shellcheck disable=SC2016
VAST_PATH_IDIOM='${VAST_PATH/'"'//'/'/'"'}'
awk -v SQ="$SQ" -v VAST_PATH_IDIOM="$VAST_PATH_IDIOM" -v GHA="$GITHUB_ACTIONS" "$BASH4_LINT_AWK_PROGRAM" "$@"
if [ $? -ne 0 ];then
 CHECK_FAILED=1
 echo "bash 4+ feature lint: FAILED (a line that is safe can be marked with a '# bash32-ok: reason' comment)"
else
 echo "bash 4+ feature lint: PASSED"
fi

if [ $CHECK_FAILED -ne 0 ];then
 echo "Bash 3.2 compatibility check FAILED"
 exit 1
fi
echo "Bash 3.2 compatibility check PASSED"
exit 0
