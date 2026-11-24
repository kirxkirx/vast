// Positions of the Sun and the Moon as seen from an observing site, for judging the observing
// conditions of an image: twilight (the altitude of the Sun) and moonlight (the altitude and
// phase of the Moon, its distance from the target and the brightening of the sky it causes).
//
// References:
//  Meeus J., 1998, Astronomical Algorithms, 2nd ed., Willmann-Bell (chapter numbers below)
//  Krisciunas K., Schaefer B. E., 1991, PASP 103, 1033, "A model of the brightness of moonlight"
//  Young A. T., 1994, Applied Optics 33, 1108 (airmass)
//
// Accuracy: the Sun (Meeus ch. 25, the low-accuracy method) to about 0.01 deg; the Moon (Meeus
// ch. 47 with the full tables 47.A and 47.B) to about 10 arcsec in longitude and 4 arcsec in
// latitude. Nutation and aberration are left out (both below 0.01 deg): the positions refer to
// the mean equinox of date, the target position is precessed from J2000 to the date (Meeus
// ch. 21) and the mean sidereal time is used (Meeus ch. 12). The parallax of the Moon (up to
// 1 deg) is taken into account with the topocentric correction of Meeus ch. 40.
// util/examples/test_sun_moon_ephemeris.sh compares the results with astropy.

#include <math.h>

#include "sun_moon.h"

#define SM_PI 3.14159265358979323846
#define SM_DEG2RAD ( SM_PI / 180.0 )
#define SM_RAD2DEG ( 180.0 / SM_PI )
#define SM_AU_KM 149597870.7
#define SM_EARTH_EQUATORIAL_RADIUS_KM 6378.14

// Meeus (1998) Table 47.A: the multiples of D, M, M', F; the coefficient of the sine term in
// the longitude (1e-6 deg) and of the cosine term in the distance (1e-3 km)
static const int moon_lr_terms[60][6]= {
 { 0, 0, 1, 0, 6288774, -20905355 },
 { 2, 0, -1, 0, 1274027, -3699111 },
 { 2, 0, 0, 0, 658314, -2955968 },
 { 0, 0, 2, 0, 213618, -569925 },
 { 0, 1, 0, 0, -185116, 48888 },
 { 0, 0, 0, 2, -114332, -3149 },
 { 2, 0, -2, 0, 58793, 246158 },
 { 2, -1, -1, 0, 57066, -152138 },
 { 2, 0, 1, 0, 53322, -170733 },
 { 2, -1, 0, 0, 45758, -204586 },
 { 0, 1, -1, 0, -40923, -129620 },
 { 1, 0, 0, 0, -34720, 108743 },
 { 0, 1, 1, 0, -30383, 104755 },
 { 2, 0, 0, -2, 15327, 10321 },
 { 0, 0, 1, 2, -12528, 0 },
 { 0, 0, 1, -2, 10980, 79661 },
 { 4, 0, -1, 0, 10675, -34782 },
 { 0, 0, 3, 0, 10034, -23210 },
 { 4, 0, -2, 0, 8548, -21636 },
 { 2, 1, -1, 0, -7888, 24208 },
 { 2, 1, 0, 0, -6766, 30824 },
 { 1, 0, -1, 0, -5163, -8379 },
 { 1, 1, 0, 0, 4987, -16675 },
 { 2, -1, 1, 0, 4036, -12831 },
 { 2, 0, 2, 0, 3994, -10445 },
 { 4, 0, 0, 0, 3861, -11650 },
 { 2, 0, -3, 0, 3665, 14403 },
 { 0, 1, -2, 0, -2689, -7003 },
 { 2, 0, -1, 2, -2602, 0 },
 { 2, -1, -2, 0, 2390, 10056 },
 { 1, 0, 1, 0, -2348, 6322 },
 { 2, -2, 0, 0, 2236, -9884 },
 { 0, 1, 2, 0, -2120, 5751 },
 { 0, 2, 0, 0, -2069, 0 },
 { 2, -2, -1, 0, 2048, -4950 },
 { 2, 0, 1, -2, -1773, 4130 },
 { 2, 0, 0, 2, -1595, 0 },
 { 4, -1, -1, 0, 1215, -3958 },
 { 0, 0, 2, 2, -1110, 0 },
 { 3, 0, -1, 0, -892, 3258 },
 { 2, 1, 1, 0, -810, 2616 },
 { 4, -1, -2, 0, 759, -1897 },
 { 0, 2, -1, 0, -713, -2117 },
 { 2, 2, -1, 0, -700, 2354 },
 { 2, 1, -2, 0, 691, 0 },
 { 2, -1, 0, -2, 596, 0 },
 { 4, 0, 1, 0, 549, -1423 },
 { 0, 0, 4, 0, 537, -1117 },
 { 4, -1, 0, 0, 520, -1571 },
 { 1, 0, -2, 0, -487, -1739 },
 { 2, 1, 0, -2, -399, 0 },
 { 0, 0, 2, -2, -381, -4421 },
 { 1, 1, 1, 0, 351, 0 },
 { 3, 0, -2, 0, -340, 0 },
 { 4, 0, -3, 0, 330, 0 },
 { 2, -1, 2, 0, 327, 0 },
 { 0, 2, 1, 0, -323, 1165 },
 { 1, 1, -1, 0, 299, 0 },
 { 2, 0, 3, 0, 294, 0 },
 { 2, 0, -1, -2, 0, 8752 } };

