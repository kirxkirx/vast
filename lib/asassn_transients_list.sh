#!/bin/bash

# We download only the first 100K and read only the top 2000 lines ~ 100 latest transients, as downloading parsing this page takes a lot of time
data=$(curl --connect-timeout 10 --retry 1 --range 0-102399 --silent --insecure https://www.astronomy.ohio-state.edu/asassn/transients.html | grep -A2000 '<th>ASAS-SN</th>' | grep -A2000 '<th>data</th>' | grep -v -e '<th>ASAS-SN</th>' -e '<th>data</th>' -e '<td></td>')
if [ -z "$data" ];then
 exit 1
fi

source_names=$(echo "$data" | grep -A2 '<tr>' | grep -v '<tr>' | sed ':a;N;$!ba;s/<\/td>\n/ /g' | sed -e 's/<td>//g' -e 's/<\/td>//g' -e 's/--\+//g' -e 's/  \+/ /g')
if [ -z "$source_names" ];then
 exit 1
fi

main_source_names=$(echo "$source_names" | while read -r input_string; do
    first_word=$(echo "$input_string" | awk '{print $1}')
    length=${#first_word}
    if [[ $length -le 3 ]]; then
        echo "$input_string" | awk '{print $1, $2}'
    else
        echo "$first_word"
    fi
done)

# Will consider only the 100 latest transients
echo "$main_source_names" | head -n100 | while read -r MAIN_SOURCE_NAME; do
    # Narrow down the data search for performance
    # MAIN_SOURCE_NAME may appear multiple times on the page, just because
    local_data=$(echo "$data" | grep -m1 -A10 "$MAIN_SOURCE_NAME")
    RA=$(echo "$local_data" | grep -v '://' | grep ':' | head -n1 | sed -e 's/<td>//g' -e 's/<\/td>//g' | awk -F ':' '{printf "%02d:%02d:%05.2f", $1, $2, $3}')
    DEC=$(echo "$local_data" | grep -v '://' | grep ':' | head -n2 | tail -n1 | sed -e 's/<td>//g' -e 's/<\/td>//g' | awk -F ':' '{printf "%+03d:%02d:%05.2f", $1, $2, $3}')
    DATE=$(echo "$local_data" | grep '<td>202.-' | sed -e 's/<td>//g' -e 's/<\/td>//g')
    MAG=$(echo "$local_data" | grep -A1 "$DATE" | tail -n1 | sed -e 's/<td>//g' -e 's/<\/td>//g')
    echo "$RA $DEC  $MAIN_SOURCE_NAME  $DATE $MAG"
done
