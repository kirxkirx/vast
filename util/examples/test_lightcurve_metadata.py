#!/usr/bin/env python3
"""Headless metadata regression checks; run after make, optionally with a build path.

All generated data and report stubs live in a temporary directory.
"""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
BUILD = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT


def run(args, cwd, **kwargs):
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True,
                            timeout=120, **kwargs)
    assert result.returncode == 0, (args, result.stdout, result.stderr)
    return result.stdout


def rows(with_flags=True, apertures=True):
    result = []
    for i in range(30):
        mag = 12 + (i % 5 - 2) * .02
        extra = ' '.join('{:.4f} .01'.format(12 - mag) for _ in range(5))
        flag = 'SE_FLAGS={} '.format((0, 4, 20, 255, 2)[i % 5])
        result.append('{:.8f} {:.4f} .02 100 200 6 image{}.fits {}{}'
                      'CCD-TEMP= -15.0\n'.format(
                          2461000 + i / 100, mag, i,
                          extra + ' ' if apertures else '',
                          flag if with_flags else ''))
    return ''.join(result)


def check_metadata(path, expected):
    lines = path.read_text().splitlines()
    assert lines, path
    for line in lines:
        fields = line.split(maxsplit=7)
        assert fields[7] == expected[fields[6]], line
    return lines


def test_rewriters(tmp):
    results = {}
    for flagged in (False, True):
        work = tmp / ('flagged' if flagged else 'control')
        work.mkdir()
        lc = work / 'out00001.dat'
        lc.write_text(rows(flagged))
        expected = {s.split()[6]: s.split(maxsplit=17)[17]
                    for s in lc.read_text().splitlines()}
        # Force an actual aperture replacement: alternative magnitudes are constant.
        for executable, args in (
                ('lib/select_aperture_with_smallest_scatter_for_each_object', []),
                ('util/calibrate_magnitude_scale', ['0', '1', '1']),
                ('lib/new_lightcurve_sigma_filter', []),
                ('lib/MagSize_filter_standalone', [])):
            run([str(BUILD / executable)] + args, work)
            lines = check_metadata(lc, expected)
            assert len(lines) == 30
            results[flagged, executable] = [s.split()[:7] for s in lines]
        run([str(BUILD / 'lib/select_only_n_random_points_from_set_of_lightcurves'),
             '10'], work)
        assert len(check_metadata(lc, expected)) == 10
    for flag, executable in results:
        assert results[False, executable] == results[True, executable], executable
    # Missing metadata must not inherit the preceding row's flag.
    work = tmp / 'mixed'
    work.mkdir()
    lc = work / 'out00001.dat'
    lc.write_text('2461000 12 .02 100 200 6 a.fits SE_FLAGS=4\n'
                  '2461001 12 .02 100 200 6 b.fits\n'
                  '2461002 12 .02 100 200 6 c.fits SE_FLAGS=0\n')
    run([str(BUILD / 'util/calibrate_magnitude_scale'), '0', '1', '1'], work)
    lines = lc.read_text().splitlines()
    assert 'SE_FLAGS=4' in lines[0] and len(lines[1].split()) == 7
    assert 'SE_FLAGS=0' in lines[2]


