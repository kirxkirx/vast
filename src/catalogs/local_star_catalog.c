// local_star_catalog - build and search local copies of star catalogs used by the
// known-star check of transient candidates (util/transients/report_transient.sh).
//
// The check asks "is there a catalogued star at least as bright as this candidate
// (plus a margin) at this position?". It used to be answered only by Gaia DR2 at CDS
// VizieR or the ESA Gaia archive, both of which can be unreachable for days. This
// program answers the same question from local files, and prints the answer in the
// same text format as lib/gaia_dr2_cone_search.sh and lib/vizquery, so the parsing
// code in report_transient.sh stays the same.
//
// Catalogs and their files:
//  - gaia_dr2: Gaia DR2 stars brighter than a G limit (19 by default), built by
//    lib/install_local_copy_of_GaiaDR2.sh from the official ESA bulk download.
//  - tycho2: the main Tycho-2 catalog (lib/catalogs/tycho2/tyc2.dat.*), positions
//    propagated to epoch 2016.0, V estimated from BT and VT.
//    Both use the zone format below.
//  - ucac5: VaST's existing local UCAC5 copy (lib/catalogs/ucac5/z001..z900, 52-byte
//    records sorted by RA, see http://cdsarc.u-strasbg.fr/ftp/I/340/readmeU5.txt),
//    read in place; positions and G magnitudes there come from Gaia DR1.
//
// Zone format (format=vast_local_star_catalog_v1): 900 declination zones of 0.2 deg,
// files z001 (dec -90.0..-89.8) .. z900, each a sequence of 24-byte little-endian
// records sorted by RA:
//   int64 id | uint32 RA*1e7 deg | int32 Dec*1e7 deg | int16 m1 | int16 m2 | int16 m3 |
//   uint8 flags | uint8 reserved
// magnitudes in millimag, -32768 = no value; Gaia: m1=G m2=BP m3=RP, flags bit 0 =
// phot_variable_flag VARIABLE; Tycho-2: m1=V estimate m2=BT m3=VT.
// zNNN.idx holds 3601 little-endian uint32: the index of the first record with
// RA >= k*0.1 deg for k=0..3600 (the last value is the number of records).
// catalog_info.txt is written last, so a directory without it is an incomplete build.
//
// Subcommands:
//   local_star_catalog gaia-extract STAGING_DIR CHUNK_NAME MAX_GMAG < GaiaSource_NNN.csv
//   local_star_catalog tycho2-extract STAGING_DIR CHUNK_NAME tyc2.dat.00 [tyc2.dat.01 ...]
//   local_star_catalog finalize STAGING_DIR OUTPUT_DIR CATALOG_NAME DESCRIPTION [MEMORY_LIMIT_MB]
//   local_star_catalog search [-cat=TYPE:DIR ...] [DIR] -c="RA DEC" -c.rs=ARCSEC
//                      [-out.max=N] [-sort=Gmag|RPmag] [Gmag=A..B|RPmag=A..B]
//     TYPE is gaia_dr2, tycho2 or ucac5; a bare DIR is read as a zone catalog.
//     RA DEC are sexagesimal (hh:mm:ss.s +dd:mm:ss.s) or decimal degrees.
//     Several catalogs are merged, sorted by magnitude in the requested band, and a
//     star listed by more than one catalog within 2 arcsec is reported once.
//     A star within 0.0005 mag of a magnitude limit is left out (see mag_passes()).
//     For Tycho-2 the band is V for both Gmag and RPmag requests; for UCAC5 it is
//     the Gaia DR1 G magnitude (UCAC f.mag when G is missing).
// Exit codes: 0 success (also when nothing matches), 1 usage error, 2 a catalog is
// missing, incomplete or unreadable (the caller should then ask an online service).

#define _FILE_OFFSET_BITS 64
#define _POSIX_C_SOURCE 200809L

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define REC_SIZE 24
#define UCAC5_REC_SIZE 52
#define ZONE_COUNT 900
#define ZONE_HEIGHT_DEG 0.2
#define RA_BINS 3600
#define RA_BIN_E7 1000000U // 0.1 deg in units of 1e-7 deg
#define MAG_NULL ( -32768 )
#define MAG_ROUNDING_TOLERANCE 0.0005 // half of the 0.001 mag precision of the stored magnitudes
#define DEDUP_RADIUS_ARCSEC 2.0
#define MAX_CATALOGS 8
#define CATALOG_FORMAT "vast_local_star_catalog_v1"

typedef struct {
 int64_t id;
 uint32_t ra_e7;
 int32_t dec_e7;
 int16_t m1, m2, m3;
 uint8_t flags;
} star_rec;

typedef struct {
 double dist_arcsec;
 int64_t id;
 double ra, dec;
 double mag_sort; // magnitude in the requested band, used for sorting and limits
 double gmag, rpmag; // printed columns (99.9999 = no value)
 int variable;
 int catalog_index;
} match_t;

typedef struct {
 match_t *m;
 size_t n, cap;
} match_list;

// -------------------------------------------------------------------------
// little-endian (de)serialization

static void put_u16( unsigned char *b, uint16_t v ) {
 b[0]= (unsigned char)( v & 0xff );
 b[1]= (unsigned char)( ( v >> 8 ) & 0xff );
}
static void put_u32( unsigned char *b, uint32_t v ) {
 int i;
 for ( i= 0; i < 4; i++ )
  b[i]= (unsigned char)( ( v >> ( 8 * i ) ) & 0xff );
}
static void put_u64( unsigned char *b, uint64_t v ) {
 int i;
 for ( i= 0; i < 8; i++ )
  b[i]= (unsigned char)( ( v >> ( 8 * i ) ) & 0xff );
}
static uint16_t get_u16( const unsigned char *b ) {
 return (uint16_t)( b[0] | ( b[1] << 8 ) );
}
static uint32_t get_u32( const unsigned char *b ) {
 return (uint32_t)b[0] | ( (uint32_t)b[1] << 8 ) | ( (uint32_t)b[2] << 16 ) | ( (uint32_t)b[3] << 24 );
}
static uint64_t get_u64( const unsigned char *b ) {
 uint64_t v= 0;
 int i;
 for ( i= 7; i >= 0; i-- )
  v= ( v << 8 ) | b[i];
 return v;
}

static void pack_rec( const star_rec *r, unsigned char *b ) {
 put_u64( b, (uint64_t)r->id );
 put_u32( b + 8, r->ra_e7 );
 put_u32( b + 12, (uint32_t)r->dec_e7 );
 put_u16( b + 16, (uint16_t)r->m1 );
 put_u16( b + 18, (uint16_t)r->m2 );
 put_u16( b + 20, (uint16_t)r->m3 );
 b[22]= r->flags;
 b[23]= 0;
}
static void unpack_rec( const unsigned char *b, star_rec *r ) {
 r->id= (int64_t)get_u64( b );
 r->ra_e7= get_u32( b + 8 );
 r->dec_e7= (int32_t)get_u32( b + 12 );
 r->m1= (int16_t)get_u16( b + 16 );
 r->m2= (int16_t)get_u16( b + 18 );
 r->m3= (int16_t)get_u16( b + 20 );
 r->flags= b[22];
}

