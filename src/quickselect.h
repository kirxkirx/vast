/*
 * Quickselect algorithm for finding the k-th smallest element in O(n) average time.
 * This is much faster than full sorting (O(n log n)) when only the median is needed.
 *
 * Based on the Hoare selection algorithm.
 */

#ifndef QUICKSELECT_H
#define QUICKSELECT_H

/* Find the k-th smallest element in arr[left..right] using quickselect.
 * WARNING: This function modifies the input array (partial reordering).
 * Returns the value of the k-th smallest element. */
double quickselect_double( double *arr, int left, int right, int k );

/* Float version of quickselect */
float quickselect_float( float *arr, int left, int right, int k );

/* Find median of n doubles using quickselect - O(n) average time.
 * WARNING: This function modifies the input array.
 * For odd n, returns the middle element.
 * For even n, returns the average of the two middle elements. */
double quickselect_median_double( double *arr, int n );

/* Float version of quickselect_median */
float quickselect_median_float( float *arr, int n );

#endif /* QUICKSELECT_H */
