#ifndef VAST_IMAGE_QUALITY_H
#define VAST_IMAGE_QUALITY_H

void choose_best_reference_image( char **input_images, int *vast_bad_image_flag, int Num );
void mark_images_with_elongated_stars_as_bad( char **input_images, int *vast_bad_image_flag, int Num );

#endif
