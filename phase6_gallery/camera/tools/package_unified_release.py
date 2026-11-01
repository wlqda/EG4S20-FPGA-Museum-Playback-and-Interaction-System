"""Package only a timing-signed, source-matched unified bit with exact TF assets."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import hashlib,json,re,shutil,zipfile,subprocess
ROOT=Path(__file__).resolve().parents[2];BUILD=ROOT/'build';OUT=BUILD/'gesture_unified'
VERSION='museum_unified_gesture_20261027_v1';RELEASE=BUILD/VERSION
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
inputs=json.loads((OUT/'BUILD_INPUTS.json').read_text(encoding='utf-8'))
for name,h in inputs.items():assert sha(ROOT/name)==h,('source changed since synthesis',name)
status=(OUT/'final.ts').read_text(encoding='utf-8')
for label in ['SWNS','HWNS']:
    value=re.search(label+r':\s*([+-]?[\d.]+)ns',status)[1]
    assert not value.startswith('-') and float(value)>=0
assert 'PASS ORIGINAL-SDC SIGNOFF' in (OUT/'signoff.log').read_text(encoding='utf-8',errors='replace')
tests={}
for name in ['gallery_ui','gallery_fat','gallery_zoom','gallery_render','floating_clock','slide_switch','render_pipeline',
 'status_rom','mount_regression','av_pcm_banks','image_read_pipeline','narration','audio_ui','real_wav','narration_mbr',
 'unified','camera_core','museum_overlay','unified_previews']:
    p=OUT/f'run_{name}.log';log=p.read_text(encoding='utf-8',errors='replace')
    assert 'PASS' in log and not re.search(r'\*\* (?:Error|Fatal):|Errors: [1-9]|Warnings: [1-9]',log),name
    tests[name]={'sha256':sha(p),'pass_messages':re.findall(r'^# .*PASS.*$',log,re.M)}
bit=OUT/'museum_phase6_gallery.bit';assert bit.is_file() and bit.stat().st_mtime>(OUT/'museum_phase6_gallery_pr.db').stat().st_mtime
RELEASE.mkdir(exist_ok=True);card=RELEASE/'TF_CARD';card.mkdir(exist_ok=True)
tf={}
for p in sorted((BUILD/'TF_CARD').iterdir()):
    if not p.is_file():continue
    color=BUILD/'color_ui_update/TF_CARD'/p.name
    source=color if color.is_file() else p
    shutil.copy2(source,card/p.name);tf[p.name]=sha(source)
for i in range(1,30):
    im=Image.open(card/f'IMG{i:05d}.BMP');assert im.size==(640,480) and im.mode=='RGB'
shutil.copy2(bit,RELEASE/'museum_phase6_unified.bit')
area=(OUT/'final.area').read_text(encoding='utf-8')
resources={name:int(re.search(r'^\s*#'+name+r'\s+(\d+)',area,re.M)[1]) for name in ['lut','reg','bram9k','bram32k','dsp']}
assert resources['lut']<=19600 and resources['bram9k']<=64 and resources['bram32k']<=16
commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
manifest={'version':VERSION,'source_commit':commit,'bit_sha256':sha(bit),'timing':status,'resources':resources,
 'build_inputs':inputs,'tests':tests,'tf_files':tf,'board_verified':False,
 'camera_baseline':'3939bd6c0f48240471b4a0f2f9748de63e1ea326'}
(RELEASE/'RELEASE_MANIFEST.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
shutil.copy2(ROOT/'camera/INTEGRATION.md',RELEASE/'INTEGRATION.md')
notes='''统一展示与手势控制版：离线验证交付，尚未实板验证。
下载museum_phase6_unified.bit至FPGA SRAM；本流程未烧Flash。
TF_CARD为完整配套资源。已有原2026-10-26 V3卡时，只需使用更新包替换八张BMP并下载新bit。
摄像头沿用3939bd6的JP1反向排线引脚，不适用于其它接线方式。
正常KEY2/3/4操作保持；KEY2+KEY3同时长按约1秒切换维护模式。
维护模式KEY2采空背景、KEY3重启跟踪、KEY4开关预览；离开维护后在中央停稳等CAM ARMED再滑动。
左右选择、下进入、上返回。轮播下滑进入首页。SW4仍控制轮播。
详细操作及验证边界见INTEGRATION.md，精确资源/bit哈希见RELEASE_MANIFEST.json。
'''
(RELEASE/'START_HERE.txt').write_text(notes,encoding='utf-8')
for name in ['normal','maintenance']:
    Image.open(OUT/(name+'.ppm')).save(RELEASE/(name+'.png'))
preview=Image.new('RGB',(1328,544),'#e5dfd3');d=ImageDraw.Draw(preview);font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',17)
for i,(name,title) in enumerate([('normal','正常观展 · 摄像头状态叠层仿真'),('maintenance','维护模式 · 合成测试图，非摄像头实拍')]):
    d.text((16+i*656,12),title,font=font,fill='#343d38');preview.paste(Image.open(RELEASE/(name+'.png')),(16+i*656,48))
preview.save(RELEASE/'overlay_preview.png')
preview_dir=RELEASE/'PREVIEWS';preview_dir.mkdir(exist_ok=True)
for p in (OUT/'preview').iterdir():
    if p.suffix in ['.png','.html','.json']:shutil.copy2(p,preview_dir/p.name)
for name in ['final.ts','final.timing','final.area','final.exceptions','signoff.log','physical_build.log','BUILD_INPUTS.json']:
    shutil.copy2(OUT/name,RELEASE/name)
full=BUILD/(VERSION+'.zip')
with zipfile.ZipFile(full,'w',zipfile.ZIP_DEFLATED,compresslevel=1) as z:
    for p in sorted(RELEASE.rglob('*')):
        if p.is_file():z.write(p,p.relative_to(RELEASE).as_posix())
update=BUILD/(VERSION+'_update.zip')
with zipfile.ZipFile(update,'w',zipfile.ZIP_DEFLATED,compresslevel=1) as z:
    for n in ['museum_phase6_unified.bit','RELEASE_MANIFEST.json','INTEGRATION.md','START_HERE.txt','overlay_preview.png']:z.write(RELEASE/n,n)
    for i in range(7,15):z.write(card/f'IMG{i:05d}.BMP',f'TF_CARD/IMG{i:05d}.BMP')
for p in [full,update]:
    with zipfile.ZipFile(p) as z:assert z.testzip() is None
    print(p,sha(p))
