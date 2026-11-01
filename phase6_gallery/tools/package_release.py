"""Make a self-contained phase6 board package and verification manifest."""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
BUILD = ROOT / "build"
BIT = BUILD / "museum_phase6_gallery.bit"
ASSETS = json.loads((ROOT / "ASSETS.json").read_text(encoding="utf-8"))
TIMING = (BUILD / "final.ts").read_text(encoding="utf-8")
if "SWNS: -" in TIMING or "HWNS: -" in TIMING:
    raise ValueError("Final timing has a violation")


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


sources = []
for node in ET.parse(ROOT / "museum_phase6_gallery.al").findall(".//File"):
    source = Path(node.get("Path"))
    if not source.is_absolute():
        source = ROOT / source
    sources.append({"path": source.relative_to(REPO).as_posix(), "sha256": sha(source)})
for filename in ("phase5.adc", "phase5.sdc"):
    path = ROOT / "constraints" / filename
    sources.append({"path": path.relative_to(REPO).as_posix(), "sha256": sha(path)})
for item in ASSETS["images"] + [ASSETS["av"]]:
    if sha(BUILD / "TF_CARD" / item["file"]) != item["sha256"]:
        raise ValueError(f"TF file differs from manifest: {item['file']}")
tests = {}
for name in ("ui", "fat", "zoom", "render"):
    path = BUILD / f"{name}.log"
    content = path.read_text(encoding="utf-8")
    if "PASS" not in content or "Errors: 1" in content:
        raise ValueError(f"Missing passing test: {name}")
    tests[name] = sha(path)

manifest = {"version": "museum-phase6-gallery-20261014", "bit_sha256": sha(BIT),
            "bit_bytes": BIT.stat().st_size, "timing": TIMING.strip(),
            "sources": sources, "assets_manifest_sha256": sha(ROOT / "ASSETS.json"),
            "logo_source": {"url": "https://www.anlogic.com/Public/Uploads/uploadfile/images/20230414/logo.svg",
                            "sha256": sha(ROOT / "assets" / "anlogic_official_logo.svg")},
            "tests": tests, "board_validation": "pending"}
manifest_path = ROOT / "RELEASE_MANIFEST.json"
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
archive = BUILD / "museum_phase6_gallery_20261014_r3.zip"
if archive.exists():
    raise FileExistsError(f"Package already exists: {archive}")
with zipfile.ZipFile(archive, "x", zipfile.ZIP_DEFLATED, compresslevel=1) as package:
    package.write(BIT, "museum_phase6_gallery.bit")
    package.write(manifest_path, "RELEASE_MANIFEST.json")
    package.write(ROOT / "ASSETS.json", "ASSETS.json")
    package.write(ROOT / "GALLERY_SOURCES.md", "GALLERY_SOURCES.md")
    package.write(ROOT / "README.md", "README.md")
    package.write(ROOT / "assets" / "anlogic_official_logo.svg", "anlogic_official_logo.svg")
    for path in sorted((BUILD / "TF_CARD").iterdir()):
        if path.is_file():
            package.write(path, f"TF_CARD/{path.name}")
with zipfile.ZipFile(archive) as package:
    if package.testzip() is not None:
        raise ValueError("Archive CRC test failed")
print(f"Packaged {archive} ({archive.stat().st_size} bytes)")
