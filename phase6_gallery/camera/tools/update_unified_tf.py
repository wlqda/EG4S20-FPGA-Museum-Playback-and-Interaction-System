"""Guarded update of the already-authorized G: MUSEUM card, with F: backups."""
from pathlib import Path
import argparse,hashlib,json,subprocess,shutil,datetime
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/gesture_unified'
parser=argparse.ArgumentParser();parser.add_argument('--apply',action='store_true');args=parser.parse_args()
card=Path('G:/').resolve();assert card==Path('G:/').resolve()
volume=json.loads(subprocess.check_output(['powershell','-NoProfile','-Command',
 '(Get-Volume -DriveLetter G | Select-Object DriveLetter,FileSystemLabel,FileSystem,Size | ConvertTo-Json -Compress)'],text=True))
assert volume['FileSystemLabel']=='MUSEUM' and volume['FileSystem']=='FAT32' and 8e9<volume['Size']<32e9,volume
baseline=json.loads((ROOT/'INTEGRATION_RELEASE_MANIFEST.json').read_text(encoding='utf-8'))
color=json.loads((ROOT/'build/color_ui_update/COLOR_UI_MANIFEST.json').read_text(encoding='utf-8'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
current={};unexpected=[]
for name,expected in baseline['tf_files'].items():
    assert Path(name).name==name
    p=card/name
    if not p.is_file():unexpected.append(name+': missing');continue
    current[name]=sha(p)
    allowed={expected}
    if name in color['tf_files']:allowed.add(color['tf_files'][name])
    if current[name] not in allowed:unexpected.append(name+': unknown contents')
audit={'volume':volume,'baseline':baseline['version'],'files':current,'unexpected':unexpected,'applied':False}
(OUT/'CARD_PREFLIGHT.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert not unexpected,unexpected
print('PASS card preflight:',len(current),'known files on G: MUSEUM',flush=True)
if args.apply:
    release=ROOT/'build/museum_unified_gesture_20261027_v1'
    manifest=json.loads((release/'RELEASE_MANIFEST.json').read_text(encoding='utf-8'))
    assert manifest['board_verified'] is False
    changed=[n for n,h in manifest['tf_files'].items() if current.get(n)!=h]
    assert set(changed)<=set(color['tf_files']),changed
    backup=OUT/('tf_backup_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'));backup.mkdir()
    for name in changed:
        source=release/'TF_CARD'/name
        assert sha(source)==manifest['tf_files'][name]
        shutil.copy2(card/name,backup/name)
        shutil.copy2(source,card/name)
    verified={name:sha(card/name) for name in manifest['tf_files']}
    assert verified==manifest['tf_files']
    audit.update(applied=True,changed=changed,backup=backup.as_posix(),verified=verified)
    (OUT/'TF_WRITE_VERIFICATION.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('PASS card update:',len(changed),'replacements;',len(verified),'hashes verified; backup',backup,flush=True)
