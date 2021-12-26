#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <limits.h> // realpath() needs it

// stat()
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#include "vast_limits.h"

// include files needed for cutout_green_channel_out_of_RGB_DSLR_image()
#include "get_path_to_vast.h"
#include "fitsio.h" // we use a local copy of this file because we use a local copy of cfitsio
#include "fitsfile_read_check.h"


void replace_file_with_symlink_if_filename_contains_white_spaces(char *filename) {
 unsigned int i, need_to_replace_with_symlink;
 char symlinkname[FILENAME_LENGTH];
 //
 char *resolvedpath;
 //
 struct stat sb; // structure returned by stat() system call
 
 // Check that the input is not a NULL string
 if( NULL == filename ) {
  fprintf(stderr, "ERROR in replace_file_with_symlink_if_filename_contains_white_spaces() the input is the NULL string!\n");
  return;
 }
 // Check
 // Check that the input file actually exist
 if( 0 != stat(filename, &sb) ) {
  fprintf(stderr, "ERROR in replace_file_with_symlink_if_filename_contains_white_spaces() the input file %s does not exits\n", filename);
  return;
 }
 // Check that the input file is not a symlink itself
 if( 0 == lstat(filename, &sb) ) {
  if( S_ISLNK(sb.st_mode) ) {
   fprintf(stderr, "WARNING from replace_file_with_symlink_if_filename_contains_white_spaces() the input file %s is already a symlink and we do not allow symlinks on symlinks\n", filename);
   return;
  }
 } 
 //

 for( need_to_replace_with_symlink= 0, i= 0; i < strlen(filename); i++ ) {
  if( filename[i] == ' ' ) {
   need_to_replace_with_symlink= 1;
   break;
  }
 }
 if( need_to_replace_with_symlink == 0 ) {
  return;
 }
 // create symlink name
 for( i= 1; i < MAX_NUMBER_OF_OBSERVATIONS; i++ ) {
  sprintf(symlinkname, "symlinks_to_images/symlink_to_image_%05d.fits", i);
  //if( 0 != stat(symlinkname, &sb) ) {
  if( 0 != lstat(symlinkname, &sb) ) {
   break; // continue if such a symlink already exists, break if this name is still empty
  }
 }
 if( i >= MAX_NUMBER_OF_OBSERVATIONS ) {
  fprintf(stderr, "ERROR: symlinks_to_images counter is out of range!\n");
  return;
 }
 fprintf(stderr, "WARNING: image path \"%s\" contains white spaces - SExtractor will not be able to handle that!\nTrying to circumvent this problem by creating symbolic link %s\n", filename, symlinkname);

 if( 0 == mkdir("symlinks_to_images", 0766) ) {
  fprintf(stderr, "Creating directory 'symlinks_to_images/'\n");
 }

 // Create symlink
 //resolvedpath= realpath(filename, 0);
 resolvedpath=malloc(PATH_MAX*sizeof(char));
 if( NULL==realpath(filename, resolvedpath) ){
  fprintf(stderr, "ERROR in realpath(%s,%s)\n",filename,resolvedpath);
  free(resolvedpath);
  return;
 }
 // before getting here make sure symlinkname does not exist already, or symlink() will throw an incorrect error message
 //
 if( 0 != symlink(resolvedpath, symlinkname) ) {
  fprintf(stderr, "ERROR in replace_file_with_symlink_if_filename_contains_white_spaces() -- cannot creat symlink to image containing a white space!\n");
  fprintf(stderr, "symlink(%s, %s) -- failed\n", resolvedpath, symlinkname);
  free(resolvedpath);
  return;
 }
 free(resolvedpath);

 strncpy(filename, symlinkname, FILENAME_LENGTH - 1);
 filename[FILENAME_LENGTH - 1]= '\0'; // just in case

 return;
}

