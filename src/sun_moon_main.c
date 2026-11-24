// util/sun_moon - the altitude of the Sun, the position and phase of the Moon and the
// moonlight at a target, for a time and an observing site (see src/sun_moon.c)

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sun_moon.h"

static void print_usage( char *progname ) {
 fprintf( stderr, "Usage: %s JD_UTC LATITUDE_DEG LONGITUDE_EAST_DEG HEIGHT_M [RA_J2000_DEG DEC_J2000_DEG [EXTINCTION_MAG DARK_SKY_V_MAG_ARCSEC2]]\n", progname );
 fprintf( stderr, "\nPrints key=value lines: the geometric (unrefracted) altitudes and the azimuths (from North\n" );
 fprintf( stderr, "through East) of the Sun and the Moon, the phase angle and the illuminated fraction of the\n" );
 fprintf( stderr, "Moon and, for a target position, its altitude and airmass, the distance from the Moon and the\n" );
 fprintf( stderr, "brightening of the dark sky by moonlight (Krisciunas & Schaefer 1991, PASP 103, 1033) for the\n" );
 fprintf( stderr, "V-band extinction coefficient and the dark zenith sky brightness given (default %.2f mag per\n", SUN_MOON_DEFAULT_EXTINCTION_MAG );
 fprintf( stderr, "airmass and %.1f mag/arcsec^2).\n", SUN_MOON_DEFAULT_DARK_SKY_V_MAG_ARCSEC2 );
 fprintf( stderr, "\nExample: %s 2461000.5 33.7480556 -101.9583333 1015 280.0 -20.0\n", progname );
 return;
}

// Read a number; 0 on success
static int read_number( const char *str, double *value ) {
 char *endptr;
 if ( str == NULL || strlen( str ) == 0 ) {
  return 1;
 }
 ( *value )= strtod( str, &endptr );
 if ( endptr == str || *endptr != '\0' ) {
  return 1;
 }
 return 0;
}

int main( int argc, char **argv ) {
 struct sun_moon_site site;
 struct sun_moon_geometry geometry;
 double jd_utc;
 double target_ra_deg;
 double target_dec_deg;
 double extinction_mag;
 double dark_sky_v;
 int have_target;

 if ( argc != 5 && argc != 7 && argc != 9 ) {
  print_usage( argv[0] );
  return 1;
 }
 if ( 0 != read_number( argv[1], &jd_utc ) || 0 != read_number( argv[2], &site.latitude_deg ) || 0 != read_number( argv[3], &site.longitude_deg ) || 0 != read_number( argv[4], &site.height_m ) ) {
  fprintf( stderr, "ERROR: cannot read the time and the site from the command line\n" );
  print_usage( argv[0] );
  return 1;
 }
 // JD 2378496.5 = 1800-01-01, JD 2524593.5 = 2200-01-01: beyond that the series are not meant to be used
 if ( jd_utc < 2378496.5 || jd_utc > 2524593.5 ) {
  fprintf( stderr, "ERROR: JD %.5f is outside the years 1800-2200\n", jd_utc );
  return 1;
 }
 if ( site.latitude_deg < -90.0 || site.latitude_deg > 90.0 || site.longitude_deg < -360.0 || site.longitude_deg > 360.0 || site.height_m < -500.0 || site.height_m > 10000.0 ) {
  fprintf( stderr, "ERROR: implausible site latitude %.6f, longitude %.6f or height %.1f m\n", site.latitude_deg, site.longitude_deg, site.height_m );
  return 1;
 }
 have_target= 0;
 target_ra_deg= 0.0;
 target_dec_deg= 0.0;
 extinction_mag= SUN_MOON_DEFAULT_EXTINCTION_MAG;
 dark_sky_v= SUN_MOON_DEFAULT_DARK_SKY_V_MAG_ARCSEC2;
 if ( argc >= 7 ) {
  if ( 0 != read_number( argv[5], &target_ra_deg ) || 0 != read_number( argv[6], &target_dec_deg ) || target_ra_deg < 0.0 || target_ra_deg > 360.0 || target_dec_deg < -90.0 || target_dec_deg > 90.0 ) {
   fprintf( stderr, "ERROR: cannot read the target position (RA 0..360, Dec -90..90 degrees)\n" );
   return 1;
  }
  have_target= 1;
 }
 if ( argc == 9 ) {
  if ( 0 != read_number( argv[7], &extinction_mag ) || 0 != read_number( argv[8], &dark_sky_v ) || extinction_mag < 0.0 || extinction_mag > 2.0 || dark_sky_v < 15.0 || dark_sky_v > 25.0 ) {
   fprintf( stderr, "ERROR: cannot read the extinction coefficient (0..2 mag) and the dark sky brightness (15..25 mag/arcsec^2)\n" );
   return 1;
  }
 }

 sun_moon_compute( jd_utc, &site, have_target, target_ra_deg, target_dec_deg, extinction_mag, dark_sky_v, &geometry );

 fprintf( stdout, "sun_alt_deg=%.4f\n", geometry.sun_alt_deg );
 fprintf( stdout, "sun_az_deg=%.4f\n", geometry.sun_az_deg );
 fprintf( stdout, "moon_alt_deg=%.4f\n", geometry.moon_alt_deg );
 fprintf( stdout, "moon_az_deg=%.4f\n", geometry.moon_az_deg );
 fprintf( stdout, "moon_ra_deg=%.5f\n", geometry.moon_ra_deg );
 fprintf( stdout, "moon_dec_deg=%.5f\n", geometry.moon_dec_deg );
 fprintf( stdout, "moon_distance_km=%.1f\n", geometry.moon_distance_km );
 fprintf( stdout, "moon_phase_angle_deg=%.4f\n", geometry.moon_phase_angle_deg );
 fprintf( stdout, "moon_illuminated_fraction=%.5f\n", geometry.moon_illuminated_fraction );
 if ( have_target != 0 ) {
  fprintf( stdout, "target_alt_deg=%.4f\n", geometry.target_alt_deg );
  fprintf( stdout, "target_az_deg=%.4f\n", geometry.target_az_deg );
  fprintf( stdout, "target_airmass=%.4f\n", geometry.target_airmass );
  fprintf( stdout, "moon_target_separation_deg=%.4f\n", geometry.moon_target_separation_deg );
  fprintf( stdout, "moon_sky_brightening_mag=%.4f\n", geometry.moon_sky_brightening_mag );
 }
 return 0;
}
