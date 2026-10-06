"""Apply only project edits to locally supplied, licensed Cypress example files."""
import hashlib
import json
import shutil

from build_config import ROOT


def prepare_sources(reference, output_dir):
    destination = output_dir / 'generated'
    manifest = json.loads((ROOT / 'gp01_changes.json').read_text())
    for relative, entry in manifest['files'].items():
        source = reference / entry['reference_file']
        if not source.is_file():
            raise SystemExit(f'Vendor example not found: {source}; see README.md')
        content = source.read_bytes()
        if hashlib.sha256(content).hexdigest() != entry['reference_sha256']:
            raise SystemExit(f'Vendor example version/hash mismatch: {source}; see gp01_changes.json')
        for edit in reversed(entry['changes']):
            offset = edit['offset']
            content = (content[:offset] + edit['insert'].encode('ascii') +
                       content[offset + edit['delete_bytes']:])
        if hashlib.sha256(content).hexdigest() != entry['result_sha256']:
            raise SystemExit(f'GP01 reconstruction hash mismatch: {relative}')
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
    (destination / 'tests').mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / 'tests/test_firmware.c', destination / 'tests/test_firmware.c')
    shutil.copyfile(ROOT / 'LICENSE-CYPRESS.txt', destination / 'LICENSE-CYPRESS.txt')
    print(f"FX3_GP01_SOURCE_RECONSTRUCTION_PASS files={len(manifest['files'])}")
    return destination
