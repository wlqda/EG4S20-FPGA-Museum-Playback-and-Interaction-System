"""Prepare clean-clone verification inputs without TD, a video stream or asset regeneration."""
from pathlib import Path
import argparse,hashlib,json,shutil,struct,subprocess,sys,wave
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--materials',type=Path,required=True,
                    help='handoff repository, handoff directory, audio_visualization package or TF_CARD')
args=parser.parse_args()
choices=[args.materials,args.materials/'TF_CARD',args.materials/'audio_visualization/TF_CARD',
         args.materials/'handoff/audio_visualization/TF_CARD']
card=next((p.resolve() for p in choices if (p/'AUDIO_MANIFEST.json').is_file()),None)
if card is None: parser.error('TF_CARD/AUDIO_MANIFEST.json not found under --materials')
manifest=json.loads((card/'AUDIO_MANIFEST.json').read_text(encoding='utf-8-sig'))
expected={r['file']:r['sha256'] for r in manifest['tracks']}
build=ROOT/'build'
out=build/'narration/TF_CARD'
tracks=[]
for i in range(1,5):
    name=f'AUD{i:05d}.WAV';source=card/name
    digest=hashlib.sha256(source.read_bytes()).hexdigest()
    if digest!=expected[name]: raise ValueError(f'WAV hash mismatch: {source}')
    with wave.open(str(source),'rb') as wav:
        if (wav.getnchannels(),wav.getsampwidth(),wav.getframerate(),wav.getcomptype())!=(1,2,48000,'NONE'):
            raise ValueError(f'Unsupported PCM format: {source}')
        frames=wav.getnframes()
        if frames<49536 or len(wav.readframes(frames))!=2*frames:
            raise ValueError(f'Truncated or insufficient PCM for fixtures: {source}')
    dest=out/name
    if dest.exists() and hashlib.sha256(dest.read_bytes()).hexdigest()!=digest:
        raise FileExistsError(f'Preserve existing unequal WAV: {dest}; use a new worktree')
    tracks.append({'file':name,'sha256':digest})
# Validate everything before writing, and never overwrite unequal source assets.
out.mkdir(parents=True,exist_ok=True)
for track in tracks:
    dest=out/track['file']
    if not dest.exists(): shutil.copy2(card/track['file'],dest)
for folder in ['gesture_full','gesture_unified','v3_preview','color_ui_update']:
    (build/folder).mkdir(parents=True,exist_ok=True)
subprocess.run([sys.executable,'-B',str(ROOT/'audio/tools/prepare_sim_fixtures.py')],check=True)
for i,track in enumerate(tracks):
    with wave.open(str(out/track['file']),'rb') as wav:
        wav.setpos(48000)
        samples=struct.unpack('<1536h',wav.readframes(1536))
    (build/f'v3_preview/wave_{i}.hex').write_text(
        ''.join(f'{(v<<8)&0xffffff:06x}\n' for v in samples),encoding='ascii')
page=ROOT/'assets/ui_v3/pages/IMG00011.png'
with Image.open(page) as image:
    image=image.convert('RGB')
    if image.size!=(640,480): raise ValueError(f'Invalid page size: {page}')
    pixels=image.get_flattened_data() if hasattr(image,'get_flattened_data') else image.getdata()
    (build/'color_ui_update/IMG00011.hex').write_text(
        ''.join(f'{r:02x}{g:02x}{b:02x}\n' for r,g,b in pixels),encoding='ascii')
(build/'gesture_full/FIXTURE_INPUTS.json').write_text(json.dumps({
    'kind':'simulation fixtures only; not a complete media card',
    'tracks':tracks,'overlay_page':{'path':page.relative_to(ROOT).as_posix(),
    'sha256':hashlib.sha256(page.read_bytes()).hexdigest()},
    'video_required':False},indent=2)+'\n',encoding='utf-8')
print('PASS verification fixtures: four hash-checked real WAVs, PCM excerpts and current museum page; no TD/video needed')

home=ROOT/'assets/ui_reference/pages/IMG00005.png'
with Image.open(home) as image:
    image=image.convert('RGB')
    assert image.size==(640,480)
    pixels=image.get_flattened_data() if hasattr(image,'get_flattened_data') else image.getdata()
    (build/'gesture_full/home_background.hex').write_text(''.join(f'{r:02x}{g:02x}{b:02x}\n' for r,g,b in pixels),encoding='ascii')

(build/'home_preview.hex').write_bytes((build/'gesture_full/home_background.hex').read_bytes())