// -------------------------------------------------------------------------
// helpers

static int16_t mag_to_millimag( double mag, int is_null ) {
 double v;
 if ( is_null || !isfinite( mag ) )
  return MAG_NULL;
 v= floor( mag * 1000.0 + 0.5 );
 if ( v < -32767.0 || v > 32767.0 )
  return MAG_NULL;
 return (int16_t)v;
}

static double millimag_to_mag( int16_t m ) {
 return (double)m / 1000.0;
}

static int zone_of_dec( double dec_deg ) {
 int z= (int)floor( ( dec_deg + 90.0 ) / ZONE_HEIGHT_DEG ) + 1;
 if ( z < 1 )
  z= 1;
 if ( z > ZONE_COUNT )
  z= ZONE_COUNT;
 return z;
}

static uint32_t ra_deg_to_e7( double ra_deg ) {
 double v;
 ra_deg= fmod( ra_deg, 360.0 );
 if ( ra_deg < 0.0 )
  ra_deg+= 360.0;
 v= floor( ra_deg * 1.0e7 + 0.5 );
 if ( v >= 3.6e9 )
  v= 0.0;
 return (uint32_t)v;
}

static int32_t dec_deg_to_e7( double dec_deg ) {
 if ( dec_deg > 90.0 )
  dec_deg= 90.0;
 if ( dec_deg < -90.0 )
  dec_deg= -90.0;
 return (int32_t)floor( dec_deg * 1.0e7 + 0.5 );
}

// angular distance in arcsec
static double angular_distance_arcsec( double ra1, double dec1, double ra2, double dec2 ) {
 const double d2r= M_PI / 180.0;
 double sdd= sin( ( dec2 - dec1 ) * d2r / 2.0 );
 double sdr= sin( ( ra2 - ra1 ) * d2r / 2.0 );
 double a= sdd * sdd + cos( dec1 * d2r ) * cos( dec2 * d2r ) * sdr * sdr;
 if ( a > 1.0 )
  a= 1.0;
 return 2.0 * asin( sqrt( a ) ) / d2r * 3600.0;
}

static int write_all( FILE *f, const void *buf, size_t n ) {
 return fwrite( buf, 1, n, f ) == n ? 0 : -1;
}

// create a directory and its missing parents, like mkdir -p
static int make_dir( const char *path ) {
 char buf[4096];
 size_t i, n= strlen( path );
 char saved;
 if ( n == 0 || n >= sizeof( buf ) ) {
  fprintf( stderr, "ERROR: bad directory name %s\n", path );
  return -1;
 }
 memcpy( buf, path, n + 1 );
 for ( i= 1; i <= n; i++ ) {
  if ( buf[i] == '/' || buf[i] == '\0' ) {
   saved= buf[i];
   buf[i]= '\0';
   if ( 0 != mkdir( buf, 0755 ) && errno != EEXIST ) {
    fprintf( stderr, "ERROR: cannot create directory %s: %s\n", buf, strerror( errno ) );
    return -1;
   }
   buf[i]= saved;
  }
 }
 return 0;
}

// write a buffer to dir/name atomically (tmp file + rename)
static int write_file_atomically( const char *dir, const char *name, const unsigned char *buf, size_t n ) {
 char path[4096], tmp[4096];
 FILE *f;
 snprintf( path, sizeof( path ), "%s/%s", dir, name );
 snprintf( tmp, sizeof( tmp ), "%s/.%s.tmp.%ld", dir, name, (long)getpid() );
 f= fopen( tmp, "wb" );
 if ( NULL == f ) {
  fprintf( stderr, "ERROR: cannot write %s: %s\n", tmp, strerror( errno ) );
  return -1;
 }
 if ( n > 0 && 0 != write_all( f, buf, n ) ) {
  fprintf( stderr, "ERROR: write error on %s\n", tmp );
  fclose( f );
  unlink( tmp );
  return -1;
 }
 if ( 0 != fclose( f ) ) {
  fprintf( stderr, "ERROR: cannot close %s\n", tmp );
  unlink( tmp );
  return -1;
 }
 if ( 0 != rename( tmp, path ) ) {
  fprintf( stderr, "ERROR: cannot rename %s to %s: %s\n", tmp, path, strerror( errno ) );
  unlink( tmp );
  return -1;
 }
 return 0;
}

// growable byte buffer of packed records
typedef struct {
 unsigned char *b;
 size_t n_rec, cap_rec;
} rec_buffer;

static int rec_buffer_add( rec_buffer *rb, const star_rec *r ) {
 size_t new_cap;
 unsigned char *nb;
 if ( rb->n_rec == rb->cap_rec ) {
  new_cap= rb->cap_rec ? rb->cap_rec * 2 : 65536;
  nb= realloc( rb->b, new_cap * REC_SIZE );
  if ( NULL == nb ) {
   fprintf( stderr, "ERROR: out of memory\n" );
   return -1;
  }
  rb->b= nb;
  rb->cap_rec= new_cap;
 }
 pack_rec( r, rb->b + rb->n_rec * REC_SIZE );
 rb->n_rec++;
 return 0;
}

static int write_chunk( const char *staging_dir, const char *chunk_name, rec_buffer *rb ) {
 char name[1024];
 snprintf( name, sizeof( name ), "%s.part", chunk_name );
 return write_file_atomically( staging_dir, name, rb->b, rb->n_rec * REC_SIZE );
}

// -------------------------------------------------------------------------
// gaia-extract

// Split a CSV line in place: fields[i] points to the start of field i, with the
// terminating comma replaced by '\0'. Double-quoted fields are unquoted. Returns the
// number of fields.
static int split_csv( char *line, char **fields, int max_fields ) {
 int n= 0;
 char *p= line;
 char *w;
 while ( n < max_fields ) {
  if ( *p == '"' ) {
   p++;
   fields[n++]= p;
   w= p;
   while ( *p ) {
    if ( *p == '"' ) {
     if ( p[1] == '"' ) {
      *w++= '"';
      p+= 2;
      continue;
     }
     p++;
     break;
    }
    *w++= *p++;
   }
   *w= '\0';
   while ( *p && *p != ',' )
    p++;
  } else {
   fields[n++]= p;
   while ( *p && *p != ',' && *p != '\n' && *p != '\r' )
    p++;
  }
  if ( *p == ',' ) {
   *p= '\0';
   p++;
   continue;
  }
  *p= '\0';
  break;
 }
 return n;
}

static int is_null_field( const char *s ) {
 return s[0] == '\0' || 0 == strcmp( s, "null" ) || 0 == strcmp( s, "NULL" ) || 0 == strcmp( s, "nan" ) || 0 == strcmp( s, "NaN" );
}

