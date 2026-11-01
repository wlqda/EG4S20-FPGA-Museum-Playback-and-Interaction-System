"""Prepare a bitmap-only color update, leaving the verified V3 card set intact."""
from pathlib import Path
from PIL import Image
import hashlib, json, shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/color_ui_update'
OUT.mkdir(parents=True, exist_ok=True)
CARD = OUT / 'TF_CARD'
CARD.mkdir(exist_ok=True)
baseline = json.loads((ROOT / 'INTEGRATION_RELEASE_MANIFEST.json').read_text(encoding='utf-8'))
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
records = {}
for i in range(5, 30):
    name = f'IMG{i:05d}'
    source = ROOT / 'assets/ui_v3/pages' / (name + '.png')
    im = Image.open(source).convert('RGB')
    assert im.size == (640, 480)
    if 7 <= i <= 14:
        target = CARD / (name + '.BMP')
        im.save(target, format='BMP')
        records[target.name] = sha(target)
        (OUT / (name + '.hex')).write_text(''.join(f'{r:02x}{g:02x}{b:02x}\n' for r,g,b in im.getdata()), encoding='ascii')
        # The live PCM window must stay on continuous unpainted paper.
        if i >= 11:
            assert all(im.getpixel((x,y)) == (244,238,228) for y in range(276,352) for x in range(336,528))
    else:
        original = Image.open(ROOT / 'build/TF_CARD' / (name + '.BMP')).convert('RGB')
        assert im.tobytes() == original.tobytes(), f'Unrelated page changed: {name}'
for i in range(4):
    shutil.copy2(ROOT / f'build/v3_preview/wave_{i}.hex', OUT / f'wave_{i}.hex')
bench = (ROOT / 'sim/tb_v3_previews.v').read_text(encoding='utf-8')
bench = bench.replace('idx=5;idx<=29', 'idx=7;idx<=14').replace('v3_preview/', 'color_ui_update/')
bench = bench.replace('25 pages, 7680000', '8 pages, 2457600')
(OUT / 'tb_color_ui.v').write_text(bench, encoding='utf-8')
manifest = {'kind':'bitmap-only color update; no hardware changes',
            'baseline_version':baseline['version'], 'compatible_bit_sha256':baseline['bit_sha256'],
            'tf_files':records, 'unchanged_other_pages':17,
            'limitations':['Common vermilion live PCM waveform retained', 'No fabricated playback duration or progress', 'Not board verified']}
(OUT / 'COLOR_UI_MANIFEST.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n', encoding='utf-8')
print('PASS: 8 color BMPs; 17 unrelated pages unchanged; PCM background continuous; no RTL changes')
