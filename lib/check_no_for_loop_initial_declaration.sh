#!/usr/bin/env bash

# Find all .c files and search for the pattern
found=0

find . -type f -name '*.c' | while IFS= read -r file; do
    if grep -E -H -n 'for[[:space:]]*\([[:space:]]*(int|size_t)' "$file"; then
        found=1
    fi
done

# Exit with appropriate code
if [ "$found" -eq 1 ]; then
    exit 1
else
    exit 0
fi