// Meeus (1998) Table 47.B: the multiples of D, M, M', F and the coefficient of the sine term
// in the latitude (1e-6 deg)
static const int moon_b_terms[60][5]= {
 { 0, 0, 0, 1, 5128122 },
 { 0, 0, 1, 1, 280602 },
 { 0, 0, 1, -1, 277693 },
 { 2, 0, 0, -1, 173237 },
 { 2, 0, -1, 1, 55413 },
 { 2, 0, -1, -1, 46271 },
 { 2, 0, 0, 1, 32573 },
 { 0, 0, 2, 1, 17198 },
 { 2, 0, 1, -1, 9266 },
 { 0, 0, 2, -1, 8822 },
 { 2, -1, 0, -1, 8216 },
 { 2, 0, -2, -1, 4324 },
 { 2, 0, 1, 1, 4200 },
 { 2, 1, 0, -1, -3359 },
 { 2, -1, -1, 1, 2463 },
 { 2, -1, 0, 1, 2211 },
 { 2, -1, -1, -1, 2065 },
 { 0, 1, -1, -1, -1870 },
 { 4, 0, -1, -1, 1828 },
 { 0, 1, 0, 1, -1794 },
 { 0, 0, 0, 3, -1749 },
 { 0, 1, -1, 1, -1565 },
 { 1, 0, 0, 1, -1491 },
 { 0, 1, 1, 1, -1475 },
 { 0, 1, 1, -1, -1410 },
 { 0, 1, 0, -1, -1344 },
 { 1, 0, 0, -1, -1335 },
 { 0, 0, 3, 1, 1107 },
 { 4, 0, 0, -1, 1021 },
 { 4, 0, -1, 1, 833 },
 { 0, 0, 1, -3, 777 },
 { 4, 0, -2, 1, 671 },
 { 2, 0, 0, -3, 607 },
 { 2, 0, 2, -1, 596 },
 { 2, -1, 1, -1, 491 },
 { 2, 0, -2, 1, -451 },
 { 0, 0, 3, -1, 439 },
 { 2, 0, 2, 1, 422 },
 { 2, 0, -3, -1, 421 },
 { 2, 1, -1, 1, -366 },
 { 2, 1, 0, 1, -351 },
 { 4, 0, 0, 1, 331 },
 { 2, -1, 1, 1, 315 },
 { 2, -2, 0, -1, 302 },
 { 0, 0, 1, 3, -283 },
 { 2, 1, 1, -1, -229 },
 { 1, 1, 0, -1, 223 },
 { 1, 1, 0, 1, 223 },
 { 0, 1, -2, -1, -220 },
 { 2, 1, -1, -1, -220 },
 { 1, 0, 1, 1, -185 },
 { 2, -1, -2, -1, 181 },
 { 0, 1, 2, 1, -177 },
 { 4, 0, -2, -1, 176 },
 { 4, -1, -1, -1, 166 },
 { 1, 0, 1, -1, -164 },
 { 4, 0, 1, -1, 132 },
 { 1, 0, -1, -1, -119 },
 { 4, -1, 0, -1, 115 },
 { 2, -2, 0, 1, 107 } };