void cutout_green_channel_out_of_RGB_DSLR_image(char *filename) {
 FILE *vast_converted_images_log;
 char vast_converted_images_log_original_image_name[FILENAME_LENGTH];

 unsigned int i; // counter
 char green_channel_only_image_name[FILENAME_LENGTH];
 //
 struct stat sb; // structure returned by stat() system call
 
 unsigned int need_to_cutout_green_channel= 0; // default is that we don't do anything
 unsigned int does_the_header_look_like_DSLR_image= 0; // default - it does not
 char *pointer_to_the_key_start; // for substring search with memmem()
 
 char program[FLEN_CARD]; // FLEN_CARD length of a FITS header card defined in fitsio.h

 char command[1024 + 3 * VAST_PATH_MAX + 2 * FILENAME_LENGTH];
 char path_to_vast_string[VAST_PATH_MAX];

 double isospeed;

 // fitsio
 long naxes3;
 int naxis;
 int status= 0;
 fitsfile *fptr; // pointer to the FITS file; defined in fitsio.h

 if( 0 != fitsfile_read_check_silent(filename) ) {
  return; // the input is not a readable FITS file, so we just quit
 }

 // It may not work if we are outside the vast work directory, but I'll deal with this later
 // Check if this image has already been converted and is still there
 vast_converted_images_log=fopen("vast_converted_images.log","r");
 if( NULL!=vast_converted_images_log ) {
  while( -1<fscanf(vast_converted_images_log,"%s %s", vast_converted_images_log_original_image_name, green_channel_only_image_name) ) {
   if( 0 == strncmp(filename, vast_converted_images_log_original_image_name, FILENAME_LENGTH) ) {
    if( 0 == fitsfile_read_check_silent(filename) ) {
     fprintf(stderr, "Found previously converted image %s %s\n", vast_converted_images_log_original_image_name, green_channel_only_image_name);
     strncpy(filename, green_channel_only_image_name, FILENAME_LENGTH - 1);
     filename[FILENAME_LENGTH - 1]= '\0'; // just in case
     fclose(vast_converted_images_log);
     return;
    }
   }
  }
  fclose(vast_converted_images_log);
 }

 
 // Extract data from fits header
 fits_open_file(&fptr, filename, READONLY, &status);
 if( 0 != status ) {
  fits_report_error(stderr, status); // print out any error messages
  fits_clear_errmsg();               // clear the CFITSIO error message stack
  return;
 }
 
 // Check if there is any hint in the header that this is a color DSLR image
 // (as ther may be many other types of images with NAXIS=3)
 
 // First, check for the presence of ISOSPEED keyword
 fits_read_key(fptr, TDOUBLE, "ISOSPEED", &isospeed, NULL, &status);
 if( 0 == status ) {
  fprintf( stderr, "Found key ISOSPEED= %.0lf %s looks like a DSLR image\n", isospeed, filename);
  does_the_header_look_like_DSLR_image= 1;
 }
 status= 0; // reset status: no problem if there was no ISOSPEED keyword
 // Second, check  if the image was created with Siril
 fits_read_key(fptr, TSTRING, "PROGRAM", program, NULL, &status);
 if( 0 == status ) {
  if( strlen(program) >= 5 ) {
   pointer_to_the_key_start= (char *)memmem(program, strlen(program), "Siril", 5);
   if( pointer_to_the_key_start != NULL ) {
    fprintf( stderr, "Found key PROGRAM= %s  -- %s looks like a DSLR image\n", program, filename);
    does_the_header_look_like_DSLR_image= 1;
   }
  }
 }
 status= 0; // reset status
 
 
 if( does_the_header_look_like_DSLR_image == 1 ) {
  fits_get_img_dim(fptr, &naxis, &status);
  if( 0 != status ) {
   fits_report_error(stderr, status); // print out any error messages
   fits_clear_errmsg();               // clear the CFITSIO error message stack
   //fits_close_file(fptr, &status);
  } else {
   if( naxis == 3 ) { 
    fprintf( stderr, "NAXIS=3 %s \n", filename);
    fits_read_key(fptr, TLONG, "NAXIS3", &naxes3, NULL, &status);
    if( 0 != status ) {
     fits_report_error(stderr, status); // print out any error messages
     fits_clear_errmsg();               // clear the CFITSIO error message stack
     //fits_close_file(fptr, &status);
    } else {
     if( naxes3 == 3 ) {
      fprintf( stderr, "NAXIS3=3 %s looks like an RGB DSLR image!\nWe'll extract the second (hopefully green) channel from it!\n", filename);
      need_to_cutout_green_channel= 1;
      //fits_close_file(fptr, &status);
     }
    }
   }
  }
 } // if( 0 == status ) after fits_read_key(fptr, TDOUBLE, "ISOSPEED"
 fits_close_file(fptr, &status); // if we are here, the FITS file is still open
 fits_clear_errmsg();               // clear the CFITSIO error message stack
 status= 0; // just in case
 
 if( need_to_cutout_green_channel == 0 ) {
  return;
 }
 // create green_channel_only_image name
 for( i= 1; i < MAX_NUMBER_OF_OBSERVATIONS; i++ ) {
  sprintf(green_channel_only_image_name, "converted_images/green_channel_only_image_%05d.fits", i);
  if( 0 != stat(green_channel_only_image_name, &sb) )
   break; // continue if such a green_channel_only_image already exists, break if this name is still empty
 }
 if( i >= MAX_NUMBER_OF_OBSERVATIONS ) {
  fprintf(stderr, "ERROR: converted_images counter is out of range!\n");
  return;
 }
 fprintf(stderr, "WARNING: image \"%s\" seems to be an RGB image - SExtractor will not be able to handle that!\nTrying to circumvent this problem extracting the green-channel-only image %s\n", filename, green_channel_only_image_name);

 if( 0 == mkdir("converted_images", 0766) ) {
  fprintf(stderr, "Creating directory 'converted_images/'\n");
 }

 // Create green_channel_only_image
 get_path_to_vast(path_to_vast_string);
 sprintf(command, "%sutil/fitscopy %s[*,*,2:2] %s", path_to_vast_string,filename, green_channel_only_image_name);
 fprintf(stderr, "%s\n", command);
 if( 0 != system(command) ) {
  fprintf(stderr, "ERROR running system()\n");
  return;
 }
 if( 0 != fitsfile_read_check(green_channel_only_image_name) ) {
  fprintf(stderr,"ERROR: the converted FITS file %s check failed!\n", green_channel_only_image_name);
  return;
 }
 
 vast_converted_images_log=fopen("vast_converted_images.log","a");
 if( NULL==vast_converted_images_log ) {
  fprintf(stderr, "WARNING: cannot open vast_converted_images.log for writing!\n");
 } else {
  fprintf(vast_converted_images_log,"%s %s\n", filename, green_channel_only_image_name);
  fclose(vast_converted_images_log);
 }
 
 strncpy(filename, green_channel_only_image_name, FILENAME_LENGTH - 1);
 filename[FILENAME_LENGTH - 1]= '\0'; // just in case

 return;
}

