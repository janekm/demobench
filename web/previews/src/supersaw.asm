; =====================================================================
;  SUPERSAW  --  a thick JP-8000-style supersaw playing a Sandstorm-style
;  riff (homage), 136 BPM, with a live spectrum analyser. DB32 spu-1.
;  SPU: stateless per-sample synthesis plus a 1024-sample history ring.
;  CPU: copies the ring oldest-first each frame. GPU pass 1 runs 160
;  Goertzel filters over it; pass 2 draws LED bars and the waveform.
; =====================================================================
.profile spu-1
.entry start

.equ FB0,   0x10000
.equ FB1,   0x1E100
.equ AOUT,  0x2C200           ; SPU output block (2048 bytes) ...
.equ RING,  0x2CA00           ; ... the SPU's 512-sample mono history (24 kHz) ...
.equ REV,   0x2D200           ; ... and 1024 reverb records of 4 bf16 (8 KB)
.equ RINGC, 0x2F200           ; oldest-first copy of the history for the GPU
.equ SPECA, 0x2FA00           ; 40 [bar, peak] pairs, ping-pong
.equ SPECB, 0x2FB40

start:
    li r1, cfg
    lw r2, 0(r1)
cfg_next:
    lw r3, 4(r1)
    addi r1, r1, 8
    jal r15, copy
    lw r2, 0(r1)
    bne r2, r0, cfg_next
    lui r12, 0xf6
    lui r13, 0xf3
    lui r14, 0xf5
    li r10, FB0
    li r11, FB1
    li r8, SPECA
    li r9, SPECB
frame:
    ; history ring, oldest sample first (the SPU writes slot t/2 mod 512)
    lw r5, 0x14(r12)            ; SPU sample counter
    addi r2, r0, 1
    shr r5, r5, r2
    andi r5, r5, 511
    add r6, r5, r5
    add r6, r6, r6
    li r1, RING
    add r1, r1, r6
    li r2, RINGC
    addi r3, r0, 512
    sub r3, r3, r5
    jal r15, copy
    li r1, RING
    add r3, r0, r5
    beq r3, r0, copied
    jal r15, copy
copied:
    lw r1, 24(r14)
    sw r1, 0x100(r13)           ; U0 = frame
    li r1, p_spec
    add r6, r0, r8              ; new spectrum
    add r5, r0, r9              ; from last frame's
    jal r7, pass
    li r1, p_disp
    add r6, r0, r10
    add r5, r0, r8
    jal r7, pass
    xor r8, r8, r9
    xor r9, r8, r9
    xor r8, r8, r9
    sw r10, 0(r14)
    addi r2, r0, 1
    sw r2, 20(r14)              ; show at the next vblank
wvbl:
    wfi
    lw r1, 20(r14)
    bne r1, r0, wvbl
    xor r10, r10, r11
    xor r11, r10, r11
    xor r10, r10, r11
    j frame

; pass(r1 = [code, len, w, h, bindings 0-2]); r6, r5 = binding 0, 2 bases
pass:
    add r2, r13, r0
    addi r3, r0, 4
    jal r15, copy
    addi r2, r13, 0x40
    addi r3, r0, 12
    jal r15, copy
    sw r6, 0x40(r13)
    sw r5, 0x60(r13)
    addi r2, r0, 1
    sw r2, 16(r13)              ; START
wgpu:
    wfi
    lw r3, 20(r13)
    beq r3, r2, wgpu
    jalr r0, 0(r7)

; copy r3 words from r1 to r2
copy:
    lw r4, 0(r1)
    sw r4, 0(r2)
    addi r1, r1, 4
    addi r2, r2, 4
    addi r3, r3, -1
    bne r3, r0, copy
    jalr r0, 0(r15)

