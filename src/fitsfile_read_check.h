// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_FITSFILE_READ_CHECK_INCLUDE_FILE

#include "vast_limits.h" // defines FILENAME_LENGTH

#include "fitsio.h" // we use a local copy of this file because we use a local copy of cfitsio

#include "safely_encode_user_input_string.h" // for any_unusual_characters_in_string()

#include <stdio.h>

#include <string.h> // for memmem() and strlen()

#include <stdlib.h> // for system()

void *memmem(const void *haystack, size_t haystacklen, const void *needle, size_t needlelen);

static int check_if_the_input_is_FPack_compressed_FITS(char *fitsfilename) {
 int status= 0;  //for cfitsio routines
 fitsfile *fptr; // pointer to the FITS file; defined in fitsio.h
 int hdutype;    // HDU types:
                 //  0 = primary array,
                 //  1 = ASCII table,
                 //  2 = binary table 
 char keystring[FLEN_CARD];
 char keycomment[FLEN_CARD];
 int number_of_hdus;
 
 char system_command[FILENAME_LENGTH+128];
 
 // Check if the file exist at all
 FILE *testfile;
 testfile=fopen(fitsfilename, "r");
 if( testfile== NULL ){
  //fprintf(stderr, "ERROR opening file %s\n", fitsfilename);
  return 1;
 }
 fclose(testfile);
 //
 // check if this is a readable FITS file (of any kind: image, table)
 fits_open_file(&fptr, fitsfilename, READONLY, &status);
 if( 0 != status ) {
  fits_report_error(stderr, status);
  fits_clear_errmsg(); // clear the CFITSIO error message stack
  if( 252 == status ) {
   fprintf(stderr, "'FITSIO status = 252' means the input %s is NOT A FITS FILE!\n", fitsfilename);
   sprintf(system_command, "file %s", fitsfilename );
   if ( 0 != system( system_command ) ) {                                
    fprintf( stderr, "There was a problem running '%s'\n", system_command );
   }
  } // if( 252 == status ) {
  return status;
 }
 fits_get_num_hdus(fptr, &number_of_hdus, &status);
 if( number_of_hdus == 1 ) {
  fits_close_file(fptr, &status);
  return 1;
 }
 // LCO images have HDU 2 as the compressed FITS image
 fits_movabs_hdu(fptr, 2, &hdutype, &status);
 fits_read_key(fptr, TSTRING, "XTENSION", keystring, keycomment, &status);
 if( 0 != status ) {
  fits_report_error(stderr, status);
  fits_clear_errmsg(); // clear the CFITSIO error message stack
  fits_close_file(fptr, &status);
  return 1;
 }
 if( 0 != strncmp(keystring, "BINTABLE", 8) ) {
  fits_close_file(fptr, &status);
  return 1;
 }
 fits_read_key(fptr, TSTRING, "TTYPE1", keystring, keycomment, &status);
 if( 0 != status ) {
  fits_report_error(stderr, status);
  fits_clear_errmsg(); // clear the CFITSIO error message stack
  fits_close_file(fptr, &status);
  return 1;
 }
 if( 0 != strncmp(keystring, "COMPRESSED_DATA", 15) ) {
  fits_close_file(fptr, &status);
  return 1;
 } 
 fits_close_file(fptr, &status);
 return 0;
}

