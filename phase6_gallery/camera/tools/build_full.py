"""Measure complete uploaded camera functionality before proceeding to P&R."""
from pathlib import Path
import argparse,subprocess,re,json,hashlib,os,shutil
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/gesture_full'
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--resource-only',action='store_true')
p.add_argument('--resume',action='store_true')
p.add_argument('--seed',type=int,default=43,help='physical placement seed (recorded with generated Tcl)')
p.add_argument('--td',default=os.environ.get('TD_EXE') or shutil.which('td_commands_prompt'),
               help='TD6.2 executable on the captain machine (or TD_EXE/PATH)')
a=p.parse_args()
if not a.td or not Path(a.td).is_file():
    p.error('TD compiler not found; the captain must pass --td or set TD_EXE/PATH')
TD=str(Path(a.td).resolve())
OUT.mkdir(parents=True,exist_ok=True)
full=(ROOT/'camera/tools/build_unified.tcl').read_text(encoding='utf-8')
split=full.index('set original [open')
gate=full[:split]+'''puts "PASS COMPLETE-CAMERA GATE"
} err]} {puts stderr "GATE FAILED: $err";exit 1}
exit 0
'''
physical='''if {[catch {
cd [file normalize [file join [file dirname [info script]] ../..]]
import_device eagle_s20.db -package EG4S20BG256
import_db build/gesture_full/museum_phase6_gallery_gate.db
'''+full[split:]
physical=re.sub(r'set_param place seed \d+',f'set_param place seed {a.seed}',physical)
(OUT/'gate_only.tcl').write_text(gate,encoding='utf-8');(OUT/'physical_only.tcl').write_text(physical,encoding='utf-8')
(OUT/'PHYSICAL_INPUTS.json').write_text(json.dumps({'seed':a.seed,'td_executable':TD,
 'physical_tcl_sha256':hashlib.sha256((OUT/'physical_only.tcl').read_bytes()).hexdigest()},indent=2)+'\n',encoding='utf-8')
def run(script,log,marker):
    with (OUT/log).open('w',encoding='utf-8') as f:
        r=subprocess.run([TD,(OUT/script).as_posix()],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
    s=(OUT/log).read_text(encoding='utf-8',errors='replace')
    if r.returncode or marker not in s:raise RuntimeError('TD failed: '+str(OUT/log))
if not a.resume:run('gate_only.tcl','gate_build.log','PASS COMPLETE-CAMERA GATE')
inputs=json.loads((OUT/'BUILD_INPUTS.json').read_text(encoding='utf-8'))
for name,h in inputs.items():assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==h,name
area=(OUT/'gate.area').read_text(encoding='utf-8')
limits={'lut':19600,'reg':19600,'bram9k':64,'bram32k':16,'dsp':29}
resources={n:int(re.search(r'^\s*#'+n+r'\s+(\d+)',area,re.M)[1]) for n in limits}
fits=all(resources[n]<=limit for n,limit in limits.items())
(OUT/'RESOURCE_ASSESSMENT.json').write_text(json.dumps({'kind':'post-gate estimate; final placement/timing still required','resources':resources,'limits':limits,'fits':fits},indent=2)+'\n',encoding='utf-8')
for n,limit in limits.items():assert resources[n]<=limit,(n,resources[n],limit)
print('PASS COMPLETE-CAMERA RESOURCE CAPACITY:',resources,flush=True)
if a.resource_only:raise SystemExit(0)
run('physical_only.tcl','physical_build.log','PASS PHYSICAL IMPLEMENTATION')
with (OUT/'signoff.log').open('w',encoding='utf-8') as f:
    r=subprocess.run([TD,(ROOT/'camera/tools/signoff_unified.tcl').as_posix()],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
assert r.returncode==0 and 'PASS ORIGINAL-SDC SIGNOFF' in (OUT/'signoff.log').read_text(encoding='utf-8',errors='replace'),'Independent signoff failed'
print('PASS complete camera, physical implementation and original-SDC signoff',flush=True)