static double sm_normalize_deg( double x ) {
 double y;
 y= fmod( x, 360.0 );
 if ( y < 0.0 ) {
  y+= 360.0;
 }
 return y;
}

// Julian centuries of TT from J2000.0
static double sm_centuries_tt( double jd_tt ) {
 return ( jd_tt - 2451545.0 ) / 36525.0;
}

// Mean obliquity of the ecliptic in degrees, Meeus (22.2)
static double sm_mean_obliquity_deg( double t ) {
 return 23.0 + 26.0 / 60.0 + ( 21.448 - 46.8150 * t - 0.00059 * t * t + 0.001813 * t * t * t ) / 3600.0;
}

// Ecliptic to equatorial coordinates, all in degrees, Meeus (13.3) and (13.4)
static void sm_ecliptic_to_equatorial( double lambda_deg, double beta_deg, double eps_deg, double *ra_deg, double *dec_deg ) {
 double l;
 double b;
 double e;
 l= lambda_deg * SM_DEG2RAD;
 b= beta_deg * SM_DEG2RAD;
 e= eps_deg * SM_DEG2RAD;
 ( *ra_deg )= sm_normalize_deg( atan2( sin( l ) * cos( e ) - tan( b ) * sin( e ), cos( l ) ) * SM_RAD2DEG );
 ( *dec_deg )= asin( sin( b ) * cos( e ) + cos( b ) * sin( e ) * sin( l ) ) * SM_RAD2DEG;
 return;
}

// Angular distance between two positions, degrees; the vector form is accurate at any separation
static double sm_separation_deg( double ra1_deg, double dec1_deg, double ra2_deg, double dec2_deg ) {
 double x1, y1, z1;
 double x2, y2, z2;
 double cx, cy, cz;
 double dot;
 x1= cos( dec1_deg * SM_DEG2RAD ) * cos( ra1_deg * SM_DEG2RAD );
 y1= cos( dec1_deg * SM_DEG2RAD ) * sin( ra1_deg * SM_DEG2RAD );
 z1= sin( dec1_deg * SM_DEG2RAD );
 x2= cos( dec2_deg * SM_DEG2RAD ) * cos( ra2_deg * SM_DEG2RAD );
 y2= cos( dec2_deg * SM_DEG2RAD ) * sin( ra2_deg * SM_DEG2RAD );
 z2= sin( dec2_deg * SM_DEG2RAD );
 cx= y1 * z2 - z1 * y2;
 cy= z1 * x2 - x1 * z2;
 cz= x1 * y2 - y1 * x2;
 dot= x1 * x2 + y1 * y2 + z1 * z2;
 return atan2( sqrt( cx * cx + cy * cy + cz * cz ), dot ) * SM_RAD2DEG;
}

// The Sun, Meeus ch. 25 (low accuracy): apparent right ascension and declination of date in
// degrees, distance in AU
static void sm_sun_position( double jd_tt, double *ra_deg, double *dec_deg, double *distance_au ) {
 double t;
 double l0;
 double m;
 double e;
 double c;
 double true_longitude;
 double true_anomaly;
 double omega;
 double lambda;
 double eps;
 t= sm_centuries_tt( jd_tt );
 l0= sm_normalize_deg( 280.46646 + 36000.76983 * t + 0.0003032 * t * t );
 m= sm_normalize_deg( 357.52911 + 35999.05029 * t - 0.0001537 * t * t );
 e= 0.016708634 - 0.000042037 * t - 0.0000001267 * t * t;
 c= ( 1.914602 - 0.004817 * t - 0.000014 * t * t ) * sin( m * SM_DEG2RAD ) + ( 0.019993 - 0.000101 * t ) * sin( 2.0 * m * SM_DEG2RAD ) + 0.000289 * sin( 3.0 * m * SM_DEG2RAD );
 true_longitude= l0 + c;
 true_anomaly= m + c;
 ( *distance_au )= 1.000001018 * ( 1.0 - e * e ) / ( 1.0 + e * cos( true_anomaly * SM_DEG2RAD ) );
 omega= 125.04 - 1934.136 * t;
 lambda= true_longitude - 0.00569 - 0.00478 * sin( omega * SM_DEG2RAD );
 eps= sm_mean_obliquity_deg( t ) + 0.00256 * cos( omega * SM_DEG2RAD );
 sm_ecliptic_to_equatorial( lambda, 0.0, eps, ra_deg, dec_deg );
 return;
}

