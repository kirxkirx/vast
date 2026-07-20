// lightcurve_png -- non-interactive PGPLOT-based lightcurve plotter.
//
// Reads a VaST-format lightcurve (auto-detected by read_lightcurve_point_raw():
// "JD mag", "JD mag err", or the full 7-column VaST format) and writes a PNG
// plot of mag vs JD with the magnitude axis inverted. Optional --upperlimits
// file overlays a second track of upper limits as downward-facing triangles.
//
// Unlike lc.c, this tool calls read_lightcurve_point_raw() which skips the
// SNR cap and the BRIGHTEST_STARS mag-range filter. Forced photometry can
// yield legitimate measurements with large errors that the standard reader
// would silently discard. Suspiciously faint magnitudes are still rejected
// against FAINTEST_STARS_ANYMAG (see vast_limits.h).
//
// Detections are drawn as red filled circles with symmetric Y error bars.
// Upper limits are drawn as blue downward triangles (cpgpoly, sized from
// the character height so they scale with the plot).
//
// Output: writes the PNG via PGPLOT's /PNG device. If the linked PGPLOT was
// built without libpng support, prints a clear error and exits non-zero;
// no plot is written.
//
// Long output paths: PGPLOT's device-string handling truncates long
// filenames (somewhere around 90 characters the PNG driver ends up trying
// to open a chopped path, prints "plotting disabled" and every plot call
// becomes a no-op while cpgbeg still reports success). To make -o work
// with arbitrarily long paths, the plot is rendered under a short
// temporary name in the current working directory whenever the requested
// output path is long, and the file is then rename()d (or byte-copied
// across filesystems) to its destination. Independently of that, the
// output file's existence and non-zero size are verified after rendering,
// so "Wrote ..." is never printed -- and the exit code is never 0 -- when
// nothing was actually written.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <getopt.h>
#include <errno.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "cpgplot.h"
#include "setenv_local_pgplot.h"
#include "lightcurve_io.h"

#define PATH_MAX_LEN 4096
// Output paths at least this long are rendered under a short temporary
// name in the current directory and then moved into place, because
// PGPLOT truncates long device filenames (see the comment at the top).
// The observed truncation point is ~90 characters; stay well below it.
#define PGPLOT_SAFE_FILENAME_LEN 80
#define DEFAULT_OUTPUT_PNG "lightcurve.png"
#define DEFAULT_WIDTH 800
#define DEFAULT_HEIGHT 600
#define X_AXIS_PAD_FRAC 0.05
#define Y_AXIS_PAD_FRAC 0.10f
#define X_AXIS_PAD_MIN_DAYS 1.0
#define Y_AXIS_PAD_MIN_MAG 0.5f

// PGPLOT colour indices used below
#define COLOR_BG 0
#define COLOR_FG 1
#define COLOR_RED 2
#define COLOR_BLUE 4

typedef struct {
 const char *input_file;
 const char *upperlimits_file;
 const char *output_png;
 const char *title;
 const char *xlabel;
 const char *ylabel;
 int width;
 int height;
} options_t;

static void print_usage( const char *progname ) {
 fprintf( stderr,
          "Usage: %s [OPTIONS] <lightcurve.dat>\n"
          "\n"
          "Plot a VaST-format lightcurve as a PNG (mag vs JD, mag axis inverted).\n"
          "Detections are red filled circles with Y error bars; upper limits are\n"
          "blue downward triangles. Uses read_lightcurve_point_raw() so noisy\n"
          "and faint points are plotted faithfully (no SNR cap).\n"
          "\n"
          "Options:\n"
          "  --upperlimits FILE   Two-column ASCII \"JD limit_mag\" file (comment\n"
          "                       lines starting with # are skipped).\n"
          "  -o, --output FILE    Output PNG filename. Default: %s\n"
          "  --title TEXT         Plot title (default: none).\n"
          "  --xlabel TEXT        X-axis label (default: auto \"JD - <offset>\").\n"
          "  --ylabel TEXT        Y-axis label (default: \"Magnitude\").\n"
          "  --width N            PNG width in pixels (default: %d).\n"
          "  --height N           PNG height in pixels (default: %d).\n"
          "  -h, --help           Show this help and exit.\n",
          progname, DEFAULT_OUTPUT_PNG, DEFAULT_WIDTH, DEFAULT_HEIGHT );
}

