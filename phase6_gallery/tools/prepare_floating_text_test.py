"""Prepare frozen floating-text test fixtures; no system font is required."""
from pathlib import Path
import json
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/text_validation'
OUT.mkdir(parents=True,exist_ok=True)
asset=json.loads((ROOT/'assets/floating_text/glyph_columns.json').read_text(encoding='utf-8'))
(OUT/'columns.hex').write_text(''.join(f'{v:06x}\n' for v in asset['columns']),encoding='ascii')
with Image.open(ROOT/'assets/ui_reference/pages/IMG00005.png') as page:
 page=page.convert('RGB')
 pixels=page.get_flattened_data() if hasattr(page,'get_flattened_data') else page.getdata()
 (OUT/'home.hex').write_text(''.join(f'{r:02x}{g:02x}{b:02x}\n' for r,g,b in pixels),encoding='ascii')
print('Prepared frozen text/home simulation fixtures:',OUT)
