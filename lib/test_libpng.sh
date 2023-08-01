#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Set the default result
LIBPNG_OK=1

# This should work if libpng is installed properly and GCC can find it
LPNG_GCC_COMMAND_LINE_OPTION="-lpng"
# If we are on mac - assume libpng is not installed properly
if [ -d /opt/local/include/ ];then
 LPNG_GCC_COMMAND_LINE_OPTION="-I/opt/local/include/ -L/opt/local/lib/ -lpng"
fi

# Write a simple program using libpng
echo "#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include <png.h>

// Creates a test image for saving. Creates a Mandelbrot Set fractal of size width x height
float *createMandelbrotImage(int width, int height, float xS, float yS, float rad, int maxIteration);

// This takes the float value 'val', converts it to red, green & blue values, then 
// sets those values into the image memory buffer location pointed to by 'ptr'
static inline void setRGB(png_byte *ptr, float val);

// This function actually writes out the PNG image file. The string 'title' is
// also written into the image file
int writeImage(char* filename, int width, int height, float *buffer, char* title);


int main(int argc, char *argv[])
{
	// Make sure that the output filename argument has been provided
	if (argc != 2) {
		fprintf(stderr, \"Please specify output file\n\");
		return 1;
	}

	// Specify an output image size
	int width = 500;
	int height = 300;

	// Create a test image - in this case a Mandelbrot Set fractal
	// The output is a 1D array of floats, length: width * height
	//printf(\"Creating Image\n\");
	float *buffer = createMandelbrotImage(width, height, -0.802, -0.177, 0.011, 110);
	if (buffer == NULL) {
		return 1;
	}

	// Save the image to a PNG file
	// The 'title' string is stored as part of the PNG file
	//printf(\"Saving PNG\n\");
	int result = writeImage(argv[1], width, height, buffer, \"This is my test image\");

	// Free up the memorty used to store the image
	free(buffer);

	return result;
}

static inline void setRGB(png_byte *ptr, float val)
{
	int v = (int)(val * 768);
	if (v < 0) v = 0;
	if (v > 768) v = 768;
	int offset = v % 256;

	if (v<256) {
		ptr[0] = 0; ptr[1] = 0; ptr[2] = offset;
	}
	else if (v<512) {
		ptr[0] = 0; ptr[1] = offset; ptr[2] = 255-offset;
	}
	else {
		ptr[0] = offset; ptr[1] = 255-offset; ptr[2] = 0;
	}
}

int writeImage(char* filename, int width, int height, float *buffer, char* title)
{
	int code = 0;
	FILE *fp;
	png_structp png_ptr;
	png_infop info_ptr;
	png_bytep row;
	
	// Open file for writing (binary mode)
	fp = fopen(filename, \"wb\");
	if (fp == NULL) {
		fprintf(stderr, \"Could not open file %s for writing\n\", filename);
		code = 1;
		goto finalise;
	}

	// Initialize write structure
	png_ptr = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
	if (png_ptr == NULL) {
		fprintf(stderr, \"Could not allocate write struct\n\");
		code = 1;
		goto finalise;
	}

	// Initialize info structure
	info_ptr = png_create_info_struct(png_ptr);
	if (info_ptr == NULL) {
		fprintf(stderr, \"Could not allocate info struct\n\");
		code = 1;
		goto finalise;
	}

	// Setup Exception handling
	if (setjmp(png_jmpbuf(png_ptr))) {
		fprintf(stderr, \"Error during png creation\n\");
		code = 1;
		goto finalise;
	}

	png_init_io(png_ptr, fp);

	// Write header (8 bit colour depth)
	png_set_IHDR(png_ptr, info_ptr, width, height,
			8, PNG_COLOR_TYPE_RGB, PNG_INTERLACE_NONE,
			PNG_COMPRESSION_TYPE_BASE, PNG_FILTER_TYPE_BASE);

	// Set title
	if (title != NULL) {
		png_text title_text;
		title_text.compression = PNG_TEXT_COMPRESSION_NONE;
		title_text.key = \"Title\";
		title_text.text = title;
		png_set_text(png_ptr, info_ptr, &title_text, 1);
	}

	png_write_info(png_ptr, info_ptr);

	// Allocate memory for one row (3 bytes per pixel - RGB)
	row = (png_bytep) malloc(3 * width * sizeof(png_byte));

	// Write image data
	int x, y;
	for (y=0 ; y<height ; y++) {
		for (x=0 ; x<width ; x++) {
			setRGB(&(row[x*3]), buffer[y*width + x]);
		}
		png_write_row(png_ptr, row);
	}

	// End write
	png_write_end(png_ptr, NULL);

	finalise:
	if (fp != NULL) fclose(fp);
	if (info_ptr != NULL) png_free_data(png_ptr, info_ptr, PNG_FREE_ALL, -1);
	if (png_ptr != NULL) png_destroy_write_struct(&png_ptr, (png_infopp)NULL);
	if (row != NULL) free(row);

	return code;
}

float *createMandelbrotImage(int width, int height, float xS, float yS, float rad, int maxIteration)
{
	float *buffer = (float *) malloc(width * height * sizeof(float));
	if (buffer == NULL) {
		fprintf(stderr, \"Could not create image buffer\n\");
		return NULL;
	}

	// Create Mandelbrot set image

	int xPos, yPos;
	float minMu = maxIteration;
	float maxMu = 0;

	for (yPos=0 ; yPos<height ; yPos++)
	{
		float yP = (yS-rad) + (2.0f*rad/height)*yPos;

		for (xPos=0 ; xPos<width ; xPos++)
		{
			float xP = (xS-rad) + (2.0f*rad/width)*xPos;

			int iteration = 0;
			float x = 0;
			float y = 0;

			while (x*x + y+y <= 4 && iteration < maxIteration)
			{
				float tmp = x*x - y*y + xP;
				y = 2*x*y + yP;
				x = tmp;
				iteration++;
			}

			if (iteration < maxIteration) {
				float modZ = sqrt(x*x + y*y);
				float mu = iteration - (log(log(modZ))) / log(2);
				if (mu > maxMu) maxMu = mu;
				if (mu < minMu) minMu = mu;
				buffer[yPos * width + xPos] = mu;
			}
			else {
				buffer[yPos * width + xPos] = 0;
			}
		}
	}

	// Scale buffer values between 0 and 1
	int count = width * height;
	while (count) {
		count --;
		buffer[count] = (buffer[count] - minMu) / (maxMu - minMu);
	}

	return buffer;
}
" > makePNG.c

# Compile it
CC=$(lib/find_gcc_compiler.sh)
$CC -o makePNG makePNG.c $LPNG_GCC_COMMAND_LINE_OPTION -lm
if [ $? != 0 ];then
 echo "
 WARNING: $CC cannot find libpng! The PNG plotting support will be disabled.

Please install libpng devel. package to proceed.
On Ubuntu you may install all packages needed to build VaST by executing:

sudo apt-get install build-essential gfortran g++ libx11-dev libxi-dev libxmu-dev libpng-dev curl wget

on other Linux distributions you'll need to do the same thing (install gfortran, g++, X11 developement libraries and libpng) using your native package manager.
" 1>&2
 LIBPNG_OK=0
fi

# Test it
if [ $LIBPNG_OK -eq 1 ];then
 ./makePNG output.png
 if [ $? != 0 ];then
  echo "
 WARNING: problem testing libpng! The PNG plotting support will be disabled.
 
Please install libpng devel. package to proceed.
On Ubuntu you may install all packages needed to build VaST by executing:

sudo apt-get install build-essential gfortran g++ libx11-dev libxi-dev libxmu-dev libpng-dev curl wget

on other Linux distributions you'll need to do the same thing (install gfortran, g++, X11 developement libraries and libpng) using your native package manager.
" 1>&2
  LIBPNG_OK=0
 fi
fi
if [ ! -s output.png ];then
  echo "
 WARNING: problem testing libpng! The PNG plotting support will be disabled.
 
Please install libpng devel. package to proceed.
On Ubuntu you may install all packages needed to build VaST by executing:

sudo apt-get install build-essential gfortran g++ libx11-dev libxi-dev libxmu-dev libpng-dev curl wget

on other Linux distributions you'll need to do the same thing (install gfortran, g++, X11 developement libraries and libpng) using your native package manager.
" 1>&2
 LIBPNG_OK=0 
fi

# Remove test files
for FILE_TO_REMOVE in makePNG.c makePNG output.png ;do
 if [ -f "$FILE_TO_REMOVE" ];then
  rm -f "$FILE_TO_REMOVE"
 fi
done

# If the script name contians test_libpng_justtest_nomovepgplot.sh
# just exit with an appropriate exit code
script_name=$(basename "$0")
search_string="test_libpng_justtest_nomovepgplot.sh"
if [[ $script_name =~ $search_string ]]; then
 if [ $LIBPNG_OK -eq 1 ];then
  exit 0
 else
  exit 1
 fi
fi

# Otherwise, if we are still here...

# Copy the appropriate lib/pgplot stub
rm -rf lib/pgplot
if [ $LIBPNG_OK -eq 1 ];then
 echo "libpng found and is working properly! :)" 1>&2
 cp -r lib/pgplot_with_libpng lib/pgplot
 echo "$LPNG_GCC_COMMAND_LINE_OPTION"
else
 echo "libpng is not found! PNG output disabled... :/" 1>&2
 cp -r lib/pgplot_without_libpng lib/pgplot
 echo ""
fi
