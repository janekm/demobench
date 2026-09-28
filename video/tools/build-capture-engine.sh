#!/bin/sh
# Build a capture-only copy of the DB32 engine in which every video frame lasts 32x as many
# ticks (and every audio block too, so sound stays at 800 samples per frame). GPU work that
# spans several vblanks on the reference engine then finishes inside one, so each frame is
# presented, as with the WebGPU path in the browser. Guest programs are unchanged.
# usage: tools/build-capture-engine.sh   -> .capture-engine/{machine.wasm,wasm-host.mjs,smooth-capture.mjs}
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUT="$HERE/../.capture-engine"
mkdir -p "$OUT"
rsync -a "$ROOT/Cargo.toml" "$ROOT/Cargo.lock" "$ROOT/crates" "$OUT/"
sed -i '' 's/pub const LINE_TICKS: u64 = 1600;/pub const LINE_TICKS: u64 = 1600 * 32;/; s/pub const AUDIO_BLOCK_TICKS: u64 = 65_536;/pub const AUDIO_BLOCK_TICKS: u64 = 65_536 * 32;/' "$OUT/crates/db-contracts/src/lib.rs"
sed -i '' 's/pub const BLOCK_TICKS: u64 = 65_536;/pub const BLOCK_TICKS: u64 = 65_536 * 32;/' "$OUT/crates/db-spu/src/lib.rs"
(cd "$OUT" && RUSTFLAGS='-C link-arg=--max-memory=16777216 -C link-arg=-zstack-size=1048576' \
  cargo build --release --target wasm32-unknown-unknown -p db-wasm)
cp "$OUT/target/wasm32-unknown-unknown/release/db_wasm.wasm" "$OUT/machine.wasm"
sed "s#export const FRAME_TICKS = 204800;#export const FRAME_TICKS = 204800 * 32;#; s#new URL('../web/machine.wasm', import.meta.url)#new URL('./machine.wasm', import.meta.url)#" \
  "$ROOT/scripts/wasm-host.mjs" > "$OUT/wasm-host.mjs"
cp "$HERE/smooth-capture.mjs" "$OUT/"
echo "capture engine ready: node $OUT/smooth-capture.mjs <demo.asm> --frames 3600 --out <dir>"