static int cmd_gaia_extract( int argc, char **argv ) {
 const char *staging_dir, *chunk_name;
 double max_gmag;
 char *line= NULL;
 size_t line_cap= 0;
 ssize_t len;
 char **fields;
 int max_fields= 1024;
 int header_seen= 0;
 int i_sid= -1, i_ra= -1, i_dec= -1, i_g= -1, i_bp= -1, i_rp= -1, i_var= -1, max_needed= -1;
 rec_buffer rb= { NULL, 0, 0 };
 long n_rows= 0;
 star_rec r;
 int nf, i;
 double g;

 if ( argc != 5 ) {
  fprintf( stderr, "Usage: %s gaia-extract STAGING_DIR CHUNK_NAME MAX_GMAG < GaiaSource.csv\n", argv[0] );
  return 1;
 }
 staging_dir= argv[2];
 chunk_name= argv[3];
 max_gmag= atof( argv[4] );
 if ( max_gmag <= 0.0 || max_gmag > 25.0 ) {
  fprintf( stderr, "ERROR: implausible MAX_GMAG %s\n", argv[4] );
  return 1;
 }
 if ( 0 != make_dir( staging_dir ) )
  return 2;
 fields= malloc( sizeof( char * ) * max_fields );
 if ( NULL == fields )
  return 2;

 while ( ( len= getline( &line, &line_cap, stdin ) ) > 0 ) {
  if ( line[0] == '#' )
   continue;
  nf= split_csv( line, fields, max_fields );
  if ( !header_seen ) {
   for ( i= 0; i < nf; i++ ) {
    if ( 0 == strcmp( fields[i], "source_id" ) )
     i_sid= i;
    else if ( 0 == strcmp( fields[i], "ra" ) )
     i_ra= i;
    else if ( 0 == strcmp( fields[i], "dec" ) )
     i_dec= i;
    else if ( 0 == strcmp( fields[i], "phot_g_mean_mag" ) )
     i_g= i;
    else if ( 0 == strcmp( fields[i], "phot_bp_mean_mag" ) )
     i_bp= i;
    else if ( 0 == strcmp( fields[i], "phot_rp_mean_mag" ) )
     i_rp= i;
    else if ( 0 == strcmp( fields[i], "phot_variable_flag" ) )
     i_var= i;
   }
   if ( i_sid < 0 || i_ra < 0 || i_dec < 0 || i_g < 0 ) {
    fprintf( stderr, "ERROR: the CSV header lacks source_id, ra, dec or phot_g_mean_mag\n" );
    free( fields );
    free( line );
    return 2;
   }
   max_needed= i_sid;
   if ( i_ra > max_needed )
    max_needed= i_ra;
   if ( i_dec > max_needed )
    max_needed= i_dec;
   if ( i_g > max_needed )
    max_needed= i_g;
   if ( i_bp > max_needed )
    max_needed= i_bp;
   if ( i_rp > max_needed )
    max_needed= i_rp;
   if ( i_var > max_needed )
    max_needed= i_var;
   header_seen= 1;
   continue;
  }
  n_rows++;
  if ( nf <= max_needed ) {
   fprintf( stderr, "ERROR: a data line has %d fields, the header needs %d - truncated input?\n", nf, max_needed + 1 );
   free( fields );
   free( line );
   free( rb.b );
   return 2;
  }
  if ( is_null_field( fields[i_g] ) )
   continue;
  g= atof( fields[i_g] );
  if ( !( g < max_gmag ) )
   continue;
  memset( &r, 0, sizeof( r ) );
  r.id= (int64_t)strtoll( fields[i_sid], NULL, 10 );
  r.ra_e7= ra_deg_to_e7( atof( fields[i_ra] ) );
  r.dec_e7= dec_deg_to_e7( atof( fields[i_dec] ) );
  r.m1= mag_to_millimag( g, 0 );
  r.m2= ( i_bp >= 0 ) ? mag_to_millimag( atof( fields[i_bp] ), is_null_field( fields[i_bp] ) ) : MAG_NULL;
  r.m3= ( i_rp >= 0 ) ? mag_to_millimag( atof( fields[i_rp] ), is_null_field( fields[i_rp] ) ) : MAG_NULL;
  r.flags= ( i_var >= 0 && 0 == strcmp( fields[i_var], "VARIABLE" ) ) ? 1 : 0;
  if ( 0 != rec_buffer_add( &rb, &r ) ) {
   free( fields );
   free( line );
   free( rb.b );
   return 2;
  }
 }
 free( fields );
 free( line );
 if ( !header_seen ) {
  fprintf( stderr, "ERROR: no CSV header found on the standard input\n" );
  free( rb.b );
  return 2;
 }
 if ( 0 != write_chunk( staging_dir, chunk_name, &rb ) ) {
  free( rb.b );
  return 2;
 }
 fprintf( stderr, "%s: kept %lu of %ld sources with G < %.2f\n", chunk_name, (unsigned long)rb.n_rec, n_rows, max_gmag );
 free( rb.b );
 return 0;
}

// -------------------------------------------------------------------------
// tycho2-extract

// copy columns [first,last] (1-based, inclusive) of a fixed-width line
static int column_text( const char *line, size_t line_len, int first, int last, char *out, size_t out_size ) {
 size_t n, i, k= 0;
 char c;
 if ( (size_t)first > line_len ) {
  out[0]= '\0';
  return 0;
 }
 n= (size_t)( last - first + 1 );
 for ( i= 0; i < n && (size_t)( first - 1 ) + i < line_len && k + 1 < out_size; i++ ) {
  c= line[first - 1 + i];
  if ( c == '\n' || c == '\r' )
   break;
  out[k++]= c;
 }
 out[k]= '\0';
 // blank?
 for ( i= 0; i < k; i++ )
  if ( !isspace( (unsigned char)out[i] ) )
   return 1;
 out[0]= '\0';
 return 0;
}

