; LOAD 0x2CE00
; =====================================================================
;  LIGHTCONE -- a 4K intro for DB32 (dynamic-1, packed).
;  Light, slowed down: light echoes in a dust nebula, relativistic flight,
;  Terrell rotation, photoelastic force chains. 150 BPM.
;  RAM: page A 0x10000 and page B 0x1C4E0 (RGB888, 160x90 letterbox: the
;  pages share the 15 black rows between them), SPU output 0x2A600, SPU
;  state 0x2AE00, image LOAD..0x30000.
; =====================================================================
.profile dynamic-1
.entry start
.equ VISA,  0x11C20             ; page A, first visible row (15)
.equ VISB,  0x1E100             ; page B, first visible row
.equ AOUT,  0x2A600
.equ SST,   0x2AE00             ; SPU state
.equ LOOP,  3456                ; 36 bars of 96 frames
.equ SCENE, 384                 ; 4 bars
.equ RECW,  12                  ; words per scene record (-> U4..U15)

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
    li r10, VISA                ; back buffer (visible rows)
    li r11, VISB                ; front buffer
    lw r9, 24(r14)              ; frame counter at the demo start
frame:
    lw r1, 24(r14)
    sub r1, r1, r9              ; demo frame
    addi r2, r0, LOOP
    blt r1, r2, inloop
    add r9, r9, r2
    sub r1, r1, r2
inloop:
    sw r1, 0x100(r13)           ; U0 = demo frame
    ; U2 = beat index = demo frame / 24
    li r2, 43691
    mul r2, r1, r2
    addi r3, r0, 20
    shr r2, r2, r3
    sw r2, 0x108(r13)
    addi r2, r0, 800
    mul r2, r9, r2
    lui r3, 0xf6
    sw r2, 0x200(r3)            ; SPU U0 = sample index of the demo start
    ; scene r8 = frame / 384, frame in the scene -> U1
    mov r8, r0
    addi r2, r0, SCENE
find:
    blt r1, r2, found
    sub r1, r1, r2
    addi r8, r8, 1
    j find
found:
    sw r1, 0x104(r13)           ; U1
    ; rebuild the scene's record from scene 0's on: each is [mask] + the
    ; words that change
    li r3, scenes
    li r4, prec
    addi r12, r0, 1
    addi r6, r8, 1
dscene:
    lw r2, 0(r3)
    addi r3, r3, 4
    mov r7, r4
dword:
    and r5, r2, r12
    beq r5, r0, dskip
    lw r5, 0(r3)
    addi r3, r3, 4
    sw r5, 0(r7)
dskip:
    addi r7, r7, 4
    shr r2, r2, r12
    bne r2, r0, dword
    addi r6, r6, -1
    bne r6, r0, dscene
    addi r2, r0, 85
    mul r5, r1, r2              ; s * 32768
    mov r1, r4
    lw r7, 0(r1)
    addi r2, r13, 0x110
    addi r3, r1, 48
    addi r8, r0, 16
    lui r15, 0x800              ; 2^23
rec:
    lw r4, 0(r1)
    andi r6, r7, 0x100
    bne r6, r0, store
    sar r6, r4, r8              ; a
    shl r4, r4, r8
    sar r4, r4, r8              ; b
    sub r4, r4, r6
    mul r4, r4, r5
    addi r12, r0, 15
    sar r4, r4, r12
    add r4, r4, r6              ; a + (b - a) s
    beq r4, r0, store
    mov r6, r0
    blt r0, r4, pos
    sub r4, r0, r4
    lui r6, 0x80000             ; sign
pos:
    addi r12, r0, 142           ; exponent of 2^23 / 256
norm:
    bltu r4, r15, dbl
    sub r4, r4, r15
    mul r12, r12, r15
    or r4, r4, r12
    or r4, r4, r6
    j store
dbl:
    add r4, r4, r4
    addi r12, r12, -1
    j norm
store:
    sw r4, 0(r2)
    addi r1, r1, 4
    addi r2, r2, 4
    addi r12, r0, 1
    shr r7, r7, r12
    bne r1, r3, rec
    ; render the frame
    addi r2, r0, 1
    sw r2, 16(r13)              ; START
wgpu:
    wfi
    lw r3, 20(r13)
    beq r3, r2, wgpu
    addi r2, r10, -7200
    sw r2, 0(r14)               ; page base of the new frame
    addi r2, r0, 1
    sw r2, 20(r14)              ; show it at the next vblank
wvbl:
    wfi
    lw r1, 20(r14)
    bne r1, r0, wvbl
    xor r10, r10, r11
    xor r11, r10, r11
    xor r10, r10, r11
    sw r10, 0x40(r13)           ; binding 0: new back buffer
    sw r11, 0x70(r13)           ; binding 3: the frame on screen
    j frame

; ---- include render.s ----
; ---------------------------------------------------------------------
; Renderer: one invocation per pixel of the 160x90 letterbox. Bindings: 0 back buffer, 1 data, 3 the frame on screen.
; Uniforms: 0 demo frame, 1 frame in the scene, 2 beat index, 4 scene type, 5 exposure, 6 flash, 7 temporal blend,
; 8..15 scene parameters (floats, lerped through the scene by the CPU).
; ---------------------------------------------------------------------
.equ U_BEAT, 2
.equ U_ROW,  3

; 2^y for y in [0, 126] (R, R2, W: scratch)


render_k:
    g.fli g12, 1.0
    g.li g1, 1
    g.uniform g22, 0
    g.itof g29, g22
    g.fli g16, 0.016666668       ; 1/60 (exact)
    g.fmul g29, g29, g16
    ; sub-pixel jitter: a 2 x 2 grid over four frames (+-1/4), then
    ; u = (x + 0.5 + jx - 80) / 45, v = (45 - y - 0.5 - jy) / 45
    g.and g16, g22, g1
    g.itof g30, g16
    g.li g17, 2
    g.and g16, g22, g17
    g.itof g28, g16
    g.fli g16, 0.25 ; exact
    g.fmul g28, g28, g16
    g.fadd g16, g16, g16
    g.fmul g30, g30, g16
    g.id g16, 0
    g.itof g16, g16
    g.fadd g30, g30, g16
    g.id g16, 1
    g.itof g16, g16
    g.fadd g28, g28, g16
    g.fli g16, -79.75 ; exact
    g.fadd g30, g30, g16
    g.fli g16, -44.75 ; exact
    g.fadd g28, g28, g16
    g.fli g16, 0.022222223       ; 1/45 (exact)
    g.fmul g30, g30, g16
    g.fsub g16, g0, g16
    g.fmul g28, g28, g16
    g.mov g13, g0
    g.mov g14, g0
    g.mov g15, g0
    ; scene type: 0 echo, 1 space, 2 stress
    g.uniform g22, 4
    g.li g17, 255
    g.and g22, g22, g17
    g.bz g22, echo
    g.sub g22, g22, g1
    g.bz g22, space

