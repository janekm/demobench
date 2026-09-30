; LOAD 0x2DA00
; =====================================================================
;  KOI -- a 4K intro for DB32 (dynamic-1, packed).
;  A koi pond, silent: Gerstner waves + FBM ripples + a GPU wave equation;
;  Schlick-Fresnel reflections, Beer-Lambert water, caustics traced from
;  refracted sunlight; koi with undulating bodies, schooling as boids.
;  RAM: page A 0x10000 and page B 0x1C4E0 (RGB888, 160x90 letterbox: the
;  pages share their 15 black rows), state A 0x2AE00,
;  state B 0x2C400 (wave grid + koi), image LOAD..0x30000.
;  Uniforms (both kernels): 0 time, 1 sin(tilt), 2 camx, 3 camz, 4 distance,
;  5 Gerstner amp, 6 ripple amp, 7/8 sun direction x/z (per unit down),
;  9 warmth, 10 overcast, 11 exposure, 12 rain, 13 school depth, 14 event,
;  15 first row (render)
; =====================================================================
.profile dynamic-1
.entry start
.equ VISA,  0x11C20             ; page A, first visible row (15)
.equ VISB,  0x1E100             ; page B, first visible row
.equ STA,   0x2AE00
.equ STB,   0x2C400
.equ LOOP,  3600                ; 9 scenes of 400 frames
.equ SCENE, 400
.equ NPAR,  13
.equ TITLE, 1600                ; depth of the title's letters (8192 = 1)

; d = frac(x), x > -1024 (R scratch, K1K = 1024.0)
; d = sin(2 pi x) / 8 = g (2|g| - 1), g = frac(x) - 1/2 (R scratch)
; d = 2^-y for 0 <= y < 60 (y, R, R2 clobbered)

start:
    lui r13, 0xf3
    lui r14, 0xf5
    li r1, cfg
    lw r2, 0(r1)
cfg_next:
    lw r3, 4(r1)
    addi r1, r1, 8
cfg_copy:
    lw r12, 0(r1)
    sw r12, 0(r2)
    addi r1, r1, 4
    addi r2, r2, 4
    addi r3, r3, -1
    bne r3, r0, cfg_copy
    lw r2, 0(r1)
    bne r2, r0, cfg_next
    li r10, VISA                ; back buffer (visible rows); front = r10 ^ 0xfd20
    li r7, STA                  ; state read this frame; written = r7 ^ 0x6a00
    lw r9, 24(r14)              ; frame counter at the demo start
frame:
    lw r1, 24(r14)
    sub r1, r1, r9              ; demo frame
    addi r2, r0, LOOP
    blt r1, r2, inloop
    add r9, r9, r2
    sub r1, r1, r2
    li r2, lastev
    addi r3, r0, -1
    sw r3, 0(r2)
inloop:
    ; events between the last frame and this one -> U14
    li r3, events
    li r2, lastev
    lw r4, 0(r2)
    sw r1, 0(r2)
    mov r5, r0
    addi r12, r0, 20
ev:
    lw r2, 0(r3)
    shr r6, r2, r12             ; frame
    blt r1, r6, ev_done
    addi r3, r3, 4
    blt r6, r4, ev
    beq r6, r4, ev
    mov r5, r2
    j ev
ev_done:
    sw r5, 0x138(r13)
    ; the time (s7.8, frame * 256 / 60) as a constant [t | t] record word
    li r2, 17476
    mul r2, r1, r2
    addi r3, r0, 12
    shr r2, r2, r3
    addi r3, r0, 16
    shl r4, r2, r3
    or r2, r2, r4
    li r3, prec
    sw r2, 0(r3)
    ; scene r6, frame in the scene r1
    mov r6, r0
    addi r2, r0, SCENE
find:
    blt r1, r2, found
    sub r1, r1, r2
    addi r6, r6, 1
    j find
found:
    ; progress, Q15 (400 frames -> 32800)
    addi r2, r0, 82
    mul r1, r1, r2
    ; keyframes 0 .. scene + 1: each a mask (stop bit 13) and the changed
    ; values; every parameter word becomes [previous | current]
    li r3, keys
    addi r6, r6, 2
    addi r8, r0, 1
    addi r11, r0, 16
dkey:
    lhu r2, 0(r3)
    addi r3, r3, 2
    li r15, prec + 4
dval:
    lw r5, 0(r15)
    andi r4, r5, 0xffff
    and r12, r2, r8
    beq r12, r0, dkeep
    lhu r4, 0(r3)
    addi r3, r3, 2
dkeep:
    shl r5, r5, r11
    or r5, r5, r4
    sw r5, 0(r15)
    addi r15, r15, 4
    shr r2, r2, r8
    bne r2, r8, dval
    addi r6, r6, -1
    bne r6, r0, dkey
    ; uniforms 0..13: each [a | b] word lerped, as floats
    addi r3, r13, 0x100
    addi r6, r0, NPAR + 1
    li r4, prec
lerp:
    lw r5, 0(r4)
    addi r4, r4, 4
    sar r2, r5, r11             ; a
    shl r5, r5, r11
    sar r5, r5, r11             ; b
    sub r5, r5, r2
    mul r5, r5, r1
    addi r15, r0, 15
    sar r5, r5, r15
    add r5, r5, r2              ; a + (b - a) e
    beq r5, r0, cstore
    mov r2, r0
    blt r0, r5, cpos
    sub r5, r0, r5
    lui r2, 0x80000             ; sign
cpos:
    addi r12, r0, 142           ; exponent of 2^23 / 256
    lui r15, 0x800              ; 2^23
cnorm:
    bltu r5, r15, cdbl
    sub r5, r5, r15
    mul r12, r12, r15
    or r5, r5, r12
    or r5, r5, r2
    j cstore
cdbl:
    add r5, r5, r5
    addi r12, r12, -1
    j cnorm
cstore:
    sw r5, 0(r3)
    addi r3, r3, 4
    addi r6, r6, -1
    bne r6, r0, lerp
    ; update: wave equation + boids, reading r7 and writing r8
    xori r8, r7, 0x6a00
    li r2, upd_k
    li r3, upd_k_end - upd_k
    addi r4, r0, 46
    addi r5, r0, 27
    mov r6, r8
    addi r12, r0, 5632
    mov r15, r7
    jal r1, dispatch
    ; render into the back buffer, reading the new state: two halves
    li r2, render_k
    li r3, render_k_end - render_k
    addi r4, r0, 160
    addi r5, r0, 45
    mov r6, r10
    li r12, 21600
    mov r15, r8
    sw r0, 0x13c(r13)           ; U15: first row
    jal r1, dispatch
    li r2, render_k
    addi r6, r10, 21600
    sw r5, 0x13c(r13)
    jal r1, dispatch
    addi r2, r10, -7200
    sw r2, 0(r14)               ; page base of the new frame
    addi r2, r0, 1
    sw r2, 20(r14)              ; show it at the next vblank
wvbl:
    wfi
    lw r1, 20(r14)
    bne r1, r0, wvbl
    xori r10, r10, 0xfd20
    mov r7, r8
    j frame

; GPU dispatch: code r2, length r3, grid r4 x r5, binding 0 (written) r6
; of length r12, binding 1 (read) r15; waits for completion (r2 changed)
dispatch:
    sw r2, 0(r13)
    sw r3, 4(r13)
    sw r4, 8(r13)
    sw r5, 12(r13)
    sw r6, 0x40(r13)
    sw r12, 0x44(r13)
    sw r15, 0x50(r13)
    addi r2, r0, 1
    sw r2, 16(r13)              ; START
wgpu:
    wfi
    lw r2, 20(r13)
    addi r2, r2, -1
    beq r2, r0, wgpu
    jalr r0, 0(r1)

