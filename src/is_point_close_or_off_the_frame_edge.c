#include "vast_limits.h" // MIN() and MAX() are defined here

// This function will check if the specified position is too close to the frame edge
int is_point_close_or_off_the_frame_edge(double x, double y, double X_im_size, double Y_im_size, double max_indent) {
 double indent;

 // We don't want to use a large indent if the image is very small
 indent= MIN(max_indent, 0.031250 * MIN(X_im_size, Y_im_size));
 // But make sure indent is at least 1 pixel
 indent= MAX(indent, 1.0);

 // Check
 if( x < indent ) {
  return 1;
 }
 if( y < indent ) {
  return 1;
 }
 if( x > X_im_size - indent ) {
  return 1;
 }
 if( y > Y_im_size - indent ) {
  return 1;
 }

 return 0; // if we are still here - the point is well within the image
}