; ---- include gfx.s ----
; ---------------------------------------------------------------------
; GPU pass 1 (40 x 1): spectrum. Bar b runs a Goertzel filter at
; f = 45 Hz * 2^(b / 5) over the last 512 samples at 24 kHz (binding 1,
; oldest first). Binding 2 holds last frame's [bar, peak] pairs; bars fall
; 2.5 px and peak caps 0.5 px per frame, written to binding 0 (ping-pong).
; ---------------------------------------------------------------------
spec_k:
    g.li g8, 4
    g.fli g10, 1.0
    ; turns per sample = 2^(0.2 b - 9.059), via exponent bits (+16 bias)
    g.id g1, 0
    g.itof g1, g1
    g.fli g2, 0.2
    g.fmul g1, g1, g2
    g.fli g2, 6.941
    g.fadd g1, g1, g2
    g.ftoi g3, g1
    g.itof g2, g3
    g.fsub g1, g1, g2              ; fraction
    g.fli g2, 0.07738064
    g.fmul g2, g2, g1
    g.fli g4, 0.22694011
    g.fadd g2, g2, g4
    g.fmul g2, g2, g1
    g.fli g4, 0.69543002
    g.fadd g2, g2, g4
    g.fmul g2, g2, g1
    g.fadd g2, g2, g10           ; 2^fraction
    g.li g4, 16
    g.sub g3, g3, g4
    g.li g4, 23
    g.shl g3, g3, g4
    g.add g2, g2, g3               ; frequency in turns per sample
    ; 2 cos(2 pi f) with the parabola sine, phase as a 32-bit angle
    g.fli g4, 4294967296.0
    g.fmul g2, g2, g4
    g.ftoi g2, g2
    g.li g4, 0x40000000
    g.add g2, g2, g4
    g.itof g7, g2
    g.fsub g3, g0, g7
    g.fmax g3, g3, g7
    g.fli g4, 8.6736174e-19
    g.fmul g3, g3, g4
    g.fli g4, 1.8626451e-09
    g.fsub g3, g4, g3
    g.fmul g7, g7, g3
    g.fadd g7, g7, g7
    ; Goertzel, two samples per iteration (S1/S2 swap roles)
    g.mov g4, g0
    g.li g9, 2048
goertzel:
    g.ld g1, g4, 1
    g.add g4, g4, g8
    g.fmul g2, g7, g5
    g.fadd g2, g2, g1
    g.fsub g6, g2, g6
    g.ld g1, g4, 1
    g.add g4, g4, g8
    g.fmul g2, g7, g6
    g.fadd g2, g2, g1
    g.fsub g5, g2, g5
    g.sub g2, g4, g9
    g.bnz g2, goertzel
    ; power = s1^2 + s2^2 - c s1 s2 ; log2 from the float's bit pattern
    g.fmul g1, g5, g5
    g.fmul g2, g6, g6
    g.fadd g1, g1, g2
    g.fmul g2, g5, g6
    g.fmul g2, g2, g7
    g.fsub g1, g1, g2
    g.fli g2, 1e-6
    g.fadd g1, g1, g2
    g.itof g1, g1
    g.fli g2, 1.1920929e-07      ; 2^-23
    g.fmul g1, g1, g2
    g.fli g2, -131.0
    g.fadd g1, g1, g2              ; log2(power) - 4
    g.fli g2, 7.0
    g.fmul g1, g1, g2
    g.id g3, 0
    g.itof g3, g3
    g.fli g2, 0.88
    g.fmul g3, g3, g2
    g.fadd g1, g1, g3              ; tilt: brighten the highs
    g.fmax g1, g1, g0
    g.id g4, 0
    g.mul g4, g4, g8
    g.add g4, g4, g4
    g.ld g2, g4, 2                ; last bar, falling
    g.fli g3, 2.5
    g.fsub g2, g2, g3
    g.fmax g1, g1, g2
    g.st g1, g4, 0
    g.add g4, g4, g8
    g.ld g2, g4, 2                ; last peak, falling slower
    g.fli g3, 0.5
    g.fsub g2, g2, g3
    g.fmax g1, g1, g2
    g.st g1, g4, 0
    g.end
spec_k_end:

