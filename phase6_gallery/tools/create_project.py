"""Prepare the standalone Phase6 TD project at the current clone location."""
from pathlib import Path
import xml.etree.ElementTree as ET
ROOT = Path(__file__).resolve().parents[1]
project_file = ROOT / "museum_phase6_gallery.al"
tree = ET.parse(project_file)
for node in tree.findall(".//File"):
    source = (ROOT / node.get("Path")).resolve()
    if not source.is_relative_to(ROOT) or not source.is_file():
        raise FileNotFoundError(source)
tree.getroot().set("Path", ROOT.as_posix())
tree.write(project_file, encoding="utf-8", xml_declaration=True)
(ROOT / "build").mkdir(exist_ok=True)
print("Prepared standalone Phase6 project:", project_file)