; ---------------------------------------------------------------------
; STRESS: a hexagonal packing of photoelastic glass disks between crossed
; circular polarisers. Every disk carries six Flamant point loads at its
; contacts, sigma += k (q q^T) with k = -F (q . u) / |q|^4, q = r - u; the
; contact force F (shared by both disks) is heavy-tailed, grows with depth
; and surges with every kick. Fringe order N = C
; (sigma1 - sigma2); light = sum over wavelengths of sin^2(pi N 550/l):
; the Michel-Levy interference colours.
; 8 zoom, 9 sin(rotation), 10 x0, 11 y0, 12 fringe constant C, 13 wave
; gain, 14 chain force, 15 depth gain
; ---------------------------------------------------------------------
; D = round(X K) (KH = 1024.5, KM = -1024: X K > -1024)
stress:
    g.fli g14, 1024.5 ; exact
    g.fli g15, -1024.0 ; exact
    g.uniform g19, 8              ; zoom
    g.uniform g20, 9              ; sin(rotation)
    g.fmul g23, g20, g20
    g.fsub g23, g12, g23
    g.sqrt g23, g23
    g.fmul g2, g30, g23
    g.fmul g21, g28, g20
    g.fsub g2, g2, g21
    g.fmul g3, g30, g20
    g.fmul g21, g28, g23
    g.fadd g3, g3, g21
    g.fmul g2, g2, g19
    g.fmul g3, g3, g19
    g.uniform g19, 10
    g.fadd g2, g2, g19
    g.uniform g19, 11
    g.fadd g3, g3, g19
    ; nearest disk centre: (2 round(x/2), 2s round(y/2s)) or offset by (1, s), s = sqrt 3
    ; <rnd CX, PX, 0.5>
    g.fli g4, 0.5 ; exact
    g.fmul g4, g2, g4
    g.fadd g4, g4, g14
    g.ftoi g4, g4
    g.itof g4, g4
    g.fadd g4, g4, g15
    g.fadd g4, g4, g4
    ; <rnd CY, PY, 0.28867513>
    g.fli g5, 0.28867513 ; exact
    g.fmul g5, g3, g5
    g.fadd g5, g5, g14
    g.ftoi g5, g5
    g.itof g5, g5
    g.fadd g5, g5, g15
    g.fli g19, 3.4641016 ; exact
    g.fmul g5, g5, g19
    g.fsub g20, g2, g12
    ; <rnd RX, B, 0.5>
    g.fli g6, 0.5 ; exact
    g.fmul g6, g20, g6
    g.fadd g6, g6, g14
    g.ftoi g6, g6
    g.itof g6, g6
    g.fadd g6, g6, g15
    g.fadd g6, g6, g6
    g.fadd g6, g6, g12
    g.fli g20, 1.7320508 ; exact
    g.fsub g23, g3, g20
    ; <rnd RY, E, 0.28867513>
    g.fli g7, 0.28867513 ; exact
    g.fmul g7, g23, g7
    g.fadd g7, g7, g14
    g.ftoi g7, g7
    g.itof g7, g7
    g.fadd g7, g7, g15
    g.fmul g7, g7, g19
    g.fadd g7, g7, g20
    ; the nearer of the two
    g.fsub g19, g2, g4
    g.fsub g20, g3, g5
    g.fmul g19, g19, g19
    g.fmul g20, g20, g20
    g.fadd g23, g19, g20
    g.fsub g19, g2, g6
    g.fsub g20, g3, g7
    g.fmul g19, g19, g19
    g.fmul g20, g20, g20
    g.fadd g19, g19, g20
    g.flt g21, g23, g19
    g.bnz g21, near_a
    g.mov g4, g6
    g.mov g5, g7
    g.mov g23, g19
near_a:
    g.fli g19, 0.9375
    g.flt g21, g19, g23
    g.bnz g21, st_bg
    g.fsub g6, g2, g4
    g.fsub g7, g3, g5
    ; the kick loads the pile: gain / (1 + 6 (t - beat))^2 on the chains
    g.uniform g20, U_BEAT
    g.itof g20, g20
    g.fli g21, 0.4 ; exact
    g.fmul g20, g20, g21
    g.fsub g20, g29, g20
    g.fli g21, 6.0
    g.fmul g20, g20, g21
    g.fadd g20, g20, g12
    g.fmul g20, g20, g20
    g.uniform g19, 13
    g.fdiv g27, g19, g20
    g.mov g8, g0
    g.mov g9, g0
    g.mov g10, g0
    g.mov g24, g12
    g.mov g25, g0
    g.fli g16, 0.5 ; exact
    g.fli g17, 0.8660254 ; exact
    g.li g26, 6
contact:
    ; contact point c + u, hashed on its half-lattice coordinates
    g.fadd g19, g4, g24
    g.fadd g20, g5, g25
    g.fli g23, 2.0 ; exact
    g.fmul g23, g19, g23
    g.fadd g23, g23, g14
    g.ftoi g23, g23
    g.fli g21, 1.1547005 ; exact
    g.fmul g21, g20, g21
    g.fadd g21, g21, g14
    g.ftoi g21, g21
    g.li g31, 73856093
    g.mul g23, g23, g31
    g.add g31, g23, g21
    g.mul g31, g31, g31
    g.mul g31, g31, g31
    g.itof g31, g31
    g.fli g23, 2.3283064e-10 ; exact
    g.fmul g31, g31, g23
    g.fadd g31, g31, g16             ; h in [0, 1)
    ; F = 0.03 + chain h^5 - depth gain y + wave h
    g.fmul g23, g31, g31
    g.fmul g23, g23, g23
    g.fmul g23, g23, g31
    g.uniform g21, 14
    g.fmul g23, g23, g21
    g.fli g21, 0.0302734375
    g.fadd g18, g23, g21
    g.uniform g21, 15
    g.fmul g21, g21, g20
    g.fsub g18, g18, g21
    g.fmul g21, g27, g31
    g.fadd g18, g18, g21
    ; Flamant load at the contact
    g.fsub g19, g6, g24
    g.fsub g20, g7, g25
    g.fmul g23, g19, g19
    g.fmul g21, g20, g20
    g.fadd g23, g23, g21
    g.fli g21, 0.0040283203125
    g.fadd g23, g23, g21
    g.fmul g23, g23, g23
    g.fmul g21, g19, g24
    g.fmul g31, g20, g25
    g.fadd g21, g21, g31
    g.fmul g21, g21, g18
    g.fdiv g21, g21, g23
    g.fsub g21, g0, g21             ; k
    g.fmul g23, g19, g21
    g.fmul g31, g23, g19
    g.fadd g8, g8, g31
    g.fmul g31, g23, g20
    g.fadd g9, g9, g31
    g.fmul g23, g20, g21
    g.fmul g23, g23, g20
    g.fadd g10, g10, g23
    ; next contact direction: rotate u by 60 degrees
    g.fmul g23, g24, g16
    g.fmul g21, g25, g17
    g.fsub g23, g23, g21
    g.fmul g21, g24, g17
    g.fmul g25, g25, g16
    g.fadd g25, g25, g21
    g.mov g24, g23
    g.sub g26, g26, g1
    g.bnz g26, contact
    ; sigma1 - sigma2 -> fringe order N
    g.fsub g19, g8, g10
    g.fmul g19, g19, g19
    g.fmul g20, g9, g9
    g.fadd g20, g20, g20
    g.fadd g20, g20, g20
    g.fadd g19, g19, g20
    g.sqrt g19, g19
    g.uniform g20, 12
    g.fmul g19, g19, g20              ; N
    ; six wavelengths of sin^2(pi N r) ~ (4 f (1 - f))^2, f = frac(N r)
    g.mov g14, g0
    g.mov g15, g0
    g.li g21, d_lambda - d_base
    g.li g26, 6
    g.fli g9, 0.00390625      ; 1/255
wave:
    g.ldb g20, g21, 1
    g.itof g20, g20
    g.fmul g20, g20, g9
    g.fmul g20, g20, g19              ; N 550/l (bytes hold 550/l * 255 / 2)
    g.fadd g20, g20, g20
    g.ftoi g23, g20
    g.itof g23, g23
    g.fsub g20, g20, g23
    g.fsub g23, g12, g20
    g.fmul g20, g20, g23
    g.fmul g20, g20, g20
    g.add g21, g21, g1
    g.ldb g6, g21, 1
    g.add g21, g21, g1
    g.ldb g7, g21, 1
    g.add g21, g21, g1
    g.ldb g8, g21, 1
    g.add g21, g21, g1
    g.itof g6, g6
    g.itof g7, g7
    g.itof g8, g8
    g.fmul g20, g20, g9
    g.vscale g6, g6, g20
    g.vadd g13, g13, g6
    g.sub g26, g26, g1
    g.bnz g26, wave
    g.jmp post
st_bg:
    g.mov g14, g0
    g.mov g15, g0