// The Moon, Meeus ch. 47: geocentric right ascension and declination (degrees, mean equinox
// of date) and distance (km)
static void sm_moon_position( double jd_tt, double *ra_deg, double *dec_deg, double *distance_km ) {
 double t;
 double lp;
 double d;
 double m;
 double mp;
 double f;
 double a1;
 double a2;
 double a3;
 double e;
 double sum_l;
 double sum_r;
 double sum_b;
 double arg;
 double coeff;
 int i;
 t= sm_centuries_tt( jd_tt );
 // Mean longitude, mean elongation, mean anomalies of the Sun and the Moon and the argument
 // of latitude, Meeus (47.1) - (47.5)
 lp= sm_normalize_deg( 218.3164477 + 481267.88123421 * t - 0.0015786 * t * t + t * t * t / 538841.0 - t * t * t * t / 65194000.0 );
 d= sm_normalize_deg( 297.8501921 + 445267.1114034 * t - 0.0018819 * t * t + t * t * t / 545868.0 - t * t * t * t / 113065000.0 );
 m= sm_normalize_deg( 357.5291092 + 35999.0502909 * t - 0.0001536 * t * t + t * t * t / 24490000.0 );
 mp= sm_normalize_deg( 134.9633964 + 477198.8675055 * t + 0.0087414 * t * t + t * t * t / 69699.0 - t * t * t * t / 14712000.0 );
 f= sm_normalize_deg( 93.2720950 + 483202.0175233 * t - 0.0036539 * t * t - t * t * t / 3526000.0 + t * t * t * t / 863310000.0 );
 a1= sm_normalize_deg( 119.75 + 131.849 * t );
 a2= sm_normalize_deg( 53.09 + 479264.290 * t );
 a3= sm_normalize_deg( 313.45 + 481266.484 * t );
 // the decreasing eccentricity of the Earth's orbit, Meeus (47.6)
 e= 1.0 - 0.002516 * t - 0.0000074 * t * t;
 sum_l= 0.0;
 sum_r= 0.0;
 sum_b= 0.0;
 for ( i= 0; i < 60; i++ ) {
  arg= ( moon_lr_terms[i][0] * d + moon_lr_terms[i][1] * m + moon_lr_terms[i][2] * mp + moon_lr_terms[i][3] * f ) * SM_DEG2RAD;
  coeff= 1.0;
  if ( moon_lr_terms[i][1] == 1 || moon_lr_terms[i][1] == -1 ) {
   coeff= e;
  }
  if ( moon_lr_terms[i][1] == 2 || moon_lr_terms[i][1] == -2 ) {
   coeff= e * e;
  }
  sum_l+= coeff * moon_lr_terms[i][4] * sin( arg );
  sum_r+= coeff * moon_lr_terms[i][5] * cos( arg );
 }
 for ( i= 0; i < 60; i++ ) {
  arg= ( moon_b_terms[i][0] * d + moon_b_terms[i][1] * m + moon_b_terms[i][2] * mp + moon_b_terms[i][3] * f ) * SM_DEG2RAD;
  coeff= 1.0;
  if ( moon_b_terms[i][1] == 1 || moon_b_terms[i][1] == -1 ) {
   coeff= e;
  }
  if ( moon_b_terms[i][1] == 2 || moon_b_terms[i][1] == -2 ) {
   coeff= e * e;
  }
  sum_b+= coeff * moon_b_terms[i][4] * sin( arg );
 }
 // the actions of Venus (A1), Jupiter (A2) and the flattening of the Earth
 sum_l+= 3958.0 * sin( a1 * SM_DEG2RAD ) + 1962.0 * sin( ( lp - f ) * SM_DEG2RAD ) + 318.0 * sin( a2 * SM_DEG2RAD );
 sum_b+= -2235.0 * sin( lp * SM_DEG2RAD ) + 382.0 * sin( a3 * SM_DEG2RAD ) + 175.0 * sin( ( a1 - f ) * SM_DEG2RAD ) + 175.0 * sin( ( a1 + f ) * SM_DEG2RAD ) + 127.0 * sin( ( lp - mp ) * SM_DEG2RAD ) - 115.0 * sin( ( lp + mp ) * SM_DEG2RAD );
 ( *distance_km )= 385000.56 + sum_r / 1000.0;
 sm_ecliptic_to_equatorial( lp + sum_l / 1000000.0, sum_b / 1000000.0, sm_mean_obliquity_deg( t ), ra_deg, dec_deg );
 return;
}

