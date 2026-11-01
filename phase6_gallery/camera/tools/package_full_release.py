"""Publish the complete uploaded gesture pipeline, switches and SRAM evidence."""
from pathlib import Path
from PIL import Image
import hashlib,json,re,shutil,subprocess,zipfile
ROOT=Path(__file__).resolve().parents[2];BUILD=ROOT/'build';OUT=BUILD/'gesture_full'
VERSION='museum_full_camera_switches_20261028_v2';RELEASE=BUILD/VERSION
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
inputs=json.loads((OUT/'BUILD_INPUTS.json').read_text(encoding='utf-8'))
for n,h in inputs.items():assert sha(ROOT/n)==h,('compiled source changed',n)
timing=(OUT/'final.ts').read_text(encoding='utf-8')
for label in ['SWNS','HWNS']:
    s=re.search(label+r':\s*([+-]?[\d.]+)ns',timing)[1];assert not s.startswith('-') and float(s)>=0
assert 'PASS ORIGINAL-SDC SIGNOFF' in (OUT/'signoff.log').read_text(encoding='utf-8',errors='replace')
tests=json.loads((OUT/'TEST_RESULTS.json').read_text(encoding='utf-8'));assert len(tests)>=25
for n,r in tests.items():assert sha(OUT/(n+'.log'))==r['sha256'],n
audit=json.loads((OUT/'FULL_FEATURE_AUDIT.json').read_text(encoding='utf-8'));assert len(audit['algorithm_sources'])==14
board=json.loads((OUT/'BOARD_DOWNLOAD_RESULT.json').read_text(encoding='utf-8'));assert board['success']
bit=OUT/'museum_phase6_gallery.bit';assert sha(bit)==board['bit_sha256']
RELEASE.mkdir(exist_ok=True);card=RELEASE/'TF_CARD';card.mkdir(exist_ok=True)
tf={}
for p in sorted((BUILD/'TF_CARD').iterdir()):
    if not p.is_file():continue
    color=BUILD/'color_ui_update/TF_CARD'/p.name;source=color if color.is_file() else p
    shutil.copy2(source,card/p.name);tf[p.name]=sha(source)
for i in range(1,30):
    im=Image.open(card/f'IMG{i:05d}.BMP');assert im.size==(640,480) and im.mode=='RGB'
shutil.copy2(bit,RELEASE/'museum_phase6_full_camera.bit')
area=(OUT/'final.area').read_text(encoding='utf-8')
resources={n:int(re.search(r'^\s*#'+n+r'\s+(\d+)',area,re.M)[1]) for n in ['lut','reg','bram9k','bram32k','dsp']}
assert resources['lut']<=19600 and resources['bram9k']<=64 and resources['bram32k']<=16
commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
manifest={'version':VERSION,'source_commit':commit,'build_inputs':inputs,'bit_sha256':sha(bit),'timing':timing,
 'resources':resources,'tests':tests,'full_feature_audit':audit,'board_download':board,'functional_board_test':False,
 'switches':{'SW2':{'pin':'C7','role':'camera RGB inset'},'SW3':{'pin':'C6','role':'gesture tracker and navigation enable'},
             'SW4':{'pin':'C5','role':'gallery autoplay'}},'tf_files':tf}
(RELEASE/'RELEASE_MANIFEST.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
notes='''完整摄像头手势统一版（SRAM JTAG已下载；识别效果待人工实板确认）

SW3开启/关闭手势；SW2独立开启/关闭原版160×120镜像视频小窗；SW4仍控制自动轮播。
识别原版14份核心源码逐字节保留，保留原80×60提取、身份关联、四向轨迹、排队及73字节G1遥测。
原版RGB332预览、目标光标/起始框、320×240掩码校准与完整诊断文本均恢复。
SW3开启时按上传版：KEY2采空背景、KEY3重启跟踪、KEY4切换校准视图。
SW3关闭时KEY2/3/4恢复菜单按键；模式切换时松开按键，释放保护防止误触菜单。
SW3关闭会停止跟踪/导航并清除待投递事件；SW2可独立继续看画面。
菜单按键在SW3关闭时使用。手在中央停稳，等S2 A1后整只手滑动：左右选择、下进入、上返回。
轮播下滑进入首页；SW3关闭时物理KEY4缩放。
保持TF资源配套；卡插回板后按KEY1复位重新挂载。本次为FPGA SRAM配置，断电需重新下载。
图片与讲解共用一次挂载目录扫描；换卡或修改文件目录后按KEY1重新挂载。
PREVIEWS为RTL仿真：RGB/掩码是合成测试激励，不是现场拍摄。
JTAG成功不代替四向成功率、音视频及长期运行的实板验收。
'''
(RELEASE/'START_HERE.txt').write_text(notes,encoding='utf-8')
shutil.copy2(ROOT/'camera/INTEGRATION.md',RELEASE/'INTEGRATION.md')
previews=RELEASE/'PREVIEWS';previews.mkdir(exist_ok=True)
for p in (OUT/'preview').iterdir():
    if p.suffix in ['.png','.html','.json']:shutil.copy2(p,previews/p.name)
for n in ['final.ts','final.area','final.timing','final.exceptions','signoff.log','FULL_FEATURE_AUDIT.json','BOARD_DOWNLOAD_RESULT.json','RESOURCE_ASSESSMENT.json','TEST_RESULTS.json']:
    shutil.copy2(OUT/n,RELEASE/n)
shutil.copy2(Path(board['cycle'])/'download.log',RELEASE/'download.log')
with zipfile.ZipFile(BUILD/(VERSION+'.zip'),'w',zipfile.ZIP_DEFLATED,compresslevel=1) as z:
    for p in sorted(RELEASE.rglob('*')):
        if p.is_file():z.write(p,p.relative_to(RELEASE).as_posix())
with zipfile.ZipFile(BUILD/(VERSION+'_bit_only.zip'),'w',zipfile.ZIP_DEFLATED,compresslevel=1) as z:
    for n in ['museum_phase6_full_camera.bit','RELEASE_MANIFEST.json','START_HERE.txt','INTEGRATION.md']:z.write(RELEASE/n,n)
for p in [BUILD/(VERSION+'.zip'),BUILD/(VERSION+'_bit_only.zip')]:
    with zipfile.ZipFile(p) as z:assert z.testzip() is None
    print('PASS package',p,sha(p))