; ---------------------------------------------------------------------
; post: exposure, flash, filmic curve, gamma, grain, temporal blend with
; the frame on screen, store
; ---------------------------------------------------------------------
post:
    g.uniform g2, 5
    g.vscale g13, g13, g2        ; exposure
    ; flash: [F | -31 F] lerped, clamped: fades out over the first 12 frames
    g.uniform g2, 6
    g.fmax g2, g2, g0
    g.fadd g13, g13, g2
    g.fadd g14, g14, g2
    g.fadd g15, g15, g2
    ; pixel, grain
    g.id g4, 1
    g.li g2, 160
    g.mul g4, g4, g2
    g.id g2, 0
    g.add g4, g4, g2
    g.uniform g5, 0
    g.li g3, 0x2C1B3C6D
    g.mul g5, g5, g3
    g.add g5, g5, g4
    g.mul g5, g5, g5
    g.mul g5, g5, g3
    g.itof g5, g5
    g.fli g3, 4.661160346586257e-12       ; +-0.01
    g.fmul g5, g5, g3
    g.uniform g6, 7
    g.add g7, g4, g4
    g.add g7, g7, g4
    g.li g8, 3
pch:
    ; filmic x (2.51 x + 0.03) / (x (2.43 x + 0.59) + 0.14), gamma 1/2, grain,
    ; then new = old + (colour - old) k with the frame on screen
    g.fmax g9, g13, g0
    g.fli g17, 2.5
    g.fmul g17, g17, g9
    g.fli g16, 0.0302734375
    g.fadd g17, g17, g16
    g.fmul g17, g17, g9
    g.fli g16, 2.4375
    g.fmul g16, g16, g9
    g.fli g22, 0.59375
    g.fadd g16, g16, g22
    g.fmul g16, g16, g9
    g.fli g22, 0.140625
    g.fadd g16, g16, g22
    g.fdiv g9, g17, g16
    g.sqrt g9, g9
    g.fadd g9, g9, g5
    g.ldb g2, g7, 3
    g.itof g2, g2
    g.fli g3, 0.00390625        ; 1/255
    g.fmul g2, g2, g3
    g.fsub g9, g9, g2
    g.fmul g9, g9, g6
    g.fadd g9, g9, g2
    g.mov g13, g14
    g.mov g14, g15
    g.mov g15, g9
    g.add g7, g7, g1
    g.sub g8, g8, g1
    g.bnz g8, pch
    g.rgb g13, g4, 0
    g.end

; ---------------------------------------------------------------------
; ECHO: a star in a dust nebula flares on every beat. The flare reaches
; the camera scattered by dust on the ellipsoid s + |X - L| = c (t - t0)
; (foci: the star L = origin and the camera), so each light echo sweeps
; through the nebula sheet by sheet, with apparent superluminal motion.
; 8-10 camera (looking at the star), 11 focal length, 12 beat gains
; (4 bytes, beat 0 lowest), 13 dust scale, 14 light speed, 15 star
; ---------------------------------------------------------------------
echo:
    g.uniform g2, 8
    g.uniform g3, 9
    g.uniform g4, 10
    g.fsub g8, g0, g2
    g.fsub g9, g0, g3
    g.fsub g10, g0, g4
    g.norm3 g8, g8
    g.mov g24, g10
    g.mov g25, g0
    g.fsub g26, g0, g8
    g.norm3 g24, g24
    ; up = FW x RT
    g.fmul g18, g9, g26
    g.fmul g23, g10, g24
    g.fmul g21, g8, g26
    g.fsub g19, g23, g21
    g.fmul g23, g9, g24
    g.fsub g20, g0, g23
    g.uniform g27, 11
    g.vscale g24, g24, g30
    g.vscale g18, g18, g28
    g.vscale g8, g8, g27
    g.vadd g5, g8, g24
    g.vadd g5, g5, g18
    g.norm3 g5, g5
; ---- the star at the centre of the screen ----
    g.fmul g18, g30, g30
    g.fmul g19, g28, g28
    g.fadd g18, g18, g19
    g.fli g19, 0.0005950927734375
    g.fadd g18, g18, g19
    g.fdiv g26, g19, g18              ; core
    g.uniform g23, 15            ; star brightness
    g.fmul g26, g26, g23
    g.mov g13, g26
    g.fli g18, 0.921875
    g.fmul g14, g26, g18
    g.fli g18, 0.796875
    g.fmul g15, g26, g18
; ---- echoes of the last eight beats ----
.equ KX, 0x2B7E1517
.equ KY, 0x6A09E667
.equ KZ, 0xBB67AE85
    g.dot3 g9, g5, g2
    g.dot3 g10, g2, g2
    g.uniform g16, 13            ; dust scale
    g.vscale g2, g2, g16
    g.vscale g5, g5, g16
    g.uniform g8, U_BEAT
pulse:
    ; gain of the beat: byte (K & 3) of the gain word
    g.li g16, 3
    g.and g16, g8, g16
    g.add g16, g16, g16
    g.add g16, g16, g16
    g.add g16, g16, g16
    g.uniform g24, 12
    g.shr g24, g24, g16
    g.li g16, 255
    g.and g24, g24, g16
    g.bz g24, p_next
    g.itof g24, g24
    ; age a = t - 0.4 K, R = c a
    g.itof g17, g8
    g.fli g22, 0.4 ; exact
    g.fmul g17, g17, g22
    g.fsub g17, g29, g17
    g.uniform g16, 14
    g.fmul g25, g17, g16           ; R
    ; s = (R^2 - |C|^2) / (2 (R + D.C)) once R > |C|
    g.fmul g16, g25, g25
    g.fsub g16, g16, g10
    g.fle g17, g16, g0
    g.bnz g17, p_next
    g.fadd g17, g25, g9
    g.fadd g17, g17, g17
    g.fdiv g26, g16, g17
    ; r^2 = |C|^2 + (2 D.C + s) s, dx = (D.C + s) / r
    g.fadd g16, g9, g9
    g.fadd g16, g16, g26
    g.fmul g16, g16, g26
    g.fadd g16, g16, g10
    g.rsqrt g17, g16
    g.fadd g22, g9, g26
    g.fmul g22, g22, g17
    ; jacobian 1 + dx (thin shell -> brightness per unit length of the ray)
    g.fadd g23, g22, g12
    g.fli g21, 0.0498046875
    g.fmax g23, g23, g21
    ; forward-scattering phase (g = 0.5): ~ 1 / (1.25 + dx)^1.5
    g.fli g21, 1.25
    g.fadd g21, g21, g22
    g.sqrt g27, g21
    g.fmul g21, g21, g27
    g.fdiv g24, g24, g21
    ; tail of the pulse inside the shell: min(1, jac s)
    g.fmul g21, g23, g26
    g.fmin g21, g21, g12
    g.fmul g24, g24, g21
    ; brightness 0.004 / (r jac) (softer than 1/r^2: old echoes stay visible)
    g.fmul g24, g24, g17
    g.fdiv g24, g24, g23
    g.fli g21, 0.0040283203125
    g.fmul g24, g24, g21
    ; colour weight w = 1 / (1 + 0.12 R): young echoes white, old ones red
    g.fli g16, 0.12109375
    g.fmul g16, g16, g25
    g.fadd g16, g16, g12
    g.fdiv g25, g12, g16
    ; dust density at X = C + s D: two octaves of ridged value noise
    g.mov g31, g0
    g.mov g16, g12
octave:
    g.vscale g18, g5, g26
    g.vadd g18, g18, g2
    g.vscale g18, g18, g16
    g.fli g16, 512.0
    g.fadd g18, g18, g16
    g.fadd g19, g19, g16
    g.fadd g20, g20, g16
    ; <vaxis QX, SX, KX>
    g.ftoi g16, g18
    g.itof g17, g16
    g.fsub g17, g18, g17
    g.fmul g23, g17, g17
    g.fadd g17, g17, g17
    g.fli g18, 3.0
    g.fsub g17, g18, g17
    g.fmul g23, g23, g17
    g.li g18, KX
    g.mul g18, g16, g18
    ; <vaxis QY, SY, KY>
    g.ftoi g16, g19
    g.itof g17, g16
    g.fsub g17, g19, g17
    g.fmul g21, g17, g17
    g.fadd g17, g17, g17
    g.fli g19, 3.0
    g.fsub g17, g19, g17
    g.fmul g21, g21, g17
    g.li g19, KY
    g.mul g19, g16, g19
    ; <vaxis QZ, SZ, KZ>
    g.ftoi g16, g20
    g.itof g17, g16
    g.fsub g17, g20, g17
    g.fmul g27, g17, g17
    g.fadd g17, g17, g17
    g.fli g20, 3.0
    g.fsub g17, g20, g17
    g.fmul g27, g27, g17
    g.li g20, KZ
    g.mul g20, g16, g20
    g.li g11, 2
