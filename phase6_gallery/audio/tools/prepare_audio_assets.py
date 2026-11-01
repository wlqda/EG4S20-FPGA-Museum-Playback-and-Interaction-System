"""Prepare a four-file narration add-on. Existing unequal files are never overwritten."""
from pathlib import Path
import argparse,hashlib,json,shutil,wave
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser()
p.add_argument("--source",type=Path,default=ROOT/"build/narration/TF_CARD")
p.add_argument("--output",type=Path,default=ROOT/"build/TF_CARD")
args=p.parse_args()
records=[]
for i in range(4):
    name=f"AUD{i+1:05d}.WAV";source=args.source/name
    with wave.open(str(source),"rb") as audio:
        if (audio.getnchannels(),audio.getsampwidth(),audio.getframerate(),audio.getcomptype())!=(1,2,48000,"NONE"):
            raise ValueError(f"Unsupported audio format: {source}")
        n=audio.getnframes()
        if not n or len(audio.readframes(n))!=2*n:raise ValueError(f"Empty/truncated audio: {source}")
    digest=hashlib.sha256(source.read_bytes()).hexdigest()
    dest=args.output/name
    if dest.exists() and hashlib.sha256(dest.read_bytes()).hexdigest()!=digest:
        raise FileExistsError(f"Use a new output folder; preserve existing asset: {dest}")
    records.append({"exhibit_id":i,"file":name,"samples":n,"duration_seconds":n/48000,"sha256":digest})
args.output.mkdir(parents=True,exist_ok=True)
for item in records:
    source=args.source/item["file"];dest=args.output/item["file"]
    if source.resolve()!=dest.resolve() and not dest.exists():shutil.copy2(source,dest)
manifest={"format":"PCM16LE mono 48000 Hz WAV","tracks":records,
          "note":"Audio add-on only; also retain all 29 original BMPs and AVVIDEO.BIN. New RTL requires a newly built and validated bitstream."}
(args.output/"AUDIO_MANIFEST.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print("Prepared four narration WAVs:",args.output)
