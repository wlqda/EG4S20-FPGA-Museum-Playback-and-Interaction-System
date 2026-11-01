"""Run current museum regressions and imported camera-core regressions separately."""
from pathlib import Path
import argparse,os,shutil,subprocess,re,json,hashlib,sys
ROOT=Path(__file__).resolve().parents[2]
BUILD=ROOT/'build';OUT=BUILD/'gesture_full'
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--vsim',default=os.environ.get('VSIM_EXE') or shutil.which('vsim'),
                    help='ModelSim executable (or VSIM_EXE/PATH)')
parser.add_argument('--timeout',type=int,default=600,help='maximum seconds per suite')
parser.add_argument('--previews',action='store_true',help='also generate and validate all 29 display scenes')
args=parser.parse_args()
if not args.vsim or not Path(args.vsim).is_file():
    parser.error('ModelSim not found; pass --vsim or set VSIM_EXE/PATH')
if args.timeout<=0: parser.error('--timeout must be positive')
VSIM=str(Path(args.vsim).resolve())
OUT.mkdir(parents=True,exist_ok=True)
required=[BUILD/n for n in ['real_wav_input.hex','real_wav_expected.hex','real_wav_sizes.hex',
                           'color_ui_update/IMG00011.hex']]
missing=[str(p) for p in required if not p.is_file()]
if missing: parser.error('Missing fixtures; run prepare_verification.py --materials <handoff>: '+', '.join(missing))
scripts=[*('sim/'+n+'.do' for n in ['run_idle_policy','run_home_alignment','run_gallery_ui','run_gallery_fat','run_gallery_zoom','run_gallery_render',
 'run_floating_clock','run_slide_switch','run_render_pipeline','run_status_rom','run_mount_regression','run_av_pcm_banks','run_image_read_pipeline','run_pcm_bank_mapping','run_bmp_skip_boundary','run_av_demux','run_shared_audio_index']),
 *('audio/sim/'+n+'.do' for n in ['run_narration','run_audio_ui','run_real_wav','run_narration_mbr']),
 *('camera/sim/'+n+'.do' for n in ['run_unified','run_camera_core','run_museum_overlay','run_full_switches','run_full_baseline_overlay'])]
scripts += ["camera/sim/run_source_health.do","camera/sim/run_prepare_stream.do","camera/sim/run_binary_denoise.do","camera/sim/run_filter_extraction.do","camera/sim/run_gesture_prepare.do","sim/run_gesture_footer.do"]
records={}
for script in scripts:
    result=subprocess.run([VSIM,'-c','-do','do ../'+script],cwd=BUILD,capture_output=True,text=True,errors='replace',timeout=args.timeout)
    log=result.stdout+result.stderr
    name=Path(script).stem;path=OUT/(name+'.log');path.write_text(log,encoding='utf-8')
    failures=re.findall(r'\*\* (?:Warning|Error|Fatal):|Errors: [1-9][0-9]*|Warnings: [1-9][0-9]*',log)
    if result.returncode or failures or 'PASS' not in log:raise RuntimeError(f'{script} failed; inspect {path}')
    records[name]={'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'pass_messages':re.findall(r'^# .*PASS.*$',log,re.M)}
    print('PASS',name,flush=True)
(OUT/'TEST_RESULTS.json').write_text(json.dumps(records,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('PASS ALL',len(records),'regression suites',flush=True)

if args.previews:
    subprocess.run([sys.executable,'-B',str(ROOT/'camera/tools/prepare_delivery_previews.py')],check=True)
    result=subprocess.run([VSIM,'-c','-do','do ../camera/sim/run_delivery_previews.do'],cwd=BUILD,capture_output=True,text=True,errors='replace',timeout=args.timeout)
    log=result.stdout+result.stderr
    (OUT/'delivery_previews.log').write_text(log,encoding='utf-8')
    if result.returncode:raise RuntimeError('Delivery display simulation failed')
    subprocess.run([sys.executable,'-B',str(ROOT/'camera/tools/validate_delivery_previews.py')],check=True)
