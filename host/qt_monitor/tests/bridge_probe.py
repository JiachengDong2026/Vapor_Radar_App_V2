"""Read-only IPC/USB probe: READ_REG two module identities, never writes hardware."""
from pathlib import Path
import argparse, base64, json, struct, subprocess, threading, time, zlib
cli = argparse.ArgumentParser(description=__doc__)
cli.add_argument('--bridge', type=Path, required=True)
cli.add_argument('--output', type=Path, required=True)
args = cli.parse_args()
repo = Path(__file__).resolve().parents[3]
output = args.output.resolve()
if output == repo or repo in output.parents:
    cli.error('Output must be outside the formal repository')
if not args.bridge.is_file():
    cli.error('Bridge executable not found')
output.mkdir(parents=True, exist_ok=False)
p = subprocess.Popen([str(args.bridge.resolve())], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
raw = bytearray(); logs = []
def reader():
    while True:
        b = p.stdout.read(1024)
        if not b: break
        raw.extend(b)
def logger():
    for line in p.stderr: logs.append(line.decode(errors='replace').strip())
t=threading.Thread(target=reader);e=threading.Thread(target=logger);t.start();e.start()
time.sleep(.5)
for seq, addr in [(200001,0x4000),(200002,0x4100)]:
    b = bytearray(52)
    struct.pack_into('<4sBBBBIIHHIQII',b,0,b'VLP1',1,0,1,10,52,seq,1,2,0,0,0,8)
    struct.pack_into('<IHH',b,40,addr,1,0)
    struct.pack_into('<I',b,48,zlib.crc32(b[:48]))
    p.stdin.write(base64.b64encode(b)+b'\n');p.stdin.flush();time.sleep(1)
p.stdin.close()
try: p.wait(timeout=3)
except subprocess.TimeoutExpired: p.kill();p.wait()
t.join();e.join()
(output/'bridge_probe.bin').write_bytes(raw)
(output/'bridge_probe.json').write_text(json.dumps(dict(logs=logs,bytes=len(raw),returncode=p.returncode),indent=2))
print(json.dumps(dict(logs=logs,bytes=len(raw),returncode=p.returncode),indent=2))
