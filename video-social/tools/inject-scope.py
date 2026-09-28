# Bake the soundtrack's waveform into a composition as base64 int8 frames, so its
# oscilloscope draws the real music deterministically (no audio analysis at render time).
# usage: python3 tools/inject-scope.py assets/audio/daybreak.wav compositions/s05-machine.html 22.5
import base64, re, sys, wave
import numpy as np

wav, html, start = sys.argv[1], sys.argv[2], float(sys.argv[3])
FPS, FRAMES, POINTS, WINDOW = 60, 450, 128, 512
w = wave.open(wav)
sr = w.getframerate()
x = np.frombuffer(w.readframes(w.getnframes()), np.int16).reshape(-1, 2).astype(np.float64).mean(1) / 32768
out = np.zeros((FRAMES, POINTS), np.int8)
for f in range(FRAMES):
    a = int(round((start + f / FPS) * sr))
    seg = x[a:a + WINDOW + 600]
    # trigger on a rising zero crossing, like a scope, so the trace holds still
    z = np.nonzero((seg[:-1] <= 0) & (seg[1:] > 0))[0]
    o = int(z[0]) if len(z) and z[0] < 600 else 0
    win = seg[o:o + WINDOW]
    if len(win) < WINDOW:
        win = np.pad(win, (0, WINDOW - len(win)))
    pts = win.reshape(POINTS, -1).mean(1) / 0.9
    out[f] = np.clip(np.round(pts * 127), -127, 127).astype(np.int8)
b64 = base64.b64encode(out.tobytes()).decode()
src = open(html).read()
new, n = re.subn(r'/\*SCOPE-BEGIN\*/.*?/\*SCOPE-END\*/', lambda m: f'/*SCOPE-BEGIN*/"{b64}"/*SCOPE-END*/', src, flags=re.S)
assert n == 1, "marker not found"
open(html, "w").write(new)
print(f"{html}: {FRAMES} frames from {start}s, {len(b64)} base64 chars")
