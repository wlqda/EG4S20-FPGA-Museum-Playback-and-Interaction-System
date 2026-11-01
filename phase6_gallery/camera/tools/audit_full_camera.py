"""Trace complete recognizer features to the uploaded active 3939bd6 sources."""
from pathlib import Path
import argparse,hashlib,json,os,re
ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline',type=Path,default=os.environ.get('GESTURE_BASELINE'),
                    help='3939bd6 project, snapshot, handoff directory or handoff repository (or GESTURE_BASELINE)')
args=parser.parse_args()
base=args.baseline or ROOT.parent/'handoff/gesture_3939bd6'
choices=[base,base/'source/phase6_gallery',base/'gesture_3939bd6/source/phase6_gallery',
         base/'handoff/gesture_3939bd6/source/phase6_gallery']
BASE=next((p.resolve() for p in choices if (p/'camera/rtl/camera_gesture_engine.v').is_file()),None)
if BASE is None:
    parser.error(f'3939bd6 source not found under {base}; pass --baseline explicitly')
OUT=ROOT/'build/gesture_full'
OUT.mkdir(parents=True,exist_ok=True)
names=['camera_sccb_master','camera_config_rom','camera_config_controller','camera_dvp_capture','camera_dvp_auto_monitor',
 'camera_source_stream','camera_hand_candidate','camera_foreground_debug','camera_foreground_overlay','camera_palm_regions',
 'camera_candidate_track','camera_swipe_tracker','camera_nav_adapter','camera_telemetry_uart']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
records=[]
reference=json.loads((ROOT/'integration_validation/full_camera_20261027/FULL_FEATURE_AUDIT.json').read_text(encoding='utf-8'))
expected={r['path']:r['uploaded_sha256'] for r in reference['algorithm_sources']}
changes={'camera_source_stream':'Keep FIFO draining and preview live during preparation; only complete post-prepare frames wait for analysis', 'camera_foreground_debug':'Inherited FILTER5 binary mask stage from 1257888', 'camera_swipe_tracker':'Five-frame acquisition, bounded step/span, final stable origin'}
for n in names:
    rel=f'camera/rtl/{n}.v';a=sha(ROOT/rel);b=sha(BASE/rel);assert b==expected[rel],rel
    if n not in changes:assert a==b,rel
    records.append({'path':rel,'uploaded_sha256':b,'current_sha256':a,'unchanged':a==b,'change':changes.get(n,'none')})
old=(BASE/'camera/rtl/camera_gesture_engine.v').read_text(encoding='utf-8')
new=(ROOT/'camera/rtl/camera_gesture_engine.v').read_text(encoding='utf-8')
assert old.split('module camera_selection_reference',1)[1]==new.split('module camera_selection_reference',1)[1]
def params(s):
    s=re.search(r'camera_foreground_debug\s*#\((.*?)\)\s*extraction\(',s,re.S)[1]
    s=re.sub(r'\.BACKGROUND_RAM_STYLE\("[^"]+"\),?','',s)
    s=re.sub(r'\.ROI_Y[01]\(ROI_Y[01]\),?','',s)
    s=re.sub(r'\.BINARY_FILTER\(5\),?','',s)
    return re.sub(r'\s+','',s).strip(',')
assert params(old)==params(new)
assert "ROI_Y0=16,ROI_Y1=464" in new
assert ".ROI_Y0(ROI_Y0),.ROI_Y1(ROI_Y1)" in new
features=['Original DVP/SCCB and 80x60 analysis geometry retained', 'FILTER5 mask processing with preparation-safe source stream', 'Five-frame central stabilization, endpoint directional decision retained', '128x112 mirrored ROI preview with independent diagnostic selection', 'Chinese synchronous ROM status and per-page footer', '73-byte G1 telemetry K distinguishes source fault and navigation overflow', 'Independent SW1 clock / SW2 preview / SW3 gesture / SW4 autoplay']
report={'uploaded_commit':'3939bd6c0f48240471b4a0f2f9748de63e1ea326','algorithm_sources':records,
 'identity_reference_unchanged':True,'modified_algorithms':changes,'extraction_parameters_unchanged_except_ram_mapping_vertical_roi_and_filter5':True,'vertical_roi':[16,464],'features':features,
 'integration_changes':['ROI [64,576) x [16,464), displayed at 128x112 without padding', 'Preparation drains FIFO, resets analysis until next fresh frame, retains live preview', 'Explicit KEY4 diagnostics only; SW2 independent', 'Compact synchronous Chinese glyph ROMs and three footer groups', 'Five-frame stable acquisition; commit origin after stability', 'Status separates source fault, navigation overflow and edge rejection']}
(OUT/'FULL_FEATURE_AUDIT.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('PASS source provenance:',sum(r['unchanged'] for r in records),'unchanged sources; three documented modifications; baseline hashes verified')
