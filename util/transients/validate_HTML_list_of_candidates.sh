#!/usr/bin/env bash

# Function to validate the presence of patterns in index.html
function validate_index_html() {
    local index_file="$1"
    local test_passed_return_code=0

    echo "Validating $index_file..."

    # Check if the file exists
    if [ ! -f "$index_file" ]; then
        echo "ERROR: $index_file not found."
        return 1
    fi

    # Define the patterns to check
    declare -A patterns
    patterns["javascript:toggleElement"]="javascript:toggleElement"
    patterns["printCandidateNameWithAbsLink"]="<script>printCandidateNameWithAbsLink"
    patterns["floating-btn"]='<button class="floating-btn"'
    patterns["folding-pre"]="<pre class='folding-pre'>"
    patterns["function_printCandidateNameWithAbsLink"]="function printCandidateNameWithAbsLink"

    # Perform the checks
    for key in "${!patterns[@]}"; do
        if ! grep -q -E "${patterns[$key]}" "$index_file"; then
            echo "ERROR: Missing ${key} in $index_file."
            test_passed_return_code=1
        else
            echo "PASS: Found ${key} in $index_file."
        fi
    done

    # Additional suggestions
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

# Call the validation function in the test section
function NMW_STL_find_NovaVul24_test() {
    local index_file="transient_report/index.html"

    validate_index_html "$index_file"
    if [ $? -ne 0 ]; then
        echo "Validation failed for $index_file."
        return 1
    else
        echo "Validation passed for $index_file."
    fi
}

NMW_STL_find_NovaVul24_test