// Parse argv into opt. Returns 0 on success, non-zero on usage error.
static int parse_args( int argc, char **argv, options_t *opt ) {
 int nextopt;
 const char *const shortopt = "o:h";
 const struct option longopt[] = {
     { "upperlimits", 1, NULL, 1001 },
     { "output", 1, NULL, 'o' },
     { "title", 1, NULL, 1002 },
     { "xlabel", 1, NULL, 1003 },
     { "ylabel", 1, NULL, 1004 },
     { "width", 1, NULL, 1005 },
     { "height", 1, NULL, 1006 },
     { "help", 0, NULL, 'h' },
     { NULL, 0, NULL, 0 } };

 opt->input_file = NULL;
 opt->upperlimits_file = NULL;
 opt->output_png = DEFAULT_OUTPUT_PNG;
 opt->title = "";
 opt->xlabel = NULL;
 opt->ylabel = "Magnitude";
 opt->width = DEFAULT_WIDTH;
 opt->height = DEFAULT_HEIGHT;

 while ( ( nextopt= getopt_long( argc, argv, shortopt, longopt, NULL ) ) != -1 ) {
  switch ( nextopt ) {
  case 1001:
   opt->upperlimits_file= optarg;
   break;
  case 'o':
   opt->output_png= optarg;
   break;
  case 1002:
   opt->title= optarg;
   break;
  case 1003:
   opt->xlabel= optarg;
   break;
  case 1004:
   opt->ylabel= optarg;
   break;
  case 1005:
   opt->width= atoi( optarg );
   break;
  case 1006:
   opt->height= atoi( optarg );
   break;
  case 'h':
   print_usage( argv[0] );
   exit( EXIT_SUCCESS );
  default:
   print_usage( argv[0] );
   return 1;
  }
 }
 if ( opt->width < 100 )
  opt->width= DEFAULT_WIDTH;
 if ( opt->height < 100 )
  opt->height= DEFAULT_HEIGHT;
 if ( optind >= argc ) {
  fprintf( stderr, "ERROR: missing input lightcurve file\n" );
  print_usage( argv[0] );
  return 1;
 }
 opt->input_file= argv[optind];
 return 0;
}

// Read the main lightcurve via read_lightcurve_point_raw() (no SNR cap, no
// BRIGHTEST_STARS filter), then drop points fainter than FAINTEST_STARS_ANYMAG.
// Returns 0 on success (including n_out == 0), -1 on
// open/OOM failure. Caller frees *jd_out / *mag_out / *err_out.
static int read_main_lightcurve( const char *path, double **jd_out,
                                 float **mag_out, float **err_out,
                                 int *n_out ) {
 FILE *fp;
 int capacity;
 int n;
 int rc;
 double j, m, e, x, y, app;
 char fits_string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];

 *jd_out= NULL;
 *mag_out= NULL;
 *err_out= NULL;
 *n_out= 0;

 capacity= count_points_in_lightcurve_file( (char *)path );
 if ( capacity <= 0 ) {
  return 0;
 }
 *jd_out= (double *)malloc( (size_t)capacity * sizeof( double ) );
 *mag_out= (float *)malloc( (size_t)capacity * sizeof( float ) );
 *err_out= (float *)malloc( (size_t)capacity * sizeof( float ) );
 if ( *jd_out == NULL || *mag_out == NULL || *err_out == NULL ) {
  free( *jd_out );
  free( *mag_out );
  free( *err_out );
  *jd_out= NULL;
  *mag_out= NULL;
  *err_out= NULL;
  return -1;
 }
 fp= fopen( path, "r" );
 if ( fp == NULL ) {
  free( *jd_out );
  free( *mag_out );
  free( *err_out );
  *jd_out= NULL;
  *mag_out= NULL;
  *err_out= NULL;
  return -1;
 }
 n= 0;
 // Pass non-NULL x/y/app to take the slow path inside _raw, which applies
 // the NaN/inf and JD-range checks. The values themselves are discarded.
 while ( n < capacity ) {
  rc= read_lightcurve_point_raw( fp, &j, &m, &e, &x, &y, &app,
                                 fits_string, NULL );
  if ( rc == -1 )
   break; // EOF
  if ( rc == 1 )
   continue; // comment / malformed / out-of-range; skip
  // Skip suspiciously faint magnitudes (instrumental or whatever), as the
  // standard reader does. FAINTEST_STARS_ANYMAG is defined in vast_limits.h.
  if ( m > FAINTEST_STARS_ANYMAG )
   continue;
  ( *jd_out )[n]= j;
  ( *mag_out )[n]= (float)m;
  ( *err_out )[n]= (float)e;
  n++;
 }
 fclose( fp );
 *n_out= n;
 return 0;
}

