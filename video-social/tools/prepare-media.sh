#!/bin/sh
# Footage and music for the 45 s social cut. Every clip is nearest-neighbour scaled to the
# exact size it occupies on the 12x9 grid of 160x120 cells (1x = one cell), so pixels stay square.
# usage: tools/prepare-media.sh <capture-dir> <daybreak-audio.wav> <wall.mp4>
set -e
CAP=$1; WAV=$2; WALL=$3
OUT=$(dirname "$0")/../assets
V="-r 60 -c:v libx264 -preset slow -crf 14 -pix_fmt yuv420p -g 30 -movflags +faststart -an"
enc() { # name demo start dur filter
  ffmpeg -loglevel error -y -ss "$3" -i "$CAP/$2/raw160.mkv" -t "$4" -vf "$5" $V "$OUT/footage/$1.mp4"; echo "$1"
}
N9="scale=1440:1080:flags=neighbor"
FULL() { echo "crop=160:90:0:$1,scale=1920:1080:flags=neighbor"; }   # 16:9 slice at 12x
enc a1-pelican  pelican  11.0   1.875 "$N9"
enc a2-carpet   carpet   23.8   1.875 "$(FULL 12)"
enc a3-limit    limit    23.5   1.875 "$(FULL 15)"
enc a4-daybreak daybreak 35.625 1.875 "scale=960:720:flags=neighbor"
enc b-tunnel    daybreak 7.5    7.5   "scale=320:240:flags=neighbor"
enc d-spheres   daybreak 30     7.5   "scale=960:720:flags=neighbor"
enc f-daylight  daybreak 52.5   7.5   "scale=640:480:flags=neighbor"
cp "$WALL" "$OUT/footage/e-wall.mp4"

# Drop: eight demos, one per beat (beat = 28.125 frames; cuts rounded to whole frames), each in
# its own module geometry on paper: 9x right, 12x full, 12x full, 9x left, 9x right, 9x left, 12x full, 9x right.
PAPER=0xf2f1ec
set -- "pelican 3.0 R" "carpet 5.4 F12" "limit 45.6 F15" "daybreak 48.75 L" "megamix 31.0 R" "megamix 10.2 L" "megamix 17.0 F15" "supersaw 6.0 R"
inputs=""; filt=""; cat=""; i=0; prev=0
for s in "$@"; do
  set -- $s; d=$1; t=$2; g=$3
  end=$(python3 -c "print(int(($i+1)*28.125+0.5))"); n=$((end-prev)); prev=$end
  case $g in
    R)   vf="scale=1440:1080:flags=neighbor,pad=1920:1080:480:0:color=$PAPER" ;;
    L)   vf="scale=1440:1080:flags=neighbor,pad=1920:1080:0:0:color=$PAPER" ;;
    F12) vf="crop=160:90:0:12,scale=1920:1080:flags=neighbor" ;;
    F15) vf="crop=160:90:0:15,scale=1920:1080:flags=neighbor" ;;
  esac
  inputs="$inputs -ss $t -i $CAP/$d/raw160.mkv"
  filt="$filt[$i:v]$vf,trim=end_frame=$n,setpts=PTS-STARTPTS,setsar=1[s$i];"
  cat="$cat[s$i]"; i=$((i+1))
done
ffmpeg -loglevel error -y $inputs -filter_complex "${filt}${cat}concat=n=8:v=1:a=0[v]" -map "[v]" $V "$OUT/footage/e-rapid.mp4"
echo e-rapid

# Music: Daybreak from the kick (7.5 s) through the drop, then its outro: 37.5 s + 7.5 s.
python3 - "$WAV" "$OUT/audio/music.wav" <<'PY'
import sys, wave, numpy as np
w = wave.open(sys.argv[1]); x = np.frombuffer(w.readframes(w.getnframes()), np.int16).reshape(-1, 2).astype(float)
SR = 48000; loop = np.concatenate([x, x])
a = loop[int(7.5 * SR):int(45 * SR)]; b = loop[int(52.5 * SR):int(60 * SR)]
out = np.concatenate([a, b])
p, h = len(a), 128                          # equal-power splice from the source's own neighbouring samples
t = (np.arange(2 * h) + 0.5) / (2 * h)
out[p - h:p + h] = loop[int(45 * SR) - h:int(45 * SR) + h] * np.cos(t * np.pi / 2)[:, None] + loop[int(52.5 * SR) - h:int(52.5 * SR) + h] * np.sin(t * np.pi / 2)[:, None]
out[:240] *= np.linspace(0, 1, 240)[:, None]
n = 2 * SR; out[-n:] *= (np.linspace(1, 0, n) ** 2)[:, None]
o = wave.open(sys.argv[2], 'wb'); o.setnchannels(2); o.setsampwidth(2); o.setframerate(SR)
o.writeframes(np.clip(np.round(out), -32768, 32767).astype(np.int16).tobytes()); o.close()
print("music", len(out) / SR, "s")
PY
