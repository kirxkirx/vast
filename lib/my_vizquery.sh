#!/bin/sh
#++++++++++++++++
# Simplified VizieR query script - uses curl only
#----------------

# Temporary file and cleanup
tt="/tmp/vq$"
trap clean_tt 1 2 3 6
clean_tt() { test -z "$tt" || rm -f $tt ; exit 2; }

# Definitions
pgm=`basename $0`

usage='
Usage: vizquery [-mime={text|fits|tsv|csv|votable}] [-site=site] [constraints...]
  Constraints are given in ASU form (-list can be used for a list of targets)
      vizquery -mime=text -source=I/239/hip_main HIP=1..10 
  by default constraints are asked on standard input.
'

if [ $# -lt 1 ]; then
    echo "$usage"
    exit 1
fi

###
### Interpret the arguments
###

cgidir="viz-bin"
vizarg=""
list=""
input_file=1	# Default: constraints in input (file or stdin)

# Initialize temp file
> $tt

while [ $# -gt 0 ]; do
    case "$1" in

     -site=*.*)	# Fully qualified site
        site=`echo "$1" | sed 's/-site=//'`
	;;

     -site=cds|-site=*)	# CDS site
	site="vizier.u-strasbg.fr"
	;;

      -mime=text|-mime=txt)
	script=asu-txt
	;;

      -mime=tsv*)
	script=asu-tsv
	;;

      -mime=csv*)
	script=asu-tsv
	echo "$1" >> $tt
	;;

      -mime=fit*)
	script=asu-fits
	echo "$1" >> $tt
	;;

      -mime=vo*|-mime=votable)
	script=votable
	;;

      -mime=*)
	script=asu-tsv
	echo "$1" >> $tt
	;;

      -out*)
        echo "$1" >> $tt
	;;

      -[lf]i[ls][te]=*)	# A list (file) of targets 
        input_file=0
	if test -z "$list"; then
	    lcol="-c"
	    list=`echo "$1" | cut -d= -f2`
	    test -z "$list" && list="-"
	    echo "-sort=_r" >> $tt
	else
	    echo "#***A single list only is acceptable" 1>&2
	    exit 1
	fi
	;;

      -list)		# A list (file) of targets 
        input_file=0
	lcol="-c"
	list="-"
	echo "-sort=_r" >> $tt
	;;

      *=*)	# Any ASU argument, assumed a search constraint
	input_file=0
        echo "$1" >> $tt
	;;

      -h*)	# HELP
	echo "$usage"
	exit 0
	;;

      -)	# additional arguments from stdin
        input_file=1
	break
	;;

    [.:\#-]*)	# Any other optional argument: for vizier
        echo "$1" >> $tt
	;;

      *)
        input_file=1
	break

    esac
    shift
done

###
### Defaults
###
test -z "$site"   && site="vizier.u-strasbg.fr"
test -z "$script" && script="asu-tsv"

# Build curl command
call="curl $VAST_CURL_PROXY -s -X POST --data-binary @$tt --retry 1 --retry-delay 5 --connect-timeout 10 --speed-limit 100 --speed-time 15 http://$site/$cgidir/$script"

# Handle input
if [ $input_file -gt 0 ]; then	# Input in a file:
    tty -s && test $# -eq 0 && echo \
           "#---Type your input ASU parameters (terminate with Control-D)" 1>&2
    cat $* >> $tt; 
elif [ -z "$list" ]; then	# No file
    echo "#...ASU parameters being sent to vizier" 1>&2
elif [ -r "$list" ]; then	# Has a valid list
    echo "#...query with a list ($lcol) in file: $list" 1>&2
    ( echo "$lcol=<<====$list"; cat "$list"; echo "====$list") >> $tt
elif [ "$list" = "-" ]; then	# stdin
    echo "#...query with a list ($lcol): enter your targets, 1 per line" 1>&2
    ( echo "$lcol=<<====$list"; cat ; echo "====$list") >> $tt
else				# Invalid input list
    echo "#***Can't read file: $list" 1>&2
    clean_tt
    exit 1
fi

# Execute the query
$call 
rm -f $tt