vplane:
    ; bilinear z-plane of corner hashes h = (X ^ Y ^ Z)^2 -> F1
    g.xor g16, g18, g19
    g.xor g16, g16, g20
    g.mul g16, g16, g16
    g.itof g16, g16
    g.li g17, KX
    g.add g17, g17, g18
    g.xor g17, g17, g19
    g.xor g17, g17, g20
    g.mul g17, g17, g17
    g.itof g17, g17
    g.fsub g17, g17, g16
    g.fmul g17, g17, g23
    g.fadd g22, g16, g17
    g.li g16, KY
    g.add g16, g16, g19
    g.xor g17, g18, g16
    g.xor g17, g17, g20
    g.mul g17, g17, g17
    g.itof g17, g17
    g.xor g16, g16, g20
    g.li g30, KX
    g.add g30, g30, g18
    g.xor g16, g16, g30
    g.mul g16, g16, g16
    g.itof g16, g16
    g.fsub g16, g16, g17
    g.fmul g16, g16, g23
    g.fadd g16, g16, g17
    g.fsub g16, g16, g22
    g.fmul g16, g16, g21
    g.fadd g30, g22, g16
    g.sub g11, g11, g1
    g.bz g11, vpl_done
    g.mov g28, g30
    g.li g16, KZ
    g.add g20, g20, g16
    g.jmp vplane
vpl_done:
    g.fsub g30, g30, g28
    g.fmul g30, g30, g27
    g.fadd g30, g30, g28
    g.bnz g31, oct2
    g.fli g16, 0.6015625
    g.fmul g31, g30, g16
    g.fli g16, 2.3125
    g.jmp octave
oct2:
    g.fli g16, 0.4 ; exact
    g.fmul g30, g30, g16
    g.fadd g31, g31, g30
    ; ridge: m = max(0, 1 - 6 |n - 1/2|)^2 (raw noise is centred on 0, scale 2^32)
    g.fsub g16, g0, g31
    g.fmax g16, g16, g31
    g.fli g17, 1.3969838619232178e-9     ; 6 / 2^32
    g.fmul g16, g16, g17
    g.fsub g16, g12, g16
    g.fmax g16, g16, g0
    g.fmul g16, g16, g16
    g.fmul g24, g24, g16
    ; colour (1, w, w^2); odd beats (claps) mirrored to (w^2, w, 1)
    g.fmul g17, g24, g25
    g.fmul g22, g17, g25
    g.and g16, g8, g1
    g.bz g16, p_warm
    g.mov g16, g24
    g.mov g24, g22
    g.mov g22, g16
p_warm:
    g.fadd g13, g13, g24
    g.fadd g14, g14, g17
    g.fadd g15, g15, g22
p_next:
    g.sub g8, g8, g1
    g.uniform g16, U_BEAT
    g.sub g16, g16, g8
    g.li g17, 8
    g.sub g16, g16, g17
    g.bnz g16, pulse
    g.jmp post

; ---------------------------------------------------------------------
; SPACE: flight down a tunnel of glowing rings (blackbody) at speed beta.
; The camera-frame ray is aberrated into the lab frame,
;   d = (dx D, dy D, (dz - beta) / q), D = 1 / (gamma q), q = 1 - beta dz,
; and every ring is seen at Planck(D T): Doppler shift and headlight.
; 8 beta, 9 beta at the scene start, 10 z0, 11 camera x, 12 sin(yaw),
; 13 glow gain, 14 letters' speed (0: none), 15 their centre, z from the camera
; ---------------------------------------------------------------------
space:
    g.mov g2, g30
    g.mov g3, g28
    g.fli g4, 1.203125
    g.uniform g18, 12             ; looking sideways (+x)?
    g.bz g18, fwd_look
    g.mov g18, g2
    g.mov g2, g4
    g.fsub g4, g0, g18
fwd_look:
    g.norm3 g2, g2
    ; aberration
    g.uniform g24, 8
    g.fmul g18, g24, g24
    g.fsub g18, g12, g18
    g.rsqrt g25, g18
    g.fmul g18, g24, g4
    g.fsub g18, g12, g18
    g.fmul g19, g25, g18
    g.fdiv g26, g12, g19
    g.fmul g5, g2, g26
    g.fmul g6, g3, g26
    g.fsub g19, g4, g24
    g.fdiv g7, g19, g18
    ; camera (x, 0.2, z0 + c t (beta0 + beta) / 2), c = 10 units / s
    g.uniform g8, 11
    g.fli g9, 0.19921875
    g.uniform g18, 9
    g.fadd g18, g18, g24
    g.uniform g19, 1
    g.itof g19, g19
    g.fmul g18, g18, g19
    g.fli g19, 0.083333336 ; exact
    g.fmul g18, g18, g19
    g.uniform g19, 10
    g.fadd g10, g18, g19
    g.bnz g15, sp_tunnel         ; second pass: the letters are done
    g.fli g15, 80.0
    g.uniform g18, 14             ; letters on (moving)?
    g.bz g18, sp_tunnel
    g.jmp letters
sp_tunnel:
    g.mov g23, g15
    g.mov g16, g13
    g.mov g29, g14
;---- tunnel: glowing rings of radius 3 every 2 units along z; each ring
; plane crossed by the ray adds w^2 / (w^2 + (rho - 3)^2), every fourth
; ring three times ----
    g.vscale g2, g8, g12
    g.fli g18, 0.5 ; exact
    g.fmul g18, g4, g18
    g.fli g19, 1024.0 ; exact
    g.fadd g18, g18, g19
    g.ftoi g22, g18
    g.li g19, 1024
    g.sub g22, g22, g19             ; floor(z / 2)
    g.mov g17, g1
    g.flt g27, g0, g7
    g.bz g27, back
    g.add g22, g22, g17
    g.jmp fwd
back:
    g.sub g17, g0, g17
fwd:
    g.itof g18, g22
    g.fadd g18, g18, g18
    g.fsub g18, g18, g4
    g.fdiv g9, g18, g7
    g.fli g18, 2.0 ; exact
    g.fdiv g10, g18, g7
    g.fsub g18, g0, g10
    g.fmax g10, g10, g18
    g.fli g25, 0.953125              ; fog per plane
    g.mov g24, g12
    g.fli g30, 0.0040283203125
    g.fli g14, 3.0
    g.mov g21, g0
    g.li g28, 40
ring:
    g.fmul g18, g5, g9
    g.fadd g18, g18, g2
    g.fmul g27, g6, g9
    g.fadd g27, g27, g3
    g.fmul g18, g18, g18
    g.fmul g27, g27, g27
    g.fadd g18, g18, g27
    g.sqrt g18, g18
    g.fsub g18, g18, g14
    g.flt g27, g30, g18              ; outside the tube: done
    g.bnz g27, rg_done
    g.fmul g18, g18, g18
    g.fadd g18, g18, g30
    g.fdiv g18, g24, g18
    g.fadd g21, g21, g18
    g.li g27, 3
    g.and g27, g22, g27
    g.bnz g27, rg_next
    g.fadd g21, g21, g18            ; every fourth ring brighter
    g.fadd g21, g21, g18
rg_next:
    g.fmul g24, g24, g25
    g.fadd g9, g9, g10
    g.add g22, g22, g17
    g.flt g18, g23, g9
    g.bnz g18, rg_done
    g.sub g28, g28, g1
    g.bnz g28, ring
rg_done:
    g.uniform g18, 13
    g.fmul g18, g18, g30
    g.fmul g21, g21, g18
;---- blackbody colours at the Doppler factor: the rings at T0, the
; letters at their own factor; per channel
; c = W_c / (2^(A_c / (D r)) - 1), (A_c, W_c) for T0 = 5500 K ----
    g.mov g4, g26
    g.mov g6, g21
    g.mov g7, g29
    g.mov g8, g16
    g.mov g13, g0
    g.mov g14, g0
    g.mov g15, g0
    g.li g27, 4
    g.li g24, 2