static int cmd_tycho2_extract( int argc, char **argv ) {
 const char *staging_dir, *chunk_name;
 int i;
 rec_buffer rb= { NULL, 0, 0 };
 long n_lines= 0;
 const double epoch_shift_yr= 16.0; // J2000 mean positions -> epoch 2016.0
 FILE *f;
 char *line;
 size_t cap;
 ssize_t len;
 char t1[8], t2[8], t3[4], buf[32], bt_s[16], vt_s[16];
 double ra, dec, bt, vt, vmag;
 int has_bt, has_vt;
 star_rec r;
 double pmra, pmde;
 char pm1[16], pm2[16];

 if ( argc < 5 ) {
  fprintf( stderr, "Usage: %s tycho2-extract STAGING_DIR CHUNK_NAME tyc2.dat.00 [tyc2.dat.01 ...]\n", argv[0] );
  return 1;
 }
 staging_dir= argv[2];
 chunk_name= argv[3];
 if ( 0 != make_dir( staging_dir ) )
  return 2;
 for ( i= 4; i < argc; i++ ) {
  f= fopen( argv[i], "r" );
  line= NULL;
  cap= 0;
  if ( NULL == f ) {
   fprintf( stderr, "ERROR: cannot open %s: %s\n", argv[i], strerror( errno ) );
   free( rb.b );
   return 2;
  }
  while ( ( len= getline( &line, &cap, f ) ) > 0 ) {
   bt= 0.0;
   vt= 0.0;
   n_lines++;
   if ( len < 177 )
    continue;
   if ( !column_text( line, (size_t)len, 1, 4, t1, sizeof( t1 ) ) || !column_text( line, (size_t)len, 6, 10, t2, sizeof( t2 ) ) || !column_text( line, (size_t)len, 12, 12, t3, sizeof( t3 ) ) )
    continue;
   if ( column_text( line, (size_t)len, 16, 27, buf, sizeof( buf ) ) ) {
    pmra= 0.0;
    pmde= 0.0;
    ra= atof( buf );
    column_text( line, (size_t)len, 29, 40, buf, sizeof( buf ) );
    dec= atof( buf );
    if ( column_text( line, (size_t)len, 42, 48, pm1, sizeof( pm1 ) ) )
     pmra= atof( pm1 );
    if ( column_text( line, (size_t)len, 50, 56, pm2, sizeof( pm2 ) ) )
     pmde= atof( pm2 );
    // pmRA is pmRA*cos(Dec), mas/yr
    if ( fabs( dec ) < 89.99 )
     ra+= pmra * epoch_shift_yr / 3.6e6 / cos( dec * M_PI / 180.0 );
    dec+= pmde * epoch_shift_yr / 3.6e6;
   } else {
    // no mean position (pflag X): use the observed position
    if ( !column_text( line, (size_t)len, 153, 164, buf, sizeof( buf ) ) )
     continue;
    ra= atof( buf );
    if ( !column_text( line, (size_t)len, 166, 177, buf, sizeof( buf ) ) )
     continue;
    dec= atof( buf );
   }
   has_bt= column_text( line, (size_t)len, 111, 116, bt_s, sizeof( bt_s ) );
   has_vt= column_text( line, (size_t)len, 124, 129, vt_s, sizeof( vt_s ) );
   if ( has_bt )
    bt= atof( bt_s );
   if ( has_vt )
    vt= atof( vt_s );
   if ( !has_bt && !has_vt )
    continue;
   if ( has_bt && has_vt )
    vmag= vt - 0.090 * ( bt - vt ); // Hipparcos/Tycho standard transformation
   else if ( has_vt )
    vmag= vt;
   else
    vmag= bt - 0.5; // only BT: a rough V for a typical star, used only as a limit
   memset( &r, 0, sizeof( r ) );
   r.id= (int64_t)atol( t1 ) * 1000000LL + (int64_t)atol( t2 ) * 10LL + (int64_t)atol( t3 );
   r.ra_e7= ra_deg_to_e7( ra );
   r.dec_e7= dec_deg_to_e7( dec );
   r.m1= mag_to_millimag( vmag, 0 );
   r.m2= mag_to_millimag( bt, !has_bt );
   r.m3= mag_to_millimag( vt, !has_vt );
   r.flags= 0;
   if ( 0 != rec_buffer_add( &rb, &r ) ) {
    free( line );
    fclose( f );
    free( rb.b );
    return 2;
   }
  }
  free( line );
  fclose( f );
 }
 if ( 0 != write_chunk( staging_dir, chunk_name, &rb ) ) {
  free( rb.b );
  return 2;
 }
 fprintf( stderr, "%s: %lu Tycho-2 stars from %ld lines\n", chunk_name, (unsigned long)rb.n_rec, n_lines );
 free( rb.b );
 return 0;
}

// -------------------------------------------------------------------------
// finalize

static int compare_packed_ra( const void *a, const void *b ) {
 uint32_t ra= get_u32( (const unsigned char *)a + 8 );
 uint32_t rb= get_u32( (const unsigned char *)b + 8 );
 if ( ra < rb )
  return -1;
 if ( ra > rb )
  return 1;
 return 0;
}

static int compare_strings( const void *a, const void *b ) {
 return strcmp( *(char *const *)a, *(char *const *)b );
}

// list the .part files in STAGING_DIR, sorted by name
static char **list_parts( const char *staging_dir, size_t *n_out ) {
 DIR *d= opendir( staging_dir );
 struct dirent *e;
 char **names= NULL;
 size_t n= 0, cap= 0;
 size_t l;
 char **nn;
 if ( NULL == d ) {
  fprintf( stderr, "ERROR: cannot open %s: %s\n", staging_dir, strerror( errno ) );
  return NULL;
 }
 while ( NULL != ( e= readdir( d ) ) ) {
  l= strlen( e->d_name );
  if ( l < 6 || e->d_name[0] == '.' || 0 != strcmp( e->d_name + l - 5, ".part" ) )
   continue;
  if ( n == cap ) {
   cap= cap ? cap * 2 : 1024;
   nn= realloc( names, cap * sizeof( char * ) );
   if ( NULL == nn ) {
    closedir( d );
    return NULL;
   }
   names= nn;
  }
  names[n]= malloc( strlen( staging_dir ) + l + 2 );
  if ( NULL == names[n] ) {
   closedir( d );
   return NULL;
  }
  sprintf( names[n], "%s/%s", staging_dir, e->d_name );
  n++;
 }
 closedir( d );
 if ( n > 0 )
  qsort( names, n, sizeof( char * ), compare_strings );
 *n_out= n;
 return names;
}

// Read every part file and call fn for each packed record
typedef int ( *record_fn )( const unsigned char *rec, void *ctx );

static int for_each_record( char **parts, size_t n_parts, record_fn fn, void *ctx ) {
 size_t i, got, k;
 FILE *f;
 unsigned char *buf= malloc( (size_t)REC_SIZE * 65536 );
 if ( NULL == buf )
  return -1;
 for ( i= 0; i < n_parts; i++ ) {
  f= fopen( parts[i], "rb" );
  if ( NULL == f ) {
   fprintf( stderr, "ERROR: cannot open %s\n", parts[i] );
   free( buf );
   return -1;
  }
  while ( ( got= fread( buf, REC_SIZE, 65536, f ) ) > 0 ) {
   for ( k= 0; k < got; k++ ) {
    if ( 0 != fn( buf + k * REC_SIZE, ctx ) ) {
     fclose( f );
     free( buf );
     return -1;
    }
   }
  }
  if ( ferror( f ) ) {
   fprintf( stderr, "ERROR: read error on %s\n", parts[i] );
   fclose( f );
   free( buf );
   return -1;
  }
  fclose( f );
 }
 free( buf );
 return 0;
}

typedef struct {
 uint64_t counts[ZONE_COUNT + 1];
} count_ctx;

static int zone_of_packed( const unsigned char *rec ) {
 int32_t dec_e7= (int32_t)get_u32( rec + 12 );
 return zone_of_dec( (double)dec_e7 / 1.0e7 );
}

static int count_fn( const unsigned char *rec, void *ctx ) {
 ( (count_ctx *)ctx )->counts[zone_of_packed( rec )]++;
 return 0;
}

typedef struct {
 int z0, z1;
 unsigned char *zone_buf[ZONE_COUNT + 1];
 uint64_t filled[ZONE_COUNT + 1];
 const uint64_t *counts;
} fill_ctx;

static int fill_fn( const unsigned char *rec, void *ctx ) {
 fill_ctx *c= (fill_ctx *)ctx;
 int z= zone_of_packed( rec );
 if ( z < c->z0 || z > c->z1 )
  return 0;
 if ( c->filled[z] >= c->counts[z] ) {
  fprintf( stderr, "ERROR: zone %d got more records than counted - did the staging files change?\n", z );
  return -1;
 }
 memcpy( c->zone_buf[z] + c->filled[z] * REC_SIZE, rec, REC_SIZE );
 c->filled[z]++;
 return 0;
}

