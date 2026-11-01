"""Generate verification-only excerpts from the four real WAV assets; retain original chunk layout."""
from pathlib import Path
import struct, wave
ROOT=Path(__file__).resolve().parents[2]
BUILD=ROOT/"build"
allbytes=[];expected=[];sizes=[]
for index in range(1,5):
    path=ROOT/f"build/narration/TF_CARD/AUD{index:05d}.WAV"
    raw=path.read_bytes();pos=12;data_pos=None
    while pos+8<=len(raw):
        ident=raw[pos:pos+4];size=struct.unpack_from("<I",raw,pos+4)[0]
        if ident==b"data":
            data_pos=pos;break
        pos+=8+size+(size&1)
    assert data_pos is not None
    take=8192
    fixture=bytearray(raw[:data_pos+8+take])
    struct.pack_into("<I",fixture,4,len(fixture)-8)
    struct.pack_into("<I",fixture,data_pos+4,take)
    assert len(fixture)<=16384
    sizes.append(len(fixture))
    allbytes.extend(fixture);allbytes.extend(bytes(16384-len(fixture)))
    pcm=fixture[data_pos+8:]
    expected.extend(struct.unpack("<4096H",pcm))
    if index==1:
        with wave.open(str(path),"rb") as wav:
            wav.setpos(48000);preview=struct.unpack("<1536h",wav.readframes(1536))
        (BUILD/"wave_samples.hex").write_text("\n".join(f"{(v<<8)&0xffffff:06x}" for v in preview)+"\n")
(BUILD/"real_wav_input.hex").write_text("\n".join(f"{v:02x}" for v in allbytes)+"\n")
(BUILD/"real_wav_expected.hex").write_text("\n".join(f"{v:04x}" for v in expected)+"\n")
(BUILD/"real_wav_sizes.hex").write_text("\n".join(f"{v:08x}" for v in sizes)+"\n")
print("Prepared real WAV excerpts:", sizes)
