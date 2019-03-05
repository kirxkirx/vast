# VaST
The Variability Search Toolkit (VaST) is a software tool for finding variable objects on a series of astronomical images. 
The images (CCD frames or digitized photographic plates) must be taken with the same instrument using the same filter 
and saved in the FITS format. The input images may be shifted/rotated/flipped with respect to each other, but they have 
to have the same scale (arcsec/pix) and overlap with each other by at least ~40%. No WCS information in FITS image header
is necessary for the basic processing and lightcurve construction, but VaST may need to plate-solve the images if automated
object identification is needed.

VaST is written in C (and partly in BASH scripting language) for GNU/Linux operating system. The latest versions are 
also tested on MacOS X and FreeBSD. The best practical way to run VaST under Windows is through Linux installed in a 
virtual machine (like VirtualBox).

The detailed description of the code may be found at [the project's homepage](http://scan.sai.msu.ru/vast/) and 
in [the VaST paper](http://adsabs.harvard.edu/abs/2018A%26C....22...28S).

Bug reports and pull requests, as well as new feature suggestions are warmly welcome!
