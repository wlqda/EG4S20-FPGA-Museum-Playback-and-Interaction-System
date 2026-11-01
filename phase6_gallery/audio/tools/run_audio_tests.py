"""Run audio integration and preserved gallery regressions. No TD/board claim."""
from pathlib import Path
import argparse, subprocess, re, json, hashlib, os, shutil
ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument("--vsim",default=os.environ.get("VSIM_EXE") or shutil.which("vsim") or "D:/intelFPGA_lite/18.1/modelsim_ase/win32aloem/vsim.exe")
args=parser.parse_args()
build=ROOT/"build";build.mkdir(exist_ok=True)
cases=[
 ("narration","../audio/sim/run_narration.do",["PASS narration:"]),
 ("audio_ui","../audio/sim/run_audio_ui.do",["PASS audio UI:","PASS waveform:"]),
 ("real_wav","../audio/sim/run_real_wav.do",["PASS real WAV:"]),
 ("ui","../sim/run_gallery_ui.do",["PASS gallery UI:"]),
 ("fat","../sim/run_gallery_fat.do",["RESULT: GALLERY 29-NAMED FAT ALL PASS"]),
 ("zoom","../sim/run_gallery_zoom.do",["PASS zoom mappings:"]),
 ("render","../sim/run_gallery_render.do",["PASS gallery render:"]),
 ("floating_clock","../sim/run_floating_clock.do",["PASS floating clock:"]),
 ("slide_switch","../sim/run_slide_switch.do",["PASS slide switch:"]),
 ("render_pipeline","../sim/run_render_pipeline.do",["PASS render pipeline:"]),
 ("status_rom","../sim/run_status_rom.do",["PASS status ROM:"]),
 ("mount_regression","../sim/run_mount_regression.do",["PASS mount regression:"]),
 ("narration_mbr","../audio/sim/run_narration_mbr.do",["PASS narration MBR:"]),
 ("av_pcm_banks","../sim/run_av_pcm_banks.do",["PASS AV PCM banks:"]),
 ("image_read_pipeline","../sim/run_image_read_pipeline.do",["PASS image read pipeline:"])]
records=[]
for name,script,markers in cases:
    result=subprocess.run([args.vsim,"-c","-do",f"do {script}"],cwd=build,capture_output=True,text=True,errors="replace",timeout=180)
    log=result.stdout+result.stderr
    (build/f"{name}.log").write_bytes(log.encode("utf-8"))
    if result.returncode or not all(m in log for m in markers) or re.search(r"\*\* (?:Error|Fatal):",log) or re.search(r"Warnings: [1-9]",log):
        raise RuntimeError(f"{name} failed: {build/name}.log\n{log[-3000:]}")
    records.append({"case":name,"markers":markers,"log_sha256":hashlib.sha256(log.encode()).hexdigest()})
    print(f"PASS {name}",flush=True)
manifest={"tests":records,"td_build":"see INTEGRATION_RELEASE_MANIFEST.json for separate TD evidence","board_validation":"pending","bit_generated":False}
(build/"audio_validation.json").write_text(json.dumps(manifest,indent=2)+"\n")
