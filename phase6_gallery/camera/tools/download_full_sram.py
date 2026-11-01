"""Download the checked full-camera bit to FPGA SRAM after explicit user authorization."""
from pathlib import Path
import hashlib,json,re,datetime,shutil,subprocess
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/gesture_full';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
inputs=json.loads((OUT/'BUILD_INPUTS.json').read_text(encoding='utf-8'))
for n,h in inputs.items():assert sha(ROOT/n)==h,('source changed',n)
s=(OUT/'final.ts').read_text(encoding='utf-8')
for label in ['SWNS','HWNS']:
    v=re.search(label+r':\s*([+-]?[\d.]+)ns',s)[1];assert not v.startswith('-') and float(v)>=0
assert 'PASS ORIGINAL-SDC SIGNOFF' in (OUT/'signoff.log').read_text(encoding='utf-8',errors='replace')
audit=json.loads((OUT/'FULL_FEATURE_AUDIT.json').read_text(encoding='utf-8'));assert all(x['unchanged'] for x in audit['algorithm_sources'])
tests=json.loads((OUT/'TEST_RESULTS.json').read_text(encoding='utf-8'));assert len(tests)>=25
for name,record in tests.items():
    p=OUT/(name+'.log');assert sha(p)==record['sha256'],name
    log=p.read_text(encoding='utf-8',errors='replace');assert not re.search(r'\*\* (?:Error|Fatal):|Errors: [1-9]|Warnings: [1-9]',log)
cycle=OUT/('board_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'));cycle.mkdir()
source=OUT/'museum_phase6_gallery.bit';bit=cycle/'firmware.bit';shutil.copy2(source,bit);fingerprint=sha(bit)
script='''if {[catch {
import_device eagle_s20.db -package EG4S20BG256
download -bit {%s}
puts "PASS FULL CAMERA JTAG SRAM DOWNLOAD"
} failure]} {puts stderr "FULL CAMERA SRAM DOWNLOAD FAILED: $failure";exit 1}
exit 0
'''%bit.as_posix()
(cycle/'download.tcl').write_text(script,encoding='utf-8')
with (cycle/'download.log').open('w',encoding='utf-8') as stream:
    result=subprocess.run(['D:/anlogic/bin/td_commands_prompt.exe',(cycle/'download.tcl').as_posix()],cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
log=(cycle/'download.log').read_text(encoding='utf-8',errors='replace')
ok=result.returncode==0 and 'PASS FULL CAMERA JTAG SRAM DOWNLOAD' in log and 'Chip validation success: EG4S20BG256' in log
record={'kind':'volatile FPGA SRAM configuration','success':ok,'bit_sha256':fingerprint,'cycle':cycle.as_posix(),
 'timing':s,'functional_board_test':False,'download_log_sha256':sha(cycle/'download.log')}
(cycle/'RESULT.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(OUT/'BOARD_DOWNLOAD_RESULT.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert ok,'Download failed; inspect '+str(cycle/'download.log')
print('PASS actual JTAG SRAM download:',fingerprint,'log',cycle/'download.log',flush=True)