; ---------------------------------------------------------------------
; GPU pass 2 (160 x 120): LED spectrum analyser (40 bars) + waveform
; of the newest 240 samples as a glowing trace.
; ---------------------------------------------------------------------
disp_k:
    g.li g11, 4
    g.li g14, 1
    g.fli g10, 1.0
    g.id g7, 1
    g.itof g12, g7
    g.li g6, 119
    g.sub g4, g6, g7
    g.itof g4, g4
    ; bar of this column: 4 columns per bar, last one is a gap
    g.id g6, 0
    g.li g7, -4
    g.and g6, g6, g7
    g.add g7, g6, g6
    g.ld g5, g7, 2
    g.add g7, g7, g11
    g.ld g15, g7, 2
    ; LED colour ramps teal -> gold -> hot pink with height
    g.fli g13, 0.009
    g.fmul g13, g4, g13
    g.fmin g13, g13, g10
    g.fadd g1, g13, g13
    g.fmin g1, g1, g10   ; r = min(2t, 1)
    g.fmul g2, g13, g13
    g.fsub g2, g10, g2   ; g = 1 - t^2
    g.fadd g7, g13, g13
    g.fsub g7, g7, g10
    g.fmul g7, g7, g7              ; (2t - 1)^2
    g.fli g8, 0.7
    g.fmul g3, g7, g8
    g.fli g8, 0.1
    g.fadd g3, g3, g8      ; b dips to 0.1 at gold
    ; lit if below the bar top, dimmed ghost otherwise; gaps between LEDs
    g.flt g9, g4, g5
    g.itof g9, g9
    ; unlit LEDs glow faintly with the kick (bar 1)
    g.li g7, 8
    g.ld g8, g7, 2
    g.fli g7, 0.0009
    g.fmul g8, g8, g7
    g.fli g7, 0.03
    g.fadd g8, g8, g7
    g.fmax g9, g9, g8
    ; peak cap: the LEDs just under the peak light up white
    g.fsub g6, g15, g4
    g.fli g7, 3.0
    g.flt g6, g6, g7
    g.flt g8, g4, g15
    g.and g6, g6, g8
    g.itof g6, g6
    g.fmax g9, g9, g6
    g.fli g7, 0.7
    g.fmul g6, g6, g7
    g.fadd g1, g1, g6
    g.fadd g2, g2, g6
    g.fadd g3, g3, g6
    g.id g6, 0                   ; column 3 of each bar is a gap
    g.li g8, 3
    g.and g6, g6, g8
    g.sub g6, g6, g8
    g.bnz g6, no_gap
    g.mov g9, g0
no_gap:
    g.id g6, 1
    g.li g8, 3
    g.itof g6, g6
    g.itof g8, g8
    g.fdiv g7, g6, g8
    g.ftoi g7, g7
    g.itof g7, g7
    g.fmul g7, g7, g8
    g.fsub g6, g6, g7              ; y mod 3
    g.fli g7, 1.5
    g.flt g6, g6, g7
    g.itof g6, g6
    g.fmul g9, g9, g6              ; every third row dark
    g.vscale g1, g1, g9
    ; waveform: samples 272 + 1.5 x and the next one (newest 240)
    g.id g6, 0
    g.shr g7, g6, g14
    g.add g6, g6, g7
    g.li g7, 272
    g.add g6, g6, g7
    g.mul g6, g6, g11
    g.ld g7, g6, 1
    g.add g6, g6, g11
    g.ld g8, g6, 1
    g.fli g6, 38.0
    g.fmul g7, g7, g6
    g.fmul g8, g8, g6
    g.fli g6, 52.0
    g.fsub g7, g6, g7
    g.fsub g8, g6, g8
    g.fmin g6, g7, g8
    g.fmax g8, g7, g8
    g.fsub g6, g6, g12
    g.fsub g8, g12, g8
    g.fmax g6, g6, g8
    g.fmax g6, g6, g0
    g.fmul g6, g6, g6
    g.fli g7, 0.7
    g.fmul g6, g6, g7
    g.fadd g6, g6, g10
    g.fdiv g6, g10, g6           ; glow
    g.fli g7, 0.8
    g.fmul g7, g6, g7
    g.fadd g1, g1, g7
    g.fadd g2, g2, g6
    g.fadd g3, g3, g6
    g.sqrt g1, g1
    g.sqrt g2, g2
    g.sqrt g3, g3
    g.id g6, 2
    g.rgb g1, g6, 0
    g.end
disp_k_end:

; ---- include spu.s ----
; ---------------------------------------------------------------------
; SPU kernel: one invocation per stereo sample (grid 64x4), stateless.
; Lead: 7-saw supersaw (JP-8000 detune curve, PolyBLEP, spread by detune)
; plus a second 7-saw layer an octave down, evaluated at every echo tap.
; Then kick, offbeat bass, clap, hats and roll at the dry position, and
; a 4-line feedback delay network reverb (24 kHz, bf16 state in RAM) fed
; by the lead and clap. Reverb reads only samples from earlier blocks.
; ---------------------------------------------------------------------
; reverb (after the dry part)

; flag bits per bar
.equ LEAD, 1
.equ OCTV, 2
.equ KICK, 4
.equ BASS, 8
.equ CLAP, 16
.equ HATS, 32
.equ ROLL, 64

spu_k:
    g.id g1, 2
    g.uniform g18, 14
    g.add g1, g1, g18
    g.id g29, 5                  ; grid height 4
    g.sltu g23, g0, g29
    g.fli g24, 1.0
    g.li g25, 5294
    g.li g4, d_taps_end - d_taps