// Read a "JD limit_mag" two-column ASCII file. Comment lines starting with
// '#', blank lines, and lines that do not parse as two fields are silently
// skipped. Returns 0 on success (including n_out == 0), -1 on open/OOM
// failure. Caller frees *jd_out / *mag_out.
static int read_upperlimits( const char *path, double **jd_out,
                             float **mag_out, int *n_out ) {
 FILE *fp;
 char buf[1024];
 char *p;
 double j;
 float m;
 int n_lines;
 int n;

 *jd_out= NULL;
 *mag_out= NULL;
 *n_out= 0;

 fp= fopen( path, "r" );
 if ( fp == NULL )
  return -1;
 n_lines= 0;
 while ( fgets( buf, sizeof( buf ), fp ) != NULL )
  n_lines++;
 fclose( fp );
 if ( n_lines == 0 )
  return 0;

 *jd_out= (double *)malloc( (size_t)n_lines * sizeof( double ) );
 *mag_out= (float *)malloc( (size_t)n_lines * sizeof( float ) );
 if ( *jd_out == NULL || *mag_out == NULL ) {
  free( *jd_out );
  free( *mag_out );
  *jd_out= NULL;
  *mag_out= NULL;
  return -1;
 }
 fp= fopen( path, "r" );
 if ( fp == NULL ) {
  free( *jd_out );
  free( *mag_out );
  *jd_out= NULL;
  *mag_out= NULL;
  return -1;
 }
 n= 0;
 while ( fgets( buf, sizeof( buf ), fp ) != NULL ) {
  p= buf;
  while ( *p == ' ' || *p == '\t' )
   p++;
  if ( *p == '\0' || *p == '\n' || *p == '\r' || *p == '#' )
   continue;
  if ( 2 == sscanf( p, "%lf %f", &j, &m ) ) {
   ( *jd_out )[n]= j;
   ( *mag_out )[n]= m;
   n++;
  }
  // silently skip malformed lines
 }
 fclose( fp );
 *n_out= n;
 return 0;
}

// Return 1 if path exists as a regular file with size > 0, else 0. Used to
// verify that PGPLOT really wrote the plot: its PNG driver can fail to open
// the output file yet leave cpgbeg reporting success ("plotting disabled").
static int file_exists_nonempty( const char *path ) {
 struct stat st;
 if ( 0 != stat( path, &st ) )
  return 0;
 if ( !S_ISREG( st.st_mode ) )
  return 0;
 if ( st.st_size <= 0 )
  return 0;
 return 1;
}

