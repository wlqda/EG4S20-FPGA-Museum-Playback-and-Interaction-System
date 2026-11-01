"""Validate generated narration assets and write an auditable manifest (stdlib only)."""
import array, hashlib, json, math, sys, wave
from pathlib import Path
project = Path(__file__).resolve().parents[2]
output = Path(sys.argv[1]) if len(sys.argv) > 1 else project / "build/narration/TF_CARD"
items = json.loads((project / "audio/narrations.json").read_text(encoding="utf-8-sig"))
records = []
for item in items:
    path = output / item["filename"]
    with wave.open(str(path), "rb") as wav:
        assert (wav.getnchannels(), wav.getsampwidth(), wav.getframerate(), wav.getcomptype()) == (1, 2, 48000, "NONE"), path
        count = wav.getnframes()
        data = wav.readframes(count)
    assert len(data) == count * 2 and count > 48000, path
    samples = array.array("h", data)
    if sys.byteorder != "little":
        samples.byteswap()
    peak = max(abs(x) for x in samples)
    rms = math.sqrt(sum(x*x for x in samples) / count)
    clipped = sum(x in (-32768, 32767) for x in samples)
    assert peak > 100 and rms > 10, f"Silent audio: {path}"
    assert clipped == 0, f"Clipping: {path}"
    record = {**item, "sample_rate": 48000, "channels": 1, "bits_per_sample": 16,
              "samples": count, "duration_seconds": round(count/48000, 3),
              "bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
              "peak_dbfs": round(20*math.log10(peak/32768), 2),
              "rms_dbfs": round(20*math.log10(rms/32768), 2), "clipped_samples": clipped}
    records.append(record)
    print(f'{item["filename"]}: {count/48000:.2f}s, peak {record["peak_dbfs"]} dBFS, PASS')
manifest = {"generated_date": "2026-10-22", "voice": "Microsoft Huihui Desktop",
            "engine": "Windows SAPI", "rate": -1, "synthetic_speech": True,
            "verification": "WAV structure, sample count, signal level, clipping, SHA256; not board-tested or manually auditioned",
            "tracks": records}
(output.parent / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