tap_loop:
    g.sub g4, g4, g29
    g.sub g4, g4, g29
    g.li g22, d_taps - d_base
    g.add g22, g22, g4
    g.ld g18, g22, 1                ; delay
    g.add g22, g22, g29
    g.ld g21, g22, 1                ; [gain | pan]
    g.sub g5, g1, g18
    g.slt g18, g5, g0
    g.bnz g18, next_tap
    g.li g18, 0xffff0000
    g.and g11, g21, g18             ; tap gain
    g.li g18, 16
    g.shl g17, g21, g18              ; tap pan
    ; ---- song position of TT ----
    g.itof g18, g5
    g.itof g19, g25
    g.fdiv g18, g18, g19
    g.ftoi g6, g18
    g.mul g18, g6, g25
    g.sub g7, g5, g18
    g.li g18, 4
    g.shr g19, g6, g18            ; bar
    g.sub g19, g19, g29              ; after the 4-bar intro the song loops 12 bars
    g.slt g18, g19, g0
    g.bnz g18, intro
    g.itof g18, g19
    g.fli g20, 0.083333336
    g.fmul g18, g18, g20
    g.ftoi g18, g18
    g.li g20, 12
    g.mul g18, g18, g20
    g.sub g19, g19, g18
intro:
    g.add g19, g19, g29
    g.li g22, d_flags - d_base
    g.add g22, g22, g19
    g.ldb g8, g22, 1
    ; samples since the beat, and kick sidechain
    g.li g18, 3
    g.and g18, g6, g18
    g.mul g28, g18, g25
    g.add g28, g28, g7
    g.mov g26, g24
    g.and g18, g8, g29             ; KICK = 4
    g.bz g18, no_duck
    g.itof g18, g28
    g.fli g19, 0.00016
    g.fmul g18, g18, g19
    g.fli g19, 0.3
    g.fadd g18, g18, g19
    g.fmin g26, g18, g24
no_duck:
    g.and g18, g8, g23            ; LEAD = 1
    g.bz g18, next_tap
    ; ---- riff note, gate: held steps continue the previous note ----
    g.li g18, 31
    g.and g19, g6, g18
    g.li g22, d_riff - d_base
    g.add g22, g22, g19
    g.ldb g9, g22, 1
    g.mov g30, g7               ; time since the note started
    g.li g10, 3282             ; staccato 16th
    g.bnz g9, not_held
    g.sub g22, g22, g23
    g.ldb g9, g22, 1
    g.add g30, g30, g25
    g.li g10, 9000             ; held 8th
    g.jmp gated
not_held:
    g.add g22, g22, g23
    g.ldb g18, g22, 1
    g.bnz g18, gated
    g.li g10, 9000
gated:
    g.sub g18, g10, g30
    g.slt g19, g18, g0
    g.bnz g19, next_tap           ; note is over
    g.itof g18, g18
    g.fli g19, 0.0025
    g.fmul g18, g18, g19              ; 8 ms release
    g.itof g14, g30
    g.fli g19, 0.007
    g.fmul g19, g14, g19           ; 3 ms attack
    g.fmin g18, g18, g19
    g.fmin g18, g18, g24
    g.fmul g11, g11, g18
    g.fmul g11, g11, g26
    g.fli g18, 0.11
    g.fmul g11, g11, g18
    ; frequency of the note
    g.add g22, g9, g9
    g.add g22, g22, g22
    g.li g18, d_freq - 4 - d_base
    g.add g22, g22, g18
    g.ld g10, g22, 1             ; note frequency (GATE is free now)
    g.mov g9, g11               ; note envelope
    g.li g27, 2                 ; layers: main, wide double (+ octave below)
    g.li g18, OCTV
    g.and g18, g8, g18
    g.bz g18, lay_n
    g.add g27, g27, g23
lay_n:
    g.li g22, d_layers - d_base
layer:
    g.ld g18, g22, 1
    g.fmul g12, g10, g18           ; pitch ratio
    g.add g22, g22, g29
    g.ld g18, g22, 1
    g.fmul g11, g9, g18           ; level
    g.add g22, g22, g29
    g.ld g5, g22, 1               ; detune amount
    g.add g22, g22, g29
    g.ld g30, g22, 1               ; stereo spread (signed)
    g.add g22, g22, g29
    g.fdiv g13, g24, g12
    g.li g15, d_det - d_base
    g.mov g16, g0