// Move src to dst: try rename() first; on a cross-filesystem failure
// (EXDEV) fall back to a byte copy followed by unlink of src. Returns 0 on
// success, -1 on failure (dst is removed if the copy was incomplete).
static int move_file( const char *src, const char *dst ) {
 FILE *in;
 FILE *out;
 size_t n_read;
 char buf[16384];

 if ( 0 == rename( src, dst ) )
  return 0;
 if ( errno != EXDEV )
  return -1;
 in= fopen( src, "rb" );
 if ( in == NULL )
  return -1;
 out= fopen( dst, "wb" );
 if ( out == NULL ) {
  fclose( in );
  return -1;
 }
 while ( ( n_read= fread( buf, 1, sizeof( buf ), in ) ) > 0 ) {
  if ( fwrite( buf, 1, n_read, out ) != n_read ) {
   fclose( in );
   fclose( out );
   unlink( dst );
   return -1;
  }
 }
 if ( ferror( in ) ) {
  fclose( in );
  fclose( out );
  unlink( dst );
  return -1;
 }
 fclose( in );
 if ( 0 != fclose( out ) ) {
  unlink( dst );
  return -1;
 }
 unlink( src );
 return 0;
}

// Sweep both tracks to find x and y plotting ranges, including detection
// error bars in the y range. Adds fractional padding with a floor for the
// single-point / single-magnitude edge cases.
static void compute_axis_ranges( const double *jd_det, const float *mag_det,
                                 const float *err_det, int n_det,
                                 const double *jd_ul, const float *mag_ul,
                                 int n_ul,
                                 double *xmin_out, double *xmax_out,
                                 float *ymin_out, float *ymax_out ) {
 int i;
 int first;
 double xmin, xmax;
 float ymin, ymax;
 double xpad;
 float ypad;

 first= 1;
 xmin= 0.0;
 xmax= 0.0;
 ymin= 0.0f;
 ymax= 0.0f;
 for ( i= 0; i < n_det; i++ ) {
  if ( first ) {
   xmin= xmax= jd_det[i];
   ymin= mag_det[i] - err_det[i];
   ymax= mag_det[i] + err_det[i];
   first= 0;
  } else {
   if ( jd_det[i] < xmin )
    xmin= jd_det[i];
   if ( jd_det[i] > xmax )
    xmax= jd_det[i];
   if ( mag_det[i] - err_det[i] < ymin )
    ymin= mag_det[i] - err_det[i];
   if ( mag_det[i] + err_det[i] > ymax )
    ymax= mag_det[i] + err_det[i];
  }
 }
 for ( i= 0; i < n_ul; i++ ) {
  if ( first ) {
   xmin= xmax= jd_ul[i];
   ymin= ymax= mag_ul[i];
   first= 0;
  } else {
   if ( jd_ul[i] < xmin )
    xmin= jd_ul[i];
   if ( jd_ul[i] > xmax )
    xmax= jd_ul[i];
   if ( mag_ul[i] < ymin )
    ymin= mag_ul[i];
   if ( mag_ul[i] > ymax )
    ymax= mag_ul[i];
  }
 }
 xpad= ( xmax - xmin ) * X_AXIS_PAD_FRAC;
 ypad= ( ymax - ymin ) * Y_AXIS_PAD_FRAC;
 if ( xpad < X_AXIS_PAD_MIN_DAYS / 2.0 )
  xpad= X_AXIS_PAD_MIN_DAYS / 2.0;
 if ( ypad < Y_AXIS_PAD_MIN_MAG / 2.0f )
  ypad= Y_AXIS_PAD_MIN_MAG / 2.0f;
 xmin-= xpad;
 xmax+= xpad;
 ymin-= ypad;
 ymax+= ypad;
 *xmin_out= xmin;
 *xmax_out= xmax;
 *ymin_out= ymin;
 *ymax_out= ymax;
}

