"""Run and preserve the targeted ModelSim regressions for a release."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
VSIM = Path("F:/intelFPGA_lite/18.1/modelsim_ase/win32aloem/vsim.exe")
CASES = {
    "ui": ("run_gallery_ui.do", "PASS gallery UI:"),
    "fat": ("run_gallery_fat.do", "RESULT: GALLERY 29-NAMED FAT ALL PASS"),
    "zoom": ("run_gallery_zoom.do", "PASS zoom mappings:"),
    "render": ("run_gallery_render.do", "PASS gallery render:"),
}
for name, (script, marker) in CASES.items():
    result = subprocess.run([str(VSIM), "-c", "-do", f"do ../sim/{script}"],
                            cwd=BUILD, capture_output=True, text=True, errors="replace")
    log = result.stdout + result.stderr
    (BUILD / f"{name}.log").write_text(log, encoding="utf-8")
    if result.returncode or marker not in log or "Errors: 1" in log or "Warnings: 1" in log:
        raise RuntimeError(f"{name} failed; see {BUILD / (name + '.log')}")
    print(f"PASS {name}")
