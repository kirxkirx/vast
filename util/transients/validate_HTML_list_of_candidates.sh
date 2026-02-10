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
    
    number_of_tags=$(grep -c -i '</body>' "$index_file")
    if [ $number_of_tags -gt 1 ];then
        echo "ERROR: multiple '</body>' tags in $index_file."
        test_passed_return_code=1
    fi
    number_of_tags=$(grep -c -i '</html>' "$index_file")
    if [ $number_of_tags -gt 1 ];then
        echo "ERROR: multiple '</html>' tags in $index_file."
        test_passed_return_code=1
    fi

    return $test_passed_return_code
}

function validate_png_images() {
    local index_file="$1"
    local report_dir
    local test_passed_return_code=0
    local png_file png_info png_width png_height

    report_dir=$(dirname "$index_file")

    echo "Validating PNG images referenced in $index_file..."

    # Check that the 'file' command is available
    if ! command -v file >/dev/null 2>&1; then
        echo "WARNING: 'file' command not found, skipping PNG image validation."
        return 0
    fi

    # Extract all PNG image filenames from <img src="..."> tags
    # These are relative paths within the report directory
    while IFS= read -r png_file; do
        # Skip empty lines
        if [ -z "$png_file" ]; then
            continue
        fi

        local full_path="$report_dir/$png_file"

        # Check file exists and is non-empty
        if [ ! -f "$full_path" ]; then
            echo "ERROR: Referenced image not found: $full_path"
            test_passed_return_code=1
            continue
        fi
        if [ ! -s "$full_path" ]; then
            echo "ERROR: Referenced image is empty: $full_path"
            test_passed_return_code=1
            continue
        fi

        # Get PNG dimensions using the 'file' command
        # Output format: "filename: PNG image data, WIDTH x HEIGHT, ..."
        png_info=$(file "$full_path")
        if ! echo "$png_info" | grep -q 'PNG image data'; then
            echo "ERROR: Not a valid PNG file: $full_path"
            test_passed_return_code=1
            continue
        fi

        png_width=$(echo "$png_info" | sed 's/.*PNG image data, //' | sed 's/ x .*//')
        png_height=$(echo "$png_info" | sed 's/.*PNG image data, //' | sed 's/.* x //' | sed 's/,.*//' | sed 's/ .*//')

        # Validate dimensions based on filename pattern
        case "$png_file" in
            *_reference.png|*_discovery*.png)
                # Finding charts must be exactly 400x400
                if [ "$png_width" != "400" ] || [ "$png_height" != "400" ]; then
                    echo "ERROR: Wrong dimensions for finding chart $png_file: got ${png_width}x${png_height}, expected 400x400"
                    # Flag the specific race condition symptom where a preview overwrites a finding chart
                    if [ "$png_width" -ge 1000 ] 2>/dev/null || [ "$png_height" -ge 1000 ] 2>/dev/null; then
                        echo "ERROR: Finding chart $png_file has full-frame preview dimensions - possible race condition between fits2png and make_finding_chart!"
                    fi
                    test_passed_return_code=1
                else
                    echo "PASS: $png_file is ${png_width}x${png_height} (finding chart)"
                fi
                ;;
            *_preview.png)
                # Full-frame previews are not square in general (depends on the FITS image aspect ratio).
                # Just verify they are larger than finding chart size and that both dimensions are positive.
                if [ "$png_width" -le 0 ] 2>/dev/null || [ "$png_height" -le 0 ] 2>/dev/null; then
                    echo "ERROR: Invalid dimensions for preview $png_file: ${png_width}x${png_height}"
                    test_passed_return_code=1
                elif [ "$png_width" = "400" ] && [ "$png_height" = "400" ]; then
                    echo "ERROR: Preview $png_file has finding chart dimensions (400x400) - possible race condition!"
                    test_passed_return_code=1
                else
                    echo "PASS: $png_file is ${png_width}x${png_height} (preview)"
                fi
                ;;
            *)
                # Unknown pattern, skip dimension check
                continue
                ;;
        esac
    done < <(grep -o 'src="[^"]*\.png"' "$index_file" | sed 's/src="//;s/"$//' | sort -u)

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

overall_result=0

validate_index_html "$index_file"
if [ $? -ne 0 ]; then
    echo "HTML validation failed for $index_file."
    echo "
Note that errors like
ERROR: Missing javascript:toggleElement in /tmp/index.html.
ERROR: Missing <script>printCandidateNameWithAbsLink in /tmp/index.html.
may appear when no coandidates are listed in the HTML file while they are expected to be there.
"
    overall_result=1
else
    echo "HTML validation passed for $index_file."
fi

validate_png_images "$index_file"
if [ $? -ne 0 ]; then
    echo "PNG image validation failed for $index_file."
    overall_result=1
else
    echo "PNG image validation passed for $index_file."
fi

if [ $overall_result -ne 0 ]; then
    echo "Overall validation FAILED for $index_file."
    exit 1
else
    echo "Overall validation PASSED for $index_file."
    exit 0
fi
