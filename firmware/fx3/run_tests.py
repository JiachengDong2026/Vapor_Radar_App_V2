from pathlib import Path
import hashlib
import json
import os
import re
import struct
import subprocess

from build_config import ROOT, configuration
from prepare_sources import prepare_sources

config = configuration("Run firmware API mocks, vendor graph and ELF/IMG validation")
root = ROOT
application = prepare_sources(config.reference, config.output_dir)
work = config.work
gcc = config.host_gcc
args=[str(gcc),'-O2','-fwhole-program','-ffunction-sections','-fdata-sections','-D__CYU3P_TX__=1',
      '-I'+str(application/'include'),'-I'+str(config.sdk/'firmware/u3p_firmware/inc'),
      str(application/'tests/test_firmware.c'),'-Wl,--gc-sections','-o',str(work/('test_firmware.exe' if os.name == 'nt' else 'test_firmware'))]
subprocess.run(args,cwd=work,check=True)
subprocess.run([str(work/('test_firmware.exe' if os.name == 'nt' else 'test_firmware'))],cwd=work,check=True)

# The state graph remains exactly the vendor-generated waveform, not a guessed replacement.
provenance=json.loads((root/'SOURCE_PROVENANCE.json').read_text())
expected_tables=provenance['vendor_state_graph']['table_body_sha256']
modified=(application/'include/cyfxgpif_syncsf.h').read_text()
for name in ['CyFxGpifTransition','CyFxGpifWavedata','CyFxGpifWavedataPosition']:
    pattern=r'Sync_Slave_Fifo_2Bit_'+name+r'\[\]\s*=\s*\{(.*?)\n\};'
    body=re.search(pattern,modified,re.S).group(1)
    assert hashlib.sha256(body.encode()).hexdigest()==expected_tables[name],name
print('FX3_VENDOR_STATE_GRAPH_UNCHANGED_PASS')

elf=(config.output_dir/'vapor_fx3.elf').read_bytes()
img=(config.output_dir/'vapor_fx3.img').read_bytes()
assert elf[:6]==b'\x7fELF\x01\x01'
assert struct.unpack_from('<H',elf,18)[0]==40 # EM_ARM
entry,phoff=struct.unpack_from('<II',elf,24)
phsize,phcount=struct.unpack_from('<HH',elf,42)
expected={}
for i in range(phcount):
    typ,off,addr,physical,filesize,memsize,flags,alignment=struct.unpack_from('<8I',elf,phoff+i*phsize)
    if typ!=1:continue
    data=elf[off:off+filesize]+bytes(memsize-filesize)
    for j,b in enumerate(data):
        if addr+j>=0x100:expected[addr+j]=b
assert img[:2]==b'CY' and img[3]==0xB0
offset=4;checksum=0;actual={};sections=0
while True:
    words,addr=struct.unpack_from('<II',img,offset);offset+=8
    if words==0:
        assert addr==entry
        assert struct.unpack_from('<I',img,offset)[0]==checksum
        assert offset+4==len(img)
        break
    length=words*4;data=img[offset:offset+length];offset+=length;sections+=1
    assert len(data)==length
    for word in struct.iter_unpack('<I',data):checksum=(checksum+word[0])&0xffffffff
    for j,b in enumerate(data):
        assert addr+j not in actual
        actual[addr+j]=b
assert actual==expected,'IMG differs from ELF load memory or BSS zero initialization'
assert entry in actual
print(f'FX3_IMG_ELF_EQUIVALENCE_PASS bytes={len(actual)} sections={sections} entry=0x{entry:08x} checksum=0x{checksum:08x}')
print('IMG_SHA256='+hashlib.sha256(img).hexdigest())
