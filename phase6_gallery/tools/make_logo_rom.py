"""Rasterize Anlogic's official SVG into a small code-native overlay ROM."""
from pathlib import Path
import sys
sys.path.insert(0, "F:/Codex/tools/python_libs")
from PIL import Image
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
SVG = ROOT / "assets" / "anlogic_official_logo.svg"
PNG = ROOT / "assets" / "anlogic_logo_290.png"
RTL = ROOT / "rtl" / "museum_gallery_logo.v"

with sync_playwright() as playwright:
    browser = playwright.chromium.launch(
        executable_path="C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
        headless=True, args=["--allow-file-access-from-files"])
    page = browser.new_page(viewport={"width": 290, "height": 33}, device_scale_factor=1)
    page.goto(SVG.as_uri())
    full = ROOT / "build" / "logo_full.png"
    full.parent.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(full), omit_background=True)
    browser.close()

image = Image.open(full).convert("RGBA")
image.save(PNG)
rows = []
for y in range(33):
    navy, red = 0, 0
    for x in range(290):
        r, g, b, a = image.getpixel((x, y))
        if a < 80:
            continue
        if r > b * 1.12 and r > g * 1.12:
            red |= 1 << x
        else:
            navy |= 1 << x
    rows.append((navy, red))

lines = [
    "// Official Anlogic site SVG, rasterized to 290x33; source URL in README.",
    "module museum_gallery_logo(input [8:0] x,input [5:0] y,output wire [1:0] color);",
    "reg [289:0] navy,red;",
    "always @* begin navy=0;red=0;case(y)",
]
for y, (navy, red) in enumerate(rows):
    lines.append(f"6'd{y}:begin navy=290'h{navy:073x};red=290'h{red:073x};end")
lines += ["default:begin navy=0;red=0;end", "endcase end",
          "assign color=x<290 ? (red[x] ? 2'd2 : navy[x] ? 2'd1 : 2'd0) : 2'd0;",
          "endmodule"]
RTL.write_text("\n".join(lines)+"\n", encoding="utf-8")
print(f"Generated {RTL}; navy pixels={sum(n.bit_count() for n,_ in rows)}, red pixels={sum(r.bit_count() for _,r in rows)}")