static int write_zone( const char *output_dir, int z, unsigned char *recs, uint64_t n ) {
 char name[32];
 unsigned char idx[( RA_BINS + 1 ) * 4];
 uint64_t i= 0, limit;
 int k;
 if ( n > 0xffffffffULL ) {
  fprintf( stderr, "ERROR: zone %d has too many records\n", z );
  return -1;
 }
 if ( n > 1 )
  qsort( recs, (size_t)n, REC_SIZE, compare_packed_ra );
 for ( k= 0; k <= RA_BINS; k++ ) {
  limit= (uint64_t)k * RA_BIN_E7;
  while ( i < n && (uint64_t)get_u32( recs + i * REC_SIZE + 8 ) < limit )
   i++;
  put_u32( idx + 4 * k, (uint32_t)( k == RA_BINS ? n : i ) );
 }
 snprintf( name, sizeof( name ), "z%03d", z );
 if ( 0 != write_file_atomically( output_dir, name, recs, (size_t)( n * REC_SIZE ) ) )
  return -1;
 snprintf( name, sizeof( name ), "z%03d.idx", z );
 return write_file_atomically( output_dir, name, idx, sizeof( idx ) );
}

static int cmd_finalize( int argc, char **argv ) {
 const char *staging_dir, *output_dir, *catalog_name, *description;
 double memory_limit_mb= 8192.0;
 char **parts;
 size_t n_parts= 0, i;
 count_ctx *cc;
 uint64_t total= 0;
 int z, z1, zz;
 char info[4096];
 time_t now;
 fill_ctx *fc;
 double pass_bytes, zone_bytes;

 if ( argc < 6 || argc > 7 ) {
  fprintf( stderr, "Usage: %s finalize STAGING_DIR OUTPUT_DIR CATALOG_NAME DESCRIPTION [MEMORY_LIMIT_MB]\n", argv[0] );
  return 1;
 }
 staging_dir= argv[2];
 output_dir= argv[3];
 catalog_name= argv[4];
 description= argv[5];
 if ( argc == 7 )
  memory_limit_mb= atof( argv[6] );
 if ( memory_limit_mb < 64.0 )
  memory_limit_mb= 64.0;
 if ( 0 != make_dir( output_dir ) )
  return 2;
 parts= list_parts( staging_dir, &n_parts );
 if ( NULL == parts || n_parts == 0 ) {
  fprintf( stderr, "ERROR: no .part files in %s\n", staging_dir );
  return 2;
 }
 cc= calloc( 1, sizeof( count_ctx ) );
 if ( NULL == cc )
  return 2;
 // the old catalog_info.txt must not vouch for a half-rewritten directory
 snprintf( info, sizeof( info ), "%s/catalog_info.txt", output_dir );
 unlink( info );
 fprintf( stderr, "Counting the records in %lu staging files\n", (unsigned long)n_parts );
 if ( 0 != for_each_record( parts, n_parts, count_fn, cc ) )
  return 2;
 for ( z= 1; z <= ZONE_COUNT; z++ )
  total+= cc->counts[z];
 fprintf( stderr, "%llu records in total\n", (unsigned long long)total );

 z= 1;
 while ( z <= ZONE_COUNT ) {
  pass_bytes= 0.0;
  z1= z;
  // group zones into a pass that fits the memory limit (a single zone always fits)
  while ( z1 <= ZONE_COUNT ) {
   zone_bytes= (double)cc->counts[z1] * REC_SIZE;
   if ( z1 > z && pass_bytes + zone_bytes > memory_limit_mb * 1048576.0 )
    break;
   pass_bytes+= zone_bytes;
   z1++;
  }
  z1--;
  fc= calloc( 1, sizeof( fill_ctx ) );
  if ( NULL == fc )
   return 2;
  fc->z0= z;
  fc->z1= z1;
  fc->counts= cc->counts;
  for ( zz= z; zz <= z1; zz++ ) {
   fc->zone_buf[zz]= malloc( cc->counts[zz] > 0 ? (size_t)cc->counts[zz] * REC_SIZE : 1 );
   if ( NULL == fc->zone_buf[zz] ) {
    fprintf( stderr, "ERROR: out of memory for zone %d\n", zz );
    return 2;
   }
  }
  fprintf( stderr, "Zones %d..%d (%.0f MB)\n", z, z1, pass_bytes / 1048576.0 );
  if ( 0 != for_each_record( parts, n_parts, fill_fn, fc ) )
   return 2;
  for ( zz= z; zz <= z1; zz++ ) {
   if ( fc->filled[zz] != cc->counts[zz] ) {
    fprintf( stderr, "ERROR: zone %d: expected %llu records, read %llu\n", zz, (unsigned long long)cc->counts[zz], (unsigned long long)fc->filled[zz] );
    return 2;
   }
   if ( 0 != write_zone( output_dir, zz, fc->zone_buf[zz], cc->counts[zz] ) )
    return 2;
   free( fc->zone_buf[zz] );
  }
  free( fc );
  z= z1 + 1;
 }

 now= time( NULL );
 snprintf( info, sizeof( info ),
           "format=%s\ncatalog=%s\ndescription=%s\nrecords=%llu\nzones=%d\nzone_height_deg=%.1f\nra_index_bins=%d\nrecord_size=%d\nbuilt_unixtime=%ld\n",
           CATALOG_FORMAT, catalog_name, description, (unsigned long long)total, ZONE_COUNT, ZONE_HEIGHT_DEG, RA_BINS, REC_SIZE, (long)now );
 if ( 0 != write_file_atomically( output_dir, "catalog_info.txt", (const unsigned char *)info, strlen( info ) ) )
  return 2;
 for ( i= 0; i < n_parts; i++ )
  free( parts[i] );
 free( parts );
 free( cc );
 fprintf( stderr, "Wrote %llu %s records to %s\n", (unsigned long long)total, catalog_name, output_dir );
 return 0;
}

// -------------------------------------------------------------------------
// search

static int match_list_add( match_list *ml, const match_t *m ) {
 size_t nc;
 match_t *nm;
 if ( ml->n == ml->cap ) {
  nc= ml->cap ? ml->cap * 2 : 64;
  nm= realloc( ml->m, nc * sizeof( match_t ) );
  if ( NULL == nm )
   return -1;
  ml->m= nm;
  ml->cap= nc;
 }
 ml->m[ml->n++]= *m;
 return 0;
}

// sexagesimal "hh:mm:ss.s" (or "hh mm ss.s") / decimal degrees
static int parse_angle( const char *s, int is_ra, double *out ) {
 double a= 0.0, b= 0.0, c= 0.0;
 int sign= 1, n;
 const char *p= s;
 char *end;
 double v;
 while ( isspace( (unsigned char)*p ) )
  p++;
 if ( *p == '-' ) {
  sign= -1;
  p++;
 } else if ( *p == '+' ) {
  p++;
 }
 if ( NULL == strchr( p, ':' ) ) {
  v= strtod( p, &end );
  if ( end == p )
   return -1;
  *out= sign * v;
  return 0;
 }
 n= sscanf( p, "%lf:%lf:%lf", &a, &b, &c );
 if ( n < 2 )
  return -1;
 *out= sign * ( a + b / 60.0 + c / 3600.0 ) * ( is_ra ? 15.0 : 1.0 );
 return 0;
}

