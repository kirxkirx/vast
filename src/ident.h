/*****************************************************************************
 *
 *  IDENT LIB MODULE: ident.h
 *  
 *  Copyright(C) 2005      Lebedev Alexandr <lebedev@xray.sai.msu.ru>
 *               
 *  This program is free software ; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation ; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY ; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program ; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
 *
 * $Id$
 *
 ****************************************************************************/

// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_IDENT_INCLUDE_FILE

#include "vast_limits.h"

struct Observation {
 int star_num;
 double JD;
 double mag;
 double mag_err;
 double X;
 double Y;
 double APER;
 char filename[FILENAME_LENGTH];
 char fits_header_keywords_to_be_recorded_in_lightcurve[FITS_KEYWORDS_IN_LC_LENGTH];
 char is_used; // Check if this observation was alredy written to disk
 //
 float float_parameters[NUMBER_OF_FLOAT_PARAMETERS]; // Array of additional star parameters
};

struct Frame {
 double X_centre;
 double Y_centre;
};

/*
  Структура описывает порядок вершин 
  треугольника из множества начальных точек star[n]
*/
struct Triangle {
 int a[3];
 float ab;
 float ac;
 float bc;
 float ab_bc_ac;
};

struct Ecv_Triangle {
 struct Triangle tr1;
 struct Triangle tr2;
 //double podobie;
 //double dpodobie;
};
/*
  Описание последовательности подобных треугольников
*/
struct Ecv_triangles {
 struct Ecv_Triangle *tr;
 int Number; //число пар
};

/*
  This structure describes a star.
*/
struct Star {
 int n;
 float x;                    // X coordinate in pixels. WILL BE TRANSFORMED TO THE REFERENCE IMAGE COORDINATE FRAME
 float y;                    // Y coordinate in pixels. WILL BE TRANSFORMED TO THE REFERENCE IMAGE COORDINATE FRAME
 double flux;                // Brightness in counts
 double flux_err;            // Error of brightness in counts -- NEW
 float mag;                  // Brightness in magnitudes
 float sigma_mag;            // Error of brightness estimation (mag.)
 double JD;                  // Julian Date of observation
 float x_frame;              // X coordinate in pixels. WILL NOT BE TRANSFORMED TO THE REFERENCE IMAGE COORDINATE FRAME
 float y_frame;              // Y coordinate in pixels. WILL NOT BE TRANSFORMED TO THE REFERENCE IMAGE COORDINATE FRAME
 char detected_on_ref_frame; // 1 - detected, 0 - not detected
 short sextractor_flag;      // Sextractor flag
 int vast_flag;              // VaST's own flag which is a sum of
                             //  1 - semimajor axis of the object (A) is larger than the aperture size
                             //  2 - the object is an outlier in mag-chi2 plot (defined only in PSF-fitting mode)
                             //  4 - the object is an outlier in mag-A plot
                             //  8 - the object is an outlier in mag-FWHM plot
                             // 16 - the object is an outlier in mag-MagAuto plot
                             // and so on

 float star_size;                                    // Semimajor axis of the star's image (A)
 float star_psf_chi2;                                // chi2 of PSF-fitting
 float float_parameters[NUMBER_OF_FLOAT_PARAMETERS]; // Array of additional star parameters for filtering
                                                     // 0 - FWHM_IMAGE
                                                     // 1 - MAG_AUTO
                                                     // ... and many more!
 int n_detected;                                     // how many times this star was detected
 int n_rejected;                                     // how many times this star was detected, but rejected according to the quality flags (mag-size, etc)
 int moving_object;    // manually match a moving object
};

#define MAXIMUM_POPADANIY 1
#define PERSENT_POPADANIY 0

/*
 Преобразование второго кадра к первому
 Сначала подобие
 Затем translate
 Затем линейное преобразование Line_Preobr
 Затем translate
*/
struct Preobr_Sk {
 //double podobie;       //Коэффициент подобия первого кадра ко второму
 double translate1[2];       //translate по осям xy
 double line[4];             //Матрица линейного преобразования
 double translate2[2];       //translate по осям xy
 double fi;                  //Угол, на который надо было довернуть кадр 2 до кадра 1 по часовой стрелке
 double sigma_podobia;       //Критерий отбора подобных треугольников
 int Number_of_ecv_triangle; //Количество подобных треугольников, которые подвергаются обработке
 double sigma_popadaniya;    //Расстояние, на котором две звезды с двух кадров воспринимаются как одна
 double sigma_popadaniya_multiple;
 double persent_popadaniy_of_ecv_triangle;
 int method;
 int Number_of_main_star; //Количество опорных звезд
};

// This function is also used in vast.c so cannot be inlined
void Star_Copy(struct Star *copy, struct Star *star);

//void Ecv_Triangle_Copy(struct Ecv_Triangle *ecv_tr1, struct Ecv_Triangle *ecv_tr2);

struct Preobr_Sk *New_Preobr_Sk();               //Создание нового преобразования (как malloc)
//struct Preobr_Sk *New_Preobr_Sk_W();             //Создание нового преобразования (как malloc)
//struct Preobr_Sk *New_Preobr_Sk_M();             //Создание нового преобразования (как malloc)
void Delete_Preobr_Sk(struct Preobr_Sk *preobr); //Удаление преобразования

struct Ecv_triangles *Init_ecv_triangles(); //Инициализация массива подобных треугольников

/*
  Добавление нового элемента в Ecv_triangles

void Add_ecv_triangles(struct Ecv_triangles *ecv_tr, int a1, int b1, int c1,
		int a2, int b2, int c2);//, double podobie);//, double dpodobie);
*/

/*
  Удаление всего Ecv_triangles
*/
void Delete_Ecv_triangles(struct Ecv_triangles *ecv_tr);