// Open PGPLOT /PNG, draw axes, plot detections (red filled circles + Y
// errorbars) then upper limits (blue downward triangles), close. Returns
// EXIT_SUCCESS / EXIT_FAILURE so main() can exit with the right code.
// plot_path is the filename PGPLOT actually writes -- main() passes either
// the requested output path or a short temporary name for long paths.
static int render_plot( const options_t *opt, const char *plot_path,
                        const double *jd_det, const float *mag_det,
                        const float *err_det, int n_det,
                        const double *jd_ul, const float *mag_ul,
                        int n_ul ) {
 char device_spec[PATH_MAX_LEN];
 char wbuf[32];
 char hbuf[32];
 char xlabel_buf[256];
 int pgplot_status;
 int i;
 double jd_offset;
 double xmin_jd, xmax_jd;
 float xmin_f, xmax_f;
 float ymin_mag, ymax_mag;
 float xch, ych;
 float tri_w_half;
 float tri_h_half;
 float tri_x[3];
 float tri_y[3];
 float *jd_det_f;
 float *jd_ul_f;

 jd_det_f= NULL;
 jd_ul_f= NULL;

 // Tell PGPLOT's PNG driver what dimensions to use; must be set before
 // cpgbeg so they take effect at device-open time.
 snprintf( wbuf, sizeof( wbuf ), "%d", opt->width );
 snprintf( hbuf, sizeof( hbuf ), "%d", opt->height );
 setenv( "PGPLOT_PNG_WIDTH", wbuf, 1 );
 setenv( "PGPLOT_PNG_HEIGHT", hbuf, 1 );

 snprintf( device_spec, sizeof( device_spec ), "%s/PNG", plot_path );
 pgplot_status= cpgbeg( 0, device_spec, 1, 1 );
 if ( pgplot_status != 1 ) {
  fprintf( stderr,
           "ERROR: cannot open PGPLOT /PNG device (\"%s\"). "
           "PGPLOT was likely built without libpng support. "
           "No plot written.\n",
           device_spec );
  return EXIT_FAILURE;
 }

 compute_axis_ranges( jd_det, mag_det, err_det, n_det,
                      jd_ul, mag_ul, n_ul,
                      &xmin_jd, &xmax_jd, &ymin_mag, &ymax_mag );

 // Subtract an integer-day offset to keep JDs in a float-friendly range.
 jd_offset= floor( xmin_jd );
 xmin_f= (float)( xmin_jd - jd_offset );
 xmax_f= (float)( xmax_jd - jd_offset );

 // Allocate float arrays for plotting (PGPLOT wants float, not double).
 if ( n_det > 0 ) {
  jd_det_f= (float *)malloc( (size_t)n_det * sizeof( float ) );
  if ( jd_det_f == NULL ) {
   cpgend();
   return EXIT_FAILURE;
  }
  for ( i= 0; i < n_det; i++ )
   jd_det_f[i]= (float)( jd_det[i] - jd_offset );
 }
 if ( n_ul > 0 ) {
  jd_ul_f= (float *)malloc( (size_t)n_ul * sizeof( float ) );
  if ( jd_ul_f == NULL ) {
   free( jd_det_f );
   cpgend();
   return EXIT_FAILURE;
  }
  for ( i= 0; i < n_ul; i++ )
   jd_ul_f[i]= (float)( jd_ul[i] - jd_offset );
 }

 // White background, black foreground -- matches the PNG branch in lc.c.
 cpgscr( COLOR_BG, 1.0, 1.0, 1.0 );
 cpgscr( COLOR_FG, 0.0, 0.0, 0.0 );
 // Redefine the detection/upper-limit colors from the default pure PGPLOT
 // red/blue to a Paul Tol inspired pair: detections #CC3311, upper limits
 // #5588BB. The desaturated blue makes the limit symbols recede so the
 // red detections stand out; the pair keeps strong separation under all
 // color-vision-deficiency types and >=3:1 contrast on white.
 cpgscr( COLOR_RED, 0.800f, 0.200f, 0.067f );  // #CC3311
 cpgscr( COLOR_BLUE, 0.333f, 0.533f, 0.733f ); // #5588BB
 cpgpage();
 // Roman font (cpgscf == 2) draws multi-stroke glyphs that look noticeably
 // more even on PGPLOT's PNG driver than the default single-stroke font 1.
 // The default font's thin strokes alias to inconsistent pixel widths and
 // patchy "shade of black" at low character sizes; Roman at a modestly
 // larger-than-default size makes labels and tick numbers crisper.
 cpgscf( 2 );
 cpgsch( 1.2 );
 cpgslw( 2 );

 // Explicit viewport sized for cpgsch(1.2) labels. PGPLOT's default viewport
 // (~10% margin on each side) was tuned for cpgsch(1.0); at our slightly
 // larger character size we widen the margins a bit so the x-axis label
 // does not hang off the bottom of the canvas and the y-label / title
 // clear the plot frame. These margins keep all labels visible while
 // leaving the plot area as large as practical.
 cpgsvp( 0.11f, 0.96f, 0.11f, 0.90f );

 // Y axis INVERTED for magnitude convention (brighter at top).
 cpgswin( xmin_f, xmax_f, ymax_mag, ymin_mag );

 // Axes and tick labels in black.
 cpgsci( COLOR_FG );
 cpgbox( "BCNTS", 0.0, 0, "BCNTSV", 0.0, 0 );

 // Axis labels and title -- drawn via cpgmtxt directly (not cpglab) so we
 // control each displacement independently. cpglab's hard-coded offsets
 // are too far (bottom 3.2, top 2.0) or too close (left 2.2 overlaps the
 // y-axis numeric labels when they have four characters like "12.5").
 // Displacements are in character heights from the corresponding edge of
 // the viewport.
 if ( opt->xlabel != NULL ) {
  cpgmtxt( "B", 2.5f, 0.5f, 0.5f, opt->xlabel );
 } else {
  snprintf( xlabel_buf, sizeof( xlabel_buf ), "JD - %.0f", jd_offset );
  cpgmtxt( "B", 2.5f, 0.5f, 0.5f, xlabel_buf );
 }
 if ( opt->ylabel != NULL && opt->ylabel[ 0 ] != '\0' ) {
  cpgmtxt( "L", 3.2f, 0.5f, 0.5f, opt->ylabel );
 }
 if ( opt->title != NULL && opt->title[ 0 ] != '\0' ) {
  cpgmtxt( "T", 0.8f, 0.5f, 0.5f, opt->title );
 }

 // Detections: red filled circles with Y error bars.
 if ( n_det > 0 ) {
  cpgsci( COLOR_RED );
  // Symbol 17 = filled circle. cpgerrb mode 6 = symmetric Y error bar.
  cpgpt( n_det, jd_det_f, mag_det, 17 );
  cpgerrb( 6, n_det, jd_det_f, mag_det, err_det, 1.0 );
 }

 // Upper limits: blue solid-filled downward triangles drawn with cpgpoly.
 // Size is tuned to match the apparent size of cpgpt symbol 17 (filled
 // circle) used for detections; the visible-circle diameter from cpgpt is
 // ~0.3 of character height, so the triangle bounding box should be of
 // similar order (NOT the full character size, which would draw triangles
 // ~3x bigger than the dots). fabsf on ych because cpgqcs returns a
 // negative ych for the inverted (mag) y-axis -- without fabsf the apex
 // would point up.
 if ( n_ul > 0 ) {
  cpgsci( COLOR_BLUE );
  cpgqcs( 4, &xch, &ych ); // 4 = world coordinates
  cpgsfs( 1 );             // 1 = solid fill
  tri_w_half= fabsf( xch ) * 0.15f;
  tri_h_half= fabsf( ych ) * 0.15f;
  for ( i= 0; i < n_ul; i++ ) {
   // Apex points to fainter magnitudes -- downward on the inverted-axis
   // screen. The base is at brighter (smaller) mag, the apex at fainter
   // (larger) mag.
   tri_x[0]= jd_ul_f[i] - tri_w_half;
   tri_y[0]= mag_ul[i] - tri_h_half; // base, brighter side (top on screen)
   tri_x[1]= jd_ul_f[i] + tri_w_half;
   tri_y[1]= mag_ul[i] - tri_h_half; // base
   tri_x[2]= jd_ul_f[i];
   tri_y[2]= mag_ul[i] + tri_h_half; // apex, fainter side (bottom on screen)
   cpgpoly( 3, tri_x, tri_y );
  }
 }

 cpgend();
 free( jd_det_f );
 free( jd_ul_f );
 return EXIT_SUCCESS;
}