static int parse_coordinates( const char *s, double *ra, double *dec ) {
 char ra_s[64], dec_s[64];
 if ( 2 != sscanf( s, "%63s %63s", ra_s, dec_s ) )
  return -1;
 if ( 0 != parse_angle( ra_s, 1, ra ) || 0 != parse_angle( dec_s, 0, dec ) )
  return -1;
 if ( *ra < 0.0 || *ra >= 360.0 || *dec < -90.0 || *dec > 90.0 )
  return -1;
 return 0;
}

typedef struct {
 double ra, dec, radius_arcsec;
 int band_rp; // 0: G, 1: RP
 int have_mag_range;
 double mag_bright, mag_faint;
} query_t;

// RA intervals (degrees, [lo,hi)) to scan for a query in a given zone
static int ra_intervals( const query_t *q, double zone_dec_lo, double zone_dec_hi, double lo[2], double hi[2] ) {
 double r_deg= q->radius_arcsec / 3600.0;
 double dmax= fmax( fabs( zone_dec_lo ), fabs( zone_dec_hi ) );
 double half_width;
 dmax= fmin( dmax, fmax( fabs( q->dec - r_deg ), fabs( q->dec + r_deg ) ) );
 if ( dmax >= 89.9 || fabs( q->dec ) + r_deg >= 89.9 ) {
  lo[0]= 0.0;
  hi[0]= 360.0;
  return 1;
 }
 half_width= r_deg / cos( dmax * M_PI / 180.0 ) + 1.0e-6;
 if ( half_width >= 180.0 ) {
  lo[0]= 0.0;
  hi[0]= 360.0;
  return 1;
 }
 if ( q->ra - half_width < 0.0 ) {
  lo[0]= 0.0;
  hi[0]= q->ra + half_width;
  lo[1]= q->ra - half_width + 360.0;
  hi[1]= 360.0;
  return 2;
 }
 if ( q->ra + half_width >= 360.0 ) {
  lo[0]= q->ra - half_width;
  hi[0]= 360.0;
  lo[1]= 0.0;
  hi[1]= q->ra + half_width - 360.0;
  return 2;
 }
 lo[0]= q->ra - half_width;
 hi[0]= q->ra + half_width;
 return 1;
}

// The catalog magnitudes are stored rounded to 0.001 mag (MAG_ROUNDING_TOLERANCE is half
// of that). A star whose rounded magnitude lies within the tolerance of a range limit
// may be on either side of it in the full-precision catalog, so it is treated as outside
// the range. The known-star check then never drops a candidate because of the rounding:
// Gaia DR3 lists WZ Aur at G = 12.8304, the local copy stores 12.830, and a check with the
// faint limit 12.83 must not take the star as brighter than the limit.
static int mag_passes( const query_t *q, double mag ) {
 if ( !isfinite( mag ) || mag >= 99.0 )
  return !q->have_mag_range;
 if ( !q->have_mag_range )
  return 1;
 return mag >= q->mag_bright + MAG_ROUNDING_TOLERANCE && mag <= q->mag_faint - MAG_ROUNDING_TOLERANCE;
}

static int read_text_file( const char *path, char *buf, size_t size ) {
 FILE *f= fopen( path, "r" );
 size_t n;
 if ( NULL == f )
  return -1;
 n= fread( buf, 1, size - 1, f );
 buf[n]= '\0';
 fclose( f );
 return 0;
}

static int info_value( const char *info, const char *key, char *out, size_t out_size ) {
 const char *p= info;
 size_t kl= strlen( key );
 size_t k;
 while ( p && *p ) {
  if ( 0 == strncmp( p, key, kl ) && p[kl] == '=' ) {
   k= 0;
   p+= kl + 1;
   while ( *p && *p != '\n' && k + 1 < out_size )
    out[k++]= *p++;
   out[k]= '\0';
   return 0;
  }
  p= strchr( p, '\n' );
  if ( p )
   p++;
 }
 return -1;
}

// search a zone catalog (gaia_dr2 or tycho2)
static int search_zone_catalog( const char *dir, int catalog_index, const query_t *q, match_list *ml ) {
 char info[4096], value[256], path[4096];
 int is_gaia, z, z_lo, z_hi;
 double r_deg= q->radius_arcsec / 3600.0;
 unsigned char idx[( RA_BINS + 1 ) * 4];
 FILE *fi, *fz;
 double lo[2], hi[2];
 int n_int, k, b0, b1;
 double zone_dec_lo;
 uint32_t first, last, i;
 unsigned char rec[REC_SIZE];
 star_rec r;
 match_t m;
 double ra, dec, dist;
 snprintf( path, sizeof( path ), "%s/catalog_info.txt", dir );
 if ( 0 != read_text_file( path, info, sizeof( info ) ) ) {
  fprintf( stderr, "ERROR: %s is not a complete local catalog (no catalog_info.txt)\n", dir );
  return 2;
 }
 if ( 0 != info_value( info, "format", value, sizeof( value ) ) || 0 != strcmp( value, CATALOG_FORMAT ) ) {
  fprintf( stderr, "ERROR: %s has an unknown catalog format\n", dir );
  return 2;
 }
 if ( 0 != info_value( info, "catalog", value, sizeof( value ) ) ) {
  fprintf( stderr, "ERROR: %s/catalog_info.txt names no catalog\n", dir );
  return 2;
 }
 is_gaia= ( 0 == strncmp( value, "gaia", 4 ) );
 z_lo= zone_of_dec( fmax( -90.0, q->dec - r_deg - 1.0e-4 ) );
 z_hi= zone_of_dec( fmin( 90.0, q->dec + r_deg + 1.0e-4 ) );
 for ( z= z_lo; z <= z_hi; z++ ) {
  zone_dec_lo= -90.0 + ( z - 1 ) * ZONE_HEIGHT_DEG;
  snprintf( path, sizeof( path ), "%s/z%03d.idx", dir, z );
  fi= fopen( path, "rb" );
  if ( NULL == fi || 1 != fread( idx, sizeof( idx ), 1, fi ) ) {
   fprintf( stderr, "ERROR: cannot read %s\n", path );
   if ( fi )
    fclose( fi );
   return 2;
  }
  fclose( fi );
  snprintf( path, sizeof( path ), "%s/z%03d", dir, z );
  fz= fopen( path, "rb" );
  if ( NULL == fz ) {
   fprintf( stderr, "ERROR: cannot read %s\n", path );
   return 2;
  }
  n_int= ra_intervals( q, zone_dec_lo, zone_dec_lo + ZONE_HEIGHT_DEG, lo, hi );
  for ( k= 0; k < n_int; k++ ) {
   b0= (int)floor( lo[k] / 0.1 );
   b1= (int)floor( hi[k] / 0.1 ) + 1;
   if ( b0 < 0 )
    b0= 0;
   if ( b1 > RA_BINS )
    b1= RA_BINS;
   first= get_u32( idx + 4 * b0 );
   last= get_u32( idx + 4 * b1 );
   if ( last <= first )
    continue;
   if ( 0 != fseeko( fz, (off_t)first * REC_SIZE, SEEK_SET ) ) {
    fclose( fz );
    return 2;
   }
   for ( i= first; i < last; i++ ) {
    if ( 1 != fread( rec, REC_SIZE, 1, fz ) ) {
     fprintf( stderr, "ERROR: short read in %s\n", path );
     fclose( fz );
     return 2;
    }
    unpack_rec( rec, &r );
    ra= (double)r.ra_e7 / 1.0e7;
    dec= (double)r.dec_e7 / 1.0e7;
    if ( fabs( dec - q->dec ) > r_deg + 1.0e-6 )
     continue;
    dist= angular_distance_arcsec( q->ra, q->dec, ra, dec );
    if ( dist > q->radius_arcsec )
     continue;
    memset( &m, 0, sizeof( m ) );
    m.dist_arcsec= dist;
    m.id= r.id;
    m.ra= ra;
    m.dec= dec;
    m.gmag= ( r.m1 == MAG_NULL ) ? 99.9999 : millimag_to_mag( r.m1 );
    if ( is_gaia )
     m.rpmag= ( r.m3 == MAG_NULL ) ? 99.9999 : millimag_to_mag( r.m3 );
    else
     m.rpmag= m.gmag; // Tycho-2: V stands in for both bands
    m.mag_sort= q->band_rp ? m.rpmag : m.gmag;
    m.variable= ( is_gaia && ( r.flags & 1 ) ) ? 1 : 0;
    m.catalog_index= catalog_index;
    if ( !mag_passes( q, m.mag_sort ) )
     continue;
    if ( 0 != match_list_add( ml, &m ) ) {
     fclose( fz );
     return 2;
    }
   }
  }
  fclose( fz );
 }
 return 0;
}