cls:
    g.bz g6, cls_next
    g.li g20, d_planck - d_base
    g.li g23, 3
chan:
    g.ld g18, g20, 1
    g.fdiv g18, g18, g4
    g.fli g19, 120.0
    g.fmin g18, g18, g19
    ; <pow2 E, Y>
    g.ftoi g17, g18
    g.itof g16, g17
    g.fsub g16, g18, g16
    g.fli g19, 0.078125
    g.fmul g19, g19, g16
    g.fli g22, 0.2265625
    g.fadd g19, g19, g22
    g.fmul g19, g19, g16
    g.fli g22, 0.6953125
    g.fadd g19, g19, g22
    g.fmul g19, g19, g16
    g.fadd g19, g19, g12
    g.li g22, 23
    g.shl g17, g17, g22
    g.add g19, g19, g17
    g.fsub g19, g19, g12
    g.add g20, g20, g27
    g.ld g18, g20, 1
    g.fdiv g18, g18, g19
    g.fmul g18, g18, g6
    g.add g20, g20, g27
    g.mov g19, g13
    g.mov g13, g14
    g.mov g14, g15
    g.fadd g15, g19, g18
    g.sub g23, g23, g1
    g.bnz g23, chan
cls_next:
    g.mov g4, g7
    g.mov g6, g8
    g.sub g24, g24, g1
    g.bnz g24, cls
    g.jmp post

; ---------------------------------------------------------------------
; Letters (Terrell rotation): LIGHTCONE as 29 boxes (letters 2 x 4, pitch 3,
; 0.2-unit grid, scaled by 0.4) flying along the tunnel (z) at
; beta_L = B (1 - s) and stopping in front of the camera. In their rest
; frame a camera ray is straight: the light left the text at t - s/c, so
; the direction is ((d.z + beta) gamma, d.y, d.x) with the lab length s
; along it, and the text is contracted by 1/gamma. Results: g1 shading,
; g2 Doppler factor (x temperature ratio 1.2), g3 hit length.
; ---------------------------------------------------------------------
letters:
    g.uniform g9, 14            ; beta_L
    g.fmul g20, g9, g9
    g.fsub g20, g12, g20
    g.rsqrt g10, g20              ; gamma
    ; Doppler of the text: 1.8 / (gamma (1 + beta d.z))
    g.fmul g20, g9, g7
    g.fadd g20, g20, g12
    g.fmul g20, g20, g10
    g.fli g23, 1.8125
    g.fdiv g14, g23, g20
    ; rest-frame direction (-(d.z + beta) gamma, d.y, d.x), in grid units
    ; (12.5 per lab unit); IV = 1 / it
    g.fadd g20, g7, g9
    g.fmul g20, g20, g10
    g.fli g23, -12.5 ; exact
    g.fmul g20, g20, g23
    g.fdiv g2, g12, g20
    g.fsub g23, g0, g23
    g.fmul g20, g6, g23
    g.fdiv g3, g12, g20
    g.fmul g20, g5, g23
    g.fdiv g4, g12, g20
    ; rest-frame origin: the text centre (x = 67 grid) is z_L (lab) along
    ; the tunnel from the camera: x = 67 - 12.5 gamma z_L, y = 12.5 c.y + 12,
    ; z = 12.5 (c.x - 1.2)
    g.uniform g20, 15
    g.fmul g20, g20, g10
    g.fmul g20, g20, g23
    g.fli g5, 67.0 ; exact
    g.fsub g5, g5, g20
    g.fmul g20, g9, g23
    g.fli g17, 12.0 ; exact
    g.fadd g6, g20, g17
    g.fli g20, 1.203125
    g.fsub g20, g8, g20
    g.fmul g7, g20, g23
    g.fli g17, 2.0 ; exact
    g.fsub g27, g0, g17
    g.fli g22, 0.5
    g.fli g29, 0.625
    g.fli g31, -0.625
    g.li g8, d_strokes - d_base
stroke:
    g.ldb g9, g8, 1
    g.add g8, g8, g1
    g.ldb g10, g8, 1
    g.add g8, g8, g1
    g.ldb g24, g8, 1
    g.add g8, g8, g1
    g.ldb g25, g8, 1
    g.add g8, g8, g1
    g.itof g9, g9
    g.itof g10, g10
    g.itof g24, g24
    g.itof g25, g25
    g.fli g18, -992.0
    g.fli g19, 992.0
    ; <slab X0, X1, OR, IV, LX>
    g.fsub g20, g9, g5
    g.fmul g20, g20, g2
    g.fsub g23, g24, g5
    g.fmul g23, g23, g2
    g.fmin g26, g20, g23
    g.fmax g23, g20, g23
    g.fmin g19, g19, g23
    g.fle g20, g26, g18
    g.bnz g20, sk8
    g.mov g18, g26
    g.fsub g21, g0, g22
    g.flt g20, g2, g0
    g.bz g20, sk8
    g.mov g21, g22
sk8:
    ; <slab Y0, Y1, OR.y, IV.y, LY>
    g.fsub g20, g10, g6
    g.fmul g20, g20, g3
    g.fsub g23, g25, g6
    g.fmul g23, g23, g3
    g.fmin g26, g20, g23
    g.fmax g23, g20, g23
    g.fmin g19, g19, g23
    g.fle g20, g26, g18
    g.bnz g20, sk9
    g.mov g18, g26
    g.fsub g21, g0, g29
    g.flt g20, g3, g0
    g.bz g20, sk9
    g.mov g21, g29
sk9:
    ; <slab ZL, ZH, OR.z, IV.z, LZ>
    g.fsub g20, g27, g7
    g.fmul g20, g20, g4
    g.fsub g23, g17, g7
    g.fmul g23, g23, g4
    g.fmin g26, g20, g23
    g.fmax g23, g20, g23
    g.fmin g19, g19, g23
    g.fle g20, g26, g18
    g.bnz g20, sk10
    g.mov g18, g26
    g.fsub g21, g0, g31
    g.flt g20, g4, g0
    g.bz g20, sk10
    g.mov g21, g31
sk10:
    ; nearer hit?
    g.flt g20, g19, g18
    g.bnz g20, st_next
    g.fle g20, g18, g0
    g.bnz g20, st_next
    g.flt g20, g18, g15
    g.bz g20, st_next
    g.mov g15, g18
    g.mov g13, g21
st_next:
    g.li g20, d_strokes_end - d_base
    g.sub g20, g8, g20
    g.bnz g20, stroke
    ; shading 0.25 + 0.75 max(0, n.l) on a hit
    g.fmax g13, g13, g0
    g.fli g20, 0.75
    g.fmul g13, g13, g20
    g.fli g20, 0.25
    g.fadd g13, g13, g20
    g.fli g20, 79.0
    g.flt g20, g15, g20
    g.itof g20, g20
    g.fmul g13, g13, g20
    g.jmp space
render_k_end:

; ---- include spu.s ----
; ---------------------------------------------------------------------
; SPU kernel: one invocation per stereo sample (grid 64 x 4). Hard techno
; at 150 BPM (4800 samples per 16th). A table of stateless voices (noise,
; pitch-swept tone, chord, CZ-style acid), a modal "rumble" tail of the
; kick, and a 4-line feedback delay network (24 kHz, bf16 state in RAM,
; reading only samples from earlier blocks). Binding 0: output (2048
; bytes); binding 1: song data. Uniform 0: sample index
; of the demo start.
; ---------------------------------------------------------------------
.equ SONG, 2764800              ; 36 bars
; -sin(2 pi x) / 8, x >= 0: g (1 - 2|g|), g = frac(x) - 1/2 (R: scratch)
; soft clip x / sqrt(1 + x^2) (R: scratch)


spu_k:
    g.fli g24, 1.0
    g.li g12, 1
    g.fli g27, 0.5 ; exact
    g.li g26, 0xffff0000
    g.li g1, 4
    g.li g11, 16
    g.id g22, 2
    g.uniform g16, 14
    g.add g22, g22, g16
    g.uniform g16, 0
    g.sub g22, g22, g16
    g.li g16, SONG
    g.slt g19, g22, g0
    g.bz g19, t_pos
    g.add g22, g22, g16