int main( int argc, char **argv ) {
 options_t opt;
 double *jd_det;
 float *mag_det;
 float *err_det;
 double *jd_ul;
 float *mag_ul;
 int n_det;
 int n_ul;
 int rc;
 int use_temp;
 char plot_path[PATH_MAX_LEN];

 jd_det= NULL;
 mag_det= NULL;
 err_det= NULL;
 jd_ul= NULL;
 mag_ul= NULL;
 n_det= 0;
 n_ul= 0;
 use_temp= 0;

 if ( parse_args( argc, argv, &opt ) != 0 )
  return EXIT_FAILURE;

 // Set PGPLOT_DIR relative to argv[0], same way lc does. Without this,
 // PGPLOT cannot find its grfont.dat and text rendering fails.
 setenv_localpgplot( argv[0] );

 if ( read_main_lightcurve( opt.input_file, &jd_det, &mag_det, &err_det,
                            &n_det ) != 0 ) {
  fprintf( stderr, "ERROR: cannot read lightcurve file %s\n",
           opt.input_file );
  return EXIT_FAILURE;
 }
 if ( opt.upperlimits_file != NULL ) {
  if ( read_upperlimits( opt.upperlimits_file, &jd_ul, &mag_ul,
                         &n_ul ) != 0 ) {
   fprintf( stderr, "ERROR: cannot read upper-limits file %s\n",
            opt.upperlimits_file );
   free( jd_det );
   free( mag_det );
   free( err_det );
   return EXIT_FAILURE;
  }
 }
 if ( n_det == 0 && n_ul == 0 ) {
  fprintf( stderr,
           "ERROR: no detections and no upper limits -- nothing to plot\n" );
  free( jd_det );
  free( mag_det );
  free( err_det );
  free( jd_ul );
  free( mag_ul );
  return EXIT_FAILURE;
 }
 // PGPLOT truncates long device filenames (see the comment at the top of
 // this file), so long output paths are rendered under a short temporary
 // name in the current directory and moved into place afterwards.
 if ( strlen( opt.output_png ) >= PGPLOT_SAFE_FILENAME_LEN ) {
  use_temp= 1;
  snprintf( plot_path, sizeof( plot_path ), "lightcurve_png_tmp_%d.png",
            (int)getpid() );
 } else {
  snprintf( plot_path, sizeof( plot_path ), "%s", opt.output_png );
 }

 rc= render_plot( &opt, plot_path, jd_det, mag_det, err_det, n_det,
                  jd_ul, mag_ul, n_ul );
 free( jd_det );
 free( mag_det );
 free( err_det );
 free( jd_ul );
 free( mag_ul );

 // Verify PGPLOT really wrote the plot before claiming success: the PNG
 // driver can fail to open the output file (permissions, bad path) and
 // print only "plotting disabled" while cpgbeg reports success -- without
 // this check the tool would exit 0 having written nothing.
 if ( rc == EXIT_SUCCESS ) {
  if ( 0 == file_exists_nonempty( plot_path ) ) {
   fprintf( stderr,
            "ERROR: PGPLOT did not write %s (see any \"PGPLOT /png:\" "
            "message above; check directory permissions). "
            "No plot written.\n",
            plot_path );
   rc= EXIT_FAILURE;
  }
 }
 if ( rc == EXIT_SUCCESS && use_temp != 0 ) {
  if ( 0 != move_file( plot_path, opt.output_png ) ) {
   fprintf( stderr,
            "ERROR: cannot move the plot from %s to %s\n",
            plot_path, opt.output_png );
   unlink( plot_path );
   rc= EXIT_FAILURE;
  }
 }
 if ( rc != EXIT_SUCCESS && use_temp != 0 ) {
  unlink( plot_path ); // best-effort temp cleanup; may not exist
 }
 if ( rc == EXIT_SUCCESS ) {
  fprintf( stderr, "Wrote %s (%d detection%s, %d upper limit%s)\n",
           opt.output_png,
           n_det, n_det == 1 ? "" : "s",
           n_ul, n_ul == 1 ? "" : "s" );
 }
 return rc;
}
