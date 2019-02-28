#++++++++++++++++
# Copyright:    (C) 2008-2017 UDS/CNRS
# License:       GNU General Public License
#.IDENTIFICATION abib.awk
#.LANGUAGE       NAWK or GAWK script
#.AUTHOR         Francois Ochsenbein [CDS]
#.ENVIRONMENT    
#.KEYWORDS       
#.VERSION  1.0   16-Jan-1997
#.PURPOSE        
#.COMMENTS       Interpret a text like
#		\bibitem{ref1} Bedijn P.J., 1987, A\&A 186, 136 
#		\bibitem{ref2} Blommaert J.A.D.L, van der Veen W.E.C.J., 
#		Habing H.J., 1993, A\&A 267, 39 
#	and generates output as
#		\bibitem{ref1}	1993A&A...267...39B
#----------------

BEGIN{
### Here the list of non-standard Journal Abbreviations in form of
### c[non-standard] = "BIBCODE"
###
### The complete list of bibcodes is at :
###	http://simbad.u-strasbg.fr/simbad/sim-display?data=journals
    c["MN"]  	= "MNRAS" ;
    c["A+A"]  	= "A&A" ;
    c["A+AS"]  	= "A&AS" ;
    c["Acta Astron."] 	= "AcA" ;
    c["New Astron."]    = "NewA" ;
    c["The Messenger"]  = "Msngr" ;
    c["Nat."]		= "Natur" ;
    "date +%Y" | getline; current_year = $1
}

### This function  generates the 18-byte bibcode
function bibcode(y, j, v, p) {
#1) Journal code (remove the backslashes)
    #printf "#...bibcode('%s', '%s', '%s', '%s')\n", y, j, v, p;
    j1 = j ;
    gsub(/[{\\}]/, "", j1) ;
    if (c[j1] != "") j1 = c[j1] ;
    if (index(j1, " ") != 0) {
	nwj = split(j1, aj);
	j1 = aj[nwj] ;
    }
    jc = j1 ;
    sub(/^[^A-Za-z]/,"bibcode?",j1) ;
    while (length(jc) < 5) jc = jc "." ;
#2) Volume
    gsub(/[.]/, "", v);
    vc = v;
    while(length(vc) < 4) vc = "." vc ;
#3) Page
    pc = p ;
    gsub(/[.]/, "", pc);
    lc = substr(pc,1,1); 
    if (index("LAp", lc)>0) { # Letter, Article, etc...
	pc = substr(pc, 2);
    }
    else lc = ".";
    while (length(pc) < 4) pc = "." pc ;
#4) Glue together
    return(y jc vc lc pc) ;
}

### This function  finds the interesting pieces in a reference text:
#	 page, volume, year...
#   We assume last word = page number, previous = volume
function print_ref(text) {
    nw = split(text, w) ;
    p  = w[nw] ;	# Page number
    nw-- ;
    v  = w[nw] ; 	# Volume number
    # For the journal  designation:
    # find first the year, the journal name follows
    for (i=2; i<nw; i++) { y=w[i]+0; if(y > 1900 && y <= current_year) break }
    y = w[i]+0; i++;
    j = w[i]; i++ ;
    if (j == v) {	# Vhen there is a volume and no page
	v = p; p = 1;
    }
    while (i < nw) { j = j " " w[i] ; i++ }
    print ref "\t" bibcode(y,j,v,p) substr(text,1,1) "\t" j1 "." v "." p ;

    ref = "" ; text = "" ;
}

### The code consists in the generation of a file with columns
### \bibitem{..}(tab)volume.page(tab)bibcode

/^ *\\bibitem[[{]/{
    if (text != "") print_ref(text) ;
    i = index($0, "}") ; 
    i++ ;
    while (substr($0,1,i) == " ") i++ ;
    text = substr($0, i); 
    ref  = $1 ;
    next
}
/ *\end{thebibliography}/ {
    if (ref != "") print_ref(text) ;
    next
}

## General Line
#/^ *$/ { if (ref != "") print_ref(text) }

{ if (ref != "") text = text " " $0 }

END { if (ref != "") print_ref(text) }
##########
