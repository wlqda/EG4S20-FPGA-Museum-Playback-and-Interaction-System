"""Build physical implementation, then sign off in a fresh TD process."""
from pathlib import Path
import argparse
import hashlib
import json
import xml.etree.ElementTree as ET
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--td", default="D:/anlogic/bin/td_commands_prompt.exe")
    args = parser.parse_args()
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    sources = [ROOT / n.get("Path") for n in ET.parse(ROOT / "museum_phase6_gallery.al").findall(".//File")]
    sources += [ROOT / "constraints/phase5.adc", ROOT / "constraints/phase5.sdc", ROOT / "build.tcl", ROOT / "signoff.tcl", ROOT / "museum_phase6_gallery.al"]
    snapshot = {p.relative_to(ROOT.parent).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    (build / "integration_build_inputs.json").write_text(json.dumps(snapshot, indent=2) + "\n", encoding="utf-8")
    for script, log_name in (("build.tcl", "physical_build.log"), ("signoff.tcl", "signoff.log")):
        with (build / log_name).open("w", encoding="utf-8") as stream:
            result = subprocess.run([args.td, (ROOT / script).as_posix()], cwd=ROOT,
                                    stdout=stream, stderr=subprocess.STDOUT)
        content = (build / log_name).read_text(encoding="utf-8", errors="replace")
        marker = "PASS PHYSICAL IMPLEMENTATION" if script == "build.tcl" else "PASS ORIGINAL-SDC SIGNOFF"
        if result.returncode or marker not in content or "BUILD FAILED" in content or "SIGNOFF FAILED" in content:
            print(f"Failed: {script}; see {build / log_name}")
            return result.returncode or 1
    (build / "td_audio_clock.log").write_text(
        (build / "physical_build.log").read_text(encoding="utf-8", errors="replace") +
        (build / "signoff.log").read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    print(f"Timing-clean bit: {build / 'museum_phase6_gallery.bit'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
