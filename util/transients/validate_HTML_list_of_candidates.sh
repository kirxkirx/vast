#!/usr/bin/env bash

function validate_index_html() {
    local index_file="$1"
    local test_passed_return_code=0

    echo "Validating $index_file..."

    if [ ! -f "$index_file" ]; then
        echo "ERROR: $index_file not found."
        return 1
    fi

    patterns=(
        "javascript:toggleElement"
        "<script>printCandidateNameWithAbsLink"
        '<button class="floating-btn"'
        "<pre class='folding-pre'>"
        "function printCandidateNameWithAbsLink"
    )

    for pattern in "${patterns[@]}"; do
        if ! grep -q "$pattern" "$index_file"; then
            echo "ERROR: Missing $pattern in $index_file."
            test_passed_return_code=1
        else
            echo "PASS: Found $pattern in $index_file."
        fi
    done

    if ! grep -q '<meta name="viewport" content="width=device-width, initial-scale=1.0">' "$index_file"; then
        echo "WARNING: Missing viewport meta tag in $index_file."
        test_passed_return_code=1
    fi

    if ! grep -q '\.floating-btn' "$index_file"; then
        echo "WARNING: Missing .floating-btn style definition in $index_file."
        test_passed_return_code=1
    fi

    return $test_passed_return_code
}

index_file="transient_report/index.html"
if [ -n "$1" ];then
 echo "Specified index file location $1"
 if [ -f "$1" ];then
  echo "$1 is a regular file"
  index_file="$1"
 elif [ -f "$1/index.html" ];then
  echo "$1 is a directory containing index.html file"
  index_file="$1/index.html"
 fi
fi

validate_index_html "$index_file"
if [ $? -ne 0 ]; then
    echo "Validation failed for $index_file."
    exit 1
else
    echo "Validation passed for $index_file."
    exit
fi