t_pos:
    g.slt g19, g22, g16
    g.bnz g19, t_in
    g.sub g22, g22, g16
t_in:
    ; 16th, bar, samples since the 16th and the beat, bar phase
    g.itof g16, g22
    g.fli g19, 4800.0 ; exact
    g.fdiv g16, g16, g19
    g.ftoi g23, g16                 ; step
    g.li g19, 4800
    g.mul g16, g23, g19
    g.sub g28, g22, g16
    g.li g16, 15
    g.and g9, g23, g16
    g.li g16, 3
    g.and g6, g23, g16
    g.mul g6, g6, g19
    g.add g6, g6, g28
    g.mul g16, g9, g19
    g.add g16, g16, g28
    g.itof g30, g16
    g.fli g16, 1.3020833e-05      ; 1 / 76800 (exact)
    g.fmul g30, g30, g16
    g.shr g23, g23, g1              ; bar
    g.add g23, g23, g23
    g.add g23, g23, g23
    g.ld g17, g23, 1               ; this bar's word
    g.add g23, g23, g1
    g.ld g21, g23, 1                ; the next bar's
    ; levels (bytes 2, 3) lerped towards the next bar's -> PADL, CUT
    g.li g4, 2
    g.mov g20, g11
    g.li g8, 255
lvl:
    g.shr g16, g17, g20
    g.and g16, g16, g8
    g.shr g19, g21, g20
    g.and g19, g19, g8
    g.sub g19, g19, g16
    g.itof g19, g19
    g.fmul g19, g19, g30
    g.itof g16, g16
    g.fadd g16, g16, g19
    g.mov g14, g25
    g.mov g25, g16
    g.li g16, 8
    g.add g20, g20, g16
    g.sub g4, g4, g12
    g.bnz g4, lvl
    ; white noise: T K1, xor-shift, K2 (unscaled)
    g.li g8, 0x9E3779B1
    g.mul g7, g22, g8
    g.shr g8, g7, g11
    g.xor g7, g7, g8
    g.li g8, 0x846ca68b
    g.mul g7, g7, g8
    g.itof g7, g7               ; +-2^31: noise voice levels carry 2^-31
    g.mov g5, g0
    g.mov g29, g0
    ; kick sidechain: min(1, 0.05 + t / 10000) in kick bars
    g.mov g13, g24
    g.and g16, g17, g12
    g.bz g16, v_start
    g.itof g16, g6
    g.fli g19, 0.00009918212890625
    g.fmul g16, g16, g19
    g.fli g19, 0.0498046875
    g.fadd g16, g16, g19
    g.fmin g13, g16, g24
v_start:
    g.li g15, d_voices - d_song
; ---- voices: [mask | mode << 5 | flag], [decay | level],
; [drive | pan (tones: start/end pitch ratio R)], [a | fe] ----
voice:
    g.ld g8, g15, 1
    g.shr g16, g17, g8              ; (shift counts use the low 5 bits: the flag)
    g.and g16, g16, g12
    g.bz g16, v_next              ; not playing in this bar
    ; the latest trigger at or before this 16th: j0 = log2 of the highest
    ; set bit of mask & (2 << pos) - 1; t = samples since it
    g.shr g19, g8, g11
    g.li g16, 2
    g.shl g16, g16, g9
    g.sub g16, g16, g12
    g.and g19, g19, g16
    g.bz g19, v_next
    g.itof g19, g19
    g.li g16, 23
    g.shr g19, g19, g16
    g.li g16, 127
    g.sub g4, g19, g16               ; j0
    g.sub g16, g9, g4
    g.li g19, 4800
    g.mul g16, g16, g19
    g.add g16, g16, g28
    g.itof g10, g16                 ; t
    ; envelope 1 / (1 + k t)^2 (or (bar phase)^3 for risers) * level
    g.add g23, g15, g1
    g.ld g2, g23, 1
    g.and g18, g2, g26
    g.fmul g18, g18, g10
    g.fadd g18, g18, g24
    g.fmul g18, g18, g18
    g.fdiv g31, g24, g18
    g.li g19, 512
    g.and g19, g8, g19
    g.bz g19, no_rise
    g.fmul g31, g30, g30
    g.fmul g31, g31, g30
no_rise:
    g.shl g2, g2, g11
    g.fmul g31, g31, g2              ; level
    ; pad: times the bar's pad level
    g.li g19, 1024
    g.and g19, g8, g19
    g.bz g19, no_padl
    g.fmul g31, g31, g14
no_padl:
    ; kick sidechain
    g.li g19, 128
    g.and g19, g8, g19
    g.bz g19, no_duck
    g.fmul g31, g31, g13
no_duck:
    g.add g23, g23, g1
    g.add g23, g23, g1
    g.ld g2, g23, 1                ; [a | fe]
    g.li g19, 96
    g.and g19, g8, g19               ; type << 5
    g.bz g19, ty_noise
    g.li g16, 32
    g.sub g19, g19, g16
    g.bz g19, ty_tone
    g.sub g19, g19, g16
    g.bz g19, ty_chord
