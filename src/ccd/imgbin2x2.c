#include <stdio.h>
#include <stdlib.h>

#include "../fitsio.h"

void rebinImage(float* input, float* output, int width, int height) {
    int new_width = width / 2;
    int new_height = height / 2;

    for (int i = 0; i < new_height; i++) {
        for (int j = 0; j < new_width; j++) {
            float sum = 0;
            sum += input[2*i*width + 2*j];
            sum += input[2*i*width + 2*j + 1];
            sum += input[(2*i + 1)*width + 2*j];
            sum += input[(2*i + 1)*width + 2*j + 1];
            output[i*new_width + j] = sum / 4.0;
        }
    }
}

void convertFloatToShort(float* input, short* output, int size, float scale) {
    for (int i = 0; i < size; i++) {
        int temp = (int)(input[i] * scale);
        if (temp > 32767) temp = 32767;
        else if (temp < -32768) temp = -32768;
        output[i] = (short)temp;
    }
}

int main(int argc, char **argv) {
    fitsfile *fptr;
    int status = 0;
    int bitpix, naxis;
    long naxes[2], fpixel[2];

    if ( 2 != argc ) {
     fprintf(stderr, "Usage: %s unbinned.fits\n",argv[0]);
     return 1;
    }

    // Open input FITS file
    if (fits_open_file(&fptr, argv[1], READONLY, &status)) {
        fits_report_error(stderr, status);
        return 1;
    }

    // Read dimensions of the image
    if (fits_get_img_param(fptr, 2, &bitpix, &naxis, naxes, &status)) {
        fits_report_error(stderr, status);
        return 1;
    }

    if (naxis != 2) {
        printf("Error: only 2D images are supported.\n");
        return 1;
    }

    // Allocate memory for the input image
    float *input_data = (float *) malloc(naxes[0] * naxes[1] * sizeof(float));
    if (input_data == NULL) {
        printf("Memory allocation error\n");
        return 1;
    }

    // Read the data
    fpixel[0] = fpixel[1] = 1;
    if (fits_read_pix(fptr, TFLOAT, fpixel, naxes[0] * naxes[1], NULL, input_data, NULL, &status))
        fits_report_error(stderr, status);

    // Close the input file
    if (fits_close_file(fptr, &status))
        fits_report_error(stderr, status);

    // Rebin the image
    int new_width = naxes[0] / 2;
    int new_height = naxes[1] / 2;
    float *output_data = (float *) malloc(new_width * new_height * sizeof(float));
    if (output_data == NULL) {
        printf("Memory allocation error\n");
        return 1;
    }

    rebinImage(input_data, output_data, naxes[0], naxes[1]);

    // Convert float data to 16-bit integer
    short *int_data = (short *) malloc(new_width * new_height * sizeof(short));
    if (int_data == NULL) {
        printf("Memory allocation error\n");
        return 1;
    }

    convertFloatToShort(output_data, int_data, new_width * new_height, 1.0); // Adjust scale as necessary

    // Write the rebinned and converted image to a new FITS file
    if (fits_create_file(&fptr, "binned_image.fits", &status))
        fits_report_error(stderr, status);

    long new_naxes[2] = {new_width, new_height};
    if (fits_create_img(fptr, SHORT_IMG, 2, new_naxes, &status))
        fits_report_error(stderr, status);

    if (fits_write_pix(fptr, TSHORT, fpixel, new_width * new_height, int_data, &status))
        fits_report_error(stderr, status);

    // Close the output file
    if (fits_close_file(fptr, &status))
        fits_report_error(stderr, status);

    // Free allocated memory
    free(input_data);
    free(output_data);
    free(int_data);
    
    fprintf(stderr, "Binned image is written to binned_image.fits\n");

    return 0;
}

