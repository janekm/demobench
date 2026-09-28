#!/bin/sh
# Cut and nearest-neighbour upscale the 160x120 lossless captures to the exact size each
# scene displays them at (the renderer smooths scaled video, so no scaling happens in CSS).
# usage: tools/encode-footage.sh <capture-dir>   (contains <demo>/raw160.mkv)
set -e
CAP=$1; OUT=$(dirname "$0")/../assets/footage
enc() { # name demo start dur width height [crop]
  vf="${7:+$7,}scale=$5:$6:flags=neighbor"
  ffmpeg -loglevel error -y -ss "$3" -i "$CAP/$2/raw160.mkv" -t "$4" -vf "$vf" -r 60 \
    -c:v libx264 -preset slow -crf 14 -pix_fmt yuv420p -g 30 -movflags +faststart -an "$OUT/$1.mp4"
  echo "$1.mp4"
}
enc title-night    daybreak 0     7.5  1920 1440
enc hero-pelican   pelican  0     3.75 1920 1440
enc hero-carpet    carpet   21.5  3.75 1920 1440
enc hero-limit     limit    45    3.75 1920 1080 crop=160:90:0:15
enc hero-daybreak  daybreak 33.75 3.75 1920 1440
enc arch-tunnel    daybreak 7.5   7.5  320  240
enc sound-tunnel   daybreak 45    7.5  960  720
enc end-daylight   daybreak 52.5  7.5  1920 1440
# creativity wall: 4x2 tiles at 3x (480x360)
set -- "pelican 10.5" "carpet 4" "limit 23.5" "daybreak 37.5" "megamix 30" "megamix 9" "megamix 16" "supersaw 5"
inputs=""; filters=""; i=0
for t in "$@"; do
  d=${t% *}; s=${t#* }
  inputs="$inputs -ss $s -t 7.5 -i $CAP/$d/raw160.mkv"
  filters="$filters[$i:v]scale=480:360:flags=neighbor,setpts=PTS-STARTPTS[t$i];"
  i=$((i+1))
done
ffmpeg -loglevel error -y $inputs -filter_complex \
  "${filters}[t0][t1][t2][t3][t4][t5][t6][t7]xstack=inputs=8:layout=0_0|480_0|960_0|1440_0|0_360|480_360|960_360|1440_360[v]" \
  -map "[v]" -r 60 -c:v libx264 -preset slow -crf 14 -pix_fmt yuv420p -g 30 -movflags +faststart -an "$OUT/wall.mp4"
echo wall.mp4
