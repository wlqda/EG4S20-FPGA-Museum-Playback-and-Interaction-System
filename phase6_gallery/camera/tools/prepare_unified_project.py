"""Create an isolated TD target without changing the verified gallery target."""
from pathlib import Path
import xml.etree.ElementTree as ET
import hashlib, json
ROOT=Path(__file__).resolve().parents[2]
tree=ET.parse(ROOT/'museum_phase6_gallery.al')
tree.getroot().set('Path',ROOT.as_posix())
tree.find('Name').text='museum_phase6_unified'
files=next(n for n in tree.iter() if any(c.tag=='File' for c in n))
camera_files=['camera_sccb_master','camera_config_rom','camera_config_controller','camera_dvp_capture',
 'camera_dvp_auto_monitor','camera_source_stream','camera_hand_candidate','camera_foreground_debug',
 'camera_foreground_overlay','camera_palm_regions','camera_candidate_track','camera_swipe_tracker',
 'camera_nav_adapter','camera_telemetry_uart','museum_camera_key_modes','museum_camera_overlay','camera_pose_overlay',
 'camera_gesture_engine','museum_phase6_unified_top']
for i,name in enumerate(camera_files):
    node=ET.SubElement(files,'File',Path=f'camera/rtl/{name}.v')
    info=ET.SubElement(node,'FileInfo')
    for key,val in [('UsedInSyn','true'),('UsedInP&R','true'),('BelongTo','design_1'),('CompileOrder',str(41+i))]:ET.SubElement(info,'Attr',Name=key,Val=val)
for n in tree.iter():
    for key,value in list(n.attrib.items()):
        if value=='museum_phase6_top':n.set(key,'museum_phase6_unified_top')
        if key=='Path' and value=='constraints/phase5.adc':n.set(key,'camera/constraints/unified.adc')
        if key=='Path' and value=='constraints/phase5.sdc':n.set(key,'camera/constraints/unified.sdc')
for node in tree.findall('.//File'):
    source=(ROOT/node.get('Path')).resolve()
    if not source.is_relative_to(ROOT) or not source.is_file():
        raise FileNotFoundError(source)
tree.write(ROOT/'museum_phase6_unified.al',encoding='utf-8',xml_declaration=True)
adc=(ROOT/'constraints/phase5.adc').read_text(encoding='utf-8')
# Original standalone DQ register placement hints bind to specific BLEs. The
# unified mapper can absorb those registers into LUT macros; let placement
# choose legal BLEs, keeping every external pin and all timing budgets intact.
adc='\n'.join(s for s in adc.splitlines() if not s.startswith('set_inst_assignment'))+'\n'
adc+='\n# 2_FPGA.pdf: SWKEY_2=C7, SWKEY_3=C6; 6_EX_DEVICE.pdf: board switches.\n'
adc+='# SW1 -> SW_1 -> RN38 -> SWKEY_1 -> C8, board schematics.\n'
adc+='set_pin_assignment { SW1 } { LOCATION = C8; IOSTANDARD = LVCMOS33; PULLTYPE = PULLDOWN; }\n'
adc+='set_pin_assignment { SW2 } { LOCATION = C7; IOSTANDARD = LVCMOS33; PULLTYPE = PULLDOWN; }\n'
adc+='set_pin_assignment { SW3 } { LOCATION = C6; IOSTANDARD = LVCMOS33; PULLTYPE = PULLDOWN; }\n'
for name in ['phase6_camera_jp1_ribbon.adc','phase6_dvp_jp1_ribbon.adc']:
    adc+='\n'+(ROOT/'camera/constraints'/name).read_text(encoding='utf-8')
(ROOT/'camera/constraints/unified.adc').write_text(adc,encoding='utf-8')
sdc=(ROOT/'camera/constraints/gesture.sdc').read_text(encoding='utf-8')
# Pad -> first synchronizer exceptions only; downstream paths remain timed.
sdc+='\nset_false_path -from [get_ports {KEY2_N KEY3_N KEY4_N}] -to [get_regs {key_modes/sync1*}]\n'
sdc+='set_false_path -from [get_ports {SW1}] -to [get_regs {clock_switch/sync*}]\n'
sdc+='set_false_path -from [get_ports {SW2}] -to [get_regs {preview_switch/sync*}]\n'
sdc+='set_false_path -from [get_ports {SW3}] -to [get_regs {gesture_switch/sync*}]\n'
(ROOT/'camera/constraints/unified.sdc').write_text(sdc,encoding='utf-8')
build=(ROOT/'build.tcl').read_text(encoding='utf-8')
build=build.replace('museum_phase6_gallery.al','museum_phase6_unified.al').replace('-top museum_phase6_top','-top museum_phase6_unified_top')
build=build.replace('constraints/phase5.adc','camera/constraints/unified.adc').replace('constraints/phase5.sdc','camera/constraints/unified.sdc')
build=build.replace('build/','build/gesture_full/')
build=build.replace('optimize_rtl\n','set_param gate pack_seq_in_io on\nset_param gate pack_effort high\nset_param rtl min_control_set 2\noptimize_rtl\n')
build=build.replace('set_param place effort high','set_param place macro_performance dsp_ram_crit_path\nset_param route effort routability\nset_param route timing greedy\nset_param place effort high')
# Retain the gallery's validated seed43/TimingUltra physical strategy.
# Uploaded camera seed2 and its default strategy are retained as diagnostics;
# both had persistent congestion for the complete unified design.
build=build.replace('route\nupdate_timing -mode final','route\nfix_hold\nupdate_timing -mode final')
build=build.replace('{SYS_CLK SERIAL_CLK PIXEL_CLK MEMORY_CLK SDRAM_CLK}', '{SYS_CLK SERIAL_CLK PIXEL_CLK MEMORY_CLK SDRAM_CLK CAMERA_CLK DVP_CLK CAPTURE_CLK}')
# The script is stored under camera/tools; ROOT is fixed relative to itself.
build=build.replace('cd [file dirname [info script]]','cd [file normalize [file join [file dirname [info script]] ../..]]')
(ROOT/'camera/tools/build_unified.tcl').write_text(build,encoding='utf-8')
signoff=(ROOT/'signoff.tcl').read_text(encoding='utf-8')
signoff=signoff.replace('cd [file dirname [info script]]','cd [file normalize [file join [file dirname [info script]] ../..]]')
signoff=signoff.replace('set phase6_signoff_output [file normalize build]','set phase6_signoff_output [file normalize build/gesture_full]')
signoff=signoff.replace('read_sdc constraints/phase5.sdc','read_sdc camera/constraints/unified.sdc')
signoff=signoff.replace('SDRAM_CLK 100}', 'SDRAM_CLK 100 CAMERA_CLK 50 DVP_CLK 25 CAPTURE_CLK 25}')
signoff=signoff.replace('five clocks','eight clocks')
(ROOT/'camera/tools/signoff_unified.tcl').write_text(signoff,encoding='utf-8')
out=ROOT/'build/gesture_full';out.mkdir(parents=True,exist_ok=True)
sources=[ROOT/n.get('Path') for n in tree.findall('.//File')]
sources += list((ROOT/'camera/constraints').glob('unified.*'))
sources += [ROOT/'museum_phase6_unified.al',ROOT/'camera/tools/build_unified.tcl',ROOT/'camera/tools/signoff_unified.tcl']
(out/'BUILD_INPUTS.json').write_text(json.dumps({p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},indent=2),encoding='utf-8')
print('Prepared isolated unified target:',len(sources),'inputs; native gallery seed43')
