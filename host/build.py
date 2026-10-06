"""Build USB diagnostic tools against a locally installed Cypress CyUSB.dll."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cyusb', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--csc', type=Path, default=Path(os.environ.get('WINDIR', 'C:/Windows')) /
                        'Microsoft.NET/Framework64/v4.0.30319/csc.exe')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    output = args.output.resolve()
    if output.is_relative_to(root.parent):
        parser.error('Generated tools must be outside the repository')
    if not args.cyusb.is_file() or not args.csc.is_file():
        parser.error('The specified CyUSB.dll or C# compiler does not exist')
    output.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(args.cyusb, output / 'CyUSB.dll')
    for name in ('SensorRun', 'CaptureIn'):
        subprocess.run([str(args.csc), '/nologo', '/target:exe', '/platform:x64',
                        '/out:' + str(output / (name + '.exe')),
                        '/reference:' + str(output / 'CyUSB.dll'),
                        '/reference:System.Windows.Forms.dll', str(root / (name + '.cs'))],
                       cwd=output, check=True)
    print('HOST_TOOLS_BUILD_PASS')


if __name__ == '__main__':
    main()