// Mean sidereal time at Greenwich in degrees, Meeus (12.4)
static double sm_gmst_deg( double jd_ut ) {
 double t;
 t= ( jd_ut - 2451545.0 ) / 36525.0;
 return sm_normalize_deg( 280.46061837 + 360.98564736629 * ( jd_ut - 2451545.0 ) + 0.000387933 * t * t - t * t * t / 38710000.0 );
}

// Precession of a J2000 position to the mean equinox of the date, Meeus (21.2) - (21.4)
static void sm_precess_from_j2000( double ra0_deg, double dec0_deg, double jd_tt, double *ra_deg, double *dec_deg ) {
 double t;
 double zeta;
 double z;
 double theta;
 double ra0;
 double dec0;
 double a;
 double b;
 double c;
 t= sm_centuries_tt( jd_tt );
 zeta= ( 2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t ) / 3600.0 * SM_DEG2RAD;
 z= ( 2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t ) / 3600.0 * SM_DEG2RAD;
 theta= ( 2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t ) / 3600.0 * SM_DEG2RAD;
 ra0= ra0_deg * SM_DEG2RAD;
 dec0= dec0_deg * SM_DEG2RAD;
 a= cos( dec0 ) * sin( ra0 + zeta );
 b= cos( theta ) * cos( dec0 ) * cos( ra0 + zeta ) - sin( theta ) * sin( dec0 );
 c= sin( theta ) * cos( dec0 ) * cos( ra0 + zeta ) + cos( theta ) * sin( dec0 );
 ( *ra_deg )= sm_normalize_deg( ( atan2( a, b ) + z ) * SM_RAD2DEG );
 // atan2 instead of asin(c): exact also close to the poles
 ( *dec_deg )= atan2( c, sqrt( a * a + b * b ) ) * SM_RAD2DEG;
 return;
}

// Topocentric right ascension and declination of a body at distance_km, Meeus ch. 11 (the
// observer's geocentric position) and ch. 40 (40.2, 40.3)
static void sm_topocentric( double ra_deg, double dec_deg, double distance_km, double lst_deg, const struct sun_moon_site *site,
                            double *ra_topo_deg, double *dec_topo_deg ) {
 double phi;
 double u;
 double rho_sin_phi;
 double rho_cos_phi;
 double sin_parallax;
 double h;
 double dec;
 double denominator;
 double delta_alpha;
 phi= site->latitude_deg * SM_DEG2RAD;
 // 0.99664719 = b/a, the ratio of the polar and equatorial radii of the Earth
 u= atan( 0.99664719 * tan( phi ) );
 rho_sin_phi= 0.99664719 * sin( u ) + site->height_m / 6378140.0 * sin( phi );
 rho_cos_phi= cos( u ) + site->height_m / 6378140.0 * cos( phi );
 sin_parallax= SM_EARTH_EQUATORIAL_RADIUS_KM / distance_km;
 h= ( lst_deg - ra_deg ) * SM_DEG2RAD;
 dec= dec_deg * SM_DEG2RAD;
 denominator= cos( dec ) - rho_cos_phi * sin_parallax * cos( h );
 delta_alpha= atan2( -1.0 * rho_cos_phi * sin_parallax * sin( h ), denominator );
 ( *ra_topo_deg )= sm_normalize_deg( ra_deg + delta_alpha * SM_RAD2DEG );
 ( *dec_topo_deg )= atan2( ( sin( dec ) - rho_sin_phi * sin_parallax ) * cos( delta_alpha ), denominator ) * SM_RAD2DEG;
 return;
}

