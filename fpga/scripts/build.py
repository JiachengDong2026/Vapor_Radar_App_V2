"""Fresh, isolated full implementation of the formal FPGA sources."""
import argparse, hashlib, json, os, subprocess, sys
from pathlib import Path

def snapshot(repo):
    return {p.relative_to(repo).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for folder in ('rtl', 'constraints', 'scripts')
            for p in sorted((repo/'fpga'/folder).rglob('*'))
            if p.is_file() and p.suffix in {'.v', '.vh', '.mem', '.xdc', '.tcl', '.py', '.json'}}

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--vivado',type=Path,required=True)
    a=ap.parse_args();repo=Path(__file__).resolve().parents[2];out=a.output.resolve()
    if out.is_relative_to(repo) or out==repo.parent or out in repo.parents:
        ap.error('Output must be an external build directory, not the repository or its ancestor')
    if out.exists(): ap.error('Use a new output directory; historical checkpoints are not reused')
    if not a.vivado.is_file(): ap.error('Vivado executable does not exist')
    before=snapshot(repo)
    if not before or not (repo/'fpga/scripts/run_full_build.tcl').is_file():
        ap.error('Build wrapper must be installed in the formal fpga/scripts directory')
    out.mkdir(parents=True)
    (out/'source_inputs.json').write_text(json.dumps(before,indent=2))
    env=os.environ.copy();env['VAPOR_BUILD_ROOT']=str(out);env['VAPOR_PYTHON']=sys.executable
    command=[str(a.vivado),'-mode','batch','-nojournal','-log',str(out/'build.log'),'-source',str(repo/'fpga/scripts/run_full_build.tcl')]
    proc=subprocess.run(command,cwd=out,env=env)
    after=snapshot(repo);changed=[p for p in before.keys()|after.keys() if before.get(p)!=after.get(p)]
    bit=out/'full_build/vapor_lidar_top.bit'
    log=(out/'build.log').read_text(errors='replace') if (out/'build.log').exists() else ''
    passed=proc.returncode==0 and not changed and bit.is_file() and 'FULL_SYSTEM_BUILD_PASS' in log and 'ERROR:' not in log
    result={'pass':passed,'cdc_review_required':True,'returncode':proc.returncode,'changed_inputs':sorted(changed),
            'bit':str(bit),'bit_sha256':hashlib.sha256(bit.read_bytes()).hexdigest() if bit.is_file() else None}
    (out/'build_result.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2))
    if not passed:raise SystemExit(1)
if __name__=='__main__':main()