//Преобразования
//void Scale(struct Star *star, int Number, double scale);//Масштаб
//void Translate(struct Star *star, int Number, double dx, double dy );//Параллельный перенос
//void Rotate(struct Star *star, int Number, double fi);//Поворот
//void Line_Preobr(struct Star *star, int Number, const double *line);//Линейное преобразование
//void Distorsion(struct Star *star, const int Number, const double X_centre, const double Y_centre, const double sigma);//Дисторсия

/*
  Сравнение звезд по расстоянию от центра поля
*/
//int compare_star_on_distance(const void *a1, const void *a2);

/*
  Сортировка звезд по расстоянию от центра поля
*/
//void Sort_in_distance_of_stars(struct Star *star, int Number, double X_centre, double Y_centre);

/*
  Сравнение звезд по яркости
*/
//int compare_star_on_mag(const void *a1, const void *a2);
/*
  Сортировка звезд по яркости
*/
void Sort_in_mag_of_stars(struct Star *star, int Number);

/*
  Нахождение треугольника из наиболее близких звезд к данной звезде
  возвращвет треугольник
*/
struct Triangle Separate(struct Star *star, int Number, int a0);

/*
  Разбиение звездного поля на треугольники
*/
struct Triangle *Separate_to_triangles(struct Star *star, int Number, int *Ntriangles);
/*
  Нахождения пар подобных треугольников на двух кадрах
*/
int Podobie(struct Preobr_Sk *preobr, struct Ecv_triangles *ecv_tr,
            //struct Star *star1, int Number1,
            //struct Star *star2, int Number2,
            struct Triangle *tr1, int Nt1,
            struct Triangle *tr2, int Nt2);

/*
  Сравнение двух пар подобных треугольников по ошибке подобия
*/
//int Compare_Ecv_triangles_on_dpodobie(const void *a, const void *b);
/*
  Сортировка пар подобных треугольников по ошибке подобия

void Sort_Ecv_triangles(struct Ecv_triangles *ecv_tr);


  Подсчет числа наложения звезд

int Popadanie_star1_to_star2(struct Star *star1, int Number1, struct Star *star2, int Number2, 
			     double sigma_popadaniya);
*/

/*
  Выбор лучшего опорного треугольника из массива подобных
  nm - индекс этого треугольника в массиве
*/
int Very_Well_triangle(struct Star *star1, int Number1, struct Star *star2, int Number2,
                       struct Ecv_triangles *ecv_tr,
                       struct Preobr_Sk *preobr, int *nm, int control1);

/*
  Нахождение линейного преобразования второго кадра к первому
*/
int Star2_to_star1_on_main_triangle(struct Preobr_Sk *preobr, struct Star *star1, int Number1, struct Star *star2,
                                    int Number2, struct Ecv_triangles *ecv_tr, int nm);

/*
  Отождествление звезд на двух полях
*/
int Ident_on_sigma(struct Star *star1, int Number1, struct Star *star2, int Number2, int *St1, int *St2, double sigma_popadaniya, double image_size_X, double image_size_Y);

/*
  Функция отождествления двух кадров возвращает количество отождествленных оъектов
  Pos1 и Pos2 - это массивы индексов эквивалентных звезд
*/
//int Ident(struct Preobr_Sk *preobr, struct Star *STAR1, int NUMBER1, struct Star *STAR2, int NUMBER2, int START_NUMBER2,
//	  struct Frame frame1, struct Frame frame2, int *Pos1, int *Pos2, int control1, struct Star *STAR3, int NUMBER3, int START_NUMBER3, int *match_retry, int min_number_of_matched_stars, double image_size_X, double image_size_Y );
int Ident(struct Preobr_Sk *preobr, struct Star *STAR1, int NUMBER1, struct Star *STAR2, int NUMBER2, int START_NUMBER2,
          int *Pos1, int *Pos2, int control1, struct Star *STAR3, int NUMBER3, int START_NUMBER3, int *match_retry, int min_number_of_matched_stars, double image_size_X, double image_size_Y);

//double autodetect_aperture(char *fitsfilename, double JD, double LAST_JD, double *LAST_APER, int param_P, double fixed_aperture, double *median_class_star, double *sigma_class_star, double X_im_size, double Y_im_size);
//double autodetect_aperture(char *fitsfilename, char *output_sextractor_catalog, int force_recompute, int param_P, double fixed_aperture, int verbose, double X_im_size, double Y_im_size);
double autodetect_aperture(char *fitsfilename, char *output_sextractor_catalog, int force_recompute, int param_P, double fixed_aperture, double X_im_size, double Y_im_size, int guess_saturation_limit_operation_mode);

// These two should be moved to a new gettime.h
int check_if_this_fits_image_is_north_up_east_left(char *fitsfilename);
int gettime(char *fitsfilename, double *JD, int *timesys, int convert_timesys_to_TT, double *dimX, double *dimY, char *stderr_output, char *log_output, int param_nojdkeyword, int verbose, char *finder_chart_timestring_output);

int read_exclude_stars_on_ref_image_lst(double *bad_stars_X, double *bad_stars_Y, int *N_bad_stars);

int read_bad_CCD_regions_lst(double *X1, double *Y1, double *X2, double *Y2, int *N);

int exclude_region(double *X1, double *Y1, double *X2, double *Y2, int N, double X, double Y, double aperture);

//void set_distance_to_neighbor_in_struct_Star(struct Star *star, int NUMBER, double aperture, double image_size_X, double image_size_Y);

// The macro below will tell the pre-processor that this header file is already included
#define VAST_IDENT_INCLUDE_FILE

#endif
// VAST_IDENT_INCLUDE_FILE
