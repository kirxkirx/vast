#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>

#include "vast_limits.h"

// Structure to hold the data from the files
typedef struct {
    double julian_date;
    char* line;
} Data;

// Comparator function for qsort()
int compare_julian_date(const void* a, const void* b) {
    double date_a = ((Data*)a)->julian_date;
    double date_b = ((Data*)b)->julian_date;
    return (date_a > date_b) - (date_a < date_b);
}

// Function to sort the content of a file
void sort_file(const char* file_name) {
    FILE* file = fopen(file_name, "r");
    if (!file) {
        perror("Error opening file");
        return;
    }

    Data data_arr[MAX_NUMBER_OF_OBSERVATIONS]; // Assuming max MAX_NUMBER_OF_OBSERVATIONS rows per file
    size_t data_count = 0;
    char line[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];

    while (fgets(line, sizeof(line), file)) {
        char* line_copy = strdup(line);
        double julian_date;
        sscanf(line_copy, "%lf", &julian_date);

        data_arr[data_count].julian_date = julian_date;
        data_arr[data_count].line = line_copy;
        data_count++;
    }
    fclose(file);

    // Sort the data array
    qsort(data_arr, data_count, sizeof(Data), compare_julian_date);

    // Write sorted data to the output file
    char output_file_name[OUTFILENAME_LENGTH];
    snprintf(output_file_name, sizeof(output_file_name), "%s", file_name);
    FILE* output_file = fopen(output_file_name, "w");

    if (!output_file) {
        fprintf(stderr, "ERROR opening output file %s\n", output_file_name);
        return;
    }

    for (size_t i = 0; i < data_count; i++) {
        fprintf(output_file, "%s", data_arr[i].line);
        free(data_arr[i].line);
    }

    fclose(output_file);
}

int main() {
    DIR* dir;
    struct dirent* ent;
    const char* dir_path = "./"; // Your directory path here

    if ((dir = opendir(dir_path)) != NULL) {
        // Count the number of outNNNNN.dat files
        int file_count = 0;
        while ((ent = readdir(dir)) != NULL) {
            if (strstr(ent->d_name, "out") && strstr(ent->d_name, ".dat")) {
                file_count++;
            }
        }
        rewinddir(dir); // Reset the directory stream
        
        fprintf(stderr,"Sorting lightcurve files in JD...\n");

        // Process the outNNNNN.dat files in parallel using OpenMP
        #ifdef VAST_ENABLE_OPENMP
        #ifdef _OPENMP
        #pragma omp parallel for
        #endif
        #endif
        for (int i = 0; i < file_count; i++) {
            while ((ent = readdir(dir)) != NULL) {
                if (strstr(ent->d_name, "out") && strstr(ent->d_name, ".dat")) {
                    //fprintf(stderr,"Processing file: %s\n", ent->d_name);
                    sort_file(ent->d_name);
                    break;
                }
            }
        }
        

        closedir(dir);
    } else {
        fprintf(stderr, "ERROR opening directory %s\n", dir_path);
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}
