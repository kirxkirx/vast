/*
 * Quickselect algorithm for finding the k-th smallest element in O(n) average time.
 * This is much faster than full sorting (O(n log n)) when only the median is needed.
 *
 * Based on the Hoare selection algorithm.
 */

#include "quickselect.h"

/* Partition function for double arrays */
static int quickselect_partition_double( double *arr, int left, int right, int pivot_idx ) {
 double pivot_val= arr[pivot_idx];
 double tmp;
 int store_idx, i;

 /* Move pivot to end */
 tmp= arr[pivot_idx];
 arr[pivot_idx]= arr[right];
 arr[right]= tmp;

 store_idx= left;
 for ( i= left; i < right; i++ ) {
  if ( arr[i] < pivot_val ) {
   tmp= arr[store_idx];
   arr[store_idx]= arr[i];
   arr[i]= tmp;
   store_idx++;
  }
 }

 /* Move pivot to its final place */
 tmp= arr[store_idx];
 arr[store_idx]= arr[right];
 arr[right]= tmp;

 return store_idx;
}

/* Quickselect for double arrays: find k-th smallest element in O(n) average time */
double quickselect_double( double *arr, int left, int right, int k ) {
 int pivot_idx, pivot_new_idx;

 while ( left < right ) {
  /* Choose middle element as pivot for better average performance */
  pivot_idx= left + ( right - left ) / 2;
  pivot_new_idx= quickselect_partition_double( arr, left, right, pivot_idx );

  if ( k == pivot_new_idx ) {
   return arr[k];
  } else if ( k < pivot_new_idx ) {
   right= pivot_new_idx - 1;
  } else {
   left= pivot_new_idx + 1;
  }
 }
 return arr[left];
}

/* Find median of n doubles using quickselect - O(n) average time */
double quickselect_median_double( double *arr, int n ) {
 int i;
 double lower, upper;

 if ( n % 2 == 1 ) {
  return quickselect_double( arr, 0, n - 1, n / 2 );
 } else {
  /* For even n, find the lower middle element first */
  lower= quickselect_double( arr, 0, n - 1, n / 2 - 1 );
  /* After quickselect, arr is partitioned: arr[n/2..n-1] >= arr[n/2-1]
   * So upper (the n/2-th smallest) is the minimum of arr[n/2..n-1] */
  upper= arr[n / 2];
  for ( i= n / 2 + 1; i < n; i++ ) {
   if ( arr[i] < upper ) {
    upper= arr[i];
   }
  }
  return 0.5 * ( lower + upper );
 }
}

/* Partition function for float arrays */
static int quickselect_partition_float( float *arr, int left, int right, int pivot_idx ) {
 float pivot_val= arr[pivot_idx];
 float tmp;
 int store_idx, i;

 /* Move pivot to end */
 tmp= arr[pivot_idx];
 arr[pivot_idx]= arr[right];
 arr[right]= tmp;

 store_idx= left;
 for ( i= left; i < right; i++ ) {
  if ( arr[i] < pivot_val ) {
   tmp= arr[store_idx];
   arr[store_idx]= arr[i];
   arr[i]= tmp;
   store_idx++;
  }
 }

 /* Move pivot to its final place */
 tmp= arr[store_idx];
 arr[store_idx]= arr[right];
 arr[right]= tmp;

 return store_idx;
}

/* Quickselect for float arrays: find k-th smallest element in O(n) average time */
float quickselect_float( float *arr, int left, int right, int k ) {
 int pivot_idx, pivot_new_idx;

 while ( left < right ) {
  /* Choose middle element as pivot for better average performance */
  pivot_idx= left + ( right - left ) / 2;
  pivot_new_idx= quickselect_partition_float( arr, left, right, pivot_idx );

  if ( k == pivot_new_idx ) {
   return arr[k];
  } else if ( k < pivot_new_idx ) {
   right= pivot_new_idx - 1;
  } else {
   left= pivot_new_idx + 1;
  }
 }
 return arr[left];
}

/* Find median of n floats using quickselect - O(n) average time */
float quickselect_median_float( float *arr, int n ) {
 int i;
 float lower, upper;

 if ( n % 2 == 1 ) {
  return quickselect_float( arr, 0, n - 1, n / 2 );
 } else {
  /* For even n, find the lower middle element first */
  lower= quickselect_float( arr, 0, n - 1, n / 2 - 1 );
  /* After quickselect, arr is partitioned: arr[n/2..n-1] >= arr[n/2-1]
   * So upper (the n/2-th smallest) is the minimum of arr[n/2..n-1] */
  upper= arr[n / 2];
  for ( i= n / 2 + 1; i < n; i++ ) {
   if ( arr[i] < upper ) {
    upper= arr[i];
   }
  }
  return 0.5f * ( lower + upper );
 }
}