osc:
    g.ld g31, g15, 1              ; detune coefficient c
    g.fmul g19, g31, g5
    g.fadd g19, g19, g24
    g.fmul g19, g19, g12              ; f * (1 + 0.36 c)
    g.fmul g20, g14, g19
    g.fadd g20, g20, g16
    g.ftoi g21, g20
    g.itof g21, g21
    g.fsub g20, g20, g21              ; phase p in [0,1)
    g.fadd g21, g20, g20
    g.fsub g21, g21, g24           ; naive saw
    g.fmul g19, g20, g13
    g.fmin g19, g19, g24
    g.fsub g19, g19, g24
    g.fmul g19, g19, g19
    g.fadd g21, g21, g19              ; PolyBLEP after the wrap
    g.fsub g19, g20, g24
    g.fmul g19, g19, g13
    g.fadd g19, g19, g24
    g.fmax g19, g19, g0
    g.fmul g19, g19, g19
    g.fsub g21, g21, g19              ; PolyBLEP before the wrap
    ; level tapers with detune; pan grows with it
    g.fsub g19, g0, g31
    g.fmax g19, g19, g31
    g.fli g20, -3.2
    g.fmul g19, g19, g20
    g.fadd g19, g19, g24
    g.fmul g21, g21, g19
    g.fmul g21, g21, g11
    g.fadd g2, g2, g21
    g.fmul g19, g31, g30
    g.fadd g19, g19, g17
    g.fmul g19, g19, g21
    g.fadd g3, g3, g19
    g.fli g19, 0.618034
    g.fadd g16, g16, g19
    g.add g15, g15, g29
    g.li g19, d_det_end - d_base
    g.sub g19, g15, g19
    g.bnz g19, osc
    g.fli g19, 1.9
    g.fadd g16, g16, g19        ; decorrelate the layers
    g.sub g27, g27, g23
    g.bnz g27, layer
next_tap:
    g.bnz g4, tap_loop
    g.mov g5, g2                 ; reverb send: lead and echoes
    g.mov g17, g3

; ---- dry part: STEP, LOC, BL, FL, DUCK now describe T ----
    ; noise (hash squared) and its high-passed version
    g.li g18, 0x9E3779B1
    g.mul g30, g1, g18
    g.mul g30, g30, g30
    g.sub g19, g1, g23
    g.mul g19, g19, g18
    g.mul g19, g19, g19
    g.itof g30, g30
    g.itof g19, g19
    g.fsub g19, g30, g19
    g.fli g18, 4.656613e-10
    g.fmul g30, g30, g18            ; white
    g.fmul g31, g19, g18              ; high-passed
    ; ---- kick: f = 50 + 150 / (1 + t/1200)^2 Hz ----
    g.and g18, g8, g29
    g.bz g18, no_kick
    g.itof g18, g28
    g.fli g19, 0.00083333
    g.fmul g19, g18, g19
    g.fadd g19, g19, g24           ; 1 + t/1200
    g.fdiv g20, g24, g19
    g.fsub g20, g24, g20
    g.fli g21, 3.75
    g.fmul g20, g20, g21              ; 150*1200/48000 (1 - 1/(1+t/1200))
    g.fli g21, 0.0010416667
    g.fmul g21, g18, g21              ; 50 t / 48000
    g.fadd g20, g20, g21              ; phase in turns
    g.ftoi g21, g20
    g.itof g21, g21
    g.fsub g20, g20, g21
    g.fli g21, 0.5
    g.fsub g20, g20, g21              ; [-.5, .5)
    g.fsub g21, g0, g20
    g.fmax g21, g21, g20
    g.fadd g21, g21, g21
    g.fsub g21, g24, g21
    g.fmul g20, g20, g21              ; -sin/8
    g.fli g21, 0.00025
    g.fmul g18, g18, g21
    g.fadd g18, g18, g24
    g.fmul g18, g18, g18
    g.fli g21, -7.0
    g.fdiv g18, g21, g18              ; amplitude envelope (sign flips the sine)
    g.fmul g20, g20, g18
    g.fadd g2, g2, g20