// Altitude and azimuth (from North through East), degrees, for the local sidereal time lst_deg
static void sm_horizontal( double ra_deg, double dec_deg, double lst_deg, double latitude_deg, double *alt_deg, double *az_deg ) {
 double h;
 double dec;
 double lat;
 double sin_alt;
 h= ( lst_deg - ra_deg ) * SM_DEG2RAD;
 dec= dec_deg * SM_DEG2RAD;
 lat= latitude_deg * SM_DEG2RAD;
 sin_alt= sin( lat ) * sin( dec ) + cos( lat ) * cos( dec ) * cos( h );
 if ( sin_alt > 1.0 ) {
  sin_alt= 1.0;
 }
 if ( sin_alt < -1.0 ) {
  sin_alt= -1.0;
 }
 ( *alt_deg )= asin( sin_alt ) * SM_RAD2DEG;
 ( *az_deg )= sm_normalize_deg( atan2( -1.0 * cos( dec ) * sin( h ), sin( dec ) * cos( lat ) - cos( dec ) * sin( lat ) * cos( h ) ) * SM_RAD2DEG );
 return;
}

double sun_moon_airmass_young1994( double alt_deg ) {
 double cz;
 double cz2;
 double cz3;
 if ( alt_deg <= 0.0 ) {
  // below the horizon; larger than the value of the formula at the horizon (about 32)
  return 40.0;
 }
 cz= cos( ( 90.0 - alt_deg ) * SM_DEG2RAD );
 cz2= cz * cz;
 cz3= cz2 * cz;
 return ( 1.002432 * cz2 + 0.148386 * cz + 0.0096467 ) / ( cz3 + 0.149864 * cz2 + 0.0102963 * cz + 0.000303978 );
}

// Krisciunas K., Schaefer B. E., 1991, PASP 103, 1033, "A model of the brightness of
// moonlight": the brightness of the moonlit sky B_moon (their eq. 15, with the illuminance of
// the Moon I* from eq. 20 and the scattering function f(rho) from eq. 21), the dark sky at the
// target (eq. 2), the airmass X(Z) of eq. 3 and the conversion between nanoLamberts and V mag
// per square arcsecond of eq. 1. The result is the brightening of the dark sky in magnitudes.
double sun_moon_ks1991_sky_brightening_mag( double moon_phase_angle_deg, double moon_target_separation_deg,
                                            double moon_alt_deg, double target_alt_deg,
                                            double extinction_mag, double dark_sky_zenith_v_mag_arcsec2 ) {
 double alpha;
 double rho;
 double illuminance;
 double scattering;
 double sin_z;
 double x_moon;
 double x_target;
 double b_moon;
 double b_zenith;
 double b_sky;
 if ( moon_alt_deg <= 0.0 || target_alt_deg <= 0.0 ) {
  return 0.0;
 }
 alpha= fabs( moon_phase_angle_deg );
 rho= moon_target_separation_deg;
 // eq. 20
 illuminance= pow( 10.0, -0.4 * ( 3.84 + 0.026 * alpha + 4.0e-9 * pow( alpha, 4.0 ) ) );
 // eq. 21: Rayleigh and Mie scattering
 scattering= pow( 10.0, 5.36 ) * ( 1.06 + cos( rho * SM_DEG2RAD ) * cos( rho * SM_DEG2RAD ) ) + pow( 10.0, 6.15 - rho / 40.0 );
 // eq. 3
 sin_z= sin( ( 90.0 - moon_alt_deg ) * SM_DEG2RAD );
 x_moon= 1.0 / sqrt( 1.0 - 0.96 * sin_z * sin_z );
 sin_z= sin( ( 90.0 - target_alt_deg ) * SM_DEG2RAD );
 x_target= 1.0 / sqrt( 1.0 - 0.96 * sin_z * sin_z );
 // eq. 15, nanoLamberts
 b_moon= scattering * illuminance * pow( 10.0, -0.4 * extinction_mag * x_moon ) * ( 1.0 - pow( 10.0, -0.4 * extinction_mag * x_target ) );
 // eq. 1 and eq. 2: the dark sky at the target, nanoLamberts
 b_zenith= 34.08 * exp( 20.7233 - 0.92104 * dark_sky_zenith_v_mag_arcsec2 );
 b_sky= b_zenith * pow( 10.0, -0.4 * extinction_mag * ( x_target - 1.0 ) ) * x_target;
 return 2.5 * log10( ( b_moon + b_sky ) / b_sky );
}

