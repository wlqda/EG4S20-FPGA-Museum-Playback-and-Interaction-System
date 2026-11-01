"""Package only a timing-clean build matching the recorded hardware inputs."""
from pathlib import Path
import hashlib
import json
import re
import xml.etree.ElementTree as ET
import zipfile
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
BUILD = ROOT / "build"
VERSION = "museum_full_bleed_all_exhibits_20261026_v3"


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main():
    timing = (BUILD / "final.ts").read_text(encoding="utf-8")
    for label in ("SWNS", "HWNS"):
        value = re.search(label + r":\s*([+-]?[\d.]+)ns", timing)
        if value is None or float(value[1]) < 0 or value[1].startswith("-"):
            raise ValueError(f"Missing/passing {label} required: {timing}")
    log = (BUILD / "td_audio_clock.log").read_text(encoding="utf-8", errors="replace")
    if "BUILD FAILED" in log or "SIGNOFF FAILED" in log or re.search(r"\bERROR:", log):
        raise ValueError("TD build contains a failure")
    if "PASS ORIGINAL-SDC SIGNOFF" not in log or "No multi-drive." not in log or "No abnormal timing path." not in log:
        raise ValueError("Independent original-SDC signoff and route DRC evidence required")
    inputs = json.loads((BUILD / "integration_build_inputs.json").read_text())
    sources = []
    for node in ET.parse(ROOT / "museum_phase6_gallery.al").findall(".//File"):
        path = ROOT / node.get("Path")
        sources.append(path)
    sources += [ROOT / "constraints/phase5.adc", ROOT / "constraints/phase5.sdc", ROOT / "build.tcl", ROOT / "signoff.tcl", ROOT / "museum_phase6_gallery.al"]
    current = {p.relative_to(REPO).as_posix(): sha(p) for p in sources}
    if current != inputs:
        raise ValueError("Hardware sources changed after the recorded build inputs")
    summary = json.loads((BUILD / "audio_validation.json").read_text())
    expected = {"narration", "audio_ui", "real_wav", "ui", "fat", "zoom", "render",
                "floating_clock", "slide_switch", "render_pipeline", "status_rom", "mount_regression", "narration_mbr", "av_pcm_banks", "image_read_pipeline"}
    if {t["case"] for t in summary["tests"]} != expected:
        raise ValueError("Complete integration regression evidence required")
    tests = {}
    for name in sorted(expected):
        path = BUILD / f"{name}.log"
        content = path.read_text(encoding="utf-8")
        if "PASS" not in content or re.search(r"Errors: [1-9]|Warnings: [1-9]|\*\* (?:Error|Fatal):", content):
            raise ValueError(f"Failing simulation: {name}")
        tests[name] = sha(path)
        record = next(t for t in summary["tests"] if t["case"] == name)
        if record["log_sha256"] != tests[name]:
            raise ValueError(f"Regression log differs from test manifest: {name}")
    assets = json.loads((ROOT / "ASSETS.json").read_text(encoding="utf-8"))
    for item in assets["images"] + [assets["av"]]:
        if sha(BUILD / "TF_CARD" / item["file"]) != item["sha256"]:
            raise ValueError(f"Bad gallery asset: {item['file']}")
    audio = json.loads((ROOT / "audio/manifest.json").read_text(encoding="utf-8"))
    for item in audio["tracks"]:
        if sha(BUILD / "TF_CARD" / item["filename"]) != item["sha256"]:
            raise ValueError(f"Bad narration asset: {item['filename']}")
    bit = BUILD / "museum_phase6_gallery.bit"
    if bit.stat().st_mtime < (BUILD / "final.ts").stat().st_mtime:
        raise ValueError("Bit predates timing evidence")
    manifest = {"version": VERSION, "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip(), "bit_sha256": sha(bit), "bit_bytes": bit.stat().st_size,
                "timing": timing, "sources": current, "tests": tests,
                "tf_files": {p.name: sha(p) for p in sorted((BUILD / "TF_CARD").iterdir()) if p.is_file()},
                "board_validation": "pending", "flash_and_power_cycle": "pending",
                "simulation_boundary": "Encrypted HDMI, PLL and PHY not simulated at packet/electrical level"}
    path = ROOT / "INTEGRATION_RELEASE_MANIFEST.json"
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    archive = BUILD / (VERSION + ".zip")
    with zipfile.ZipFile(archive, "x", zipfile.ZIP_DEFLATED, compresslevel=1) as package:
        package.write(bit, bit.name)
        for filename in ("INTEGRATION_RELEASE_MANIFEST.json", "INTEGRATION_PROGRESS.md", "README.md", "ASSETS.json"):
            package.write(ROOT / filename, filename)
        for name in ("final.ts", "final.area", "final.exceptions", "final.timing", "td_audio_clock.log", "integration_build_inputs.json", "audio_validation.json", "final_physical_check.log"):
            package.write(BUILD / name, "validation/" + name)
        for name in expected:
            package.write(BUILD / f"{name}.log", f"validation/{name}.log")
        for item in sorted((BUILD / "TF_CARD").iterdir()):
            if item.is_file():
                package.write(item, "TF_CARD/" + item.name)
    with zipfile.ZipFile(archive) as package:
        if package.testzip() is not None:
            raise ValueError("Archive CRC failure")
    print(f"Packaged {archive}: {archive.stat().st_size} bytes; bit SHA256 {manifest['bit_sha256']}")


if __name__ == "__main__":
    main()
