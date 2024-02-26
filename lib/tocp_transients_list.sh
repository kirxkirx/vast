#!/bin/bash

curl --silent http://www.cbat.eps.harvard.edu/unconf/tocp.html | grep -e 'PNV J' -e 'TCP J' -e 'PSN J' | awk -F'>' '{print $2" "$3}' | sed -e 's/<\/a//g' -e 's/*//g' -e 's/2015 11 16 8167/2015 11 16.8167/g' -e 's/04 17 54 27/04 17 54.27/g' -e 's/01 34 21.40 +30 23 26.6./01 34 21.40 +30 23 26.6 /g' -e 's/14 51 37 83 +40 35 51 4  17 0 U/14 51 37.83 +40 35 51.4  17.0 U/g' | awk '{print $6":"$7":"$8" "$9":"$10":"$11"  "$1" "$2"  "$3"-"$4"-"$5"  "$12"mag"}' | uniq