// search VaST's native UCAC5 zone files (52-byte records sorted by Gaia DR1 RA in mas)
static int ucac5_read_ra_mas( FILE *f, uint64_t i, int32_t *ra_mas ) {
 unsigned char b[4];
 if ( 0 != fseeko( f, (off_t)( i * UCAC5_REC_SIZE + 8 ), SEEK_SET ) || 1 != fread( b, 4, 1, f ) )
  return -1;
 *ra_mas= (int32_t)get_u32( b );
 return 0;
}

static int search_ucac5( const char *dir, int catalog_index, const query_t *q, match_list *ml ) {
 char path[4096];
 int z, z_lo, z_hi;
 double r_deg= q->radius_arcsec / 3600.0;
 FILE *f;
 struct stat st;
 uint64_t n, a, b, i, mid;
 double lo[2], hi[2];
 int n_int, k;
 double zone_dec_lo;
 int32_t lo_mas, hi_mas, ra_mas, dec_mas;
 unsigned char rec[UCAC5_REC_SIZE];
 int16_t phgm, im1;
 double ra, dec, dist, mag;
 match_t m;
 snprintf( path, sizeof( path ), "%s/z001", dir );
 if ( 0 != access( path, R_OK ) ) {
  fprintf( stderr, "ERROR: no local copy of UCAC5 in %s\n", dir );
  return 2;
 }
 z_lo= zone_of_dec( fmax( -90.0, q->dec - r_deg - 1.0e-4 ) );
 z_hi= zone_of_dec( fmin( 90.0, q->dec + r_deg + 1.0e-4 ) );
 for ( z= z_lo; z <= z_hi; z++ ) {
  zone_dec_lo= -90.0 + ( z - 1 ) * ZONE_HEIGHT_DEG;
  snprintf( path, sizeof( path ), "%s/z%03d", dir, z );
  f= fopen( path, "rb" );
  if ( NULL == f || 0 != fstat( fileno( f ), &st ) ) {
   fprintf( stderr, "ERROR: cannot read %s\n", path );
   if ( f )
    fclose( f );
   return 2;
  }
  n= (uint64_t)st.st_size / UCAC5_REC_SIZE;
  n_int= ra_intervals( q, zone_dec_lo, zone_dec_lo + ZONE_HEIGHT_DEG, lo, hi );
  for ( k= 0; k < n_int; k++ ) {
   lo_mas= (int32_t)floor( lo[k] * 3.6e6 );
   hi_mas= (int32_t)ceil( hi[k] * 3.6e6 );
   a= 0;
   b= n;
   // first record with RA >= lo
   while ( a < b ) {
    mid= a + ( b - a ) / 2;
    if ( 0 != ucac5_read_ra_mas( f, mid, &ra_mas ) ) {
     fclose( f );
     return 2;
    }
    if ( ra_mas < lo_mas )
     a= mid + 1;
    else
     b= mid;
   }
   if ( a >= n )
    continue;
   if ( 0 != fseeko( f, (off_t)( a * UCAC5_REC_SIZE ), SEEK_SET ) ) {
    fclose( f );
    return 2;
   }
   for ( i= a; i < n; i++ ) {
    if ( 1 != fread( rec, UCAC5_REC_SIZE, 1, f ) )
     break;
    ra_mas= (int32_t)get_u32( rec + 8 );
    if ( ra_mas > hi_mas )
     break;
    dec_mas= (int32_t)get_u32( rec + 12 );
    phgm= (int16_t)get_u16( rec + 40 );
    im1= (int16_t)get_u16( rec + 42 );
    ra= (double)ra_mas / 3.6e6;
    dec= (double)dec_mas / 3.6e6;
    if ( fabs( dec - q->dec ) > r_deg + 1.0e-6 )
     continue;
    dist= angular_distance_arcsec( q->ra, q->dec, ra, dec );
    if ( dist > q->radius_arcsec )
     continue;
    if ( phgm > 0 )
     mag= phgm / 1000.0;
    else if ( im1 > 0 )
     mag= im1 / 1000.0;
    else
     mag= 99.9999;
    memset( &m, 0, sizeof( m ) );
    m.dist_arcsec= dist;
    m.id= (int64_t)get_u64( rec );
    m.ra= ra;
    m.dec= dec;
    m.gmag= mag;
    m.rpmag= mag;
    m.mag_sort= mag;
    m.variable= 0;
    m.catalog_index= catalog_index;
    if ( !mag_passes( q, m.mag_sort ) )
     continue;
    if ( 0 != match_list_add( ml, &m ) ) {
     fclose( f );
     return 2;
    }
   }
  }
  fclose( f );
 }
 return 0;
}

static int compare_matches( const void *a, const void *b ) {
 const match_t *x= (const match_t *)a, *y= (const match_t *)b;
 if ( x->mag_sort < y->mag_sort )
  return -1;
 if ( x->mag_sort > y->mag_sort )
  return 1;
 if ( x->dist_arcsec < y->dist_arcsec )
  return -1;
 if ( x->dist_arcsec > y->dist_arcsec )
  return 1;
 return 0;
}