no_kick:
    ; ---- offbeat bass: 2 detuned saws + sub, riff root two octaves down ----
    g.li g18, BASS
    g.and g18, g8, g18
    g.bz g18, no_bass
    g.li g18, 2
    g.and g18, g6, g18
    g.bz g18, no_bass             ; plays on the '&' of each beat
    g.li g18, 1
    g.and g18, g6, g18
    g.mul g18, g18, g25
    g.add g18, g18, g7             ; samples since the bass note
    g.itof g14, g18
    g.li g18, 31
    g.and g19, g6, g18
    g.li g22, d_riff - d_base
    g.add g22, g22, g19
    g.ldb g9, g22, 1
    g.bnz g9, bass_note
    g.sub g22, g22, g23
    g.ldb g9, g22, 1
bass_note:
    g.add g22, g9, g9
    g.add g22, g22, g22
    g.li g18, d_freq - 4 - d_base
    g.add g22, g22, g18
    g.ld g12, g22, 1
    g.fli g18, 0.5
    g.fmul g12, g12, g18
    g.fdiv g13, g24, g12
    ; envelope: 2 ms attack, decay, cut before the next beat
    g.fli g18, 0.01
    g.fmul g18, g14, g18
    g.fmin g18, g18, g24
    g.fli g19, 0.0001
    g.fmul g19, g14, g19
    g.fadd g19, g19, g24
    g.fdiv g11, g18, g19
    g.fmul g11, g11, g26
    g.fli g18, 0.16
    g.fmul g11, g11, g18
    g.mov g16, g0
    g.li g15, d_det - d_base    ; outermost detunes of the lead table: +-4%
    g.mov g27, g23
    g.add g27, g27, g23
bass_osc:
    g.ld g31, g15, 1
    g.fli g19, 0.06
    g.fmul g19, g31, g19
    g.fadd g19, g19, g24
    g.fmul g19, g19, g12
    g.fmul g20, g14, g19
    g.fadd g20, g20, g16
    g.ftoi g21, g20
    g.itof g21, g21
    g.fsub g20, g20, g21
    g.fadd g21, g20, g20
    g.fsub g21, g21, g24
    g.fmul g19, g20, g13
    g.fmin g19, g19, g24
    g.fsub g19, g19, g24
    g.fmul g19, g19, g19
    g.fadd g21, g21, g19
    g.fsub g19, g20, g24
    g.fmul g19, g19, g13
    g.fadd g19, g19, g24
    g.fmax g19, g19, g0
    g.fmul g19, g19, g19
    g.fsub g21, g21, g19
    g.fmul g21, g21, g11
    g.fadd g2, g2, g21
    g.fmul g19, g31, g21
    g.fadd g3, g3, g19
    g.fli g19, 0.5
    g.fadd g16, g16, g19
    g.li g19, 24
    g.add g15, g15, g19           ; c[0] then c[6]
    g.sub g27, g27, g23
    g.bnz g27, bass_osc
    ; sub sine an octave below
    g.fli g19, 0.5
    g.fmul g20, g12, g19
    g.fmul g20, g20, g14
    g.ftoi g21, g20
    g.itof g21, g21
    g.fsub g20, g20, g21
    g.fli g21, 0.5
    g.fsub g20, g20, g21
    g.fsub g21, g0, g20
    g.fmax g21, g21, g20
    g.fadd g21, g21, g21
    g.fsub g21, g24, g21
    g.fmul g20, g20, g21
    g.fli g21, -5.0
    g.fmul g20, g20, g21
    g.fmul g20, g20, g11
    g.fadd g2, g2, g20
no_bass:
    ; ---- clap on beats 2 and 4 ----
    g.li g18, CLAP
    g.and g18, g8, g18
    g.bz g18, no_clap
    g.and g18, g6, g29
    g.bz g18, no_clap
    g.itof g18, g28
    g.fli g19, 0.0015
    g.fmul g18, g18, g19
    g.fadd g18, g18, g24
    g.fmul g18, g18, g18
    g.fli g19, 0.32
    g.fdiv g18, g19, g18
    g.fmul g19, g30, g18
    g.fadd g2, g2, g19
    g.fadd g5, g5, g19            ; claps go to the reverb too
    g.fmul g19, g31, g18              ; bright part slightly off-centre
    g.fli g20, 0.3
    g.fmul g19, g19, g20
    g.fadd g3, g3, g19