; ---- include render.s ----
; ---------------------------------------------------------------------
; Render: one invocation per pixel, in two dispatches of 160 x 45 rows
; (uniform 15: first row). Bindings: 0 back buffer (from that row),
; 1 state (wave-equation grid + koi), 2 data.
; No calls on the GPU: the shared routines (slope, noise, koi, pads)
; return through J.
;   J 0 view slope, 1..3 caustic slopes (noise inside them: J < 4)
;   J 4 floor depth noise, 6 koi pattern noise
;   J 7 pads at the surface point, 8 pads shading the receiver
;   J 20 koi seen through the water, 21 koi shading the receiver
;   J 30 a lily pad was hit: no caustics
; ---------------------------------------------------------------------
; d = exp(-x) ~ (1 + x / 16)^-16

render_k:
    g.fli g24, 1.0
    g.fli g25, 1024.0 ; exact

; ---- A: camera ray D and the surface point S --------------------------
    g.uniform g14, 1             ; sin(tilt)
    g.fmul g13, g14, g14
    g.fsub g13, g24, g13
    g.sqrt g13, g13
    g.id g8, 0
    g.itof g8, g8
    g.fli g2, -79.5 ; exact
    g.fadd g8, g8, g2
    g.fli g2, 0.00625 ; exact
    g.fmul g8, g8, g2
    g.id g3, 1
    g.uniform g15, 15
    g.add g3, g3, g15
    g.itof g3, g3
    g.fli g15, 44.5 ; exact
    g.fsub g3, g15, g3
    g.fmul g3, g3, g2
    g.fmul g9, g3, g14
    g.fsub g9, g9, g13
    g.fmul g10, g3, g13
    g.fadd g10, g10, g14
    g.norm3 g8, g8
    ; camera (camx, dist ct, camz - dist st); S = C + D (C.y / -D.y)
    g.uniform g15, 4
    g.fmul g13, g13, g15
    g.fmul g14, g14, g15
    g.fsub g15, g0, g9
    g.fdiv g15, g13, g15
    g.fmul g11, g8, g15
    g.uniform g3, 2
    g.fadd g11, g11, g3
    g.fmul g12, g10, g15
    g.uniform g3, 3
    g.fadd g12, g12, g3
    g.fsub g12, g12, g14
    g.mov g5, g11
    g.mov g1, g12
    g.mov g26, g0
    g.jmp slope
ret_view:

; ---- B: normal, lily pads, Fresnel, reflection, refraction -------------
    g.fsub g13, g0, g16
    g.mov g14, g24
    g.fsub g15, g0, g17
    g.norm3 g13, g13
    ; lily pads float on the surface
    g.mov g16, g11
    g.mov g17, g12
    g.li g26, 7
    g.jmp pads
ret_pv:
    g.uniform g18, 7
    g.fsub g19, g0, g24
    g.uniform g20, 8
    g.norm3 g18, g18                ; direction the sunlight travels
    g.dot3 g3, g8, g13
    g.fsub g3, g0, g3
    g.fmax g3, g3, g0
    ; Schlick: F = 0.02 + 0.98 (1 - cos)^5
    g.fsub g2, g24, g3
    g.fmul g4, g2, g2
    g.fmul g4, g4, g4
    g.fmul g4, g4, g2
    g.fli g2, 0.984375
    g.fmul g4, g4, g2
    g.fli g2, 0.02001953125
    g.fadd g4, g4, g2
    ; reflected ray: sky height |R.y| and the sun's glitter (s^32)
    g.fadd g2, g3, g3
    g.vscale g21, g13, g2
    g.vadd g21, g21, g8
    g.fsub g7, g0, g22
    g.fmax g7, g7, g22
    g.dot3 g6, g21, g18
    g.fsub g6, g0, g6
    g.fmax g6, g6, g0
    g.fmul g6, g6, g6
    g.fmul g6, g6, g6
    g.fmul g6, g6, g6
    g.fmul g6, g6, g6
    g.fmul g6, g6, g6
    ; refraction (eta = 1 / 1.333): T = eta D + (eta c - sqrt(1 - eta^2 (1 - c^2))) N
    g.fmul g2, g3, g3
    g.fsub g2, g24, g2
    g.fli g27, 0.5625 ; exact
    g.fmul g2, g2, g27
    g.fsub g2, g24, g2
    g.sqrt g2, g2
    g.fli g27, 0.75 ; exact
    g.fmul g3, g3, g27
    g.fsub g3, g3, g2
    g.vscale g8, g8, g27
    g.vscale g13, g13, g3
    g.vadd g8, g8, g13              ; T
    ; phase C layout: DIRX, IVY, DIRZ = T.xz / -T.y, 1 / -T.y
    g.fsub g2, g0, g9
    g.fdiv g9, g24, g2
    g.fmul g8, g8, g9
    g.fmul g10, g10, g9
    g.mov g13, g4
    g.mov g14, g7
    g.mov g15, g6

; ---- C: koi seen through the water -------------------------------------
    g.mov g3, g0                ; FI: no koi
    g.fli g1, 100.0            ; BEST depth
    g.li g26, 20
    g.jmp fishes
ret_fv:

; ---- D: the receiver (koi or floor) and its colour --------------------
    ; floor depth 1.6 +- 0.6 (noise)
    g.fli g2, 0.3515625
    g.fmul g18, g11, g2
    g.fmul g19, g12, g2
    g.li g26, 4
    g.jmp vn
ret_depth:
    g.fli g2, 2.801243681460619e-10      ; 0.6 / 2^31
    g.fmul g16, g22, g2
    g.fli g2, 1.59375
    g.fadd g16, g16, g2
    ; a koi's body in front?
    g.li g17, d_floor - d_base
    g.bz g3, rc_floor
    g.fli g2, 1.5
    g.flt g2, g5, g2
    g.bz g2, rc_floor
    g.mov g16, g1
    g.mov g17, g0
rc_floor:
    g.fmul g2, g8, g16
    g.fadd g11, g11, g2
    g.fmul g2, g10, g16
    g.fadd g12, g12, g2
    g.fmul g8, g16, g9
    g.bnz g17, floor
    ; ---- koi: base or patch colour by noise on the body (4 schemes)
    g.li g2, 5376
    g.sub g17, g3, g2             ; koi * 32
    g.itof g21, g17
    g.fli g2, 0.010009765625
    g.fmul g21, g21, g2            ; pattern seed
    g.li g2, 2
    g.shr g17, g17, g2
    g.li g2, 24
    g.and g17, g17, g2
    g.li g2, d_koi - d_base
    g.add g17, g17, g2
    g.fli g2, 5.0
    g.fmul g18, g4, g2
    g.fadd g18, g18, g21
    g.fli g2, 1.203125
    g.fmul g19, g5, g2
    g.fadd g19, g19, g21
    g.li g26, 6
    g.jmp vn
ret_koi:
    g.li g2, 6
    g.add g2, g17, g2
    g.ldb g21, g2, 2              ; threshold (signed byte)
    g.li g2, 24
    g.shl g21, g21, g2
    g.itof g21, g21
    g.flt g21, g21, g22
    g.bz g21, k_base
    g.li g2, 3
    g.add g17, g17, g2             ; patch colour
k_base:
    g.fli g20, 0.00390625       ; 1 / 255
    ; eyes near the head's sides
    g.fli g2, 0.099609375
    g.flt g2, g4, g2
    g.bz g2, k_noeye
    g.fmul g2, g5, g5
    g.fli g21, 0.12109375
    g.flt g2, g21, g2
    g.bz g2, k_noeye
    g.fli g20, 0.0001983642578125
k_noeye:
    ; round body: 1 - 0.45 ln^2
    g.fmul g2, g5, g5
    g.fli g21, -0.453125
    g.fmul g2, g2, g21
    g.fadd g1, g2, g24
    g.mov g9, g0
    g.jmp colour
