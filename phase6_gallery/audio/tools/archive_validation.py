"""Archive passed simulation logs plus exact inputs; never claim synthesis or board validation."""
from pathlib import Path
import hashlib,json,re,shutil,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[2]
BUILD=ROOT/"build";OUT=ROOT/"audio/validation"
report=json.loads((BUILD/"audio_validation.json").read_text())
for entry in report["tests"]:
    log=(BUILD/f'{entry["case"]}.log').read_text(encoding="utf-8")
    if not all(m in log for m in entry["markers"]) or re.search(r"\*\* (?:Error|Fatal):",log):
        raise ValueError(f"Unpassed test: {entry['case']}")
    normalized=log.encode("utf-8")
    if hashlib.sha256(normalized).hexdigest()!=entry["log_sha256"]:
        raise ValueError(f"Log changed since test run: {entry['case']}")
OUT.mkdir(parents=True,exist_ok=True)
for entry in report["tests"]:
    name=entry["case"]+".txt"
    (OUT/name).write_bytes((BUILD/f'{entry["case"]}.log').read_text(encoding="utf-8").encode("utf-8"))
    entry["log"]=name
inputs=[]
paths={ROOT/"museum_phase6_gallery.al",ROOT/"build.tcl"}
tree=ET.parse(ROOT/"museum_phase6_gallery.al")
for entry in tree.findall(".//File"):
    path=(ROOT/entry.get("Path")).resolve()
    if not path.is_relative_to(ROOT) or not path.is_file():raise ValueError(path)
    paths.add(path)
for path in sorted(paths):
    inputs.append({"path":path.relative_to(ROOT).as_posix(),"sha256":hashlib.sha256(path.read_bytes()).hexdigest()})
report["compiled_input_manifest"]=inputs
report["test_sources"]=[{"path":p.relative_to(ROOT).as_posix(),"sha256":hashlib.sha256(p.read_bytes()).hexdigest()}
 for p in sorted((ROOT/"audio/sim").glob("*")) if p.is_file()]
report["baseline"]="f79634391f836f4b1e45b32e17b0adf3de657122"
report["date"]="2026-10-23"
report["compiled_input_manifest_note"]="Inputs intended for TD; listing hashes does not mean TD has compiled them."
report["delivery"]="Source and simulation handoff; integration lead owns TD compile, bitstream and board acceptance."
(OUT/"checks.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(f"Archived {len(report['tests'])} passing suites and {len(inputs)} project inputs")
