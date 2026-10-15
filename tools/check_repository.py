"""Check tracked source hygiene and the mobile/Python checkpoint relationship."""
from pathlib import Path, PurePosixPath
import hashlib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BLOCKED_DIRS = {
    '.git', '.idea', '.dart_tool', '.venv', '__pycache__', 'build', 'dist',
    '.gradle', '.kotlin', '.android-tools', 'node_modules', 'runs',
}
SECRET_PATTERNS = {
    'private key': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'GitHub token': re.compile(rb'\bgh[pousr]_[A-Za-z0-9]{30,}\b|\bgithub_pat_[A-Za-z0-9_]{40,}\b'),
    'cloud access key': re.compile(rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
    'Google API key': re.compile(rb'\bAIza[0-9A-Za-z_-]{35}\b'),
}


def main():
    output = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT)
    names = [name for name in output.decode('utf-8').split('\0') if name]
    errors = []
    if not names:
        raise SystemExit('No tracked files. Stage the publication files first.')
    for name in names:
        relative = PurePosixPath(name)
        file = ROOT / name
        if file.is_symlink():
            errors.append(f'{name}: symlink requires review')
            continue
        blocked = bool(set(relative.parts) & BLOCKED_DIRS)
        blocked |= '/data/raw/' in '/' + name or '/data/processed/' in '/' + name
        blocked |= relative.suffix.lower() in {'.jks', '.keystore', '.apk', '.aab', '.pyc'}
        blocked |= relative.name in {'key.properties', 'local.properties', '.env'}
        blocked |= relative.name.startswith('.env.') and relative.name != '.env.example'
        if blocked:
            errors.append(f'{name}: private, generated, or release-only file')
        if file.stat().st_size > 10 * 1024 * 1024:
            errors.append(f'{name}: over 10 MiB; use a release asset')
        data = file.read_bytes()
        for label, pattern in SECRET_PATTERNS.items():
            if pattern.search(data):
                errors.append(f'{name}: possible {label}; inspect privately')
    checkpoint = ROOT / 'academic-risk/model/course_risk.pt'
    actual_hash = hashlib.sha256(checkpoint.read_bytes()).hexdigest()
    expected_hash = (checkpoint.parent / 'model.sha256').read_text().strip()
    exported = json.loads((ROOT / 'forma/assets/course_risk.json').read_text())
    if actual_hash != expected_hash or exported['source_sha256'] != actual_hash:
        errors.append('Python checkpoint, checksum, and mobile export do not match')
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    print(f'PASS: {len(names)} tracked files; source hygiene and model checksums verified.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