floor:
    ; ---- floor: sand; a translucent fin in front (FI)
    g.fli g20, 0.0032958984375            ; 0.85 / 255
    g.mov g1, g24
    g.mov g9, g3
colour:
    g.li g2, 2
    g.add g2, g17, g2
    g.ldb g5, g2, 2
    g.li g2, 1
    g.add g2, g17, g2
    g.ldb g4, g2, 2
    g.ldb g3, g17, 2
    g.itof g3, g3
    g.itof g4, g4
    g.itof g5, g5
    g.vscale g3, g3, g20
    g.bz g9, shadows
    g.fli g2, 0.5 ; exact
    g.vscale g3, g3, g2
    g.fli g2, 0.421875
    g.fadd g3, g3, g2
    g.fadd g4, g4, g2
    g.fadd g5, g5, g2

; ---- E: shadows of koi and pads on the receiver --------------------------
shadows:
    g.mov g27, g8                ; PL
    g.mov g9, g16
    ; towards the sun, per unit of depth: minus the landing offset of
    ; sunlight through flat water
    g.mov g16, g0
    g.mov g17, g0
    g.li g26, 22
    g.jmp ret_caus
ret_sflat:
    g.fsub g8, g0, g23
    g.fsub g10, g0, g7
    g.li g26, 21
    g.jmp fishes
ret_fs:
    ; the surface point that sunlight reaching the receiver passed through;
    ; a lily pad there shades it
    g.fmul g16, g8, g9
    g.fadd g16, g16, g11
    g.fmul g17, g10, g9
    g.fadd g17, g17, g12
    g.li g26, 8
    g.jmp pads
ret_ps:
    g.mov g19, g16
    g.mov g20, g17
    ; view path + sun path: 1 / |Lr.y| = sqrt(1 + |LS|^2)
    g.fmul g2, g8, g8
    g.fmul g21, g10, g10
    g.fadd g2, g2, g21
    g.fadd g2, g2, g24
    g.sqrt g2, g2
    g.fmul g2, g2, g9
    g.fadd g17, g2, g27           ; TOT
    g.mov g16, g27               ; PL
    ; to the phase F layout
    g.mov g18, g1
    g.mov g21, g9
    g.mov g8, g3                ; COL
    g.mov g9, g4
    g.mov g10, g5
    g.mov g4, g15               ; GL
    g.mov g3, g14                ; RY
    g.mov g15, g13                ; F
    g.mov g14, g21               ; QD
    g.mov g5, g19
    g.mov g1, g20

; ---- F: light per channel: Beer-Lambert along the view and sun paths,
; in-scattering, sky reflection. A = direct sunlight (times caustics
; later), B = everything else.
chan1:
    g.uniform g19, 9              ; warmth
    g.uniform g2, 10             ; overcast: dims the sun and its glitter
    g.fsub g2, g24, g2
    g.fli g27, 8.0 ; exact
    g.fmul g4, g4, g2
    g.fmul g4, g4, g27
    g.fli g27, 1.3125
    g.fmul g20, g2, g27            ; sun intensity
    g.fli g27, -0.3984375
    g.fmul g21, g19, g27
    g.fadd g21, g21, g24         ; ambient
    g.fsub g22, g24, g15
    g.li g23, d_chan - d_base
ch1:
    ; transmittance of the view path and of sun + view path
    g.ld g31, g23, 2              ; sigma
    g.fmul g28, g31, g16
    ; <expn TV, T2>
    g.fli g6, 0.0625 ; exact
    g.fmul g6, g6, g28
    g.fadd g6, g6, g24
    g.fmul g6, g6, g6
    g.fmul g6, g6, g6
    g.fmul g6, g6, g6
    g.fmul g6, g6, g6
    g.fdiv g6, g24, g6
    g.fmul g28, g31, g17
    ; <expn TS, T2>
    g.fli g30, 0.0625 ; exact
    g.fmul g30, g30, g28
    g.fadd g30, g30, g24
    g.fmul g30, g30, g30
    g.fmul g30, g30, g30
    g.fmul g30, g30, g30
    g.fmul g30, g30, g30
    g.fdiv g30, g24, g30
    ; sunlight colour: SI (1 - W k)
    g.li g2, 4
    g.add g23, g23, g2
    g.ld g31, g23, 2
    g.fmul g31, g31, g19            ; W k
    g.fmul g7, g20, g31
    g.fsub g7, g20, g7
    ; A = col (1 - F) sun Ts shadow
    g.fmul g30, g30, g7
    g.fmul g30, g30, g18
    g.fmul g30, g30, g22
    g.fmul g30, g30, g8
    ; ambient
    g.add g23, g23, g2
    g.ld g29, g23, 2
    g.fmul g29, g29, g21
    ; B = (1 - F) (col amb Tv + scat (sun + amb) (1 - Tv)) + F (sky + glint)
    g.fmul g28, g8, g29
    g.fmul g28, g28, g6
    g.fadd g29, g29, g7
    g.fsub g6, g24, g6
    g.fmul g29, g29, g6
    g.add g23, g23, g2
    g.ld g6, g23, 2              ; scattering colour
    g.fmul g29, g29, g6
    g.fadd g28, g28, g29
    g.fmul g28, g28, g22
    ; sky: (hor + (zen - hor) |R.y|) (1 - W k)
    g.add g23, g23, g2
    g.ld g29, g23, 2              ; horizon
    g.add g23, g23, g2
    g.ld g6, g23, 2              ; zenith
    g.fsub g6, g6, g29
    g.fmul g6, g6, g3
    g.fadd g29, g29, g6
    g.fsub g31, g24, g31
    g.fmul g29, g29, g31
    g.fmul g31, g7, g4
    g.fadd g29, g29, g31
    g.fmul g29, g29, g15
    g.fadd g28, g28, g29
    ; rotate: A <- (A.y, A.z, a), B <- (B.y, B.z, b)
    g.mov g8, g9
    g.mov g9, g10
    g.mov g10, g30
    g.mov g11, g12
    g.mov g12, g13
    g.mov g13, g28
    g.add g23, g23, g2
    g.li g2, d_chan_end - d_base
    g.sub g2, g23, g2
    g.bnz g2, ch1
    g.li g2, 30
    g.sub g2, g26, g2
    g.fli g15, 1.0               ; caustics of a pad: none
    g.bz g2, final
    g.li g26, 1
    g.jmp slope