static void check_if_the_input_is_MaxIM_compressed_FITS(char *fitsfilename) {
 FILE *f;
 unsigned char *buffer; // buffer for a part of the header
 unsigned char *pointer_to_the_key_start;
 int getc_return_value;
 int i; 
 f= fopen(fitsfilename, "r");
 if( f == NULL ) {
  return;
 }
 buffer= malloc(65536 * sizeof(char));
 if( buffer == NULL ) {
  fprintf(stderr, "ERROR in check_if_the_input_is_MaxIM_compressed_FITS(): cannot allocate buffer memory\n");
  fclose(f);
  return;
 }
 memset(buffer, 0, 65535); // wipe the memory just in case there was something there
 for( i= 0; i < 65535; i++ ) {
  // getc returns int, not unsigned char
  //buffer[i]= getc(f);
  getc_return_value= getc(f);
  //if( buffer[i] == EOF ) {
  if( getc_return_value == EOF ) {
   break;
  }
  buffer[i]= (unsigned char)getc_return_value;
 }
 fclose(f);
 // Check for signs of the compressed FITS image
 pointer_to_the_key_start= (unsigned char *)memmem(buffer, 65535 - 80, "SIMPLE", 6);
 if( pointer_to_the_key_start != NULL ) {
  pointer_to_the_key_start= (unsigned char *)memmem(buffer, 65535 - 80, "BITPIX", 6);
  if( pointer_to_the_key_start != NULL ) {
   pointer_to_the_key_start= (unsigned char *)memmem(buffer, 65535 - 80, "NAXIS", 5);
   if( pointer_to_the_key_start != NULL ) {
    fprintf(stderr, "\n#########################################################\nThe file %s \nactually looks like a FITS image compressed by MaxIM DL.\nPlease open the image in MaxIM DL software and save it as\nUncompressed FITS. I'm not aware of any other (legal) way\nto uncompress such images.\n#########################################################\n", fitsfilename);
   }
  }
 }
 free(buffer);
 return;
}

// This function will check if the input is a readable FITS image
static inline int fitsfile_read_check(char *fitsfilename) {
 int status= 0;  //for cfitsio routines
 fitsfile *fptr; // pointer to the FITS file; defined in fitsio.h
 int hdutype, naxis;
 long naxes3;
 long naxes4;
 //
 char system_command[FILENAME_LENGTH+128];
 //
 unsigned int i,cfitsio_image_cutout;
 //
 if( (int)strlen(fitsfilename)>FILENAME_LENGTH ) {
  fprintf(stderr, "ERROR in fitsfile_read_check(): the input filename is too long: %d bytes while FILENAME_LENGTH=%d %s\n", (int)strlen(fitsfilename), FILENAME_LENGTH, fitsfilename);
  return 1;
 }
 if( 0 != any_unusual_characters_in_string(fitsfilename) ){
  fprintf(stderr, "The input filename contains unexpected characters!\n");
  return 1;
 }
 //
 // Check if the file exist at all
 FILE *testfile;
 // do this check only if the file does not use CFITSIO image cutout interface
 cfitsio_image_cutout= 0;
 for( i=0; i<strlen(fitsfilename); i++ ) {
  if( fitsfilename[i] == '[' ) {
   cfitsio_image_cutout= 1;
   break;
  }
 }
 if( cfitsio_image_cutout == 0 ) {
  testfile=fopen(fitsfilename, "r");
  if( testfile== NULL ){
   fprintf(stderr, "ERROR opening file %s\n", fitsfilename);
   return 1;
  }
  fclose(testfile);
 }
 //
 // check if this is a readable FITS image
 fits_open_image(&fptr, fitsfilename, READONLY, &status);
 if( 0 != status ) {
  fits_report_error(stderr, status);
  fits_clear_errmsg(); // clear the CFITSIO error message stack
  if( 252 == status ) {
   fprintf(stderr, "'FITSIO status = 252' means the input %s is NOT A FITS FILE!\n", fitsfilename);
   sprintf(system_command, "file %s", fitsfilename );
   if ( 0 != system( system_command ) ) {                                
    fprintf( stderr, "There was a problem running '%s'\n", system_command );
   }
  } // if( 252 == status ) {
  check_if_the_input_is_MaxIM_compressed_FITS(fitsfilename);
  return status;
 }
 fits_get_hdu_type(fptr, &hdutype, &status);
 if( status || hdutype != IMAGE_HDU ) {
  fprintf(stderr, "%s is not a FITS image! Is it a FITS table?\n", fitsfilename);
  fits_close_file(fptr, &status);
  return 1;
 }
 fits_get_img_dim(fptr, &naxis, &status);
 if( status || naxis != 2 ) {
  if( naxis == 3 ) {
   fits_read_key(fptr, TLONG, "NAXIS3", &naxes3, NULL, &status);
   // Yes, we now support on-the-fly conversion of RGB images (G channel extraction)
   if( naxes3 == 1 || naxes3 == 3 ) {
    fprintf(stderr, "%s image has NAXIS = %d, but NAXIS3 = %ld -- maybe there is some hope to handle this image...\n", fitsfilename, naxis, naxes3);
    fits_close_file(fptr, &status);
    return 0;
   }
  }
  if( naxis == 4 ) {
   fits_read_key(fptr, TLONG, "NAXIS3", &naxes3, NULL, &status);
   if( naxes3 == 1 ) {
    fits_read_key(fptr, TLONG, "NAXIS4", &naxes4, NULL, &status);
    if( naxes4 == 1 ) {
     fprintf(stderr, "%s image has NAXIS = %d, but NAXIS3 = %ld and NAXIS4 = %ld -- maybe there is some hope to handle this image...\n", fitsfilename, naxis, naxes3, naxes4);
     fits_close_file(fptr, &status);
     return 0;
    }
   }
  }
  fprintf(stderr, "%s image has NAXIS = %d.  Only 2-D images are supported. -- fitsfile_read_check()\n", fitsfilename, naxis);
  fits_close_file(fptr, &status);
  return 1;
 }
 fits_close_file(fptr, &status);
 //
 if( 0 == check_if_the_input_is_FPack_compressed_FITS( fitsfilename ) ) {
  fprintf(stderr, "ERROR in fitsfile_read_check(): the input file is a compressed FITS image.\nPlease uncompressed the FITS image with 'util/funpack' before processing with VaST.\n");
  return 1;
 }
 //
 return 0;
}

