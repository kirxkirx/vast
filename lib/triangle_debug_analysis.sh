#!/bin/bash

# Triangle Matching Debug Analysis Script
# Run this after VaST processing to get a quick summary

echo "=== VaST Triangle Matching Debug Analysis ==="
echo ""

# Check if debug files exist
if [ ! -f "triangle_matching_debug.log" ]; then
    echo "ERROR: Debug files not found. Make sure you ran VaST with debug modifications."
    exit 1
fi

echo "1. TRIANGLE CONSTRUCTION SUMMARY:"
echo "================================="
if [ -f "triangle_matching_debug.log" ]; then
    grep "Reference triangles:" triangle_matching_debug.log
    grep "Current image triangles:" triangle_matching_debug.log
    grep "Equivalent triangles found:" triangle_matching_debug.log
fi
echo ""

echo "2. TRIANGLE MATCHING ANALYSIS:"
echo "=============================="
if [ -f "triangle_similarity_analysis.log" ]; then
    echo "Similarity tolerance: $(grep "Similarity tolerance:" triangle_similarity_analysis.log | cut -d: -f2)"
    echo "Total potential matches: $(grep "Total potential scale matches found:" triangle_similarity_analysis.log | cut -d: -f2)"
fi
echo ""

echo "3. BEST TRIANGLE MATCH:"
echo "======================"
if [ -f "best_triangle_match.log" ]; then
    grep "Number of matched stars:" best_triangle_match.log
    grep "Rotation angle:" best_triangle_match.log
    echo "Translation: $(grep "Translation:" best_triangle_match.log | cut -d: -f2)"
else
    echo "No best triangle match found - algorithm failed at triangle level"
fi
echo ""

echo "4. FINAL MATCHING RESULTS:"
echo "=========================="
if [ -f "final_matching_stats.log" ]; then
    grep "Total stars matched:" final_matching_stats.log
    grep "Success rate:" final_matching_stats.log
    grep "Average matching distance:" final_matching_stats.log
    
    # Count number of bad matches
    bad_matches=$(grep "distance>" final_matching_stats.log | wc -l)
    if [ $bad_matches -gt 0 ]; then
        echo "WARNING: $bad_matches matches with distance > 2.0 pixels"
    fi
else
    echo "No final matching results - algorithm failed before star matching"
fi
echo ""

echo "5. DEBUG FILES GENERATED:"
echo "========================="
echo "DS9 Region files:"
for file in debug_*.reg; do
    if [ -f "$file" ]; then
        count=$(grep -c "circle\|line" "$file" 2>/dev/null || echo "0")
        echo "  $file ($count objects)"
    fi
done

echo ""
echo "Log files:"
for file in *debug*.log *matching*.log best_triangle*.log final_matching*.log triangle_similarity*.log; do
    if [ -f "$file" ]; then
        size=$(wc -l < "$file")
        echo "  $file ($size lines)"
    fi
done

echo ""
echo "6. QUICK DIAGNOSIS:"
echo "=================="

# Determine likely failure mode
equivalent_triangles=$(grep "Equivalent triangles found:" triangle_matching_debug.log | cut -d: -f2 | tr -d ' ')
matched_stars=0
if [ -f "final_matching_stats.log" ]; then
    matched_stars=$(grep "Total stars matched:" final_matching_stats.log | cut -d: -f2 | tr -d ' ')
fi

if [ "$equivalent_triangles" = "0" ]; then
    echo "DIAGNOSIS: No equivalent triangles found"
    echo "LIKELY CAUSES:"
    echo "  - Scale change between images"
    echo "  - Rotation > expected"
    echo "  - Poor star detection quality"
    echo "  - Insufficient bright stars common to both images"
    echo ""
    echo "NEXT STEPS:"
    echo "  1. Load both images in DS9"
    echo "  2. Load debug_reference_stars.reg and debug_current_stars.reg"
    echo "  3. Check if bright stars are detected in both images"
    echo "  4. Examine triangle construction in debug_all_triangles.reg"
    
elif [ "$equivalent_triangles" -gt "0" ] && [ "$matched_stars" = "0" ]; then
    echo "DIAGNOSIS: Triangles found but no star matches"
    echo "LIKELY CAUSES:"
    echo "  - Incorrect triangle correspondence"
    echo "  - Coordinate transformation failure"
    echo "  - Too strict matching radius"
    echo ""
    echo "NEXT STEPS:"
    echo "  1. Check best_triangle_match.log for reasonable transformation"
    echo "  2. Load debug_best_triangle.reg to verify triangle match"
    echo "  3. Examine debug_final_matches.reg for alignment issues"
    
elif [ "$matched_stars" -gt "0" ]; then
    success_rate=$(grep "Success rate:" final_matching_stats.log | cut -d: -f2 | cut -d% -f1 | tr -d ' ')
    if [ "${success_rate%.*}" -lt "50" ]; then
        echo "DIAGNOSIS: Low matching success rate ($success_rate%)"
        echo "LIKELY CAUSES:"
        echo "  - Systematic coordinate distortion"
        echo "  - Partial field overlap"
        echo "  - Image quality differences"
    else
        echo "DIAGNOSIS: Matching appears successful ($success_rate% success rate)"
        echo "Check final_matching_stats.log for detailed statistics"
    fi
else
    echo "DIAGNOSIS: Unable to determine failure mode"
    echo "Check log files manually for more details"
fi

echo ""
echo "7. DS9 VISUALIZATION COMMANDS:"
echo "=============================="
echo "To load all debug regions in DS9:"
echo "  ds9 reference_image.fits &"
echo "  # In DS9: File -> Load Regions -> debug_reference_stars.reg"
echo "  # In DS9: File -> Load Regions -> debug_all_triangles.reg"
echo "  # In DS9: File -> Load Regions -> debug_best_triangle.reg"
echo ""
echo "  ds9 current_image.fits &"
echo "  # In DS9: File -> Load Regions -> debug_current_stars.reg"
echo "  # In DS9: File -> Load Regions -> debug_final_matches.reg"
echo ""
echo "Analysis complete. Check the generated files for detailed debugging information."
