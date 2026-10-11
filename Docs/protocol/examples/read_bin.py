"""Offline VLP BIN inspection, Python 3.9+ standard library, NO hardware access.
Validates framing/CRC/padding; previews point layouts, not full cycle reassembly.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import struct
from vlp_reference import StreamParser


def preview(frame):
    h, p = frame.header, frame.payload
    schema = struct.unpack_from('<H', p)[0] if len(p) >= 2 else -1
    result = {'file_offset':frame.offset, 'source':hex(h['source']), 'message':hex(h['message']),
              'schema':schema, 'flags':hex(h['flags']), 'cycle':h['cycle'],
              'timestamp_ticks':str(h['timestamp_ticks'])}
    if h['message'] == 0x1000:
        if len(p)<20: raise ValueError('RAW header truncated')
        _, bits, rate, total, fmt = struct.unpack_from('<HHIII',p)
        if schema == 1:
            head,index,count,first,n,reserved=20,0,1,0,total,struct.unpack_from('<I',p,16)[0]
        elif schema == 2 and len(p)>=32:
            head=32
            index,count,first,n,reserved=struct.unpack_from('<HHIII',p,16)
        else: raise ValueError('unsupported RAW schema')
        if fmt not in (0,1) or not 1<=bits<=32 or reserved or len(p)!=head+n*4:
            raise ValueError('invalid RAW point layout')
        result.update(adc_bits=bits,rate_hz=rate,total_points=total,format=fmt,
                      fragment_index=index,fragment_count=count,first_point=first,fragment_points=n,
                      first_codes=list(struct.unpack_from('<'+('i' if fmt==0 else 'I')*min(n,4),p,head)))
    else:
        if schema != 2 or len(p)<32: raise ValueError('unsupported DLIA schema')
        _,fmt,rate,total,index,count,first,n,width,reserved=struct.unpack_from('<HHIIHHIIII',p)
        if fmt not in (0,1,2) or width!=(fmt+1)*8 or reserved or len(p)!=32+n*width:
            raise ValueError('invalid DLIA point layout')
        result.update(rate_hz=rate,total_points=total,format=fmt,fragment_index=index,
                      fragment_count=count,first_point=first,fragment_points=n,bytes_per_point=width,
                      point_order=[['H1','H2'],['I1','Q1','I2','Q2'],['I1','Q1','I2','Q2','H1','H2']][fmt],
                      first_point_values=list(struct.unpack_from('<'+'i'*(width//4),p,32)) if n else [])
    if not rate or not total or not n or not count or index>=count or first+n>total:
        raise ValueError('invalid fragment range')
    return result


def main():
    cli=argparse.ArgumentParser(description=__doc__)
    cli.add_argument('capture',type=Path)
    cli.add_argument('--chunk-size',type=int,default=65536)
    args=cli.parse_args()
    if not 1<=args.chunk_size<=16*1024*1024: cli.error('chunk size must be 1..16777216')
    parser=StreamParser(); counts=Counter(); previews={}; ticks=[]
    def handle(frames):
        for frame in frames:
            h=frame.header; key=f"{h['kind']:02X}/{h['source']:04X}/{h['message']:04X}"
            counts[key]+=1
            if h['flags']&1:
                if not ticks: ticks.append(h['timestamp_ticks'])
                if len(ticks)==1: ticks.append(h['timestamp_ticks'])
                else: ticks[1]=h['timestamp_ticks']
            if key not in previews and h['kind']==0x10 and ((h['message']==0x1000 and h['source'] in (0x20,0x21)) or (h['message']==0x1001 and h['source'] in (0x30,0x31))):
                previews[key]=preview(frame)
    with args.capture.open('rb') as capture:
        for chunk in iter(lambda:capture.read(args.chunk_size),b''): handle(parser.feed(chunk))
    handle(parser.finish())
    stats=parser.statistics()
    print(json.dumps({'file':str(args.capture),'frame_counts':dict(counts),'parser':stats,
                      'first_last_valid_ticks':[str(x) for x in ticks], 'previews':previews,
                      'note':'CRC/frame validation only; no complete-cycle or sensor-validity acceptance.'},ensure_ascii=False,indent=2))
    return int(bool(stats['discarded_bytes']) or stats['frames']==0)


if __name__=='__main__':
    raise SystemExit(main())