static int cmd_search( int argc, char **argv ) {
 const char *cat_type[MAX_CATALOGS], *cat_dir[MAX_CATALOGS];
 int n_cat= 0, i, have_coords= 0, have_radius= 0, out_max= 50, status;
 size_t k, n_out= 0;
 query_t q;
 match_list ml= { NULL, 0, 0 };
 char *keep;
 const char *a, *colon, *v, *dots;
 static char types[MAX_CATALOGS][32];
 size_t tl, j;

 memset( &q, 0, sizeof( q ) );
 for ( i= 2; i < argc; i++ ) {
  a= argv[i];
  if ( 0 == strncmp( a, "-cat=", 5 ) ) {
   colon= strchr( a + 5, ':' );
   if ( NULL == colon || n_cat >= MAX_CATALOGS ) {
    fprintf( stderr, "ERROR: bad catalog argument %s\n", a );
    return 1;
   }
   tl= (size_t)( colon - ( a + 5 ) );
   if ( tl == 0 || tl >= sizeof( types[0] ) ) {
    fprintf( stderr, "ERROR: bad catalog argument %s\n", a );
    return 1;
   }
   memcpy( types[n_cat], a + 5, tl );
   types[n_cat][tl]= '\0';
   cat_type[n_cat]= types[n_cat];
   cat_dir[n_cat]= colon + 1;
   n_cat++;
  } else if ( 0 == strncmp( a, "-c=", 3 ) ) {
   if ( 0 != parse_coordinates( a + 3, &q.ra, &q.dec ) ) {
    fprintf( stderr, "ERROR: cannot parse coordinates %s\n", a + 3 );
    return 1;
   }
   have_coords= 1;
  } else if ( 0 == strncmp( a, "-c.rs=", 6 ) ) {
   q.radius_arcsec= atof( a + 6 );
   have_radius= q.radius_arcsec > 0.0;
  } else if ( 0 == strncmp( a, "-out.max=", 9 ) ) {
   out_max= atoi( a + 9 );
  } else if ( 0 == strncmp( a, "-sort=", 6 ) ) {
   if ( 0 == strcmp( a + 6, "RPmag" ) )
    q.band_rp= 1;
   else if ( 0 == strcmp( a + 6, "Gmag" ) )
    q.band_rp= 0;
   else {
    fprintf( stderr, "ERROR: unsupported sort field %s (Gmag or RPmag)\n", a + 6 );
    return 1;
   }
  } else if ( 0 == strncmp( a, "Gmag=", 5 ) || 0 == strncmp( a, "RPmag=", 6 ) ) {
   v= strchr( a, '=' ) + 1;
   dots= strstr( v, ".." );
   if ( NULL == dots ) {
    fprintf( stderr, "ERROR: bad magnitude range %s\n", a );
    return 1;
   }
   q.mag_bright= atof( v );
   q.mag_faint= atof( dots + 2 );
   q.have_mag_range= 1;
   q.band_rp= ( a[0] == 'R' );
  } else if ( 0 == strncmp( a, "-timeout=", 9 ) || 0 == strncmp( a, "-mime=", 6 ) || 0 == strncmp( a, "-out.form=", 10 ) || 0 == strncmp( a, "-out.add=", 9 ) || 0 == strncmp( a, "-out=", 5 ) ) {
   // accepted for compatibility with the vizquery command line
  } else if ( a[0] != '-' && n_cat < MAX_CATALOGS ) {
   cat_type[n_cat]= "zone";
   cat_dir[n_cat]= a;
   n_cat++;
  } else {
   fprintf( stderr, "ERROR: unknown argument %s\n", a );
   return 1;
  }
 }
 if ( n_cat == 0 || !have_coords || !have_radius ) {
  fprintf( stderr, "Usage: %s search [-cat=gaia_dr2|tycho2|ucac5:DIR ...] [DIR] -c=\"RA DEC\" -c.rs=ARCSEC [-out.max=N] [-sort=Gmag|RPmag] [Gmag=A..B]\n", argv[0] );
  return 1;
 }
 if ( out_max < 1 )
  out_max= 1;

 for ( i= 0; i < n_cat; i++ ) {
  if ( 0 == strcmp( cat_type[i], "ucac5" ) )
   status= search_ucac5( cat_dir[i], i, &q, &ml );
  else
   status= search_zone_catalog( cat_dir[i], i, &q, &ml );
  if ( 0 != status ) {
   free( ml.m );
   return status;
  }
 }
 if ( ml.n > 1 )
  qsort( ml.m, ml.n, sizeof( match_t ), compare_matches );
 // a star listed by several catalogs is reported once: drop an entry within
 // DEDUP_RADIUS_ARCSEC of an entry from another catalog listed earlier in the output
 keep= calloc( ml.n ? ml.n : 1, 1 );
 if ( NULL == keep ) {
  free( ml.m );
  return 2;
 }
 for ( k= 0; k < ml.n; k++ ) {
  keep[k]= 1;
  if ( n_cat < 2 )
   continue;
  for ( j= 0; j < k; j++ ) {
   if ( !keep[j] || ml.m[j].catalog_index == ml.m[k].catalog_index )
    continue;
   if ( angular_distance_arcsec( ml.m[j].ra, ml.m[j].dec, ml.m[k].ra, ml.m[k].dec ) < DEDUP_RADIUS_ARCSEC ) {
    keep[k]= 0;
    break;
   }
  }
 }

 printf( "#\n#   Local star catalog search (lib/catalogs/local_star_catalog), vizquery-like output\n" );
 for ( i= 0; i < n_cat; i++ )
  printf( "#   catalog %d: %s %s\n", i + 1, cat_type[i], cat_dir[i] );
 printf( "#   center %.7f %+.7f radius %.2f arcsec\n#\n", q.ra, q.dec, q.radius_arcsec );
 printf( "    _r              Source         RA_ICRS         DE_ICRS    Gmag   RPmag Var\n" );
 for ( k= 0; k < ml.n && (int)n_out < out_max; k++ ) {
  if ( !keep[k] )
   continue;
  printf( " %.3f %lld %015.11f %+.11f %.4f %.4f %s\n", ml.m[k].dist_arcsec, (long long)ml.m[k].id, ml.m[k].ra, ml.m[k].dec, ml.m[k].gmag, ml.m[k].rpmag, ml.m[k].variable ? "VARIABLE" : "NOT_AVAILABLE" );
  n_out++;
 }
 printf( "#END#\n" );
 free( keep );
 free( ml.m );
 return 0;
}

int main( int argc, char **argv ) {
 if ( argc < 2 ) {
  fprintf( stderr, "Usage: %s gaia-extract|tycho2-extract|finalize|search ...\n", argv[0] );
  return 1;
 }
 if ( 0 == strcmp( argv[1], "gaia-extract" ) )
  return cmd_gaia_extract( argc, argv );
 if ( 0 == strcmp( argv[1], "tycho2-extract" ) )
  return cmd_tycho2_extract( argc, argv );
 if ( 0 == strcmp( argv[1], "finalize" ) )
  return cmd_finalize( argc, argv );
 if ( 0 == strcmp( argv[1], "search" ) )
  return cmd_search( argc, argv );
 fprintf( stderr, "ERROR: unknown subcommand %s\n", argv[1] );
 return 1;
}