; -- acid: CZ-style resonant saw (1 - p) sin(2 pi r p), r = 2 + cut env,
;    notes from the pattern (the table's decay shapes them)
    g.li g16, d_acid - d_song
    g.add g16, g16, g4
    g.ldb g4, g16, 1
    g.bz g4, v_next
    g.mov g19, g4
    g.li g16, d_notes - d_song
    g.add g19, g19, g19
    g.add g19, g19, g19
    g.add g16, g16, g19
    g.ld g19, g16, 1                ; turns per sample
    g.fmul g16, g10, g19
    g.ftoi g19, g16
    g.itof g19, g19
    g.fsub g16, g16, g19              ; phase p
    g.and g18, g2, g26            ; a: cutoff envelope rate
    g.fmul g18, g18, g10
    g.fadd g18, g18, g24
    g.fmul g18, g18, g18
    g.fdiv g18, g24, g18
    g.fmul g18, g18, g25
    g.fli g19, 0.12109375
    g.fmul g18, g18, g19
    g.fadd g18, g18, g24
    g.fadd g18, g18, g24
    g.fmul g18, g18, g16
    ; <sinp Y, A>
    g.ftoi g3, g18
    g.itof g3, g3
    g.fsub g19, g18, g3
    g.fsub g19, g19, g27
    g.fsub g3, g0, g19
    g.fmax g3, g3, g19
    g.fadd g3, g3, g3
    g.fsub g3, g24, g3
    g.fmul g19, g19, g3
    g.fsub g18, g24, g16
    g.fmul g19, g19, g18
    g.fadd g16, g16, g16
    g.fsub g16, g16, g24
    g.fli g18, 0.0498046875
    g.fmul g16, g16, g18
    g.fadd g19, g19, g16
    g.jmp v_out
; -- noise
ty_noise:
    g.mov g19, g7
    g.jmp v_out
; -- tone: sine, f = fe (1 + (R - 1) / (1 + a t)^2):
;    phase fe (t + (R - 1) / a (1 - 1 / (1 + a t)))
ty_tone:
    g.and g18, g2, g26            ; a
    g.fmul g16, g18, g10
    g.fadd g16, g16, g24
    g.fdiv g16, g24, g16
    g.fsub g16, g24, g16
    g.fdiv g16, g16, g18
    g.sub g23, g23, g1
    g.ld g20, g23, 1                ; [drive | R]
    g.shl g20, g20, g11
    g.fsub g20, g20, g24
    g.fmul g16, g16, g20
    g.fadd g16, g16, g10
    g.shl g20, g2, g11             ; fe
    g.fmul g16, g16, g20
    ; <sinp Y, X>
    g.ftoi g3, g16
    g.itof g3, g3
    g.fsub g19, g16, g3
    g.fsub g19, g19, g27
    g.fsub g3, g0, g19
    g.fmax g3, g3, g19
    g.fadd g3, g3, g3
    g.fsub g3, g24, g3
    g.fmul g19, g19, g3
    g.jmp v_out
; -- chord: five notes in detuned pairs, integral turns per bar so the bar
;    phases join; saw blended towards triangle by a
ty_chord:
    g.and g18, g2, g26            ; a
    g.mov g19, g0
    g.mov g21, g0                 ; side
    g.li g23, d_chord - d_song
    g.li g4, 10
ch_note:
    g.ld g16, g23, 1
    g.itof g16, g16
    g.fmul g16, g16, g30
    g.ftoi g20, g16
    g.itof g20, g20
    g.fsub g16, g16, g20
    g.fadd g16, g16, g16
    g.fsub g16, g16, g24           ; saw
    g.fsub g20, g0, g16
    g.fmax g20, g20, g16
    g.fadd g20, g20, g20
    g.fsub g20, g24, g20           ; triangle 1 - 2 |saw|
    g.fsub g20, g20, g16
    g.fmul g20, g20, g18
    g.fadd g16, g16, g20
    g.fadd g19, g19, g16
    g.and g20, g4, g12
    g.bz g20, ch_left
    g.fadd g21, g21, g16
    g.jmp ch_next
ch_left:
    g.fsub g21, g21, g16
ch_next:
    g.add g23, g23, g1
    g.sub g4, g4, g12
    g.bnz g4, ch_note
    g.fmul g21, g21, g31
    g.fmul g21, g21, g27
    g.fadd g29, g29, g21
; -- common: y = soft(osc env drive), mid, pan (not for tones)
v_out:
    g.fmul g19, g19, g31
    g.add g23, g15, g1
    g.add g23, g23, g1
    g.ld g2, g23, 1                ; [drive | pan]
    g.and g18, g2, g26
    g.fmul g19, g19, g18
    ; <soft Y>
    g.fmul g3, g19, g19
    g.fadd g3, g3, g24
    g.rsqrt g3, g3
    g.fmul g19, g19, g3
    g.fadd g5, g5, g19
    g.li g16, 96
    g.and g16, g8, g16
    g.li g20, 32
    g.sub g16, g16, g20
    g.bz g16, v_next              ; tones: no pan (R is there)
    g.shl g2, g2, g11
    g.fmul g18, g19, g2
    g.fadd g29, g29, g18
v_next:
    g.add g15, g15, g11
    g.li g16, d_voices_end - d_song
    g.sub g16, g15, g16
    g.bnz g16, voice
    ; output with soft limiter
    g.fadd g16, g5, g29
    g.fsub g19, g5, g29
    ; <soft X>
    g.fmul g3, g16, g16
    g.fadd g3, g3, g24
    g.rsqrt g3, g3
    g.fmul g16, g16, g3
    ; <soft Y>
    g.fmul g3, g19, g19
    g.fadd g3, g3, g24
    g.rsqrt g3, g3
    g.fmul g19, g19, g3
    g.id g18, 2
    g.add g18, g18, g18
    g.add g18, g18, g18
    g.add g18, g18, g18
    g.st g16, g18, 0
    g.add g18, g18, g1
    g.st g19, g18, 0
    g.end
spu_k_end:


; ---------------------------------------------------------------------
; GPU data (binding 1)
; ---------------------------------------------------------------------
.align 4
d_base:
; ---- include scenes.s ----
; generated by src/scenes.py
.align 4
d_lambda:
    .byte 163, 24, 0, 112
    .byte 148, 6, 10, 140
    .byte 135, 5, 108, 3
    .byte 124, 70, 123, 0
    .byte 115, 121, 14, 0
    .byte 107, 29, 0, 0
.align 4
d_planck:
    .float 9.75, 848.0, 10.75, 1088.0, 12.75, 2080.0 
scenes:
    .word 0xfff ; scene 0
    .word 0x00010100 ; 0: raw
    .word 0x008001c0 ; 1: 0.5 1.75
    .word 0x00000000 ; 2: 0 -0
    .word 0x00980098 ; 3: 0.6 0.6
    .word 0x05000300 ; 4: 5 3
    .word 0x018000cc ; 5: 1.5 0.8
    .word 0xf000f300 ; 6: -16 -13
    .word 0x014c014c ; 7: 1.3 1.3
    .word 0x000000ff ; 8: raw
    .word 0x00430043 ; 9: 0.26 0.26
    .word 0x14001400 ; 10: 20 20
    .word 0x00330033 ; 11: 0.2 0.2
    .word 0x976 ; scene 1
    .word 0x01c001c0 ; 1: 1.75 1.75
    .word 0x0098da30 ; 2: 0.6 -37.8
    .word 0x0300fc00 ; 4: 3 -4
    .word 0x00ccff80 ; 5: 0.8 -0.5
    .word 0xf300f400 ; 6: -13 -12
    .word 0x00be00d2 ; 8: raw
    .word 0x004d004d ; 11: 0.3 0.3
    .word 0x3f6 ; scene 2
    .word 0x01800180 ; 1: 1.5 1.5
    .word 0x00000000 ; 2: 0 -0
    .word 0xfc00fe80 ; 4: -4 -1.5
    .word 0xff800134 ; 5: -0.5 1.2
    .word 0xf400f780 ; 6: -12 -8.5
    .word 0x01340180 ; 7: 1.2 1.5
    .word 0xaabeaac8 ; 8: raw
    .word 0x004d004d ; 9: 0.3 0.3
    .word 0xff7 ; scene 3
    .word 0x00000101 ; 0: raw
    .word 0x01000098 ; 1: 1 0.6
    .word 0x00cccda0 ; 2: 0.8 -50.4
    .word 0x000000f4 ; 4: 0 0.95
    .word 0x00000000 ; 5: 0 0
    .word 0x00000000 ; 6: 0 0
    .word 0x00e800e8 ; 7: 0.9 0.9
    .word 0x00000000 ; 8: 0 0
    .word 0x00cc0100 ; 9: 0.8 1
    .word 0x00000000 ; 10: 0 0
    .word 0x00000000 ; 11: 0 0
    .word 0xf9e ; scene 4
    .word 0x00cc00cc ; 1: 0.8 0.8
    .word 0x0100c100 ; 2: 1 -63
    .word 0x00d800d8 ; 3: 0.85 0.85
    .word 0x00000000 ; 4: 0 0
    .word 0xfda0fda0 ; 7: -2.4 -2.4
    .word 0x01000100 ; 8: 1 1
    .word 0x00800080 ; 9: 0.5 0.5
    .word 0x00cc004d ; 10: 0.8 0.3
    .word 0xf4000900 ; 11: -12 9
    .word 0xfbf ; scene 5
    .word 0x00000102 ; 0: raw
    .word 0x01c001c0 ; 1: 1.75 1.75
    .word 0x0098da30 ; 2: 0.6 -37.8
    .word 0x00980098 ; 3: 0.6 0.6
    .word 0x03600260 ; 4: 3.4 2.4
    .word 0xffe60040 ; 5: -0.1 0.25
    .word 0x01000100 ; 7: 1 1
    .word 0x008000cc ; 8: 0.5 0.8
    .word 0x00000000 ; 9: 0 0
    .word 0x01000380 ; 10: 1 3.5
    .word 0x00080008 ; 11: 0.03 0.03
    .word 0x7f4 ; scene 6
    .word 0x0100c100 ; 2: 1 -63
    .word 0x02300300 ; 4: 2.2 3
    .word 0x004dffe6 ; 5: 0.3 -0.1
    .word 0x03000300 ; 6: 3 3
    .word 0x00000000 ; 7: 0 0
    .word 0x00cc00cc ; 8: 0.8 0.8
    .word 0x03000300 ; 9: 3 3
    .word 0x02800280 ; 10: 2.5 2.5
    .word 0xff3 ; scene 7
    .word 0x00000101 ; 0: raw
    .word 0x00800080 ; 1: 0.5 0.5
    .word 0x00f400fc ; 4: 0.96 0.99
    .word 0x00f400f4 ; 5: 0.96 0.96
    .word 0x28002800 ; 6: 40 40
    .word 0xfe980198 ; 7: -1.4 1.6
    .word 0x00000000 ; 8: 0 0
    .word 0x01000100 ; 9: 1 1
    .word 0x00000000 ; 10: 0 0
    .word 0x00000000 ; 11: 0 0
    .word 0xff3 ; scene 8
    .word 0x00010100 ; 0: raw
    .word 0x01c00000 ; 1: 1.75 0
    .word 0xfe000600 ; 4: -2 6
    .word 0x02000080 ; 5: 2 0.5
    .word 0xf700f000 ; 6: -9 -16
    .word 0x014c014c ; 7: 1.3 1.3
    .word 0x007800ff ; 8: raw
    .word 0x00430043 ; 9: 0.26 0.26
    .word 0x14001400 ; 10: 20 20
    .word 0x004d004d ; 11: 0.3 0.3

; ---- include font.s ----
; generated: LIGHTCONE stroke boxes (x0, y0, x1, y1) in 0.2-unit steps (strokes 0.8 wide),
; letters 2 x 4, pitch 3: the text spans x 0..134, y 0..24
d_strokes:
    .byte 0, 0, 4, 24
    .byte 0, 0, 14, 4
    .byte 20, 0, 24, 24
    .byte 30, 20, 44, 24
    .byte 30, 0, 34, 24
    .byte 30, 0, 44, 4
    .byte 40, 0, 44, 14
    .byte 35, 10, 44, 14
    .byte 45, 0, 49, 24
    .byte 55, 0, 59, 24
    .byte 45, 10, 59, 14
    .byte 60, 20, 74, 24
    .byte 65, 0, 69, 24
    .byte 75, 20, 89, 24
    .byte 75, 0, 79, 24
    .byte 75, 0, 89, 4
    .byte 90, 0, 94, 24
    .byte 100, 0, 104, 24
    .byte 90, 20, 104, 24
    .byte 90, 0, 104, 4
    .byte 105, 0, 109, 24
    .byte 115, 0, 119, 24
    .byte 108, 13, 112, 17
    .byte 112, 7, 116, 11
    .byte 120, 0, 124, 24
    .byte 120, 20, 134, 24
    .byte 120, 0, 134, 4
    .byte 120, 10, 131, 14
d_strokes_end:

d_end:
prec:                           ; the current scene's record
    .word 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
; ---- include song.s ----
; generated by src/song.py
.align 4
d_song:
d_bars:
    .word 0x00000480 ; bar 0
    .word 0x00370480 ; bar 1
    .word 0x006e0480 ; bar 2
    .word 0x00a50580 ; bar 3
    .word 0x00c8008b ; bar 4
    .word 0x00a5008b ; bar 5
    .word 0x0082008b ; bar 6
    .word 0x005f008b ; bar 7
    .word 0x1428003f ; bar 8
    .word 0x261e003f ; bar 9
    .word 0x3714003f ; bar 10
    .word 0x480a003f ; bar 11
    .word 0x5a00003f ; bar 12
    .word 0x7600003f ; bar 13
    .word 0x9100003f ; bar 14
    .word 0xac00033f ; bar 15
    .word 0xaa00047f ; bar 16
    .word 0xb900007f ; bar 17
    .word 0xc800007f ; bar 18
    .word 0xd700007f ; bar 19
    .word 0x28ff00a0 ; bar 20
    .word 0x34f600a0 ; bar 21
    .word 0x41ee00a0 ; bar 22
    .word 0x4ee503a0 ; bar 23
    .word 0xdc00047f ; bar 24
    .word 0xe400007f ; bar 25
    .word 0xeb00007f ; bar 26
    .word 0xf200007f ; bar 27
    .word 0xfa00047f ; bar 28
    .word 0xee0f007f ; bar 29
    .word 0xe11e007f ; bar 30
    .word 0xd42d027f ; bar 31
    .word 0x00dc048b ; bar 32
    .word 0x00a5008b ; bar 33
    .word 0x006e0080 ; bar 34
    .word 0x00370080 ; bar 35
    .word 0x00000480 ; bar 36
d_voices:
    .word 0x11110020
    .word 0x39603f60 ; bf 0.000213623046875, 0.875
    .word 0x42004100 ; bf 32, 8
    .word 0x3b243a76 ; bf 0.0025, 0.0009375
    .word 0xeeee00a1
    .word 0x39d03ea0 ; bf 0.000396728515625, 0.3125
    .word 0x41c03fc0 ; bf 24, 1.5
    .word 0x3b453a6e ; bf 0.003, 0.0009094583333333334
    .word 0x0001002a
    .word 0x38203f30 ; bf 0.00003814697265625, 0.6875
    .word 0x414040a0 ; bf 12, 5
    .word 0x39af3a24 ; bf 0.0003333333333333333, 0.000625
    .word 0x0001000a
    .word 0x38a02e80 ; bf 0.0000762939453125, 5.820766091346741e-11
    .word 0x3f800000 ; bf 1, 0
    .word 0x00000000 ; bf 0, 0
    .word 0xffff0082
    .word 0x3b802f00 ; bf 0.00390625, 1.1641532182693481e-10
    .word 0x3f803ed0 ; bf 1, 0.40625
    .word 0x00000000 ; bf 0, 0
    .word 0x44440083
    .word 0x3a202f20 ; bf 0.0006103515625, 1.4551915228366852e-10
    .word 0x3f80bed0 ; bf 1, -0.40625
    .word 0x00000000 ; bf 0, 0
    .word 0x10100004
    .word 0x3ac02fa0 ; bf 0.00146484375, 2.9103830456733704e-10
    .word 0x3f803dd0 ; bf 1, 0.1015625
    .word 0x00000000 ; bf 0, 0
    .word 0x10100004
    .word 0x39a02ee0 ; bf 0.00030517578125, 1.0186340659856796e-10
    .word 0x3f80bdd0 ; bf 1, -0.1015625
    .word 0x00000000 ; bf 0, 0
    .word 0x80800004
    .word 0x3aa02ea0 ; bf 0.001220703125, 7.275957614183426e-11
    .word 0x3f803f30 ; bf 1, 0.6875
    .word 0x00000000 ; bf 0, 0
    .word 0xffff00e5
    .word 0x3a203e20 ; bf 0.0006103515625, 0.15625
    .word 0x41900000 ; bf 18, 0
    .word 0x39d20000 ; bf 0.0004, 0
    .word 0x484800c6
    .word 0x3a403e10 ; bf 0.000732421875, 0.140625
    .word 0x3f800000 ; bf 1, 0
    .word 0x00000000 ; bf 0, 0
    .word 0x00010447
    .word 0x00003900 ; bf 0, 0.0001220703125
    .word 0x3f800000 ; bf 1, 0
    .word 0x3f800000 ; bf 1, 0
    .word 0x00010208
    .word 0x00002f30 ; bf 0, 1.6007106751203537e-10
    .word 0x3f800000 ; bf 1, 0
    .word 0x00000000 ; bf 0, 0
    .word 0xffff0009
    .word 0x3b002fa0 ; bf 0.001953125, 2.9103830456733704e-10
    .word 0x3f800000 ; bf 1, 0
    .word 0x00000000 ; bf 0, 0
d_voices_end:
d_notes:
    .float 0.0, 0.001922607421875, 0.002288818359375, 0.0025634765625, 0.00286865234375, 0.00323486328125, 0.00384521484375 
d_acid:
    .byte 1, 1, 6, 1, 0, 1, 4, 1, 2, 1, 0, 6, 1, 5, 1, 3
.align 4
; chord (F minor add 9): turns per bar (76800 samples) of each note, detuned pairs
d_chord:
    .word 279, 280, 332, 333, 419, 418, 558, 559, 627, 628
d_song_end:


; MMIO configuration script: [dest, count, words...], 0 terminates
cfg:
    .word 0xf3000, 4, render_k, render_k_end - render_k, 160, 90
    .word 0xf3040, 15, VISA, 43200, 3, 0, d_base, d_end - d_base, 1, 0, 0, 0, 0, 0, VISB, 43200, 1
    .word 0xf6040, 5, spu_k, spu_k_end - spu_k, 64, 4, AOUT
    .word 0xf6100, 7, AOUT, 2048, 3, 0, d_song, d_song_end - d_song, 1
    .word 0xf6000, 1, 1
    .word 0xf5004, 4, 480, 4, 0, 1
    .word 0

