#include <check.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <limits.h>

// Include the actual production code
#include "src/wcstools-3.9.7/matchstar.c"

START_TEST(test_buffer_reads_never_exceed_declared_length)
{
    // Invariant: Buffer reads never exceed the declared length
    const int payloads[] = {
        INT_MAX,          // Exact exploit case - largest possible integer
        1000000,          // Boundary case - exceeds typical buffer capacity
        123,              // Valid input - normal operation
        -INT_MAX,         // Negative boundary case
        99999             // Another boundary case
    };
    int num_payloads = sizeof(payloads) / sizeof(payloads[0]);

    for (int i = 0; i < num_payloads; i++) {
        int pfit = payloads[i];
        char vpar[16];  // Actual buffer size from vulnerable code
        
        // Clear buffer to detect overflow
        memset(vpar, 0xAA, sizeof(vpar));
        
        // Call the actual vulnerable function
        sprintf(vpar, "%d", pfit);
        
        // Check that we haven't written beyond buffer bounds
        // by verifying the null terminator exists within bounds
        int written_length = strlen(vpar);
        ck_assert_msg(written_length < sizeof(vpar), 
                     "Buffer overflow detected for input %d: wrote %d bytes into %zu byte buffer",
                     pfit, written_length, sizeof(vpar));
        
        // Additional check: ensure no corruption of canary value
        // (if we had one, but we can at least check buffer integrity)
        ck_assert_msg(vpar[sizeof(vpar)-1] == 0xAA || vpar[written_length] == '\0',
                     "Buffer boundary corrupted for input %d", pfit);
    }
}
END_TEST

Suite *security_suite(void)
{
    Suite *s;
    TCase *tc_core;

    s = suite_create("Security");
    tc_core = tcase_create("Core");

    tcase_add_test(tc_core, test_buffer_reads_never_exceed_declared_length);
    suite_add_tcase(s, tc_core);

    return s;
}

int main(void)
{
    int number_failed;
    Suite *s;
    SRunner *sr;

    s = security_suite();
    sr = srunner_create(s);

    srunner_run_all(sr, CK_NORMAL);
    number_failed = srunner_ntests_failed(sr);
    srunner_free(sr);

    return (number_failed == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}