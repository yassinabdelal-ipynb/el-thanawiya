"""Download pinned public sources and extract only the OULAD tables used by this project."""
from pathlib import Path
import hashlib
import io
import json
import zipfile
import requests

ROOT = Path(__file__).resolve().parent
SOURCES = {
    'student-performance.zip': ('https://archive.ics.uci.edu/static/public/320/student%2Bperformance.zip', '82ae9d66437b9808df42e8c89d2bb179c46e9cfbcf06f38abc1d20b3b747e177', 'CC BY 4.0'),
    'oulad.zip': ('https://archive.ics.uci.edu/static/public/349/open+university+learning+analytics+dataset.zip', 'f2ed1902616c1fe8d2824d872c0b7d2d72be435bf0124d077044fe4be2c6d3e4', 'CC BY 4.0'),
    'halabja-grades.csv': ('https://zenodo.org/records/16623461/files/StudentGradesDataset.csv?download=1', '813942b7efff0775e02e622b16de1e5158c203c3e6a648a9d5be1ca225e7566e', 'Reuse terms not verified; audit only, excluded from training'),
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ensure_sources():
    raw = ROOT / 'data' / 'raw'
    raw.mkdir(parents=True, exist_ok=True)
    for name, (url, expected, license_name) in SOURCES.items():
        path = raw / name
        if not path.exists():
            print(f'Downloading {name} ...', flush=True)
            temporary = path.with_suffix(path.suffix + '.part')
            with requests.get(url, stream=True, timeout=(20, 120)) as response:
                response.raise_for_status()
                with temporary.open('wb') as handle:
                    for chunk in response.iter_content(1024 * 1024):
                        handle.write(chunk)
            if sha256(temporary) != expected:
                raise ValueError(f'{name} checksum differs from reviewed source; inspect before using it')
            temporary.replace(path)
        if sha256(path) != expected:
            raise ValueError(f'{name} checksum failed')
    school = raw / 'school'
    school.mkdir(exist_ok=True)
    expected_school = {
        'student-mat.csv': 'e47f9ee225e1ee6e69b7564e6dac7123e80b8486677fe111f351964cef5dec80',
        'student-por.csv': 'a7594a11d7771c0efe1a740824e0e833da9c4cad07c39a9766a874575563fb3f',
    }
    with zipfile.ZipFile(raw / 'student-performance.zip') as outer:
        with zipfile.ZipFile(io.BytesIO(outer.read('student.zip'))) as inner:
            for name, checksum in expected_school.items():
                contents = inner.read(name)
                if hashlib.sha256(contents).hexdigest() != checksum:
                    raise ValueError(f'{name} differs from the reviewed training source')
                (school / name).write_bytes(contents)
    out = raw / 'oulad'
    out.mkdir(exist_ok=True)
    with zipfile.ZipFile(raw / 'oulad.zip') as archive:
        for name in ['studentInfo.csv', 'studentAssessment.csv', 'assessments.csv', 'courses.csv', 'studentRegistration.csv', 'OULAD.names']:
            # Exact allowlist avoids zip path traversal and unused 450 MB clickstream data.
            (out / name).write_bytes(archive.read(name))
    (raw / 'sources.json').write_text(json.dumps({name: {'url': item[0], 'sha256': item[1], 'license': item[2]} for name, item in SOURCES.items()}, indent=2), encoding='utf-8')
    return raw


if __name__ == '__main__':
    ensure_sources()
    print('Reviewed sources are present and checksums match.')
