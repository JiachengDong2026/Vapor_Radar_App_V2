"""Build SDK source, ARM firmware, and the vendor IMG converter without make."""
from pathlib import Path
import hashlib
import json
import os
import subprocess

from build_config import ROOT, configuration
from prepare_sources import prepare_sources

args = configuration(__doc__, arm_required=True)
root = ROOT
sdk = args.sdk
src = sdk / 'FX3_SDK_1_3_1_SRC/sdk/firmware/src'
common = sdk / 'firmware/common'
work = args.work
out = args.output_dir
reports = out / 'reports'
reports.mkdir(exist_ok=True)
gcc = args.arm_gcc
arm = gcc.parent
suffix = gcc.suffix
application = prepare_sources(args.reference, out)

# Pin the SDK used on the board. Do not silently switch to an installed 1.3.5 SDK.
provenance = json.loads((root / 'SDK_PROVENANCE.json').read_text())
for item in provenance['files']:
    path = sdk / item['path']
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
        raise SystemExit(f"SDK dependency missing or changed: {path}; see README.md")
print(f"FX3_SDK_PROVENANCE_PASS files={len(provenance['files'])}")

flags=['-mcpu=arm926ej-s','-mthumb-interwork','-O1','-g','-ffunction-sections','-fdata-sections',
       '-DCYU3P_FX3=1','-DCYU3P_SILICON=1','-DCYU3P_STORAGE_SDIO_SUPPORT=1','-D__CYU3P_TX__=1',
       '-I'+str(sdk/'FX3_SDK_1_3_1_SRC/sdk/firmware/include'),'-I'+str(sdk/'firmware/u3p_firmware/inc'),
       '-I'+str(application/'include')]
def run(args):
    result=subprocess.run([str(x) for x in args],cwd=work,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    if result.stdout:print(result.stdout,end='',flush=True)
    if result.returncode:raise SystemExit(result.returncode)
    return result.stdout

objects=[]
sources=sorted(p for p in src.rglob('*.c') if 'fxapp' not in p.parts)
sources += sorted((src/'system').glob('*_gcc.S'))
for p in sources:
    obj=work/('sdk_'+p.parent.name+'_'+p.stem+'.o')
    run([gcc,*flags,'-I'+str(p.parent),'-c',p,'-o',obj]);objects.append(obj)
lib=work/'vapor_sdk.a'
run([arm/('arm-none-eabi-ar'+suffix),'rcs',lib,*objects])
appobjects=[]
for p in [*sorted((application/'src').glob('*.c')),common/'cyfxtx.c',common/'cyfx_gcc_startup.S']:
    obj=work/(p.stem+'.o')
    run([gcc,*flags,'-Wall','-c',p,'-o',obj]);appobjects.append(obj)
elf=out/'vapor_fx3.elf'
mapfile=out/'vapor_fx3.map'
libc=run([gcc,'-mcpu=arm926ej-s','-print-file-name=libc.a']).strip()
libgcc=run([gcc,'-mcpu=arm926ej-s','-print-libgcc-file-name']).strip()
run([arm/('arm-none-eabi-ld'+suffix),'-T',common/'fx3_512k.ld','-d','--gc-sections','--no-wchar-size-warning',
     '-Map',mapfile,'-o',elf,*appobjects,'--start-group',lib,
     src/'fx3lib/source/fx3_release/cyfx3lib.a',src/'rtos/fx3_release/cyu3threadx.a',libc,libgcc,'--end-group'])
size=run([arm/('arm-none-eabi-size'+suffix),elf])
(reports/'size.txt').write_text(size)
headers=run([arm/('arm-none-eabi-readelf'+suffix),'-h','-l',elf])
(reports/'elf_headers.txt').write_text(headers)
hostgcc=args.host_gcc
converter=work/('elf2img.exe' if os.name == 'nt' else 'elf2img')
run([hostgcc,'-O2',sdk/'util/elf2img/elf2img.c','-o',converter])
img=out/'vapor_fx3.img'
run([converter,'-i',elf,'-o',img])
manifest={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [elf,img]}
(reports/'ARTIFACT_SHA256.json').write_text(json.dumps(manifest,indent=2))
(reports/'BUILD_ENVIRONMENT.json').write_text(json.dumps({
    'sdk':str(sdk), 'arm_gcc':str(gcc), 'host_gcc':str(hostgcc),
    'arm_gcc_version':run([gcc,'--version']).splitlines()[0],
    'host_gcc_version':run([hostgcc,'--version']).splitlines()[0],
    'source_directory':str(root), 'generated_source_directory':str(application),
    'reference_directory':str(args.reference), 'output_directory':str(out),
    'sdk_provenance_sha256':hashlib.sha256((root/'SDK_PROVENANCE.json').read_bytes()).hexdigest(),
},indent=2)+'\n')
print('VAPOR_FX3_ARM_BUILD_PASS')
