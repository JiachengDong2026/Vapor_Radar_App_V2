"""Reproducible offline RD105 schema2 and RTU vectors, no device access."""
import hashlib,json,struct
from pathlib import Path

def rtu(body):
    crc=0xffff
    for byte in body:
        crc^=byte
        for _ in range(8):crc=(crc>>1)^(0xa001 if crc&1 else 0)
    return body+crc.to_bytes(2,'little')

def record(channel,target,actual,duty):
    entries=[(0x14,7,target),(0x15,7,actual),(2,3,0),(0x480,3,channel),(0x481,7,duty),(0x482,3,0)]
    return struct.pack('<HH',2,len(entries))+b''.join(struct.pack('<HBB',tag,kind,4)+struct.pack('<i' if kind==7 else '<I',value) for tag,kind,value in entries)

def vectors():
    values={
        'station2_ch1_target_read':rtu(bytes.fromhex('02 03 10 00 00 02')),
        'station2_ch2_target_write_25C':rtu(bytes.fromhex('02 10 20 00 00 02 04 00 26 25 A0')),
        'station2_ch2_target_ACK':rtu(bytes.fromhex('02 10 20 00 00 02')),
        'station2_target_readback_25C':rtu(bytes.fromhex('02 03 04 00 26 25 A0')),
        'schema2_channel1':record(1,25000000,25000000,-40000),
        'schema2_channel2':record(2,-12500000,-10000000,20000)}
    return {name:dict(bytes=len(data),hex=data.hex(' '),sha256=hashlib.sha256(data).hexdigest()) for name,data in values.items()}

if __name__=='__main__':
    Path(__file__).with_name('rd105_golden_20261115.json').write_text(json.dumps(vectors(),indent=2)+'\n',encoding='utf-8')
