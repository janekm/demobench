# Neon Stadium

An original arena-rave riff written as an homage to Zombie Nation's *Kernkraft 400*. Select **Neon stadium / supersaw & drums** in the viewer, then enable **Sound on**. The [complete cartridge source](../examples/neon-stadium.asm) is **3,604 payload bytes**, including synthesis code, note events, tables and the CPU visual.

Seven saws span detune ratios 0.955 to 1.045, with separate starting phases, balanced stereo weights and guest polyBLEP correction. The lead is an octave below the first sustained draft, centred around E3 rather than E4. Notes last a quarter, half or dotted quarter, with explicit ties: their oscillator phase and envelope continue across eighth-note table rows. A roughly 5 ms attack leads to flat sustain, followed by about 30 ms of release at the event end. The full lead gain is 0.96. This replaces the earlier draft's short, repeatedly triggered envelopes.

The 128 BPM arrangement lasts exactly eight bars (15 seconds). It combines gated bass and chord stabs, a pitch-swept kick, filtered avalanche-noise snare and offbeat hats, and kick-driven attenuation of the music. Sparse drum entry and a brief gap precede the full drop at 7.5 seconds. All algorithms execute as ordinary `g.*` instructions; the SPU API has no new synthesis features. The original Signal Garden remains a separate technical study.

## Reproduce the capture

```sh
npm run capture:audio -- --demo neon-stadium --frames 1800
```

This captures two complete loops: **30 seconds / 1,440,000 stereo frames at 48 kHz**. The two loops are byte-identical in the PCM16 WAV and meet at silence. Files: [WAV](../artifacts/neon-stadium.wav), [cartridge](../artifacts/neon-stadium.db32), [capture report](../artifacts/neon-stadium.json), [screen](../artifacts/neon-stadium.png).

| Measurement | Result |
| --- | ---: |
| Absolute peak | 0.846489 |
| Overall RMS | 0.139892 |
| Drop bar RMS range | 0.15853–0.18636 |
| DC offset | 0.000331 |
| Clipped or nonfinite samples | 0 |
| Reference SPU queue overruns | 0 |
| Reference block work limit | 65,536 ticks |

The reference capture used WASM SHA-256 `8fbac8f8ef7771c0522d05b2d928c760b52075b21c513f9546617184dded0780`. Raw float PCM SHA-256 is `054cc577d96cf34a1f856e8cc561b4766f3b374a489489fcd5dab94e71a1eb83`; WAV SHA-256 is `58c045d54e81827d810481746ac2f2da749afb7dbdd801f7b8dd0c6673fa472a`.

`npm test` passed all 90 existing tests. The final 3,604-byte cartridge also ran in the real WebGPU viewer with a running AudioContext, approximately 60 FPS, observed block dispatch time around 0.5–0.6 ms, and no kernel fallback or browser warning/error logs. Desktop playback did report dropped presentation frames during interactive testing; those are separate from the uninterrupted reference WAV. Sound quality is for listening review, not inferred from numerical tests.
