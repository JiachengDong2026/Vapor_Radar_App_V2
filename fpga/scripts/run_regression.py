"""Run formal RTL testbenches using the installed Vivado simulator."""
import argparse, json, os, shutil, subprocess, time
from pathlib import Path

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--repo',type=Path,default=Path(__file__).resolve().parents[2])
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--vivado-bin',type=Path,required=True)
    ap.add_argument('tests',nargs='*')
    a=ap.parse_args(); repo=a.repo.resolve(); root=repo/'fpga'; output=a.output.resolve()
    if output.is_relative_to(repo) or output in repo.parents:
        ap.error('Regression output must be outside the repository and its ancestors')
    if output.exists(): ap.error('Use a new regression output directory')
    if not (root/'scripts/sources.json').is_file(): ap.error('Not a formal FPGA repository')
    output.mkdir(parents=True)
    sources=[root/p for p in json.loads((root/'scripts/sources.json').read_text())['rtl']]
    models=list((root/'sim').glob('*/models/*.v'))+list((root/'sim/common').glob('*.v'))
    tests={p.stem:p for p in (root/'tests').glob('*/tb_*.v')}
    selected=a.tests or sorted(tests)
    unknown=set(selected)-tests.keys()
    if unknown: ap.error('Unknown tests: '+', '.join(sorted(unknown)))
    work=output/'work';work.mkdir(exist_ok=True)
    for f in [root/'rtl/wms/sine_q31.mem']+list((root/'sim').glob('*/vectors/*')):
        if f.is_file():shutil.copyfile(f,work/f.name)
    inc=[root/'rtl/include',root/'rtl/adc',root/'rtl/dila',root/'sim/system/vectors']
    glbl=a.vivado_bin.parent/'data/verilog/src/glbl.v'
    def run(tool,args,log,timeout=3600):
        cmd=[str(a.vivado_bin/(tool+('.bat' if os.name=='nt' else '')))]+list(map(str,args))
        with log.open('w',encoding='utf8') as fp:
            proc=subprocess.run(cmd,cwd=work,stdout=fp,stderr=subprocess.STDOUT,timeout=timeout)
        text=log.read_text(encoding='utf8',errors='replace')
        if proc.returncode or 'ERROR:' in text or 'Fatal:' in text or 'FATAL:' in text:
            raise RuntimeError(str(log)+'\n'+text[-3500:])
        return text
    flags=[]
    for d in inc: flags += ['-i',d]
    project=work/'sources.prj'
    project.write_text(''.join('verilog work '+chr(34)+str(f).replace(chr(92),'/')+chr(34)+'\n' for f in sources+models+[tests[n] for n in selected]+[glbl]))
    run('xvlog',flags+['-prj',project],output/'compile.log')
    results=[]
    for name in selected:
        started=time.time()
        try:
            run('xelab',[name,'glbl','-mt','4','-L','unisims_ver','-timescale','1ns/1ps','-s',name+'_sim'],output/(name+'_elab.log'))
            text=run('xsim',[name+'_sim','-runall'],output/(name+'.log'))
            if 'PASS' not in text or '$finish called at time' not in text:
                raise RuntimeError('Missing PASS or normal testbench completion: '+name)
            item={'test':name,'pass':True,'seconds':round(time.time()-started,2)}
        except Exception as e:
            item={'test':name,'pass':False,'error':str(e),'seconds':round(time.time()-started,2)}
        results.append(item);(output/'results.json').write_text(json.dumps(results,indent=2))
        print(json.dumps(item),flush=True)
    if not all(x['pass'] for x in results):raise SystemExit(1)
    print('FORMAL_REGRESSION_PASS count='+str(len(results)))
if __name__=='__main__':main()