no_clap:
    ; ---- hats: closed 16ths, open on the offbeat ----
    g.li g18, HATS
    g.and g18, g8, g18
    g.bz g18, no_hats
    g.itof g18, g7
    g.fli g19, 0.004
    g.fmul g18, g18, g19
    g.fadd g18, g18, g24
    g.fmul g18, g18, g18
    g.fli g19, 0.05
    g.fdiv g18, g19, g18
    g.fmul g19, g31, g18
    g.fadd g2, g2, g19
    g.fsub g3, g3, g19
    g.li g18, 2
    g.and g18, g6, g18
    g.bz g18, no_hats
    g.li g18, 1
    g.and g18, g6, g18
    g.mul g18, g18, g25
    g.add g18, g18, g7
    g.itof g18, g18
    g.fli g19, 0.0004
    g.fmul g18, g18, g19
    g.fadd g18, g18, g24
    g.fmul g18, g18, g18
    g.fli g19, 0.07
    g.fdiv g18, g19, g18
    g.fmul g19, g31, g18
    g.fadd g2, g2, g19
    g.fadd g3, g3, g19
no_hats:
    ; ---- snare roll build: every 16th, louder through two bars ----
    g.li g18, ROLL
    g.and g18, g8, g18
    g.bz g18, no_roll
    g.li g18, 31
    g.and g18, g6, g18
    g.add g18, g18, g23
    g.itof g18, g18
    g.fli g19, 0.012
    g.fmul g19, g18, g19
    g.itof g18, g7
    g.fli g20, 0.0025
    g.fmul g18, g18, g20
    g.fadd g18, g18, g24
    g.fmul g18, g18, g18
    g.fdiv g18, g19, g18
    g.fmul g19, g30, g18
    g.fadd g2, g2, g19
no_roll:
    ; ---- reverb: 4 lines, delays 500-900 at 24 kHz; records of 4 bf16 ----
    ; line outputs are damped (two adjacent samples) and scaled by the decay
    g.shr g6, g1, g23
    g.li g13, 0xffff0000
    g.li g14, 1023
    g.li g16, 3
    g.fli g20, 0.232
    g.li g7, d_rev - d_base
rev_line:
    g.ld g18, g7, 1               ; delay
    g.add g7, g7, g29
    g.ld g4, g7, 1              ; 4096 + word offset in the record
    g.add g7, g7, g29
    g.ld g15, g7, 1              ; 16: low half, 0: high half
    g.add g7, g7, g29
    g.sub g18, g6, g18
    g.and g21, g18, g14
    g.shl g21, g21, g16
    g.add g21, g21, g4
    g.ld g21, g21, 0
    g.shl g21, g21, g15
    g.and g19, g21, g13
    g.sub g18, g18, g23
    g.and g21, g18, g14
    g.shl g21, g21, g16
    g.add g21, g21, g4
    g.ld g21, g21, 0
    g.shl g21, g21, g15
    g.and g21, g21, g13
    g.fadd g21, g21, g19
    g.fmul g21, g21, g20
    g.mov g12, g11
    g.mov g11, g10
    g.mov g10, g9
    g.mov g9, g21
    g.li g18, d_rev_end - d_base
    g.sub g18, g7, g18
    g.bnz g18, rev_line
    ; wet signal, pumped by the kick
    g.fadd g18, g9, g11
    g.fadd g19, g10, g12
    g.fli g21, 0.15
    g.fmul g21, g21, g26
    g.fmul g18, g18, g21
    g.fmul g19, g19, g21
    g.fadd g21, g18, g19
    g.fadd g2, g2, g21
    g.fsub g21, g18, g19
    g.fadd g3, g3, g21
    ; ---- output with soft limiter x / sqrt(1 + x^2) ----
    g.fadd g18, g2, g3
    g.fsub g19, g2, g3
    g.fmul g20, g18, g18
    g.fadd g20, g20, g24
    g.rsqrt g20, g20
    g.fmul g18, g18, g20
    g.fmul g20, g19, g19
    g.fadd g20, g20, g24
    g.rsqrt g20, g20
    g.fmul g19, g19, g20
    g.id g22, 2
    g.mul g22, g22, g29
    g.add g22, g22, g22
    g.st g18, g22, 0
    g.add g22, g22, g29
    g.st g19, g22, 0
    g.fadd g31, g18, g19              ; mono mix for the analyser
    ; even samples advance the reverb: Hadamard mix plus the send
    g.and g18, g1, g23
    g.bnz g18, rev_done
    g.fadd g18, g9, g10
    g.fsub g19, g9, g10
    g.fadd g20, g11, g12
    g.fsub g21, g11, g12
    g.fadd g9, g18, g20
    g.fsub g11, g18, g20
    g.fadd g10, g19, g21
    g.fsub g12, g19, g21
    g.fadd g18, g5, g17            ; send L
    g.fsub g19, g5, g17            ; send R
    g.fadd g9, g9, g18
    g.fadd g10, g10, g19
    g.fsub g11, g11, g18
    g.fsub g12, g12, g19
    g.shr g9, g9, g15            ; pack to bf16 (SH = 16 after the loop)
    g.and g10, g10, g13
    g.or g9, g9, g10
    g.shr g11, g11, g15
    g.and g12, g12, g13
    g.or g11, g11, g12
    g.and g22, g6, g14
    g.shl g22, g22, g16
    g.add g22, g22, g4              ; RB = 4096 after the loop
    g.st g9, g22, 0
    g.add g22, g22, g29
    g.st g11, g22, 0
    ; analyser history at 24 kHz: ring[k mod 512] after the output block
    g.shr g18, g14, g23
    g.and g22, g6, g18
    g.mul g22, g22, g29
    g.shr g18, g4, g23
    g.add g22, g22, g18
    g.st g31, g22, 0
