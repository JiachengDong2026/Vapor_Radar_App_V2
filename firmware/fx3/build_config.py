"""Explicit, external dependencies shared by the firmware build and tests."""
from pathlib import Path
import argparse
import os
import shutil

ROOT = Path(__file__).resolve().parent


def executable(value, fallback):
    candidate = value or shutil.which(fallback)
    if not candidate or not Path(candidate).is_file():
        raise SystemExit(f"Tool not found: {candidate or fallback}; set the corresponding option/environment variable")
    return Path(candidate).resolve()


def configuration(description, arm_required=False):
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument('--sdk', default=os.environ.get('VAPOR_FX3_SDK'),
                        help='External SDK 1.3.1 source bundle (see README.md)')
    parser.add_argument('--output-dir', default=os.environ.get('VAPOR_FX3_OUTPUT'),
                        help='Required external directory for all generated files')
    parser.add_argument('--reference', default=os.environ.get('VAPOR_FX3_REFERENCE'),
                        help='External, hash-pinned vendor slfifosync example directory')
    parser.add_argument('--host-gcc', default=os.environ.get('VAPOR_HOST_GCC'))
    if arm_required:
        parser.add_argument('--arm-gcc', default=os.environ.get('VAPOR_ARM_GCC'))
    args = parser.parse_args()
    if not args.sdk or not args.output_dir or not args.reference:
        parser.error('--sdk, --reference and --output-dir (or their VAPOR_FX3_* variables) are required')
    args.sdk = Path(args.sdk).resolve()
    args.reference = Path(args.reference).resolve()
    args.output_dir = Path(args.output_dir).resolve()
    repository = ROOT.parents[1]
    if args.output_dir == repository or repository in args.output_dir.parents:
        parser.error('Use an output directory outside the repository')
    if args.output_dir == args.sdk or args.sdk in args.output_dir.parents:
        parser.error('The SDK must remain read-only; choose a separate output directory')
    if args.output_dir == args.reference or args.reference in args.output_dir.parents:
        parser.error('The vendor example must remain read-only; choose a separate output directory')
    args.host_gcc = executable(args.host_gcc, 'gcc')
    if arm_required:
        args.arm_gcc = executable(args.arm_gcc, 'arm-none-eabi-gcc')
    args.output_dir.mkdir(parents=True, exist_ok=True)
    args.work = args.output_dir / '.work'
    args.work.mkdir(exist_ok=True)
    os.environ['TMP'] = os.environ['TEMP'] = str(args.work)
    return args