; ---- G: caustics. Sunlight refracted at S_c and two neighbours lands on
; the receiver plane; the brightness is the ratio of the areas.
; sunlight refracted by a surface of slope (HX, HZ) -> GX, GZ: where it
; lands, per unit of depth. J 22: flat water, for the shadows.
ret_caus:
    g.fsub g18, g0, g17         ; (NN.y is HZ's register)
    g.fsub g16, g0, g16
    g.mov g17, g24
    g.norm3 g16, g16
    g.uniform g19, 7
    g.fsub g20, g0, g24
    g.uniform g21, 8
    g.norm3 g19, g19
    g.dot3 g22, g19, g16
    g.fsub g22, g0, g22
    g.fmul g2, g22, g22
    g.fsub g2, g24, g2
    g.fli g6, 0.5625 ; exact
    g.fmul g2, g2, g6
    g.fsub g2, g24, g2
    g.sqrt g2, g2
    g.fli g6, 0.75 ; exact
    g.fmul g22, g22, g6
    g.fsub g22, g22, g2
    g.vscale g16, g16, g22
    g.vscale g19, g19, g6
    g.vadd g16, g16, g19            ; refracted sunlight
    g.fsub g2, g0, g17
    g.fdiv g2, g24, g2
    g.fmul g23, g16, g2            ; landing offset per unit of depth
    g.fmul g7, g18, g2
    g.li g2, 22
    g.sub g2, g26, g2
    g.bz g2, ret_sflat
    g.fli g6, 0.099609375               ; E: spacing of the three sample points
    g.li g2, 2
    g.sub g2, g26, g2
    g.bz g2, cs2
    g.slt g2, g0, g2
    g.bnz g2, cs3
    g.mov g15, g23
    g.mov g3, g7
    g.fadd g5, g5, g6
    g.li g26, 2
    g.jmp slope
cs2:
    ; a = E + QD (Gx - G0x), b = QD (Gz - G0z)
    g.fsub g23, g23, g15
    g.fmul g23, g23, g14
    g.fadd g23, g23, g6
    g.fsub g7, g7, g3
    g.fmul g7, g7, g14
    ; K0 = a E - QD (a G0z - b G0x)
    g.fmul g3, g3, g23
    g.fmul g15, g15, g7
    g.fsub g3, g3, g15
    g.fmul g3, g3, g14
    g.fmul g4, g23, g6
    g.fsub g4, g4, g3
    g.fmul g15, g23, g14
    g.fmul g3, g7, g14
    g.fsub g5, g5, g6
    g.fadd g1, g1, g6
    g.li g26, 3
    g.jmp slope
cs3:
    ; det = K0 + a QD Gz - b QD Gx; caustic = E^2 / |det|
    g.fmul g7, g7, g15
    g.fmul g23, g23, g3
    g.fsub g7, g7, g23
    g.fadd g7, g7, g4
    g.fsub g2, g0, g7
    g.fmax g7, g7, g2
    g.fli g2, 0.001190185546875
    g.fmax g7, g7, g2
    g.fmul g6, g6, g6
    g.fdiv g15, g6, g7

; ---- H: out = B + A caustics, exposure, tone curve, gamma
final:
    g.uniform g3, 11
    g.fli g1, 3.0 ; exact
fin:
    g.fmul g4, g8, g15
    g.fadd g4, g4, g11
    g.fmul g4, g4, g3
    ; x / sqrt(x^2 + 0.12): filmic toe and shoulder, display gamma
    g.fmul g5, g4, g4
    g.fli g2, 0.12109375
    g.fadd g5, g5, g2
    g.rsqrt g5, g5
    g.fmul g5, g5, g4
    g.mov g8, g9
    g.mov g9, g10
    g.mov g11, g12
    g.mov g12, g13
    g.mov g13, g5
    g.fsub g1, g1, g24
    g.bnz g1, fin
    g.id g4, 2
    g.rgb g11, g4, 0
    g.end

; ---- include slope.s ----
; ---------------------------------------------------------------------
; slope(PX, PZ) -> HX, HZ: gradient of the water surface, the sum of
;  - the wave equation: central differences at the 4 surrounding grid
;    points, bilinearly weighted
;  - three Gerstner waves: the analytic normal of the trochoid
;  - FBM ripples: value noise, 3 octaves (2 for caustics), drifting
; Keeps g1..g12, J, FONE, K1K. Returns to ret_view (J = 0) or ret_caus.
; ---------------------------------------------------------------------
slope:
    g.fli g2, 4.0 ; exact
    g.fmul g18, g5, g2
    g.fmul g19, g1, g2
    g.fli g2, 23.5 ; exact
    g.fadd g18, g18, g2
    g.fli g2, 13.5 ; exact
    g.fadd g19, g19, g2
    g.fmax g18, g18, g24
    g.fmax g19, g19, g24
    g.fli g2, 45.0 ; exact
    g.fmin g18, g18, g2
    g.fli g2, 25.0 ; exact
    g.fmin g19, g19, g2
    g.ftoi g20, g19
    g.itof g2, g20
    g.fsub g19, g19, g2
    g.li g7, 16
    g.li g23, 192
    g.mul g20, g20, g23
    g.ftoi g21, g18
    g.itof g2, g21
    g.fsub g18, g18, g2
    g.li g22, 4
    g.mul g21, g21, g22
    g.add g20, g20, g21            ; byte offset of cell (i, j)
    g.mov g16, g0
    g.mov g17, g0
    g.fsub g30, g24, g19
    g.fadd g27, g24, g24
sl_z:
    g.fsub g6, g24, g18
    g.mov g21, g20
    g.fadd g28, g24, g24
sl_x:
    g.add g29, g21, g22
    g.ld g29, g29, 1
    g.sar g29, g29, g7
    g.sub g31, g21, g22
    g.ld g31, g31, 1
    g.sar g31, g31, g7
    g.sub g29, g29, g31
    g.itof g29, g29
    g.fmul g2, g6, g30
    g.fmul g29, g29, g2
    g.fadd g16, g16, g29
    g.add g29, g21, g23
    g.ld g29, g29, 1
    g.sar g29, g29, g7
    g.sub g31, g21, g23
    g.ld g31, g31, 1
    g.sar g31, g31, g7
    g.sub g29, g29, g31
    g.itof g29, g29
    g.fmul g29, g29, g2
    g.fadd g17, g17, g29
    g.fsub g6, g24, g6
    g.add g21, g21, g22
    g.fsub g28, g28, g24
    g.bnz g28, sl_x
    g.fsub g30, g24, g30
    g.add g20, g20, g23
    g.fsub g27, g27, g24
    g.bnz g27, sl_z
    g.fli g2, 0.000244140625     ; 1 / 8192 per unit, / 2 cells of 0.25 (exact)
    g.fmul g16, g16, g2
    g.fmul g17, g17, g2
sl_g:
; ---- Gerstner: slope = gA sum(2 pi a k cos) / (1 - gA sum(q k a sin))
    g.li g18, d_waves - d_base
    g.li g29, 4
    g.mov g7, g0
    g.mov g6, g0
    g.mov g30, g0
gw:
    g.ld g19, g18, 2
    g.add g18, g18, g29
    g.ld g20, g18, 2
    g.add g18, g18, g29
    g.ld g21, g18, 2              ; turns per second
    g.add g18, g18, g29
    g.uniform g23, 0
    g.fmul g21, g21, g23
    g.fmul g23, g19, g5
    g.fsub g21, g23, g21
    g.fmul g23, g20, g1
    g.fadd g21, g21, g23
    ; <sint S, TH>
    ; <frac S, TH>
    g.fadd g22, g21, g25
    g.ftoi g2, g22
    g.itof g2, g2
    g.fsub g22, g22, g2
    g.fli g2, 0.5 ; exact
    g.fsub g22, g22, g2
    g.fsub g2, g0, g22
    g.fmax g2, g2, g22
    g.fadd g2, g2, g2
    g.fsub g2, g2, g24
    g.fmul g22, g22, g2
    g.fli g23, 0.25 ; exact
    g.fadd g21, g21, g23
    ; <sint C, TH>
    ; <frac C, TH>
    g.fadd g23, g21, g25
    g.ftoi g2, g23
    g.itof g2, g2
    g.fsub g23, g23, g2
    g.fli g2, 0.5 ; exact
    g.fsub g23, g23, g2
    g.fsub g2, g0, g23
    g.fmax g2, g2, g23
    g.fadd g2, g2, g2
    g.fsub g2, g2, g24
    g.fmul g23, g23, g2
    g.ld g21, g18, 2              ; 2 pi a
    g.add g18, g18, g29
    g.fmul g23, g23, g21
    g.fmul g19, g19, g23
    g.fadd g7, g7, g19
    g.fmul g20, g20, g23
    g.fadd g6, g6, g20
    g.ld g21, g18, 2              ; q k a
    g.add g18, g18, g29
    g.fmul g22, g22, g21
    g.fadd g30, g30, g22
    g.li g23, d_waves_end - d_base
    g.sub g23, g18, g23
    g.bnz g23, gw
    g.uniform g23, 5              ; gA
    g.fmul g30, g30, g23
    g.fsub g30, g24, g30
    g.fdiv g23, g23, g30
    g.fmul g7, g7, g23
    g.fadd g16, g16, g7
    g.fmul g6, g6, g23
    g.fadd g17, g17, g6
sl_f:
; ---- FBM ripples: each octave rotated by 45 degrees and x 2 in
; frequency; amplitude x frequency constant per octave; drifting
    g.uniform g27, 0
    g.fli g2, 0.30078125
    g.fmul g18, g27, g2
    g.fadd g18, g18, g5
    g.fadd g19, g27, g1
    g.fli g2, 2.1875
    g.fmul g18, g18, g2
    g.fmul g19, g19, g2
    g.uniform g20, 6             ; fA
    g.fli g2, 3.0850060284137726e-9         ; 2.2 x 6 (noise derivative) / 2^32
    g.fmul g20, g20, g2
    g.fadd g21, g24, g24
    g.bnz g26, fbm
    g.fadd g21, g21, g24
fbm:
    g.jmp vn
fret:
    g.fmul g2, g23, g20
    g.fadd g16, g16, g2
    g.fmul g2, g7, g20
    g.fadd g17, g17, g2
    g.fsub g27, g18, g19
    g.fadd g19, g18, g19
    g.fli g2, 1.4375
    g.fmul g18, g27, g2
    g.fmul g19, g19, g2
    g.fsub g21, g21, g24
    g.bnz g21, fbm
    g.bz g26, ret_view
    g.jmp ret_caus

; ---------------------------------------------------------------------
; Value noise and its gradient: vn(NX, NZ) -> NV, NGX, NGZ (NX, NZ kept).
; Lattice values are hashed integers in [-2^31, 2^31); the gradient is 1/6
; of the true one. Returns by J: < 4 fret, 4 depth, 6 koi.
; ---------------------------------------------------------------------
vn:
    g.fadd g30, g18, g25
    g.ftoi g31, g30
    g.itof g2, g31
    g.fsub g30, g30, g2
    g.fadd g29, g19, g25
    g.ftoi g28, g29
    g.itof g2, g28
    g.fsub g29, g29, g2
    g.li g27, 0x85EBCA6B
    g.li g2, 0x9E3779B1
    g.mul g31, g31, g2
    g.mul g28, g28, g27
    ; <hash HA>
    g.xor g22, g31, g28
    g.mul g22, g22, g27
    g.itof g22, g22
    g.add g31, g31, g2
    ; <hash HB>
    g.xor g23, g31, g28
    g.mul g23, g23, g27
    g.itof g23, g23
    g.sub g31, g31, g2
    g.add g28, g28, g27
    ; <hash HC>
    g.xor g6, g31, g28
    g.mul g6, g6, g27
    g.itof g6, g6
    g.add g31, g31, g2
    ; <hash HD>
    g.xor g7, g31, g28
    g.mul g7, g7, g27
    g.itof g7, g7
    g.fsub g23, g23, g22           ; k1
    g.fsub g7, g7, g6
    g.fsub g7, g7, g23           ; k3
    g.fsub g6, g6, g22           ; k2
    ; u = f^2 (3 - 2f), du / 6 = f (1 - f)
    g.fsub g2, g24, g30
    g.fmul g31, g30, g2
    g.fadd g2, g2, g2
    g.fadd g2, g2, g24
    g.fmul g2, g2, g30
    g.fmul g30, g2, g30
    g.fsub g2, g24, g29
    g.fmul g28, g29, g2
    g.fadd g2, g2, g2
    g.fadd g2, g2, g24
    g.fmul g2, g2, g29
    g.fmul g29, g2, g29
    ; v = a + ux (k1 + k3 uz) + k2 uz; gx = (k1 + k3 uz) dux; gz = (k2 + k3 ux) duz
    g.fmul g2, g7, g29
    g.fadd g2, g2, g23
    g.fmul g7, g7, g30
    g.fadd g7, g7, g6
    g.fmul g7, g7, g28
    g.fmul g23, g2, g31
    g.fmul g2, g2, g30
    g.fadd g22, g22, g2
    g.fmul g2, g6, g29
    g.fadd g22, g22, g2
    g.li g2, 4
    g.sub g2, g26, g2
    g.slt g31, g2, g0
    g.bnz g31, fret
    g.bz g2, ret_depth
    g.jmp ret_koi

; ---------------------------------------------------------------------
; Koi: for each koi, the point PT = O + DIR s on its depth plane is taken
; into the fish's frame; the spine is displaced sideways by a travelling
; wave growing towards the tail (the "vertex shader"), then body, tail
; fin and pectoral fins are tested against their outlines.
; J 20: s = depth, keep the nearest (FI record, FU u, FLN lat / width or
;       2 for a fin, BEST depth). J 21: s = QD - depth, darken SH.
; In: g1 DIRX, g3 DIRZ, g4 OX, g5 OZ, g2 QD (shadows). Scratch g13..g27.
; ---------------------------------------------------------------------
fishes:
    g.li g16, 5376
    g.li g30, 4
    g.li g29, 21
    g.sub g29, g26, g29             ; 0: shadows
fish:
    g.ld g17, g16, 1              ; depth
    g.bz g29, f_sh
    g.flt g2, g17, g1
    g.bz g2, f_next
    g.jmp f_pt
f_sh:
    g.fsub g17, g9, g17
    g.fli g2, 0.0498046875
    g.flt g2, g2, g17
    g.bz g2, f_next
f_pt:
    g.add g20, g16, g30
    g.ld g18, g20, 1
    g.fsub g18, g11, g18
    g.fmul g2, g8, g17
    g.fadd g18, g18, g2
    g.add g20, g20, g30
    g.ld g19, g20, 1
    g.fsub g19, g12, g19
    g.fmul g2, g10, g17
    g.fadd g19, g19, g2
    g.fmul g21, g18, g18
    g.fmul g2, g19, g19
    g.fadd g21, g21, g2
    g.fli g2, 0.828125
    g.flt g2, g21, g2
    g.bz g2, f_next
    g.add g20, g20, g30
    g.ld g21, g20, 1              ; hx
    g.add g20, g20, g30
    g.ld g20, g20, 1              ; hz
    ; along and across the fish, in lengths of 1.3
    g.fmul g22, g18, g21
    g.fmul g2, g19, g20
    g.fadd g22, g22, g2
    g.fmul g23, g19, g21
    g.fmul g2, g18, g20
    g.fsub g23, g23, g2
    g.fli g2, 0.765625
    g.fmul g22, g22, g2
    g.fmul g23, g23, g2
    g.fli g2, 0.453125
    g.fsub g22, g2, g22            ; u: 0 head .. 1 tail tip
    ; the spine: lat -= (0.015 + 0.09 u^2) sin(2 pi (1.114 u - phase))
    g.li g2, 20
    g.add g20, g16, g2
    g.ld g7, g20, 1              ; phase
    g.fli g2, 1.125
    g.fmul g21, g22, g2
    g.fsub g21, g21, g7
    ; <sint WV, T2>
    ; <frac WV, T2>
    g.fadd g7, g21, g25
    g.ftoi g2, g7
    g.itof g2, g2
    g.fsub g7, g7, g2
    g.fli g2, 0.5 ; exact
    g.fsub g7, g7, g2
    g.fsub g2, g0, g7
    g.fmax g2, g2, g7
    g.fadd g2, g2, g2
    g.fsub g2, g2, g24
    g.fmul g7, g7, g2
    g.fmul g20, g22, g22
    g.fli g2, 0.71875
    g.fmul g20, g20, g2
    g.fli g2, 0.12109375
    g.fadd g20, g20, g2            ; (x 8: sint gives sin / 8)
    g.fmul g7, g7, g20
    g.fsub g23, g23, g7
    g.fsub g6, g0, g23
    g.fmax g6, g6, g23          ; |lat|
    ; body half width 0.284 sqrt(u (0.92 - u)) (1.2 - u)
    g.fli g2, 0.921875
    g.fsub g20, g2, g22
    g.fmul g20, g20, g22
    g.fmax g20, g20, g0
    g.sqrt g20, g20
    g.fli g2, 1.203125
    g.fsub g21, g2, g22
    g.fmul g20, g20, g21
    g.fli g2, 0.28125
    g.fmul g20, g20, g2
    g.flt g2, g6, g20
    g.bz g2, f_fins
    ; body
    g.bz g29, f_sbody
    g.mov g1, g17
    g.mov g3, g16
    g.mov g4, g22
    g.fdiv g5, g23, g20
    g.jmp f_next
f_sbody:
    g.fli g2, 0.3984375
    g.fmul g1, g1, g2
    g.jmp f_next
f_fins:
    ; tail fin: |lat| < 0.28 u - 0.2, u < 1.05
    g.fli g2, 1.046875
    g.flt g2, g22, g2
    g.bz g2, f_next
    g.fli g2, 0.28125
    g.fmul g20, g22, g2
    g.fli g2, 0.19921875
    g.fsub g20, g20, g2
    g.flt g2, g6, g20
    g.bnz g2, f_fin
    ; pectoral fins: 0 < |lat| - 0.09 < 0.625 u - 0.125, u < 0.36
    g.fli g2, 0.359375
    g.flt g2, g22, g2
    g.bz g2, f_next
    g.fli g2, 0.08984375
    g.fsub g6, g6, g2
    g.flt g2, g6, g0
    g.bnz g2, f_next
    g.fli g2, 0.625
    g.fmul g20, g22, g2
    g.fli g2, 0.125
    g.fsub g20, g20, g2
    g.flt g2, g6, g20
    g.bz g2, f_next
f_fin:
    g.bz g29, f_sbody
    g.bnz g3, f_next
    g.mov g3, g16
    g.fli g5, 2.0 ; exact
f_next:
    g.li g2, 32
    g.add g16, g16, g2
    g.li g2, 5632
    g.sub g2, g16, g2
    g.bnz g2, fish
    g.bnz g29, ret_fv
    g.jmp ret_fs


; ---------------------------------------------------------------------
; Lily pads: drifting discs with a notch. In: g13, g14 the surface point.
; J 7: a hit shades the pad (pad_hit); J 8: shadow (SH g12).
; Scratch g15..g22.
; ---------------------------------------------------------------------
pads:
    g.li g18, d_pads - d_base
    g.li g19, 4
pad:
    g.ld g20, g18, 2              ; x0
    g.add g18, g18, g19
    g.uniform g23, 0
    g.ld g22, g18, 2              ; drift speed
    g.add g18, g18, g19
    g.fmul g22, g22, g23
    g.fadd g20, g20, g22
    g.fsub g20, g16, g20
    g.ld g21, g18, 2              ; z0
    g.add g18, g18, g19
    g.fsub g21, g17, g21
    g.ld g7, g18, 2              ; r^2
    g.add g18, g18, g19
    g.fmul g6, g20, g20
    g.fmul g22, g21, g21
    g.fadd g6, g6, g22
    g.flt g2, g6, g7
    g.bz g2, pad_next
    ; the notch: |dz| < n dx (n = +-0.3: the notch's side)
    g.ld g22, g18, 2
    g.fmul g22, g22, g20
    g.fsub g23, g0, g21
    g.fmax g23, g23, g21
    g.flt g2, g23, g22
    g.bnz g2, pad_next
    g.li g2, 7
    g.sub g2, g26, g2
    g.bz g2, pad_hit
    g.fli g2, 0.150390625
    g.fmul g1, g1, g2
pad_next:
    g.add g18, g18, g19
    g.li g2, d_pads_end - d_base
    g.sub g2, g18, g2
    g.bnz g2, pad
    g.li g2, 7
    g.sub g2, g26, g2
    g.bz g2, ret_pv
    g.jmp ret_ps
pad_hit:
    ; green, lighter towards the rim
    g.fdiv g6, g6, g7
    g.fli g2, 0.453125
    g.fmul g6, g6, g2
    g.fli g2, 0.703125
    g.fadd g6, g6, g2
    g.fli g8, 0.099609375
    g.fli g9, 0.26953125
    g.fli g10, 0.0498046875
    g.vscale g8, g8, g6
    g.fli g18, 0.796875              ; SH
    g.mov g14, g0                ; QD
    g.mov g15, g0                ; F
    g.mov g3, g0                ; RY
    g.mov g4, g0               ; GL
    g.mov g16, g0               ; PL
    g.mov g17, g0               ; TOT
    g.li g26, 30
    g.jmp chan1

render_k_end:

; ---- include update.s ----
; ---------------------------------------------------------------------
; Update: one dispatch per frame, grid 46 x 27. Rows 0..25: the wave
; equation, one invocation per inner cell; row 26: boids, one per koi.
; Bindings: 0 the new state (written), 1 the old state, 2 data.
; State: 48 x 28 cell words [h(t+1) | h(t)] (16-bit, 8192 = 1 unit), then
; eight 32-byte koi records: depth, x, z, hx, hz (heading), phase, speed.
; ---------------------------------------------------------------------
upd_k:
    g.fli g7, 1.0
    g.fli g25, 1024.0 ; exact
    g.li g14, 1
    g.li g13, 16
    g.id g8, 0
    g.id g15, 1
    g.li g2, 26
    g.sub g2, g15, g2
    g.bz g2, boid
    g.add g8, g8, g14
    g.add g15, g15, g14             ; an inner cell: the border is never written
    g.li g18, 48
    g.mul g18, g15, g18
    g.add g18, g18, g8
    g.add g18, g18, g18
    g.add g18, g18, g18            ; byte offset of the cell
    g.ld g19, g18, 1
    g.shl g29, g19, g13
    g.sar g29, g29, g13         ; h(t-1)
    g.sar g19, g19, g13         ; h(t)
    ; h(t+1) = h + v - v / 64 + c^2 (sum of neighbours - 4 h), c^2 = 1 / 16
    g.li g1, 4
    g.sub g17, g18, g1
    g.ld g17, g17, 1
    g.sar g23, g17, g13
    g.add g17, g18, g1
    g.ld g17, g17, 1
    g.sar g17, g17, g13
    g.add g23, g23, g17
    g.li g1, 192
    g.sub g17, g18, g1
    g.ld g17, g17, 1
    g.sar g17, g17, g13
    g.add g23, g23, g17
    g.add g17, g18, g1
    g.ld g17, g17, 1
    g.sar g17, g17, g13
    g.add g23, g23, g17
    g.add g17, g19, g19
    g.add g17, g17, g17
    g.sub g23, g23, g17
    g.li g1, 4
    g.sar g23, g23, g1
    g.sub g17, g19, g29
    g.li g1, 6
    g.sar g16, g17, g1
    g.sub g17, g17, g16
    g.add g23, g23, g17
    g.add g23, g23, g19
    g.mov g12, g0
    ; rain: a drop on this cell with probability rain / 512 per frame
    g.id g17, 2
    g.li g1, 0x9E3779B1
    g.mul g17, g17, g1
    g.uniform g16, 0
    g.xor g17, g17, g16
    g.li g1, 0x85EBCA6B
    g.mul g17, g17, g1
    g.uniform g16, 12
    g.fli g1, 8388608.0 ; exact
    g.fmul g16, g16, g1
    g.ftoi g16, g16
    g.sltu g17, g17, g16
    g.bz g17, no_rain
    g.li g1, 420
    g.sub g12, g12, g1
no_rain:
    ; the title: from 7.5 s to 9 s, KOI (a 16 x 7 bitmap, a cell per pixel
    ; from cell (17, 10)) is held in the water: letters pressed down, the
    ; rest of its rectangle flat
    g.uniform g1, 0
    g.fli g17, -7.5 ; exact
    g.fadd g1, g1, g17
    g.fli g17, -1.5 ; exact
    g.fadd g17, g1, g17
    g.fmul g1, g1, g17
    g.flt g1, g1, g0
    g.bz g1, t_done
    g.li g1, 17
    g.sub g17, g8, g1               ; column
    g.li g1, 16
    g.sltu g16, g17, g1
    g.bz g16, t_done
    g.li g1, 10
    g.sub g16, g15, g1
    g.li g1, 7
    g.sltu g1, g16, g1
    g.bz g1, t_done
    g.li g1, 6
    g.sub g16, g1, g16               ; bitmap row, top first
    g.add g16, g16, g16
    g.li g1, 3
    g.shr g1, g17, g1
    g.add g16, g16, g1
    g.li g1, d_glyph - d_base
    g.add g16, g16, g1
    g.ldb g16, g16, 2
    g.li g1, 7
    g.and g17, g17, g1
    g.sub g17, g1, g17
    g.shr g16, g16, g17
    g.and g16, g16, g14
    g.li g1, -TITLE
    g.mul g23, g16, g1             ; letters pressed down, the gaps held at rest
    g.mov g19, g23
t_done:
    ; a drop event: frame << 20 | amp / 8 << 12 | z << 6 | x (0: none)
    g.uniform g9, 14
    g.li g1, 63
    g.and g17, g9, g1
    g.sub g17, g8, g17
    g.mul g17, g17, g17
    g.li g16, 6
    g.shr g16, g9, g16
    g.and g16, g16, g1
    g.sub g16, g15, g16
    g.mul g16, g16, g16
    g.add g17, g17, g16               ; d^2 in cells
    g.li g1, 5
    g.sub g17, g1, g17
    g.slt g1, g0, g17
    g.bz g1, no_event
    g.li g16, 12
    g.shr g16, g9, g16
    g.li g1, 255
    g.and g16, g16, g1
    g.mul g17, g17, g16
    g.sub g12, g12, g17
no_event:
    ; koi near the surface push the water above them
    g.li g24, 5376
push:
    g.ld g1, g24, 1               ; depth (0: not yet placed)
    g.fli g17, 0.30078125
    g.flt g17, g1, g17
    g.bz g17, push_next
    g.bz g1, push_next
    g.fli g9, 4.0 ; exact
    g.li g1, 4
    g.add g16, g24, g1
    g.ld g1, g16, 1                ; x -> cell
    g.fmul g1, g1, g9
    g.fli g17, 24.0 ; exact
    g.fadd g1, g1, g17
    g.ftoi g1, g1
    g.sub g1, g1, g8
    g.bnz g1, push_next
    g.li g1, 4
    g.add g16, g16, g1
    g.ld g1, g16, 1                ; z -> cell
    g.fmul g1, g1, g9
    g.fli g17, 14.0 ; exact
    g.fadd g1, g1, g17
    g.ftoi g1, g1
    g.sub g1, g1, g15
    g.bnz g1, push_next
    g.li g1, 120
    g.sub g12, g12, g1
push_next:
    g.li g1, 32
    g.add g24, g24, g1
    g.li g1, 5632
    g.sub g1, g24, g1
    g.bnz g1, push
    ; impulses displace h(t+1) and h(t) alike; pack [h(t+1) | h(t)]
    g.add g23, g23, g12
    g.add g19, g19, g12
    g.shl g23, g23, g13
    g.li g1, 0xffff
    g.and g19, g19, g1
    g.or g23, g23, g19
cell_out:
    g.st g23, g18, 0
    g.end

; ---------------------------------------------------------------------
; Boids: cohesion, alignment and separation within the school, and a
; target wandering around the camera's point of interest.
; ---------------------------------------------------------------------
boid:
    g.li g1, 8
    g.sltu g1, g8, g1
    g.bz g1, b_end
    g.li g12, 4
    g.li g17, 5
    g.shl g24, g8, g17
    g.li g1, 5376
    g.add g24, g24, g1             ; this koi's record
    g.add g31, g24, g12
    g.ld g15, g31, 1
    g.add g31, g31, g12
    g.ld g18, g31, 1
    g.add g31, g31, g12
    g.ld g19, g31, 1
    g.add g31, g31, g12
    g.ld g29, g31, 1
    g.add g31, g31, g12
    g.add g31, g31, g12
    g.ld g23, g31, 1
    g.bnz g23, b_live
    ; first frame: along a diagonal, heading +x
    g.itof g15, g8
    g.fli g17, 0.703125
    g.fmul g15, g15, g17
    g.fli g17, -2.5
    g.fadd g15, g15, g17
    g.fli g17, 0.6015625
    g.fmul g18, g15, g17
    g.mov g19, g7
    g.fli g23, 0.5
b_live:
    g.mov g6, g0
    g.mov g22, g0
    g.mov g9, g0
    g.mov g5, g0
    g.mov g28, g0
    g.mov g20, g0
    g.mov g4, g0
    g.li g31, 5380                ; x of koi 0
b_nb:
    g.add g1, g24, g12
    g.sub g1, g31, g1
    g.bz g1, b_nb_next
    g.ld g3, g31, 1
    g.fsub g3, g3, g15
    g.add g16, g31, g12
    g.ld g21, g16, 1
    g.fsub g21, g21, g18
    g.fmul g27, g3, g3
    g.fmul g1, g21, g21
    g.fadd g27, g27, g1
    g.fli g1, 6.0
    g.flt g1, g27, g1
    g.bz g1, b_nb_next
    g.fadd g6, g6, g3
    g.fadd g22, g22, g21
    g.fadd g4, g4, g7
    g.add g16, g16, g12
    g.ld g17, g16, 1
    g.fadd g9, g9, g17            ; headings
    g.add g16, g16, g12
    g.ld g17, g16, 1
    g.fadd g5, g5, g17
    g.flt g1, g27, g7
    g.bz g1, b_nb_next
    g.fli g1, 0.0498046875
    g.fadd g27, g27, g1
    g.fdiv g27, g7, g27
    g.fmul g3, g3, g27
    g.fsub g28, g28, g3
    g.fmul g21, g21, g27
    g.fsub g20, g20, g21
b_nb_next:
    g.li g1, 32
    g.add g31, g31, g1
    g.li g1, 5636
    g.sub g1, g31, g1
    g.bnz g1, b_nb
    ; steering: 0.35 separation + 0.25 cohesion + 0.4 alignment + 0.5 target
    g.fli g1, 0.3515625
    g.fmul g28, g28, g1
    g.fmul g20, g20, g1
    g.bz g4, b_alone
    g.fdiv g4, g7, g4
    g.fli g1, 0.25
    g.fmul g1, g1, g4
    g.fmul g6, g6, g1
    g.fmul g22, g22, g1
    g.fadd g28, g28, g6
    g.fadd g20, g20, g22
    g.fmul g9, g9, g4
    g.fsub g9, g9, g19
    g.fmul g5, g5, g4
    g.fsub g5, g5, g29
    g.fli g1, 0.3984375
    g.fmul g9, g9, g1
    g.fmul g5, g5, g1
    g.fadd g28, g28, g9
    g.fadd g20, g20, g5
b_alone:
    ; the target wanders around the camera's point of interest
    g.uniform g26, 0
    g.fli g16, 0.03515625
    g.fmul g16, g26, g16
    ; <sint DX, C>
    ; <frac DX, C>
    g.fadd g3, g16, g25
    g.ftoi g2, g3
    g.itof g2, g2
    g.fsub g3, g3, g2
    g.fli g2, 0.5 ; exact
    g.fsub g3, g3, g2
    g.fsub g2, g0, g3
    g.fmax g2, g2, g3
    g.fadd g2, g2, g2
    g.fsub g2, g2, g7
    g.fmul g3, g3, g2
    g.fli g16, 10.5               ; 1.3 x 8
    g.fmul g3, g3, g16
    g.uniform g16, 2
    g.fadd g3, g3, g16
    g.fsub g3, g3, g15
    g.fli g16, 0.052734375
    g.fmul g16, g26, g16
    g.fli g27, 0.25 ; exact
    g.fadd g16, g16, g27
    ; <sint DZ, C>
    ; <frac DZ, C>
    g.fadd g21, g16, g25
    g.ftoi g2, g21
    g.itof g2, g2
    g.fsub g21, g21, g2
    g.fli g2, 0.5 ; exact
    g.fsub g21, g21, g2
    g.fsub g2, g0, g21
    g.fmax g2, g2, g21
    g.fadd g2, g2, g2
    g.fsub g2, g2, g7
    g.fmul g21, g21, g2
    g.fli g16, 6.375                ; 0.8 x 8
    g.fmul g21, g21, g16
    g.uniform g16, 3
    g.fadd g21, g21, g16
    g.fsub g21, g21, g18
    g.fli g16, 0.5
    g.fmul g3, g3, g16
    g.fmul g21, g21, g16
    g.fadd g28, g28, g3
    g.fadd g20, g20, g21
    ; v += force dt; speed clamped to [0.35, 0.9]; heading = v / |v|
    g.fli g16, 0.0166015625
    g.fmul g28, g28, g16
    g.fmul g20, g20, g16
    g.fmul g3, g19, g23
    g.fadd g3, g3, g28
    g.fmul g21, g29, g23
    g.fadd g21, g21, g20
    g.fmul g1, g3, g3
    g.fmul g17, g21, g21
    g.fadd g1, g1, g17
    g.rsqrt g1, g1
    g.fmul g19, g3, g1
    g.fmul g29, g21, g1
    g.fdiv g1, g7, g1
    g.fli g17, 0.3515625
    g.fmax g23, g1, g17
    g.fli g17, 0.90625
    g.fmin g23, g23, g17
    g.fmul g1, g23, g16
    g.fmul g3, g19, g1
    g.fadd g15, g15, g3
    g.fmul g21, g29, g1
    g.fadd g18, g18, g21
    ; depth eases towards the school's (U13), staggered by koi
    g.ld g3, g24, 1
    g.bnz g3, b_depth
    g.fli g3, 0.6015625
b_depth:
    g.itof g21, g8
    g.fli g17, 0.0400390625
    g.fmul g21, g21, g17
    g.uniform g17, 13
    g.fadd g21, g21, g17
    g.fsub g21, g21, g3
    g.fli g17, 0.02001953125
    g.fmul g21, g21, g17
    g.fadd g3, g3, g21
    g.st g3, g24, 0
    g.add g31, g24, g12
    g.st g15, g31, 0
    g.add g31, g31, g12
    g.st g18, g31, 0
    g.add g31, g31, g12
    g.st g19, g31, 0
    g.add g31, g31, g12
    g.st g29, g31, 0
    ; tail phase advances with speed
    g.add g31, g31, g12
    g.ld g3, g31, 1
    g.fli g17, 0.953125
    g.fmul g17, g23, g17
    g.fli g21, 0.640625
    g.fadd g17, g17, g21
    g.fmul g17, g17, g16
    g.fadd g3, g3, g17
    ; <frac B, DX>
    g.fadd g17, g3, g25
    g.ftoi g2, g17
    g.itof g2, g2
    g.fsub g17, g17, g2
    g.st g17, g31, 0
    g.add g31, g31, g12
    g.st g23, g31, 0
b_end:
    g.end
upd_k_end:


; ---------------------------------------------------------------------
; GPU data (binding 2)
; ---------------------------------------------------------------------
.align 4
d_base:
; ---- include data.s ----
; generated by gen.py
.align 4
d_waves:            ; kx, kz (turns per unit), turns per second, 8 x (2 pi a, q k a)
    .float 0.30859375, 0.095703125, 0.421875, 50.0, 4.3125 
    .float 0.4609375, -0.25, 0.546875, 30.0, 4.25 
    .float 0.22265625, 0.796875, 0.6875, 17.5, 3.4375 
d_waves_end:
d_chan:
    .float 0.453125, 0.3984375, 0.16015625, 0.02001953125, 0.75, 0.25 
    .float 0.140625, 0.65625, 0.21875, 0.08984375, 0.84375, 0.453125 
    .float 0.109375, 0.921875, 0.2578125, 0.099609375, 0.953125, 0.796875 
d_chan_end:
d_pads:            ; x0, drift, z0, r^2, notch side
    .float 2.625, 0.0302734375, 1.203125, 0.3046875, 0.30078125 
    .float 3.375, 0.0302734375, 0.3515625, 0.16015625, -0.30078125 
    .float -3.625, 0.0400390625, -1.59375, 0.25, 0.30078125 
    .float -1.203125, 0.02001953125, 2.5, 0.203125, -0.30078125 
d_pads_end:
d_floor:
    .byte 107, 97, 77, 0
d_koi:
    .byte 242, 237, 224, 240, 56, 10, 10, 0
    .byte 255, 150, 25, 255, 215, 90, 30, 0
    .byte 242, 237, 224, 14, 13, 15, 45, 0
    .byte 20, 20, 24, 240, 76, 12, 0, 0
d_glyph:           ; KOI, 16 x 7
    .byte 137, 206
    .byte 146, 36
    .byte 162, 36
    .byte 194, 36
    .byte 162, 36
    .byte 146, 36
    .byte 137, 206
.align 4

; ---- include scenes.s ----
; generated by gen.py
.align 4
keys:          ; per keyframe: mask (bit 13 stops), then the changed s7.8 values
    .byte 255, 63, 0, 0, 128, 255, 179, 255, 0, 6, 8, 0, 10, 0, 64, 0, 90, 0, 102, 0, 0, 0, 0, 0, 0, 0, 128, 0
    .byte 54, 37, 77, 0, 51, 0, 5, 0, 3, 0, 51, 0, 0, 1
    .byte 54, 32, 154, 255, 77, 0, 12, 0, 10, 0
    .byte 13, 32, 222, 0, 205, 255, 0, 5
    .byte 15, 32, 100, 0, 77, 0, 51, 0, 154, 5
    .byte 31, 32, 0, 0, 0, 0, 0, 0, 0, 6, 20, 0
    .byte 16, 58, 13, 0, 218, 0, 0, 1, 230, 0
    .byte 18, 58, 179, 255, 5, 0, 51, 0, 0, 0, 31, 0
    .byte 221, 53, 228, 0, 102, 255, 102, 4, 10, 0, 51, 0, 77, 255, 192, 0, 51, 1, 128, 0
    .byte 5, 37, 165, 0, 179, 255, 230, 0, 0, 0
.align 4
events:        ; frame << 20 | amp / 8 << 12 | z << 6 | x, then a stop
    .word 0x03c57396
    .word 0x0aa3225f
    .word 0x12c3e4ce
    .word 0x5144b314
    .word 0x82a3e3da
    .word 0x8ca382d2
    .word 0xcc64b398
    .word 0xd5c32415
    .word 0xffffffff

d_end:
prec:                           ; [previous | current] keyframe values: time, parameters
    .word 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
lastev:
    .word -1

; MMIO configuration script: [dest, count, words...], 0 terminates
cfg:
    .word 0xf3048, 7, 3, 0, 0, 5632, 1, 0, d_base
    .word 0xf3064, 2, d_end - d_base, 1
    .word 0xf5004, 4, 480, 4, 0, 1
    .word 0