void sun_moon_compute( double jd_utc, const struct sun_moon_site *site,
                       int have_target, double target_ra_deg, double target_dec_deg,
                       double extinction_mag, double dark_sky_zenith_v_mag_arcsec2,
                       struct sun_moon_geometry *result ) {
 double jd_tt;
 double lst_deg;
 double sun_ra_deg;
 double sun_dec_deg;
 double sun_distance_au;
 double sun_distance_km;
 double moon_ra_deg;
 double moon_dec_deg;
 double moon_distance_km;
 double elongation;
 double phase_angle;
 double target_ra_date_deg;
 double target_dec_date_deg;

 jd_tt= jd_utc + SUN_MOON_TT_MINUS_UTC_SEC / 86400.0;
 // UT1 - UTC is below 0.9 s, so UTC stands in for UT1
 lst_deg= sm_normalize_deg( sm_gmst_deg( jd_utc ) + site->longitude_deg );

 sm_sun_position( jd_tt, &sun_ra_deg, &sun_dec_deg, &sun_distance_au );
 sm_horizontal( sun_ra_deg, sun_dec_deg, lst_deg, site->latitude_deg, &result->sun_alt_deg, &result->sun_az_deg );

 sm_moon_position( jd_tt, &moon_ra_deg, &moon_dec_deg, &moon_distance_km );
 result->moon_distance_km= moon_distance_km;
 // the phase angle from the geocentric elongation, Meeus (48.2) and (48.3)
 elongation= sm_separation_deg( sun_ra_deg, sun_dec_deg, moon_ra_deg, moon_dec_deg ) * SM_DEG2RAD;
 sun_distance_km= sun_distance_au * SM_AU_KM;
 phase_angle= atan2( sun_distance_km * sin( elongation ), moon_distance_km - sun_distance_km * cos( elongation ) );
 result->moon_phase_angle_deg= phase_angle * SM_RAD2DEG;
 result->moon_illuminated_fraction= ( 1.0 + cos( phase_angle ) ) / 2.0;
 sm_topocentric( moon_ra_deg, moon_dec_deg, moon_distance_km, lst_deg, site, &result->moon_ra_deg, &result->moon_dec_deg );
 sm_horizontal( result->moon_ra_deg, result->moon_dec_deg, lst_deg, site->latitude_deg, &result->moon_alt_deg, &result->moon_az_deg );

 result->target_alt_deg= 0.0;
 result->target_az_deg= 0.0;
 result->target_airmass= 0.0;
 result->moon_target_separation_deg= 0.0;
 result->moon_sky_brightening_mag= 0.0;
 if ( have_target != 0 ) {
  sm_precess_from_j2000( target_ra_deg, target_dec_deg, jd_tt, &target_ra_date_deg, &target_dec_date_deg );
  sm_horizontal( target_ra_date_deg, target_dec_date_deg, lst_deg, site->latitude_deg, &result->target_alt_deg, &result->target_az_deg );
  result->target_airmass= sun_moon_airmass_young1994( result->target_alt_deg );
  result->moon_target_separation_deg= sm_separation_deg( result->moon_ra_deg, result->moon_dec_deg, target_ra_date_deg, target_dec_date_deg );
  result->moon_sky_brightening_mag= sun_moon_ks1991_sky_brightening_mag( result->moon_phase_angle_deg, result->moon_target_separation_deg,
                                                                         result->moon_alt_deg, result->target_alt_deg,
                                                                         extinction_mag, dark_sky_zenith_v_mag_arcsec2 );
 }
 return;
}