rev_done:
    g.end
spu_k_end:


; ---------------------------------------------------------------------
; music data (SPU binding 1)
; ---------------------------------------------------------------------
.align 4
d_base:
; bar flags: 1 lead, 2 lead octave layer, 4 kick, 8 bass, 16 clap, 32 hats, 64 roll
; bars 0-3 intro, then 4..15 loop: 8 bars full, 2 breakdown, 2 build
d_flags:
    .byte 1, 1, 37, 37
    .byte 63, 63, 63, 63, 63, 63, 63, 63
    .byte 3, 3, 67, 99
; the riff, 32 sixteenths: note index (1 B4, 2 E5, 3 D5, 4 A4), 0 = held
d_riff:
    .byte 1, 1, 1, 1, 1, 0
    .byte 1, 1, 1, 1, 1, 1, 1, 0
    .byte 2, 2, 2, 2, 2, 2, 2, 0
    .byte 3, 3, 3, 3, 3, 3, 3, 0
    .byte 4, 4
    .byte 1                     ; wrap-around for the look-ahead
.align 4
; note frequencies in turns per sample
d_freq:
    .float 0.0051446175, 0.006867241, 0.006118016, 0.0045833335
; supersaw detune curve (JP-8000, relative)
d_det:
    .float -0.11002313, -0.06288439, -0.01952356, 0.0, 0.01991221, 0.06216538, 0.10745242
d_det_end:
; supersaw layers: pitch ratio, level, detune amount, stereo spread
d_layers:
    .float 1.0, 1.0, 0.36, 9.0
    .float 1.0, 0.75, 0.62, -9.0
    .float 0.5, 0.55, 0.36, 9.0
; taps: [delay] [.bf gain, pan]; last entry processed first, dry tap last
d_taps:
    .word 0
    .word 0x3f800000 ; bf 1, 0
    .word 1733
    .word 0x3e613f1a ; bf 0.22, 0.6
    .word 2851
    .word 0x3e38bf1a ; bf 0.18, -0.6
    .word 15882                 ; dotted 8th ping-pong
    .word 0x3ea4bf40 ; bf 0.32, -0.75
    .word 31764
    .word 0x3e4d3f40 ; bf 0.2, 0.75
    .word 47646
    .word 0x3df6bf40 ; bf 0.12, -0.75
d_taps_end:
; reverb lines: delay (24 kHz samples), byte offset of its word, unpack shift
d_rev:
    .word 887, 4100, 0
    .word 757, 4100, 16
    .word 631, 4096, 0
    .word 523, 4096, 16          ; last: leaves RB = 4096, SH = 16
d_rev_end:
d_end:

; ---------------------------------------------------------------------
; MMIO configuration script: [dest, count, words...], 0 terminates
; ---------------------------------------------------------------------
cfg:
    .word 0xf6040, 5, spu_k, spu_k_end - spu_k, 64, 4, AOUT
    .word 0xf6100, 7, AOUT, 12288, 3, 0, d_base, d_end - d_base, 1
    .word 0xf6000, 1, 1
    .word 0xf5004, 4, 480, 4, 0, 1
    .word 0
; GPU passes: code, length, grid, bindings 0..2
p_spec:
    .word spec_k, spec_k_end - spec_k, 40, 1
    .word 0, 320, 3, 0, RINGC, 2048, 1, 0, 0, 320, 1, 0
p_disp:
    .word disp_k, disp_k_end - disp_k, 160, 120
    .word 0, 57600, 3, 0, RINGC, 2048, 1, 0, 0, 320, 1, 0