def test_report(tmp):
    work = tmp / 'report'
    work.mkdir()
    for subdir in ('util', 'lib'):
        (work / subdir).mkdir()
    stubs = {
        'util/get_image_date': "echo '        JD 2461000.50000'\necho 'MPC format 2026 10 20.00000'\n",
        'lib/find_star_in_wcs_catalog': "echo '15.0 20.0'\n",
        'lib/deg2hms': "echo '01:00:00.00 +20:00:00.0'\n",
    }
    for name, body in stubs.items():
        path = work / name
        path.write_text('#!/bin/sh\n' + body)
        path.chmod(0o755)
    (work / 'vast_summary.log').write_text('Ref.  image: a b c ref.fits\n')
    (work / 'vast_image_details.log').write_text(
        ' '.join(['x'] * 16 + ['ref.fits']) + '\n' +
        ' '.join(['x'] * 16 + ['ref2.fits']) + '\n')
    for name in ('ref.fits', 'new.fits'):
        (work / ('wcs_' + name)).touch()
        (work / ('wcs_' + name + '.wcscat.ucac5')).touch()
    source = (ROOT / 'util/transients/report_transient.sh').read_text()
    # Execute the actual table/report block, stubbing only unrelated astronomy tools.
    block = source[source.index('REFERENCE_IMAGE=$(grep'):source.index(
        '# We need to reformat util/colstat output')]
    setup = 'LIGHTCURVEFILE=out00001.dat\nclean_tmp_files() { :; }\n'
    for field in ('JD', 'RA', 'DEC', 'MAG', 'X', 'Y'):
        setup += 'REPORT_TRANSIENT_TMPFILE_{}=tmp_{}\n'.format(field, field)
    baseline = None
    baseline_html = None
    for token in ('', 'SE_FLAGS=0', 'SE_FLAGS=2', 'SE_FLAGS=4', 'SE_FLAGS=20',
                  'SE_FLAGS=255', 'SE_FLAGS=004', 'SE_FLAGS=8',
                  'SE_FLAGS=256', 'SE_FLAGS=-4', 'SE_FLAGS=4x', 'XSE_FLAGS=4'):
        (work / 'out00001.dat').write_text(
            '2461000 12 .02 100 200 6 ref.fits\n'
            '2461001 11 .02 100 200 6 new.fits ' + token + '\n')
        html = run(['bash', '-c', setup + block], work,
                   env=dict(os.environ, LC_ALL='C'))
        table = re.search(r'<table.*?</table>', html, re.S).group()
        if baseline is None:
            baseline = table
            baseline_html = html
        assert table == baseline, token
        # Existing grep -B consumers in test_vast.sh and unmw/autoprocess.sh
        # must still reach the anchor and discovery rows from the mean line.
        # Only the paragraph may differ, including its surrounding newlines.
        without_flags = re.sub(r'<p>SExtractor measurement flags:<br>.*?</p>',
                               '', html)
        assert without_flags == baseline_html, token
        saturated = token in ('SE_FLAGS=4', 'SE_FLAGS=20', 'SE_FLAGS=255', 'SE_FLAGS=004')
        assert ('SATURATED - magnitude unreliable.' in html) == saturated, token
        if saturated:
            assert html.index('SATURATED') > html.index('</table>')
        if token == '':
            assert 'SExtractor measurement flags' not in html


def test_no_fits_keywords(tmp):
    source = (ROOT / 'util/examples/test_vast.sh').read_text()
    # Exercise the actual no-header-recording assertion with metadata alone
    # and with unwanted header keywords, in either order.
    assertion = source.split(
        "# Any other token containing '=' still indicates unwanted header recording.\n",
        1)[1].splitlines()[0]
    for metadata, unwanted in (
            ('', False), ('0.01 .02 SE_FLAGS=0', False),
            ('SE_FLAGS=255', False), ('CCD-TEMP= -15', True),
            ('SE_FLAGS=4 CCD-TEMP= -15', True),
            ('CCD-TEMP= -15 SE_FLAGS=0', True),
            ('SE_FLAGS=bad', True)):
        result = subprocess.run(['bash', '-c', assertion], cwd=tmp,
                                env=dict(os.environ, A=metadata), timeout=10)
        assert result.returncode == (0 if unwanted else 1), metadata


def test_writer(tmp):
    # A small harness around the production writer, including both compile-time formats.
    source = (ROOT / 'src/vast.c').read_text()
    start = source.index('void write_obs_to_file(')
    writer = source[start:source.index('\n}', start) + 2]
    for apertures in (False, True):
        program = tmp / ('writer_apertures.c' if apertures else 'writer_plain.c')
        program.write_text(
            '#include "vast_types.h"\n#include "lightcurve_io.h"\n' +
            ('' if apertures else '#undef WRITE_ADDITIONAL_APERTURES_TO_LIGHTCURVES\n') +
            writer + '\nint main(void) {\n'
            ' struct Observation obs;\n int i;\n'
            ' memset(&obs, 0, sizeof(obs));\n'
            ' obs.JD=2461000; obs.mag=12; obs.mag_err=.02; obs.APER=6;\n'
            ' obs.filename="test.fits";\n'
            ' obs.fits_header_keywords_to_be_recorded_in_lightcurve="CCD-TEMP= -15";\n'
            ' for(i=0;i<256;i++) { obs.sextractor_flag=(unsigned char)i;'
            ' write_obs_to_file(stdout,&obs); }\n return 0;\n}\n')
        binary = program.with_suffix('')
        run(['cc', '-I', str(ROOT / 'src'), str(program), '-lm', '-o', str(binary)], tmp)
        lines = run([str(binary)], tmp).splitlines()
        assert len(lines) == 256
        for flag, line in enumerate(lines):
            fields = line.split()
            assert fields[17 if apertures else 7] == 'SE_FLAGS={}'.format(flag)
            assert line.endswith('CCD-TEMP= -15')


with tempfile.TemporaryDirectory(prefix='vast-metadata-test-') as directory:
    temp = Path(directory)
    test_writer(temp)
    test_rewriters(temp)
    test_report(temp)
    test_no_fits_keywords(temp)
print('PASS: metadata preservation, unchanged photometry, and unchanged HTML table')
