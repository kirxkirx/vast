// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_SUN_MOON_HEADER_FILE

// Positions of the Sun and the Moon as seen from an observing site, for judging the observing
// conditions of an image (twilight, moonlight). The algorithms and their accuracy are described
// in src/sun_moon.c; util/examples/test_sun_moon_ephemeris.sh checks them against astropy.

// TT - UTC in seconds: 37 leap seconds (since 2017-01-01) + 32.184 s. Before 2017 it was a few
// seconds less, which moves the Moon by less than 0.001 deg.
#define SUN_MOON_TT_MINUS_UTC_SEC 69.184

// Defaults of the moonlight model (Krisciunas & Schaefer 1991) when the caller has no better
// values: the V-band extinction coefficient of a site at about 1 km and a moderately dark sky
#define SUN_MOON_DEFAULT_EXTINCTION_MAG 0.20
#define SUN_MOON_DEFAULT_DARK_SKY_V_MAG_ARCSEC2 21.0

struct sun_moon_site {
 double latitude_deg;  // geodetic, north positive
 double longitude_deg; // east positive
 double height_m;      // above sea level
};

struct sun_moon_geometry {
 // All altitudes are geometric (no refraction), of the centre of the body
 double sun_alt_deg;
 double sun_az_deg;   // from North through East
 double moon_alt_deg; // topocentric
 double moon_az_deg;
 double moon_ra_deg;  // topocentric, mean equinox of date
 double moon_dec_deg;
 double moon_distance_km;          // geocentric
 double moon_phase_angle_deg;      // 0 = full Moon, 180 = new Moon
 double moon_illuminated_fraction; // 0..1
 // The following are set only when a target position is given
 double target_alt_deg;
 double target_az_deg;
 double target_airmass;                 // Young (1994); 40 below the horizon
 double moon_target_separation_deg;     // topocentric
 double moon_sky_brightening_mag;       // Krisciunas & Schaefer (1991); 0 with the Moon below the horizon
};

// Airmass for a geometric altitude, Young (1994, Applied Optics 33, 1108); 40 at or below the horizon
double sun_moon_airmass_young1994( double alt_deg );

// Brightening of the dark sky at a target by moonlight, in magnitudes, from the model of
// Krisciunas K., Schaefer B. E., 1991, PASP 103, 1033 "A model of the brightness of moonlight".
// Returns 0 when the Moon or the target is below the horizon.
double sun_moon_ks1991_sky_brightening_mag( double moon_phase_angle_deg, double moon_target_separation_deg,
                                            double moon_alt_deg, double target_alt_deg,
                                            double extinction_mag, double dark_sky_zenith_v_mag_arcsec2 );

// Fill the geometry for the time JD_UTC at the site. With have_target != 0 the target fields
// are computed for the J2000 (ICRS) position target_ra_deg, target_dec_deg.
void sun_moon_compute( double jd_utc, const struct sun_moon_site *site,
                       int have_target, double target_ra_deg, double target_dec_deg,
                       double extinction_mag, double dark_sky_zenith_v_mag_arcsec2,
                       struct sun_moon_geometry *result );

// The header is included
#define VAST_SUN_MOON_HEADER_FILE
#endif