// same as above but never print anything to the terminal
static inline int fitsfile_read_check_silent(char *fitsfilename) {
 int status= 0;  //for cfitsio routines
 fitsfile *fptr; // pointer to the FITS file; defined in fitsio.h
 int hdutype, naxis;
 long naxes3;
 long naxes4;
 // Check if the file exist at all
 FILE *testfile;
 testfile=fopen(fitsfilename, "r");
 if( testfile== NULL ){
  //fprintf(stderr, "ERROR opening file %s\n", fitsfilename);
  return 1;
 }
 fclose(testfile);
 //
 // check if this is a readable FITS image
 fits_open_image(&fptr, fitsfilename, READONLY, &status);
 if( 0 != status ) {
  //fits_report_error( stderr, status );
  fits_clear_errmsg(); // clear the CFITSIO error message stack
  check_if_the_input_is_MaxIM_compressed_FITS(fitsfilename);
  return status;
 }
 if( fits_get_hdu_type(fptr, &hdutype, &status) || hdutype != IMAGE_HDU ) {
  //fprintf( stderr, "%s is not a FITS image! Is it a FITS table?\n", fitsfilename );
  fits_close_file(fptr, &status);
  return 1;
 }
 fits_get_img_dim(fptr, &naxis, &status);
 if( status || naxis != 2 ) {
  if( naxis == 3 ) {
   fits_read_key(fptr, TLONG, "NAXIS3", &naxes3, NULL, &status);
   // Yes, we now support on-the-fly conversion of RGB images (G channel extraction)
   if( naxes3 == 1 || naxes3 == 3 ) {
    fits_close_file(fptr, &status);
    return 0;
   }
  }
  if( naxis == 4 ) {
   fits_read_key(fptr, TLONG, "NAXIS3", &naxes3, NULL, &status);
   if( naxes3 == 1 ) {
    fits_read_key(fptr, TLONG, "NAXIS4", &naxes4, NULL, &status);
    if( naxes4 == 1 ) {
     //fprintf( stderr, "%s image has NAXIS = %d, but NAXIS3 = %ld and NAXIS4 = %ld -- maybe there is some hope to handle this image...\n", fitsfilename, naxis, naxes3, naxes4 );
     fits_close_file(fptr, &status);
     return 0;
    }
   }
  }
  //fprintf( stderr, "%s image has NAXIS = %d.  Only 2-D images are supported.\n", fitsfilename, naxis );
  fits_close_file(fptr, &status);
  return 1;
 }
 fits_close_file(fptr, &status);
 //
 if( 0 == check_if_the_input_is_FPack_compressed_FITS( fitsfilename ) ) {
  fprintf(stderr, "ERROR in fitsfile_read_check(): the input file is a compressed FITS image.\nPlease uncompressed the FITS image with 'util/funpack' before processing with VaST.\n");
  return 1;
 }
 //
 return 0;
}


// The macro below will tell the pre-processor that this header file is already included
#define VAST_FITSFILE_READ_CHECK_INCLUDE_FILE
#endif
// VAST_FITSFILE_READ_CHECK_INCLUDE_FILE
