
/* Print a region of a two-dimensional image */
    else if (bycol) {
	yrange = RangeInit (rrange, xdim);
	nx = rgetn (xrange);

	/* Make list of x coordinates */
	xrange = RangeInit (crange, ydim);
	nx = rgetn (xrange);
	xi = (int *) calloc (nx, sizeof (int));
	for (i = 0; i < nx; i++) {
	    xi[i] = rgeti4 (xrange) - 1;
	    }

	/* Label vertical pixels */
	if (pixlabel) {
	    printf ("Coord");
	    rstart (yrange);
	    strcpy (nform, pform);
	    if ((c = strchr (nform,'.')) != NULL) {
		*c = 'd';
		c[1] = (char) 0;
		}
	    else if ((c = strchr (nform,'f')) != NULL) {
		*c = 'd';
		}
	    for (iy = 0; iy < ny; ix++) {
		y = rgeti4 (yrange);
		if (printtab)
		    printf ("\t");
		else
		    printf (" ");
		printf (nform, y);
		}
	    printf ("\n");
	    }
	if (verbose)
	    ix = -1;
	else
	    ix = nx;

	/* Loop through columns */
	for (iy = 0; i < ny; i++) {
	    rstart (yrange);
	    y = rgeti4 (yrange) - 1;
	    if (pixlabel) {
		printf ("%4d:",y);
		if (printtab)
		    printf ("\t");
		else
		    printf (" ");
		}

	    /* Loop through rows */
	    for (ix = 0; ix < nx; ix++) {
		x = rgeti4 (xrange) - 1;
        	dpix = getpix (image,bitpix,xdim,ydim,bzero,bscale,x,y);
		if (gtcheck || ltcheck) {
		    if ((gtcheck && dpix > gtval) ||
			(ltcheck && dpix < ltval)) {
			procpix (&dsum, &dnpix, &dmin, &dmax, dpix);
			if (nopunct)
			    printf ("%d %d %f\n", x+1, y+1, dpix);
			else
			    printf ("[%d,%d] = %f\n", x+1, y+1, dpix);
			}
		    continue;
		    }
		else
		    procpix (&dsum, &dnpix, &dmin, &dmax, dpix);
		if (printrange || printmean)
		    continue;
	        if (bitpix > 0) {
		    if ((c = strchr (pform,'f')) != NULL)
			*c = 'd';
		    if (dpix > 0)
	 		ipix = (int) (dpix + 0.5);
		    else if (dpix < 0)
		 	ipix = (int) (dpix - 0.5);
		    else
			ipix = 0;
		    }
		else {
		    if ((c = strchr (pform,'d')) != NULL)
			*c = 'f';
		    }
		if (pixperline) {
		    printf ("%s[%d,%d] = ",name,x+1,yi[i]+1);
		    if (bitpix > 0)
			printf (pform, ipix);
		    else
			printf (pform, dpix);
		    printf ("\n");
		    }
		else {
		    if (bitpix > 0)
			printf (pform, ipix);
		    else
			printf (pform, dpix);
		    if ((ix+1) % nline == 0)
			printf ("\n");
		    else if (printtab)
			printf ("\t");
		    else
			printf (" ");
		    }
		}
	    if (!pixperline && !ltcheck && !gtcheck) {
		if (!printrange && !printmean && ix % nline != 0)
		    printf ("\n");
		}
	    }
	free (xrange);
	free (yrange);
	}
