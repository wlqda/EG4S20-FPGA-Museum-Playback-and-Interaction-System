"""Build the exact Phase6 TF set from bundled pages and credited photos."""
from __future__ import annotations

import hashlib
import argparse
import json
from pathlib import Path
import shutil
import struct

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[1]
BASE_PAGES = ROOT / "assets" / "base_pages"
CARD = ROOT / "build" / "TF_CARD"
SOURCE = ROOT / "source_photos"

PHOTOS = [
    ("01_bronze/01_original.jpg", "青铜方鼎", "Met DP140735", "photograph"),
    ("01_bronze/02_real.jpg", "青铜方鼎", "Met DP140736", "photograph"),
    ("01_bronze/03_real.jpg", "青铜方鼎", "Met DP140737", "photograph"),
    ("02_porcelain/01_original.jpg", "青花瓷瓶", "World Imaging / Shanghai Museum", "photograph"),
    ("02_porcelain/02_ai_left.png", "青花瓷瓶", "user supplied", "AI generated"),
    ("02_porcelain/03_ai_right.png", "青花瓷瓶", "user supplied", "AI generated"),
    ("03_jade/01_original.jpg", "玉璧", "Met DP-45486-001", "photograph"),
    ("03_jade/02_real_reverse.jpg", "玉璧", "Met DP-45486-002", "photograph"),
    ("03_jade/03_archive_reference.jpg", "玉璧", "Commons MET 50 145 141 O1", "archive photograph"),
    ("03_jade/04_ai_oblique.png", "玉璧", "user supplied", "AI generated"),
    ("04_figurine/01_original.jpg", "陶侍女俑", "Met DP702322", "photograph"),
    ("04_figurine/02_real.jpg", "陶侍女俑", "Met DP702323", "photograph"),
    ("04_figurine/03_ai_side.png", "陶侍女俑", "user supplied", "AI generated"),
]


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build(av_file: Path) -> None:
    old = json.loads((BASE_PAGES / "ASSETS.json").read_text(encoding="utf-8"))
    av_source = av_file.resolve()
    if not av_source.is_file():
        raise FileNotFoundError(f"Supply the matching AVVIDEO.BIN using --av-file: {av_source}")
    if sha(av_source) != old["av"]["sha256"]:
        raise ValueError("AV stream differs from the published manifest")
    CARD.mkdir(parents=True, exist_ok=True)
    records = []
    for item in old["images"]:
        source = BASE_PAGES / (Path(item["file"]).stem + ".png")
        variant = item["file"] == "IMG00005.BMP" and (ROOT/"assets/home_three_entries.png").exists()
        if variant: source=ROOT/"assets/home_three_entries.png"
        guide_variant=ROOT/"assets/ui_v2"/(Path(item["file"]).stem+".png")
        if guide_variant.exists():source=guide_variant;variant=True
        full_variant=ROOT/"assets/ui_v3/pages"/(Path(item["file"]).stem+".png")
        if full_variant.exists():source=full_variant;variant=True
        dest = CARD / item["file"]
        with Image.open(source) as source_image:
            source_image.convert("RGB").save(dest, format="BMP")
        if not variant and sha(dest) != item["sha256"]:
            raise ValueError(f"Reconstructed base page differs from manifest: {dest}")
        record=dict(item)
        record["sha256"]=sha(dest)
        if variant:record["variant"]="full-bleed-subjects-v3"
        records.append(record)

    for photo_no, (relative, title, credit, kind) in enumerate(PHOTOS):
        original = SOURCE / relative
        path = CARD / f"IMG{photo_no + 17:05d}.BMP"
        full_variant=ROOT/"assets/ui_v3/pages"/(path.stem+".png")
        if full_variant.exists():
            with Image.open(full_variant) as source_image:
                source_image.convert("RGB").save(path,format="BMP")
        else:
            with Image.open(original) as source_image:
                fitted = ImageOps.contain(source_image.convert("RGB"), (640, 360), Image.Resampling.LANCZOS)
                canvas = Image.new("RGB", (640, 480), (21, 20, 18))
                canvas.paste(fitted, ((640 - fitted.width) // 2, 54 + (360 - fitted.height) // 2))
                canvas.save(path, format="BMP")
        raw = path.read_bytes()
        if struct.unpack_from("<ii", raw, 18) != (640, 480) or struct.unpack_from("<H", raw, 28)[0] != 24:
            raise ValueError(f"Unexpected BMP geometry: {path}")
        records.append({"index": photo_no + 16, "file": path.name, "page": "gallery",
                        "photo": relative, "title": title, "kind": kind, "credit": credit,
                        "source_sha256": sha(original), "bytes": len(raw), "sha256": sha(path),
                        "variant":"full-bleed-subjects-v3" if full_variant.exists() else "legacy",
                        "background_outpainted":(ROOT/"assets/ui_v3/generated"/f"gallery_{photo_no+1:02d}.png").exists()})

    if av_source != (CARD / "AVVIDEO.BIN").resolve():
        shutil.copy2(av_source, CARD / "AVVIDEO.BIN")
    for name in ("SOURCE_CREDITS.md", "EXHIBITS.md"):
        source = BASE_PAGES / name
        if source.exists():
            shutil.copy2(source, CARD / name)
    (ROOT / "ASSETS.json").write_text(json.dumps({"version": "gallery-phase6-full-bleed-v3",
        "images": records, "av": old["av"]}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    credits = ["# 文物照片来源", "", "下表记录用于轮播的输入文件。AI 标记依据用户提供的文件名，尚未独立核实生成过程。", "",
               "| TF 文件 | 标题 | 原文件 | 类型 | 来源或标记 |", "|---|---|---|---|---|"]
    for item in records[16:]:
        credits.append(f"| {item['file']} | {item['title']} | {item['photo']} | {item['kind']} | {item['credit']} |")
    credits += ["", "## 原始馆藏页面", "",
                "- 青铜方鼎（Met 49.135.2）：https://www.metmuseum.org/art/collection/search/60594",
                "- 玉璧（Met 50.145.141）：https://www.metmuseum.org/art/collection/search/42840",
                "- 陶侍女俑（Met 2015.500.7.4）：https://www.metmuseum.org/art/collection/search/54078",
                "- 青花瓷瓶原图：https://commons.wikimedia.org/wiki/File:Blue_and_white_vase_Jingdezhen_Ming_Yongle_1403_1424.jpg",
                "- 玉璧历史照片：https://commons.wikimedia.org/wiki/File:MET_50_145_141_O1.jpeg", ""]
    credits += ["", "## V3 图像衍生说明", "", "轮播图04、09、11、12使用内置image_gen扩展背景；其余轮播保留原始画面比例。列表/详情/讲解使用四份AI去背景主体。图像为展示衍生稿，原始照片保留，不能替代原始馆藏影像资料。生成提示词与来源见assets/ui_v3/GENERATION_MANIFEST.json。", ""]
    with (CARD/"SOURCE_CREDITS.md").open("a",encoding="utf-8") as stream:
        stream.write("\n\n"+"\n".join(credits[-5:])+"\n")
    (ROOT / "GALLERY_SOURCES.md").write_text("\n".join(credits), encoding="utf-8")
    (CARD / "GALLERY_SOURCES.md").write_text("\n".join(credits), encoding="utf-8")
    print(f"Prepared {len(records)} BMP images and AV stream in {CARD}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--av-file", type=Path, default=CARD / "AVVIDEO.BIN",
                        help="Published AVVIDEO.BIN; omitted when already in build/TF_CARD")
    build(parser.parse_args().av_file)
