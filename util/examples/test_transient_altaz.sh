#!/usr/bin/env bash
# Offline regression test of FITS coordinates reported by the transient factory.
# Uses the compiled util/listhead and temporary, minimal FITS images only.
set -euo pipefail
export LC_ALL=C
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
python3 - "$SCRIPT_DIR/../.." <<'PY'
from pathlib import Path
import hashlib
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]).resolve()
source = (root / 'util/transients/transient_factory_test31.sh').read_text()
function = re.search(r'^function report_second_epoch_image_altaz \{\n.*?^ return 0\n\}\n',
                     source, re.M | re.S).group()
cases = [
    ('decimal', {'CENTALT': '22.55', 'CENTAZ': '239.7625'}, '22.6', '239.8'),
    ('sexagesimal', {'OBJCTALT': "'45 00 00'", 'OBJCTAZ': "'123:45:36'"}, '45.0', '123.8'),
    ('preferred', {'CENTALT': '20', 'OBJCTALT': '21', 'CENTAZ': '100', 'OBJCTAZ': '101'}, '20.0', '100.0'),
    ('fallback', {'CENTALT': '999', 'OBJCTALT': '0', 'CENTAZ': "'N/A'", 'OBJCTAZ': '0'}, '0.0', '0.0'),
    ('azimuth_only', {'CENTAZ': '2.397625D2'}, None, '239.8'),
    ('altitude_only', {'CENTALT': '-5'}, '-5.0', None),
    ('near_cloud_limit', {'CENTALT': '19.99'}, '20.0', None),
    ('missing', {}, None, None),
    ('invalid', {'CENTALT': "'NaN'", 'CENTAZ': '361'}, None, None),
    ('bad_minutes', {'OBJCTAZ': "'10 60 00'"}, None, None),
    ('boundaries', {'CENTALT': '-90', 'CENTAZ': '360'}, '-90.0', '360.0'),
]
with tempfile.TemporaryDirectory(prefix='vast-altaz-') as work:
    work = Path(work)
    (work / 'util').mkdir()
    (work / 'util/listhead').symlink_to(root / 'util/listhead')
    images = []
    hashes = []
    for name, keys, _, _ in cases:
        cards = ['SIMPLE  =                    T', 'BITPIX  =                   16',
                 'NAXIS   =                    0']
        cards += [f'{key:8s}= {value}' for key, value in keys.items()]
        cards.append('END')
        image = work / (name + '.fits')
        image.write_bytes(''.join(card.ljust(80) for card in cards).ljust(2880).encode('ascii'))
        images.append(str(image))
        hashes.append(hashlib.sha256(image.read_bytes()).digest())
    result = subprocess.run(['bash', '-c', function + '\nreport_second_epoch_image_altaz "$@"'
                             '\nprintf "%s\\n" "${SECOND_EPOCH_CENTER_ALTITUDES[@]}" > center_altitudes.txt',
                             'test', *images], cwd=work, text=True, capture_output=True, check=True)
    assert result.stdout == (work / 'transient_factory_test31.txt').read_text()
    # The cloud check uses only valid center altitudes at their original
    # precision. A target altitude fallback is suitable for display only.
    center_altitudes = (work / 'center_altitudes.txt').read_text().splitlines()
    assert [float(deg) if deg else None for deg in center_altitudes] == [
        22.55, None, 20, None, None, -5, 19.99, None, None, None, -90,
    ]
    for image, old_hash, (name, _, alt, az) in zip(images, hashes, cases):
        assert hashlib.sha256(Path(image).read_bytes()).digest() == old_hash
        for coordinate, expected in [('altitude', alt), ('azimuth', az)]:
            lines = [line for line in result.stdout.splitlines()
                     if line.endswith('  ' + name + '.fits') and 'field ' + coordinate in line.lower()]
            assert len(lines) == 1, (name, coordinate, lines)
            if expected is None:
                assert lines[0].startswith('No field ' + coordinate), lines
            else:
                assert lines[0].startswith(f'Field {coordinate} during imaging: {expected} deg '), lines
    assert 'ERROR' not in result.stdout
print(f'PASS: {len(cases)} FITS coordinate cases; headers unchanged; stdout matches report log')
PY
