"""USB control for integrated DM422/PPS firmware; no JTAG image loading.

Requires the existing VaporUsbBridge.exe and CyUSB.dll. Only one host may own
the FX3. Default command is read-only status. A move always disables on exit.
"""
import argparse
import base64
from decimal import Decimal
import json
from pathlib import Path
import queue
import struct
import subprocess
import threading
import time
import zlib


def utc_at_tick(tick, pps_tick, utc_us, measured_hz):
    if measured_hz <= 0:
        raise ValueError('PPS frequency is not calibrated')
    return Decimal(utc_us) + Decimal(tick - pps_tick) * Decimal(1000000) / Decimal(measured_hz)


def command_frame(sequence, address, value=None, count=1):
    payload = struct.pack('<II', address, count)
    if value is not None:
        payload += struct.pack('<I', value & 0xffffffff)
    header = struct.pack('<IBBBBI IHHI QII', 0x31504c56, 1, 0, 1, 10,
                         44+len(payload), sequence, 1, 2 if value is None else 3,
                         0, 0, 0, len(payload))
    frame = header+payload
    return frame+struct.pack('<I', zlib.crc32(frame))


class Usb:
    def __init__(self, bridge):
        self.proc = subprocess.Popen([str(Path(bridge).resolve())], stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=None, bufsize=0)
        self.frames = queue.Queue()
        self.seq = 700000
        threading.Thread(target=self._reader, daemon=True).start()

    def _reader(self):
        pending = bytearray()
        try:
            while True:
                part = self.proc.stdout.read(16384)
                if not part:
                    raise IOError('USB bridge exited')
                pending.extend(part)
                while len(pending) >= 40:
                    size = struct.unpack_from('<I', pending, 8)[0]
                    if pending[:4] != b'VLP1' or pending[4:6] != b'\x01\x00' or pending[7] != 10 or not 44 <= size <= 1048576:
                        raise IOError('Invalid VLP header')
                    if size != 44+struct.unpack_from('<I', pending, 36)[0]:
                        raise IOError('Invalid VLP payload length')
                    aligned = (size+3)&~3
                    if len(pending) < aligned:
                        break
                    frame = bytes(pending[:size]); del pending[:aligned]
                    if zlib.crc32(frame[:-4]) != struct.unpack_from('<I', frame, size-4)[0]:
                        raise IOError('VLP CRC failed')
                    if frame[6] in (2, 0x7f):
                        self.frames.put(frame)
        except Exception as exc:
            self.frames.put(exc)

    def command(self, address, value=None, count=1):
        self.seq += 1
        frame = command_frame(self.seq, address, value, count)
        self.proc.stdin.write(base64.b64encode(frame)+b'\n'); self.proc.stdin.flush()
        deadline = time.monotonic()+1.5
        while True:
            try:
                reply = self.frames.get(timeout=max(.001, deadline-time.monotonic()))
            except queue.Empty:
                raise TimeoutError('No USB ACK; request is not retried') from None
            if isinstance(reply, Exception):
                raise reply
            if struct.unpack_from('<I', reply, 12)[0] != self.seq:
                if time.monotonic() >= deadline:
                    raise TimeoutError('No matching USB ACK')
                continue
            expected_id = 2 if value is None else 3
            if struct.unpack_from('<HH', reply, 16) != (1, expected_id) or len(reply)<48:
                raise IOError('Unexpected reply source or command')
            status = struct.unpack_from('<I', reply, 40)[0]
            if status:
                raise IOError(f'Register {address:04x} rejected: status {status}')
            if value is not None:
                if len(reply)!=48:
                    raise IOError('Unexpected write response length')
                return
            if len(reply)!=56+4*count or struct.unpack_from('<II', reply, 44)!=(address,count):
                raise IOError('Unexpected read range')
            return list(struct.unpack_from('<'+'I'*count, reply, 52))

    def read(self, address, count=1):
        return self.command(address, count=count)

    def write(self, address, value):
        self.command(address, value)

    def snapshot(self):
        self.read(0x1044)  # latches all fields before reading the record
        p = self.read(0x1048, 7)
        return dict(ticks_per_second=p[0], seq=p[1], pps_tick=p[2]|(p[3]<<32),
                    utc_us=p[4]|(p[5]<<32), status=p[6],
                    calibrated=bool(p[6]&1), utc_valid=bool(p[6]&2))

    def close(self):
        self.proc.stdin.close()
        try:
            self.proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self.proc.terminate(); self.proc.wait(timeout=2)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bridge', type=Path, required=True)
    sub = parser.add_subparsers(dest='command')
    sub.add_parser('status');sub.add_parser('disable')
    move = sub.add_parser('move')
    move.add_argument('--steps', type=int, required=True, help='signed pulse count, absolute value 1..400')
    move.add_argument('--hz', type=int, default=100)
    anchor = sub.add_parser('anchor', help='epoch must be established from navigation timing evidence')
    anchor.add_argument('--seq', type=int, required=True)
    anchor.add_argument('--utc-seconds', type=int, required=True)
    args = parser.parse_args()
    if args.command == 'move' and (not 1<=abs(args.steps)<=400 or not 20<=args.hz<=400):
        parser.error('steps must be +/-1..400 and hz 20..400')
    if args.command == 'anchor' and (not 0<=args.seq<=0xffffffff or not 946684800<=args.utc_seconds<=0xffffffff):
        parser.error('anchor seconds/sequence outside uint32 or UTC range')
    usb = Usb(args.bridge)
    motor_armed = False
    try:
        if usb.read(0x6700)[0]!=0x00470200 or usb.read(0x1000)[0]!=0x00020200:
            raise IOError('Wrong integrated firmware revision')
        if args.command == 'move':
            # Explicit invocation authorizes this finite move. Nothing runs on
            # script import, status, USB reconnect, or heartbeat recovery.
            motor_armed=True
            usb.write(0x6704,0);usb.write(0x6738,1);usb.write(0x670c,0xffffffff)
            usb.write(0x6714,args.hz);usb.write(0x6710,args.steps)
            global_enabled=usb.read(4)[0]
            usb.write(4,global_enabled|1)
            usb.write(0x6738,1);usb.write(0x6704,1);usb.write(0x672c,1)
            deadline=time.monotonic()+abs(args.steps)/args.hz+5
            while True:
                usb.write(0x6738,1)
                status=usb.read(0x673c)[0]
                if status&8:
                    raise IOError('Motor watchdog fault; explicit recovery required')
                if not status&2:
                    if not status&4:
                        raise IOError('Move ended without completion')
                    break
                if time.monotonic()>deadline:
                    raise TimeoutError('Motion deadline exceeded')
                time.sleep(.1)
            print(json.dumps(dict(position_ticks=usb.read(0x6724)[0],completed_pulses=(status>>8)&0xffff)))
        elif args.command == 'disable':
            usb.write(0x6704,0)
        elif args.command == 'anchor':
            usb.write(0x1070,args.utc_seconds);usb.write(0x1074,args.seq);usb.write(0x1078,1)
            print(json.dumps(usb.snapshot()))
        else:
            print(json.dumps(dict(pps=usb.snapshot(), motor_core=hex(usb.read(0x673c)[0]),
                                  motor_position=usb.read(0x6724)[0]),indent=2))
    finally:
        try:
            if motor_armed:
                usb.write(0x6704,0)
        finally:
            usb.close()


if __name__ == '__main__':
    main()
