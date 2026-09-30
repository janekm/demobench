; LOAD 0x2E000
; =====================================================================
;  MEGAMIX -- a megademo in 4K for DB32 (dynamic-1, packed).
;  The whole program is a compressed RAM image unpacked to LOAD.
;  RAM: FB0 0x10000, FB1 0x1E100 (RGB888 pages), SPU output 0x2C200,
;  object table 0x2CA00, image LOAD..0x30000.
;  Per frame the CPU finds the current part, copies its parameters into
;  GPU uniforms, runs the prepass (object table) and the renderer in
;  strips, and flips pages at vblank.
; =====================================================================
.profile dynamic-1

.entry start
.equ FB0,   0x10000
.equ FB1,   0x1E100
.equ AOUT,  0x2C200
.equ TABLE, 0x2CA00
.equ TABSZ, 1024
.equ LOOP,  3600

start:
    lui r13, 0xf3
    lui r14, 0xf5
    li r1, cfg
    lw r2, 0(r1)
cfg_next:
    lw r3, 4(r1)
    addi r1, r1, 8
    jal r15, copy
    lw r2, 0(r1)
    bne r2, r0, cfg_next
    lui r10, 0x10               ; back buffer
    li r11, FB1                 ; front buffer
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
    addi r2, r0, 800
    mul r2, r9, r2
    sw r2, 0x3200(r13)          ; SPU U0 = sample index of the demo start
    ; part = frame / 450: six words -> U2..U7, frame in the part -> U1
    addi r3, r0, -1
    li r8, parts - 24
    addi r2, r0, 450
find:
    addi r8, r8, 24
    sub r1, r1, r2
    blt r3, r1, find
    add r1, r1, r2
    sw r1, 0x104(r13)
    add r1, r8, r0
    addi r2, r13, 0x108
    addi r3, r0, 6
    jal r15, copy
    ; prepass: one invocation per object, table writable
    li r1, h_pre
    addi r5, r0, 3
    jal r7, pass
    ; renderer in three strips of 40 rows, table read-only
    mov r6, r0
strip:
    sw r6, 0x124(r13)           ; U9 = first row
    li r1, h_render
    addi r5, r0, 1
    jal r7, pass
    addi r6, r6, 40
    addi r2, r0, 120
    blt r6, r2, strip
    sw r10, 0(r14)
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

; pass(r1 = [code, bytes, width, height], r5 = table flags)
pass:
    add r2, r13, r0
    addi r3, r0, 4
    jal r15, copy
    sw r5, 0x68(r13)
    addi r2, r0, 1
    sw r2, 16(r13)
wgpu:
    wfi
    lw r3, 20(r13)
    beq r3, r2, wgpu
    jalr r0, 0(r7)

; copy r3 words from r1 to r2
copy:
    lw r12, 0(r1)
    sw r12, 0(r2)
    addi r1, r1, 4
    addi r2, r2, 4
    addi r3, r3, -1
    bne r3, r0, copy
    jalr r0, 0(r15)

; ---- include gpu.s ----
; ---------------------------------------------------------------------
; Renderer: one invocation per pixel of a 40-row strip (grid 160 x 40).
; uniforms: 0 demo frame, 1 frame in the part, 2 part type, 3 text items
;   (one per byte), 4 [.bf flash, palette spread], 5..7 part parameters,
;   8 and 10..15 pooled float constants (.fpool), 9 first row of the strip.
; bindings: 0 back buffer, 1 data (text items, font, strings),
;   2 object table, 3 front buffer (the previous frame).
; setup runs twice: before the part (which may use every register but
; COL) and again on the way to post (text, flash, gamma, store). Setup
; also leaves the centred pixel (x - 80, 60 - y) in g26, g27.
; ---------------------------------------------------------------------
; -sin(2 pi p) / 16, parabolic, for p >= 0 turns (R: scratch)
; the same for p > -256
; -sin(2 pi p) / 16 and -cos(2 pi p) / 16, p >= 0 (R: scratch)


render_k:
setup:                          ; (run again after the part, for post)
    g.li g30, 1
    g.li g29, 4
    g.uniform g23, 11 ; pooled 1.0
    g.uniform g24, 10 ; pooled 0.5
    g.id g25, 0
    g.itof g25, g25
    g.id g26, 1
    g.uniform g27, 9
    g.add g26, g26, g27
    g.itof g26, g26
    g.uniform g27, 0
    g.itof g27, g27
    g.fli g28, 0.016666668  ; exact
    g.fmul g27, g27, g28
    g.uniform g28, 1
    g.itof g28, g28
    g.bnz g21, post
    g.fli g20, 80.0  ; exact
    g.fsub g20, g25, g20          ; XC
    g.fli g21, 60.0  ; exact
    g.fsub g21, g21, g26          ; YC (up)
    g.uniform g13, 2
    g.bz g13, p_copper
    g.sub g13, g13, g30
    g.bz g13, p_rt
    g.sub g13, g13, g30
    g.bz g13, p_plasma
    g.sub g13, g13, g30
    g.bz g13, p_tunnel
    g.sub g13, g13, g30
    g.bz g13, p_sdf
repost:
    g.li g21, 1
    g.jmp setup

; ---- include p_copper.s ----
; ---------------------------------------------------------------------
; Type 0: crack intro. Horizontal parallax stars, a snake of copper bars
; (red, green, blue shades rotating), logo and sine scroller (text items).
; ---------------------------------------------------------------------
p_copper:
    ; stars: one per row, speed and brightness from a row hash
    g.ftoi g16, g26
    g.li g10, 0x9E3779B1
    g.mul g16, g16, g10
    g.itof g12, g16
    g.fli g10, 4.656613e-10       ; 2^-31 (exact)
    g.fmul g12, g12, g10              ; -1 .. 1
    g.fmul g8, g12, g12
    g.fmul g8, g8, g27
    g.fadd g8, g8, g12
    g.fadd g8, g8, g23
    g.ftoi g11, g8
    g.itof g11, g11
    g.fsub g8, g8, g11
    g.fli g10, 160.0
    g.fmul g8, g8, g10
    g.fsub g8, g8, g25
    g.fmul g8, g8, g8
    g.flt g8, g8, g23
    g.bz g8, nostar
    g.fmul g12, g12, g12
    g.mov g1, g12
    g.mov g2, g12
    g.mov g3, g12
nostar:
    ; copper bars
    g.uniform g13, 11 ; pooled 1.0
    g.uniform g14, 8 ; pooled 0.3125
    g.fli g15, 0.078125
    g.li g7, 7
bar:
    g.itof g8, g7
    g.uniform g10, 13 ; pooled 0.046875
    g.fmul g8, g8, g10
    g.fli g10, 0.34375
    g.fmul g10, g27, g10
    g.fadd g8, g8, g10
    ; <sinp P, P>
    g.ftoi g11, g8
    g.itof g11, g11
    g.fsub g8, g8, g11
    g.fsub g8, g8, g24
    g.fsub g11, g0, g8
    g.fmax g11, g11, g8
    g.fsub g11, g24, g11
    g.fmul g8, g8, g11
    g.fli g10, 640.0
    g.fmul g8, g8, g10
    g.fadd g9, g21, g8            ; YC + offset
    g.fli g10, 0.203125
    g.fmul g9, g9, g10
    g.fmul g9, g9, g9
    g.fsub g9, g23, g9
    g.flt g10, g9, g0
    g.bnz g10, nobar
    g.vscale g1, g13, g9
    g.fmul g9, g9, g9
    g.fmul g9, g9, g9
    g.fmul g9, g9, g9
    g.fadd g1, g1, g9
    g.fadd g2, g2, g9
    g.fadd g3, g3, g9
nobar:
    g.mov g10, g15
    g.mov g15, g14
    g.mov g14, g13
    g.mov g13, g10
    g.sub g7, g7, g30
    g.bnz g7, bar
    g.jmp repost

; ---- include p_rt.s ----
; ---------------------------------------------------------------------
; Type 1: ray tracer over the prepass sphere table. U5 = sphere count N
; (1: Boing ball in front of a gridded wall, 64: chrome vector balls over
; a checkerboard). U6 = [.bf eye y, eye z], U7 = [.bf lens shift, focal].
; Diffuse hits continue toward the sun: the sphere loop doubles as the
; shadow test and the sky's sun term supplies the direct light.
; ---------------------------------------------------------------------
p_rt:
    g.mov g7, g20                ; XC
    g.mov g8, g21              ; YC
    g.li g21, 0xffff0000
    g.uniform g20, 6
    g.and g14, g20, g21
    g.li g24, 16
    g.shl g15, g20, g24
    g.uniform g20, 7
    g.and g4, g20, g21              ; lens shift
    g.fadd g8, g8, g4
    g.shl g9, g20, g24             ; focal
    g.norm3 g7, g7
    g.fli g26, -0.4375
    g.fli g27, 0.5625
    g.fli g28, -0.6875
    g.mov g10, g23
    g.mov g11, g23
    g.mov g12, g23
    g.li g25, 4
bounce:
    g.fli g31, 1024.0
    g.mov g22, g0
    ; floor y = 0
    g.flt g20, g8, g0
    g.bz g20, nofloor
    g.fdiv g20, g14, g8
    g.fsub g31, g0, g20
    g.mov g22, g30
nofloor:
    ; wall z = 3.5 (Boing)
    g.uniform g24, 5
    g.sub g20, g24, g30
    g.bnz g20, nowall
    g.flt g20, g0, g9
    g.bz g20, nowall
    g.fli g20, 3.5
    g.fsub g20, g20, g15
    g.fdiv g20, g20, g9
    g.flt g21, g20, g31
    g.bz g21, nowall
    g.mov g31, g20
    g.li g22, 2
nowall:
    g.shl g24, g24, g29
sph:
    g.sub g24, g24, g29
    g.ld g19, g24, 2
    g.sub g24, g24, g29
    g.ld g18, g24, 2
    g.sub g24, g24, g29
    g.ld g17, g24, 2
    g.sub g24, g24, g29
    g.ld g16, g24, 2
    g.sphere g20, g13, g7, g16
    g.flt g21, g20, g31
    g.bz g21, smiss
    g.flt g21, g0, g20
    g.bz g21, smiss
    g.mov g31, g20
    g.vscale g4, g16, g23
    g.li g22, 3
smiss:
    g.bnz g24, sph
    g.bz g22, sky
    g.vscale g16, g7, g31
    g.vadd g13, g13, g16             ; hit point
    g.li g20, 3
    g.sub g20, g22, g20
    g.bnz g20, plane
    g.vsub g4, g13, g4
    g.norm3 g4, g4
    g.uniform g20, 5
    g.sub g20, g20, g30
    g.bz g20, boing
    ; chrome
    g.fli g20, 0.75
    g.vscale g10, g10, g20
    g.reflect3 g7, g7, g4
    g.jmp next
boing:
    ; checker: sign of Im(z^8) for z = (spun longitude, latitude), axis
    ; tilted 17 degrees
    g.uniform g20, 11 ; pooled 1.0
    g.fli g21, 0.28125
    g.fmul g16, g4, g20
    g.fmul g31, g5, g21
    g.fadd g16, g16, g31           ; x'
    g.fmul g17, g5, g20
    g.fmul g31, g4, g21
    g.fsub g17, g17, g31       ; y'
    g.li g24, 16
    g.ld g20, g24, 2                ; spin sin
    g.add g24, g24, g29
    g.ld g21, g24, 2                ; spin cos
    g.fmul g31, g16, g21
    g.fmul g22, g6, g20
    g.fsub g18, g31, g22        ; u = c x' - s z
    g.fmul g31, g16, g20
    g.fmul g22, g6, g21
    g.fadd g19, g31, g22        ; v = s x' + c z
    g.fmul g20, g17, g17
    g.fsub g20, g23, g20
    g.fmax g20, g20, g0
    g.sqrt g16, g20                ; r = sqrt(1 - y'^2)
    g.mov g21, g23
    g.li g22, 2
baxis:
    g.li g24, 3
bsq:
    g.fmul g20, g18, g19
    g.fmul g18, g18, g18
    g.fmul g31, g19, g19
    g.fsub g18, g18, g31
    g.fadd g19, g20, g20
    g.sub g24, g24, g30
    g.bnz g24, bsq
    g.fmul g21, g21, g19
    g.mov g18, g16
    g.mov g19, g17
    g.sub g22, g22, g30
    g.bnz g22, baxis
    g.uniform g16, 10 ; pooled 0.5
    g.fli g17, 0.4375
    g.fli g18, 0.4375
    g.flt g21, g21, g0
    g.bz g21, diffuse
    g.fli g17, 0.009765625
    g.fli g18, 0.009765625
    g.jmp diffuse
plane:
    ; floor (0, 1, 0), pattern on (x, z); wall (0, 0, -1), pattern on (x, y)
    g.mov g4, g0
    g.mov g5, g23
    g.mov g6, g0
    g.mov g21, g15
    g.sub g20, g22, g30
    g.bz g20, isfloor
    g.mov g5, g0
    g.fsub g6, g0, g23
    g.mov g21, g14
isfloor:
    ; cells of half a unit: u = 2x + 512, v = 2(z or y) + 512
    g.fli g16, 512.0
    g.fadd g17, g13, g13
    g.fadd g17, g17, g16
    g.fadd g18, g21, g21
    g.fadd g18, g18, g16
    g.ftoi g20, g17
    g.ftoi g21, g18
    g.uniform g22, 5
    g.sub g22, g22, g30
    g.bz g22, grid
    ; checkerboard, contrast fading with distance
    g.xor g20, g20, g21
    g.and g20, g20, g30
    g.itof g20, g20
    g.uniform g16, 10 ; pooled 0.5
    g.fsub g20, g20, g16
    g.fli g21, 4.0
    g.fdiv g21, g21, g31
    g.fmin g21, g21, g23
    g.fmul g20, g20, g21
    g.uniform g21, 10 ; pooled 0.5
    g.fmul g20, g20, g21
    g.fli g21, 0.25
    g.fadd g20, g20, g21
    g.mov g16, g20
    g.mov g17, g20
    g.mov g18, g20
    g.jmp diffuse
grid:                           ; purple lines on grey
    g.itof g20, g20
    g.fsub g17, g17, g20
    g.itof g21, g21
    g.fsub g18, g18, g21
    g.fmin g20, g17, g18
    g.fli g21, 0.0107421875              ; lines widen with distance (no sparkle)
    g.fmul g21, g21, g31
    g.fli g16, 0.1015625
    g.fmax g21, g21, g16
    g.uniform g16, 8 ; pooled 0.3125
    g.uniform g17, 8 ; pooled 0.3125
    g.uniform g18, 8 ; pooled 0.3125
    g.flt g20, g20, g21
    g.bz g20, diffuse
    g.uniform g16, 15 ; pooled 0.21875
    g.fli g17, 0.025390625
    g.uniform g18, 15 ; pooled 0.21875
diffuse:
    g.fmul g10, g10, g16
    g.fmul g11, g11, g17
    g.fmul g12, g12, g18
    g.uniform g20, 8 ; pooled 0.3125
    g.vscale g16, g10, g20
    g.vadd g1, g1, g16         ; ambient
    g.dot3 g20, g4, g26
    g.fmax g20, g20, g0
    g.vscale g10, g10, g20
    g.vscale g7, g26, g23         ; continue toward the sun
next:
    g.fli g20, 0.001953125
    g.vscale g16, g4, g20
    g.vadd g13, g13, g16
    g.sub g25, g25, g30
    g.bnz g25, bounce
    g.jmp repost
sky:                            ; blue, darker overhead, sun glow
    g.fmax g20, g8, g0
    g.fli g21, -0.625
    g.fmul g20, g20, g21
    g.fadd g20, g20, g23
    g.uniform g16, 8 ; pooled 0.3125
    g.fli g17, 0.40625
    g.fli g18, 0.6875
    g.vscale g16, g16, g20
    g.dot3 g20, g7, g26
    g.fmax g20, g20, g0
    g.fmul g20, g20, g20
    g.fmul g20, g20, g20
    g.fmul g20, g20, g20
    g.fmul g20, g20, g20
    g.fmul g20, g20, g20
    g.fli g21, 1.5
    g.fmul g20, g20, g21
    g.fadd g16, g16, g20
    g.fadd g17, g17, g20
    g.fadd g18, g18, g20
    g.fmul g16, g16, g10
    g.fmul g17, g17, g11
    g.fmul g18, g18, g12
    g.vadd g1, g1, g16
    g.jmp repost

; ---- include p_plasma.s ----
; ---------------------------------------------------------------------
; Type 2: plasma, three waves at 0, 140 and 280 degrees over screen
; coordinates that swing through +-30 degrees; U5 = frequency.
; ---------------------------------------------------------------------
p_plasma:
    g.fli g16, 0.05078125
    g.fmul g9, g27, g16
    ; <sinp Q.y, P>
    g.ftoi g17, g9
    g.itof g17, g17
    g.fsub g11, g9, g17
    g.fsub g11, g11, g24
    g.fsub g17, g0, g11
    g.fmax g17, g17, g11
    g.fsub g17, g24, g17
    g.fmul g11, g11, g17
    g.fli g16, 8.0
    g.fmul g11, g11, g16
    g.mov g10, g23
    g.norm3 g10, g10
    g.fmul g7, g20, g10            ; XC
    g.fmul g16, g21, g11          ; YC
    g.fsub g7, g7, g16
    g.fmul g8, g20, g11
    g.fmul g16, g21, g10
    g.fadd g8, g8, g16
    g.uniform g18, 5
    g.mov g19, g0
    g.li g15, 3
pw:
    g.fmul g9, g7, g18
    g.fmul g16, g8, g19
    g.fadd g9, g9, g16
    g.uniform g16, 14 ; pooled 0.15625
    g.fmul g16, g27, g16
    g.fadd g9, g9, g16
    ; <sinb A, P>
    g.fli g17, 256.0
    g.fadd g16, g9, g17
    ; <sinp A, A>
    g.ftoi g17, g16
    g.itof g17, g17
    g.fsub g16, g16, g17
    g.fsub g16, g16, g24
    g.fsub g17, g0, g16
    g.fmax g17, g17, g16
    g.fsub g17, g24, g17
    g.fmul g16, g16, g17
    g.fadd g13, g13, g16
    g.fli g16, -0.75
    g.fmul g9, g18, g16
    g.fli g16, 0.625
    g.fmul g17, g19, g16
    g.fsub g9, g9, g17
    g.fmul g17, g18, g16
    g.fli g16, -0.75
    g.fmul g19, g19, g16
    g.fadd g19, g19, g17
    g.mov g18, g9
    g.sub g15, g15, g30
    g.bnz g15, pw
    g.fli g16, 4.0
    g.fmul g13, g13, g16
    g.fli g16, 0.0703125
    g.fmul g14, g27, g16
    g.fadd g13, g13, g14
    g.fli g16, 2.0
    g.fadd g13, g13, g16
    g.fli g14, 0.5625
    g.jmp palette

; ---- include p_tunnel.s ----
; ---------------------------------------------------------------------
; Type 3: classic tunnel. Centre on a Lissajous path; depth 48 / r
; scrolls toward the viewer; 16 sectors from an atan2 approximation,
; twisted with depth into a spiral checkerboard; hue by depth, black fog.
; U5 = speed.
; ---------------------------------------------------------------------
p_tunnel:
    g.uniform g8, 15 ; pooled 0.21875
    g.fmul g16, g27, g8
    ; <sinp U, P>
    g.ftoi g12, g16
    g.itof g12, g12
    g.fsub g15, g16, g12
    g.fsub g15, g15, g24
    g.fsub g12, g0, g15
    g.fmax g12, g12, g15
    g.fsub g12, g24, g12
    g.fmul g15, g15, g12
    g.fli g8, 352.0
    g.fmul g15, g15, g8
    g.fsub g15, g20, g15            ; XC
    g.uniform g8, 14 ; pooled 0.15625
    g.fmul g16, g27, g8
    ; <sinp V, P>
    g.ftoi g12, g16
    g.itof g12, g12
    g.fsub g7, g16, g12
    g.fsub g7, g7, g24
    g.fsub g12, g0, g7
    g.fmax g12, g12, g7
    g.fsub g12, g24, g12
    g.fmul g7, g7, g12
    g.fli g8, 256.0
    g.fmul g7, g7, g8
    g.fsub g7, g21, g7            ; YC
    g.fmul g8, g15, g15
    g.fmul g9, g7, g7
    g.fadd g8, g8, g9
    g.sqrt g8, g8
    g.fadd g14, g8, g23          ; r + 1
    g.fli g8, 48.0
    g.fdiv g10, g8, g14
    g.uniform g8, 5              ; speed
    g.fmul g8, g27, g8
    g.fadd g10, g10, g8              ; depth
    ; angle in turns
    g.fsub g8, g0, g15
    g.fmax g8, g8, g15
    g.fsub g9, g0, g7
    g.fmax g9, g9, g7
    g.fmin g11, g8, g9
    g.fmax g16, g8, g9
    g.fli g12, 0.0009765625
    g.fmax g16, g16, g12
    g.fdiv g11, g11, g16
    g.fsub g16, g23, g11
    g.fli g12, 0.04296875
    g.fmul g16, g16, g12
    g.fli g12, 0.125
    g.fadd g16, g16, g12
    g.fmul g11, g11, g16              ; atan(min / max) / 2 pi
    g.flt g8, g8, g9
    g.bz g8, tn_oct
    g.fli g12, 0.25
    g.fsub g11, g12, g11
tn_oct:
    g.flt g8, g15, g0
    g.bz g8, tn_half
    g.fsub g11, g24, g11
tn_half:
    g.flt g8, g7, g0
    g.bz g8, tn_sign
    g.fsub g11, g0, g11
tn_sign:
    ; spiral checker: sectors twisted by depth
    g.fli g8, 16.0
    g.fmul g11, g11, g8
    g.uniform g8, 10 ; pooled 0.5
    g.fmul g8, g10, g8
    g.fadd g11, g11, g8
    g.fli g8, 64.0
    g.fadd g11, g11, g8
    g.ftoi g11, g11
    g.fadd g8, g10, g10
    g.ftoi g8, g8
    g.xor g11, g11, g8
    g.and g11, g11, g30
    g.itof g11, g11
    g.fli g8, 0.625
    g.fmul g11, g11, g8
    g.fli g8, 0.40625
    g.fadd g11, g11, g8
    ; fog: dark in the distance
    g.fli g8, 0.015625
    g.fmul g14, g14, g8
    g.fmin g14, g14, g23
    g.fmul g14, g14, g14
    g.fmul g14, g14, g11
    g.uniform g8, 13 ; pooled 0.046875
    g.fmul g13, g10, g8
    g.jmp palette

; ---- include p_sdf.s ----
; ---------------------------------------------------------------------
; Type 4: flight down a corridor of an infinite Menger sponge (cells of
; size 1/2, three folds; a fourth pass gives the box distance), rolling
; through the part. Sphere tracing; no normals: one extra distance sample
; toward a fixed light gives N.L, the steps left the occlusion, and the
; march accumulates an edge glow. Fog runs into a bright haze of another
; hue. U5 = speed, U6 = roll rate (per frame), U7 = glow.
; ---------------------------------------------------------------------
p_sdf:
    ; eye on the corridor axis; roll (c, s) = norm(1, rate * (frame - 225)),
    ; a sweep through the part
    g.uniform g19, 5
    g.fmul g31, g27, g19
    g.fli g4, 224.0
    g.fsub g4, g28, g4
    g.uniform g19, 6
    g.fmul g11, g4, g19
    g.mov g10, g23
    g.mov g12, g0
    g.norm3 g10, g10
    g.mov g4, g20                ; XC
    g.mov g19, g21                ; YC
    g.fmul g7, g4, g10
    g.fmul g5, g19, g11
    g.fsub g7, g7, g5
    g.fmul g8, g19, g10
    g.fmul g5, g4, g11
    g.fadd g8, g8, g5
    g.fli g9, 88.0
    g.norm3 g7, g7
    g.fli g20, 3.0
    g.fli g15, 0.05078125
    g.li g17, 48
sd_march:
    g.vscale g10, g7, g15
    g.fadd g12, g12, g31
sd_sample:
    ; repeat with period 1: p = fract(p / 2 + 32.5) - 1 / 2 (sponge of size 1/2)
    g.li g5, 3
sd_rep:
    g.fli g19, 32.5  ; exact
    g.fmul g4, g10, g24
    g.fadd g4, g4, g19
    g.ftoi g19, g4
    g.itof g19, g19
    g.fsub g4, g4, g19
    g.fsub g4, g4, g24
    g.mov g10, g11
    g.mov g11, g12
    g.mov g12, g4
    g.sub g5, g5, g30
    g.bnz g5, sd_rep
    ; Menger folds; the fourth pass ends with the box distance
    g.mov g18, g23
    g.li g5, 4
sd_fold:
    g.fsub g19, g0, g10
    g.fmax g10, g10, g19
    g.fsub g19, g0, g11
    g.fmax g11, g11, g19
    g.fsub g19, g0, g12
    g.fmax g12, g12, g19
    g.fmax g19, g10, g11
    g.fmin g11, g10, g11
    g.fmax g10, g19, g12
    g.fmin g12, g19, g12
    g.fmax g19, g11, g12
    g.fmin g12, g11, g12
    g.mov g11, g19
    g.sub g5, g5, g30
    g.bz g5, sd_dist
    g.vscale g10, g10, g20
    g.fsub g10, g10, g23
    g.fsub g11, g11, g23
    g.fsub g19, g23, g12
    g.fmin g12, g12, g19
    g.fmul g18, g18, g20
    g.jmp sd_fold
sd_dist:
    g.fsub g19, g10, g24
    g.fdiv g16, g19, g18
    g.bnz g22, sd_lit
    ; glow: + 1 / (1 + 400 d^2) per step
    g.fmul g19, g16, g16
    g.fli g4, 2048.0
    g.fmul g19, g19, g4
    g.fadd g19, g19, g23
    g.fdiv g19, g23, g19
    g.fadd g6, g6, g19
    g.fadd g15, g15, g16
    g.fli g19, 0.001953125
    g.flt g19, g16, g19
    g.bnz g19, sd_hit
    g.sub g17, g17, g30
    g.bnz g17, sd_march
sd_hit:
    ; one more sample toward a light up and to the side: d / 0.05 ~ N.L
    g.mov g22, g30
    g.vscale g10, g7, g15
    g.uniform g19, 12 ; pooled 0.03125
    g.fadd g10, g10, g19
    g.fadd g11, g11, g19
    g.fli g19, -0.025390625
    g.fadd g12, g12, g19
    g.fadd g12, g12, g31
    g.jmp sd_sample
sd_lit:
    g.fli g19, 20.0
    g.fmul g14, g16, g19
    g.fmax g14, g14, g0
    g.fmin g14, g14, g23
    g.uniform g19, 14 ; pooled 0.15625
    g.fadd g14, g14, g19
    g.itof g19, g17
    g.uniform g4, 13 ; pooled 0.046875
    g.fmul g19, g19, g4
    g.fmul g14, g14, g19            ; occlusion from the steps left
    g.fmul g14, g14, g14
    ; fog f = 1 / (1 + t^2 / 3) into a bright haze of another hue
    g.fmul g19, g15, g15
    g.uniform g4, 8 ; pooled 0.3125
    g.fmul g19, g19, g4
    g.fadd g19, g19, g23
    g.fdiv g19, g23, g19
    g.fsub g4, g23, g19           ; 1 - f
    g.fmul g14, g14, g19
    g.fli g19, 0.6875
    g.fmul g19, g4, g19
    g.fadd g14, g14, g19
    g.uniform g19, 7
    g.fmul g19, g6, g19
    g.fadd g14, g14, g19            ; glow
    g.uniform g19, 8 ; pooled 0.3125
    g.fmul g13, g4, g19
    g.uniform g19, 12 ; pooled 0.03125
    g.fmul g19, g31, g19
    g.fadd g13, g13, g19
    g.jmp palette


; ---------------------------------------------------------------------
; palette: COL = BR * ((1 + sin(2 pi (H + k * spread))) / 2)^2, k = 0, 1, 2 (H >= 0);
; spread = low half of uniform 5
; ---------------------------------------------------------------------
palette:
    g.uniform g18, 4
    g.li g19, 16
    g.shl g18, g18, g19
    g.li g19, 3
pal:
    ; <sinp S, H>
    g.ftoi g31, g13
    g.itof g31, g31
    g.fsub g5, g13, g31
    g.fsub g5, g5, g24
    g.fsub g31, g0, g5
    g.fmax g31, g31, g5
    g.fsub g31, g24, g31
    g.fmul g5, g5, g31
    g.fli g6, -8.0
    g.fmul g5, g5, g6
    g.fadd g5, g5, g24
    g.fmul g5, g5, g5
    g.fmul g5, g5, g14
    g.mov g1, g2
    g.mov g2, g3
    g.mov g3, g5
    g.fadd g13, g13, g18
    g.sub g19, g19, g30
    g.bnz g19, pal
    g.jmp repost

; ---------------------------------------------------------------------
; post: two text items (drop shadow, then gold letters), flash, gamma
; ---------------------------------------------------------------------
post:
    g.uniform g13, 3
    g.li g11, 0xffff0000
    g.li g12, 16
tslot:
    g.li g9, 255
    g.and g14, g13, g9
    g.bz g14, tnext
    g.shl g14, g14, g29
    g.sub g14, g14, g12           ; item records start the data
    g.li g16, 2                ; 2: shadow one pixel down-right, 1: letters
tpass:
    g.ld g8, g14, 1               ; [x0 | y0] of the leading space's blank row
    g.and g15, g8, g11
    g.fsub g15, g25, g15
    g.shl g7, g8, g12
    g.fsub g7, g26, g7
    g.sub g9, g16, g30
    g.itof g9, g9
    g.fsub g15, g15, g9
    g.fsub g7, g7, g9
    g.add g9, g14, g29
    g.ld g8, g9, 1                ; [1 / scale | scroll]
    g.and g10, g8, g11
    g.fmul g15, g15, g10
    g.fmul g7, g7, g10
    g.shl g8, g8, g12
    g.fmul g8, g8, g28
    g.fadd g15, g15, g8
    g.add g9, g9, g29
    g.ld g8, g9, 1                ; [16 * wobble | 6 * length (int)]
    g.fli g10, 0.0126953125
    g.fmul g18, g25, g10
    ; <sinp S, S>
    g.ftoi g19, g18
    g.itof g19, g19
    g.fsub g18, g18, g19
    g.fsub g18, g18, g24
    g.fsub g19, g0, g18
    g.fmax g19, g19, g18
    g.fsub g19, g24, g19
    g.fmul g18, g18, g19
    g.and g10, g8, g11
    g.fmul g18, g18, g10
    g.fadd g7, g7, g18
    g.sub g8, g8, g10
    ; row 0 of every glyph and the leading space are blank, so a truncated
    ; coordinate just outside the text draws nothing
    g.ftoi g18, g7
    g.li g10, 6
    g.sltu g19, g18, g10
    g.bz g19, tmiss
    g.fli g19, 0.16666667  ; exact
    g.fmul g19, g15, g19
    g.ftoi g17, g19                ; character
    g.ftoi g15, g15
    g.sltu g19, g15, g8
    g.bz g19, tmiss
    g.mul g19, g17, g10
    g.sub g15, g15, g19               ; column 0..5
    g.li g10, 5
    g.slt g19, g15, g10
    g.bz g19, tmiss
    g.mul g18, g18, g10
    g.add g18, g18, g15               ; glyph bit
    g.add g9, g9, g29
    g.ld g8, g9, 1                ; string offset
    g.add g8, g8, g17
    g.ldb g8, g8, 1               ; glyph word offset
    g.mul g8, g8, g29
    g.ld g8, g8, 1
    g.shr g8, g8, g18
    g.and g8, g8, g30
    g.bz g8, tmiss
    g.sub g9, g16, g30
    g.bz g9, tfill
    g.fli g10, 0.203125
    g.vscale g1, g1, g10
    g.jmp tmiss
tfill:                          ; white-gold, darker towards the baseline
    g.fli g10, 0.078125
    g.fmul g10, g7, g10
    g.mov g1, g23
    g.fsub g2, g23, g10
    g.fadd g10, g10, g10
    g.fsub g3, g23, g10
tmiss:
    g.sub g16, g16, g30
    g.bnz g16, tpass
tnext:
    g.li g9, 8
    g.shr g13, g13, g9
    g.bnz g13, tslot
    ; flash at the start of a part: + max(0, flash - frames / 12)
    g.uniform g10, 4
    g.and g10, g10, g11
    g.fli g9, 0.0859375
    g.fmul g9, g28, g9
    g.fsub g9, g10, g9
    g.fmax g9, g9, g0
    g.fadd g1, g1, g9
    g.fadd g2, g2, g9
    g.fadd g3, g3, g9
    ; gamma, store
    g.sqrt g1, g1
    g.sqrt g2, g2
    g.sqrt g3, g3
    g.ftoi g9, g25
    g.ftoi g10, g26
    g.li g15, 160
    g.mul g10, g10, g15
    g.add g9, g9, g10
    g.rgb g1, g9, 0
    g.end
render_k_end:

; ---- include pre.s ----
; ---------------------------------------------------------------------
; Prepass: one invocation per sphere (grid 64), writes the sphere table
; (binding 2): [x, y, z, r] per record. Uniform 6 = sphere count N:
;   N = 1   Boing ball: hops on every beat, sweeps left and right;
;           record 1 holds its q_spin as a turned unit vector
;   N = 64  vector balls: a 4x4x4 lattice breathing into a sphere and
;           back, turning about two axes, kicked out on the beat
; ---------------------------------------------------------------------
pre_k:
    g.li g9, 1
    g.li g2, 4
    g.uniform g24, 11 ; pooled 1.0
    g.uniform g18, 10 ; pooled 0.5
    g.id g23, 2
    g.uniform g31, 5
    g.slt g16, g23, g31
    g.bz g16, q_pend
    g.shl g21, g23, g2
    g.uniform g8, 0
    g.itof g8, g8
    g.fli g16, 0.035555556        ; beats per frame (exact)
    g.fmul g8, g8, g16
    g.ftoi g13, g8
    g.itof g13, g13
    g.fsub g13, g8, g13
    g.sub g12, g31, g9
    g.bz g12, q_boing
    ; ---- balls: lattice point L -> sphere, morph m = (1 - cos(t / 8)) / 2
    g.li g12, 3
    g.li g20, 2
q_lat:
    g.li g16, 3
    g.and g16, g23, g16
    g.itof g16, g16
    g.fli g10, 1.5
    g.fsub g16, g16, g10
    g.mov g4, g5
    g.mov g5, g6
    g.mov g6, g16
    g.shr g23, g23, g20
    g.sub g12, g12, g9
    g.bnz g12, q_lat
    g.fli g16, 0.75
    g.vscale g4, g4, g16
    g.norm3 g10, g4                ; C..C+2 = L / |L|  (C, S, J)
    g.fli g16, 2.5
    g.vscale g10, g10, g16
    g.vsub g10, g10, g4
    g.uniform g16, 12 ; pooled 0.03125
    g.fmul g16, g8, g16
    ; <sinp B, A>
    g.ftoi g19, g16
    g.itof g19, g19
    g.fsub g20, g16, g19
    g.fsub g20, g20, g18
    g.fsub g19, g0, g20
    g.fmax g19, g19, g20
    g.fsub g19, g18, g19
    g.fmul g20, g20, g19
    g.fli g16, -8.0
    g.fmul g20, g20, g16
    g.fadd g20, g20, g18
    g.vscale g10, g10, g20
    g.vadd g4, g4, g10
    ; kick: out by 12% on the beat
    g.fsub g16, g24, g13
    g.fmul g16, g16, g16
    g.fmul g16, g16, g16
    g.fli g20, 0.125
    g.fmul g16, g16, g20
    g.fadd g16, g16, g24
    g.vscale g4, g4, g16
    g.fli g17, 0.04296875
    g.fmul g17, g8, g17
    g.fli g15, 0.02734375
    g.fmul g15, g8, g15
    g.fli g22, 0.34375
    g.fli g3, 3.0
    g.mov g12, g0
    g.jmp q_rotate
q_boing:
    ; ---- Boing: parabolic hop landing on each beat, 8-beat sweep ----
    g.fsub g16, g24, g13
    g.fmul g16, g16, g13
    g.fli g20, 8.0
    g.fmul g16, g16, g20
    g.fadd g5, g16, g24
    g.fli g16, 0.0625
    g.fmul g16, g8, g16
    ; <sinp B, A>
    g.ftoi g19, g16
    g.itof g19, g19
    g.fsub g20, g16, g19
    g.fsub g20, g20, g18
    g.fsub g19, g0, g20
    g.fmax g19, g19, g20
    g.fsub g19, g18, g19
    g.fmul g20, g20, g19
    g.fli g16, 44.0
    g.fmul g4, g20, g16              ; x: sweep +-2.75 over 16 beats
    g.mov g22, g24
    g.li g12, 1
    g.jmp q_store
q_spin:                           ; record 1: (1, 0, 0) turned by the q_spin
    g.mov g12, g0
    g.li g16, 16
    g.add g21, g21, g16
    g.mov g4, g24
    g.mov g5, g0
    g.mov g6, g0
    g.fli g17, 0.0625
    g.fmul g17, g8, g17
    g.mov g15, g0
    g.mov g3, g0
q_rotate:                         ; turn (x, z) by AN, cycle to (y, z, x); twice
    g.li g23, 2
q_rot:
    ; <sincos S, C, AN>
    g.ftoi g19, g17
    g.itof g19, g19
    g.fsub g11, g17, g19
    g.fsub g11, g11, g18
    g.fli g19, 0.25
    g.fadd g10, g11, g19
    g.fle g19, g18, g10
    g.itof g19, g19
    g.fsub g10, g10, g19
    g.fsub g19, g0, g11
    g.fmax g19, g19, g11
    g.fsub g19, g18, g19
    g.fmul g11, g11, g19
    g.fsub g19, g0, g10
    g.fmax g19, g19, g10
    g.fsub g19, g18, g19
    g.fmul g10, g10, g19
    g.fli g16, -16.0
    g.fmul g10, g10, g16
    g.fmul g11, g11, g16
    g.fmul g16, g4, g10
    g.fmul g20, g6, g11
    g.fsub g16, g16, g20
    g.fmul g20, g4, g11
    g.fmul g6, g6, g10
    g.fadd g6, g6, g20
    g.mov g4, g5
    g.mov g5, g6
    g.mov g6, g16
    g.mov g17, g15
    g.sub g23, g23, g9
    g.bnz g23, q_rot
    g.fadd g5, g5, g3
q_store:
    g.st g4, g21, 2
    g.add g16, g21, g2
    g.st g5, g16, 2
    g.add g16, g16, g2
    g.st g6, g16, 2
    g.add g16, g16, g2
    g.st g22, g16, 2
    g.bnz g12, q_spin
q_pend:
    g.end
pre_k_end:

; ---- include spu.s ----
; ---------------------------------------------------------------------
; SPU kernel: one invocation per stereo sample frame (grid 64x4)
;   for tap in taps: for voice in voices: for j < poly: FM/noise voice
; Sines are computed as -sin scaled to +-2^29 (F*(|F|*2^-31 - 1), F = phase);
; noise is +-2^31, voice gains are pre-scaled by 2^-29.
; ---------------------------------------------------------------------
.equ U_7,  1
.equ U_23, 2
.equ U_3,  3
.equ SONG, 2880000

spu_k:
    g.id g4, 2
    g.uniform g1, 14
    g.add g4, g4, g1
    g.uniform g1, 0
    g.sub g4, g4, g1               ; sample in the loop (the CPU moves the loop
    g.li g1, SONG                ; start once per drawn frame: wrap both ways)
    g.slt g16, g4, g0
    g.bz g16, t_pos
    g.add g4, g4, g1
t_pos:
    g.slt g16, g4, g1
    g.bnz g16, t_in
    g.sub g4, g4, g1
t_in:
    g.id g10, 5                  ; grid height = 4
    g.sltu g24, g0, g10
    g.mul g29, g10, g10
    g.li g30, 0xffff0000
    g.li g20, 5625
    g.fli g12, 1.0
    g.fli g13, 4.656613e-10      ; 2^-31 (exact)
    g.li g11, d_taps_end - d_taps
tap_loop:
    g.li g8, d_taps - 8 - d_song
    g.add g8, g8, g11
    g.ld g1, g8, 1                ; tap delay in samples
    g.sub g7, g4, g1
    g.slt g16, g7, g0             ; echoes of the loop's end at its start
    g.bz g16, tt_pos
    g.li g16, SONG
    g.add g7, g7, g16
tt_pos:
    ; musical position of TT: 16th step, bar, samples into step
    g.itof g1, g7
    g.itof g16, g20
    g.fdiv g1, g1, g16
    g.ftoi g16, g1
    g.mul g1, g16, g20
    g.sub g28, g7, g1
    g.shr g15, g16, g10
    g.shl g1, g15, g10
    g.sub g25, g16, g1             ; step in bar
    g.li g1, 31
    g.and g15, g15, g1           ; song loops every 32 bars
    g.ldb g18, g15, 1           ; bar flags live at data offset 0
    g.uniform g1, U_3
    g.and g21, g15, g1
    g.shl g21, g21, g10              ; (bar & 3) * 16
    g.li g6, d_voices - d_song
voice_loop:
    g.ldb g23, g6, 1             ; taps*8 | poly
    g.sltu g1, g23, g11
    g.bnz g1, next_voice
    g.add g8, g6, g24
    g.ldb g1, g8, 1
    g.and g1, g1, g18             ; voice enabled in this bar?
    g.bz g1, next_voice
    g.add g8, g8, g24
    g.ldb g9, g8, 1
    g.add g8, g8, g24
    g.ldb g3, g8, 1               ; trigger mask offset
    g.add g8, g8, g24
    g.ldb g17, g8, 1               ; note array offset
    g.and g1, g9, g29          ; four-bar pattern?
    g.bz g1, one_bar
    g.add g3, g3, g21
    g.add g17, g17, g21
one_bar:
    g.ld g19, g3, 1                ; trigger mask
    g.add g1, g25, g24
    g.shl g1, g24, g1
    g.sub g1, g1, g24
    g.and g16, g19, g1               ; triggers at or before POS
    g.bz g16, next_voice
    g.sub g19, g19, g16               ; triggers after POS
    g.shl g1, g24, g29
    g.or g19, g19, g1
    g.sub g1, g0, g19
    g.and g19, g19, g1               ; lowest later trigger
    g.itof g16, g16
    g.itof g19, g19
    g.uniform g1, U_23
    g.shr g16, g16, g1               ; 127 + j0 (float exponent of highest bit)
    g.shr g19, g19, g1               ; 127 + j1
    g.sub g19, g19, g16
    g.mul g22, g19, g20        ; note length in samples
    g.li g1, 127
    g.sub g16, g16, g1               ; j0
    g.sub g1, g25, g16
    g.mul g1, g1, g20
    g.add g27, g1, g28            ; samples since note on
    g.itof g26, g27
    g.add g17, g17, g16
    g.ldb g17, g17, 1               ; note byte
    g.and g1, g9, g24
    g.bnz g1, chord_rel
    g.bz g17, next_voice          ; absolute-note rest
chord_rel:
    g.uniform g1, U_7
    g.and g23, g23, g1             ; poly count
    g.mov g2, g0
poly_loop:
    ; ---- note number ----
    g.mov g1, g17
    g.and g16, g9, g24
    g.bz g16, abs_note
    g.add g1, g17, g2
    g.uniform g16, U_7
    g.and g1, g1, g16
    g.shr g16, g21, g24
    g.add g1, g1, g16
    g.li g16, d_chords - d_song
    g.add g1, g1, g16
    g.ldb g1, g1, 1
abs_note:
    g.add g16, g8, g24
    g.ldb g16, g16, 1               ; base note (+36 bias, folded into pitch constant)
    g.add g1, g1, g16
    g.li g16, d_trans - d_song
    g.add g16, g16, g15
    g.ldb g16, g16, 1               ; key of the bar
    g.add g1, g1, g16
    ; ---- phase increment = 2^((16n + j)/192 + c) ----
    g.shl g1, g1, g10
    g.add g1, g1, g2
    g.itof g1, g1
    g.fli g16, 0.0052083333       ; 1/192 (exact)
    g.fmul g1, g1, g16
    g.ftoi g19, g1
    g.itof g16, g19
    g.fsub g1, g1, g16
    g.fli g16, 0.07738064  ; exact
    g.fmul g16, g16, g1
    g.fli g3, 0.22694011  ; exact
    g.fadd g16, g16, g3
    g.fmul g16, g16, g1
    g.fli g3, 0.69543002  ; exact
    g.fadd g16, g16, g3
    g.fmul g16, g16, g1
    g.fadd g16, g16, g12
    g.uniform g1, U_23
    g.shl g19, g19, g1
    g.add g16, g16, g19
    g.ftoi g5, g16
    g.mul g5, g5, g27          ; carrier phase
    ; ---- modulator: sin(ratio * phase + 90deg) ----
    g.li g1, 5
    g.shr g1, g9, g1
    g.mul g16, g5, g1
    g.bnz g1, fm_ratio
    g.li g16, 0x40000000          ; ratio 0: constant modulator -> pitch sweep
fm_ratio:
    g.itof g16, g16
    g.fsub g19, g0, g16
    g.fmax g19, g19, g16
    g.fmul g19, g19, g13
    g.fsub g19, g19, g12
    g.fmul g16, g16, g19
    g.add g3, g8, g10
    g.ld g17, g3, 1                ; [index*2^-3 | index decay]
    g.shl g1, g17, g29
    g.fmul g1, g1, g26
    g.fadd g1, g1, g12
    g.fmul g1, g1, g1
    g.fmul g1, g1, g1              ; (1 + k t)^4
    g.and g19, g17, g30
    g.fmul g19, g19, g16
    g.fdiv g19, g19, g1
    g.ftoi g19, g19
    g.shl g19, g19, g10
    g.add g5, g5, g19
    ; ---- carrier ----
    g.itof g16, g5
    g.fsub g19, g0, g16
    g.fmax g19, g19, g16
    g.fmul g19, g19, g13
    g.fsub g19, g19, g12
    g.fmul g16, g16, g19
    ; ---- noise mix ----
    g.add g3, g3, g10
    g.add g3, g3, g10
    g.ld g17, g3, 1                ; [gain*2^-31 | noise]
    g.shl g19, g17, g29
    g.bz g19, no_noise
    g.li g1, 0x9E3779B1
    g.mul g1, g7, g1
    g.mul g1, g1, g1
    g.itof g1, g1
    g.fsub g1, g1, g16
    g.fmul g1, g1, g19
    g.fadd g16, g16, g1
no_noise:
    g.and g17, g17, g30
    g.fmul g16, g16, g17
    ; ---- envelope: min(1, attack ramp, release ramp) / (1 + k t)^4 ----
    g.sub g3, g3, g10
    g.ld g17, g3, 1                ; [amp decay | attack rate]
    g.shl g1, g17, g29
    g.fmul g1, g1, g26
    g.sub g19, g22, g27
    g.itof g19, g19
    g.fli g3, 0.00390625
    g.fmul g19, g19, g3
    g.fmin g1, g1, g19
    g.fmin g1, g1, g12
    g.fmul g16, g16, g1
    g.and g1, g17, g30
    g.fmul g1, g1, g26
    g.fadd g1, g1, g12
    g.fmul g1, g1, g1
    g.fmul g1, g1, g1
    g.fdiv g16, g16, g1
    ; ---- sidechain duck (voice mode bit 2 and kick flag bit 2) ----
    g.and g1, g9, g18
    g.and g1, g1, g10
    g.bz g1, no_duck
    g.uniform g1, U_3
    g.and g1, g25, g1
    g.mul g1, g1, g20
    g.add g1, g1, g28
    g.itof g1, g1
    g.fli g19, 0.0001220703125
    g.fmul g1, g1, g19
    g.fli g19, 0.25
    g.fadd g1, g1, g19
    g.fmin g1, g1, g12
    g.fmul g16, g16, g1
no_duck:
    ; ---- tap gain / pan, accumulate mid & side ----
    g.li g3, d_taps - 4 - d_song
    g.add g3, g3, g11
    g.ld g17, g3, 1                ; [gain | pan]
    g.and g1, g17, g30
    g.fmul g16, g16, g1
    g.fadd g31, g31, g16
    g.shl g17, g17, g29
    g.fmul g1, g17, g16
    g.fadd g14, g14, g1
    g.add g2, g2, g24
    g.sub g1, g2, g23
    g.bnz g1, poly_loop
next_voice:
    g.li g1, 20
    g.add g6, g6, g1
    g.li g1, d_voices_end - d_song
    g.sub g1, g6, g1
    g.bnz g1, voice_loop
next_tap:
    g.sub g11, g11, g10
    g.sub g11, g11, g10
    g.bnz g11, tap_loop
    ; ---- output ----
    g.fadd g1, g31, g14
    g.fsub g16, g31, g14
    ; soft limiter x / sqrt(1 + x^2)
    g.fmul g19, g1, g1
    g.fadd g19, g19, g12
    g.rsqrt g19, g19
    g.fmul g1, g1, g19
    g.fmul g19, g16, g16
    g.fadd g19, g19, g12
    g.rsqrt g19, g19
    g.fmul g16, g16, g19
    g.id g8, 2
    g.mul g8, g8, g10
    g.add g8, g8, g8
    g.st g1, g8, 0
    g.add g8, g8, g10
    g.st g16, g8, 0
    g.end
spu_k_end:

; ---- include song.s ----
; ---------------------------------------------------------------------
; Song (SPU binding 1 = d_song .. d_song_end)
; 128 BPM, 16th = 5625 samples, bar = 16 steps, 32 bars = 60 s, looping.
; Am | F | C | E; the last drop (bars 24-27) is a whole step up.
; voice: [taps*8|poly, bar flags mask, mode, mask offset, notes offset, base+234-36, 0, 0]
;        .bf index*2^-3, index decay/4/SR ; .bf amp decay/4/SR, attack/SR
;        .bf gain*2^-29, noise
; mode: 1 chord-relative, 4 duck, 16 four-bar pattern, ratio<<5
; bar flags: 1 bass, 2 snare+hats, 4 kick, 8 arp, 16 chip lead, 32 pad,
;   64 big lead, 128 crash (first bar of a four) / roll (last bar)
; ---------------------------------------------------------------------
.align 4
d_song:
d_flags:
    .byte 0x28,0x28,0x28,0xA8   ; copper intro: chip arp, pad; roll
    .byte 0xAF,0x2F,0x2F,0x2F   ; Boing: kick, bass, hats
    .byte 0xBF,0x3F,0x3F,0x3F   ; plasma: chip lead
    .byte 0xBF,0x3F,0x3F,0xBF   ; tunnel; roll
    .byte 0xEF,0x6F,0x6F,0x6F   ; balls: drop, big lead
    .byte 0x38,0x38,0x38,0xB8   ; fractal: breakdown; roll
    .byte 0xEF,0x6F,0x6F,0x6F   ; fractal: drop a whole step up
    .byte 0x2D,0x29,0x29,0x28   ; outro
d_trans:
    .byte 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0
    .byte 0,0,0,0, 0,0,0,0, 2,2,2,2, 0,0,0,0
; trigger masks, 16-byte rows: [lead bar k] [crash bar k] [roll bar k] [1-bar]
p_lead:  .word 0xC949
p_crash: .word 0x0001
p_roll:  .word 0
p_kick:  .word 0x1111
         .word 0x4949, 0, 0
p_snare: .word 0x1010
         .word 0xC949, 0, 0
p_hat:   .word 0xFFFF
         .word 0x1149, 0, 0xFF55
p_bass:  .word 0xEEEE
p_arp:   .word 0xFFFF
p_pad:   .word 0x0001
; lead notes: 4 bars x 16 steps (MIDI, 0 = rest)
n_lead:
    .byte 76,0,0,81, 0,0,79,0, 76,0,0,72, 0,0,74,76
    .byte 77,0,0,76, 0,0,72,0, 69,0,0,72, 0,0,69,0
    .byte 67,0,0,72, 0,0,76,0, 79,0,0,76, 0,0,72,74
    .byte 76,0,0,74, 0,0,71,0, 68,0,0,0, 71,0,0,0
; chord-relative notes: degree 0..7 (two octaves of 4 chord tones)
n_bass:  .byte 0,0,4,0, 0,0,4,0, 0,0,4,0, 0,0,4,0
n_arp:   .byte 0,1,2,3, 4,5,6,7, 6,5,4,3, 2,1,2,3
n_zero:  .byte 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0
; chords, 8 tones each: Am F C E
d_chords:
    .byte 57,60,64,69, 69,72,76,81
    .byte 53,57,60,65, 65,69,72,77
    .byte 48,52,55,60, 60,64,67,72
    .byte 52,56,59,64, 64,68,71,76
.align 4
d_voices:
v_kick:
    .byte 9, 0x04, 0x01, p_kick-d_song, n_zero-d_song, 36-24+198, 0, 0
    .word 0x40203920 ; bf 2.5, 0.000152587890625
    .word 0x38203c88 ; bf 0.00003814697265625, 0.0166015625
    .word 0x30b00000 ; bf 1.280568540096283e-9, 0
v_snare:
    .byte 25, 0x02, 0x01, p_snare-d_song, n_zero-d_song, 36-7+198, 0, 0
    .word 0x3f403920 ; bf 0.75, 0.000152587890625
    .word 0x38b03ca0 ; bf 0.00008392333984375, 0.01953125
    .word 0x30103ea0 ; bf 5.238689482212067e-10, 0.3125
v_hat:
    .byte 25, 0x02, 0x01, p_hat-d_song, n_zero-d_song, 36+198, 0, 0
    .word 0x00000000 ; bf 0, 0
    .word 0x3a003d30 ; bf 0.00048828125, 0.04296875
    .word 0x2ea03f80 ; bf 7.275957614183426e-11, 1
v_crash:
    .byte 9, 0x80, 0x11, p_crash-d_song, n_zero-d_song, 36+198, 0, 0
    .word 0x00000000 ; bf 0, 0
    .word 0x37603d30 ; bf 0.0000133514404296875, 0.04296875
    .word 0x2ee03f80 ; bf 1.0186340659856796e-10, 1
v_roll:
    .byte 25, 0x80, 0x11, p_roll-d_song, n_zero-d_song, 36-7+198, 0, 0
    .word 0x3f003920 ; bf 0.5, 0.000152587890625
    .word 0x38f03ca0 ; bf 0.00011444091796875, 0.01953125
    .word 0x2fe03eb0 ; bf 4.0745362639427185e-10, 0.34375
v_bass:
    .byte 9, 0x01, 0x25, p_bass-d_song, n_bass-d_song, 36-12+198, 0, 0
    .word 0x3e803840 ; bf 0.25, 0.0000457763671875
    .word 0x37e03c08 ; bf 0.000026702880859375, 0.00830078125
    .word 0x30000000 ; bf 4.656612873077393e-10, 0
v_arp:
    .byte 73, 0x08, 0x45, p_arp-d_song, n_arp-d_song, 36+198, 0, 0
    .word 0x3dc03800 ; bf 0.09375, 0.000030517578125
    .word 0x38703c50 ; bf 0.000057220458984375, 0.0126953125
    .word 0x2f500000 ; bf 1.8917489796876907e-10, 0
v_lead:
    .byte 41, 0x10, 0x50, p_lead-d_song, n_lead-d_song, 36+198, 0, 0
    .word 0x3db03690 ; bf 0.0859375, 0.000004291534423828125
    .word 0x36d03aa0 ; bf 0.000006198883056640625, 0.001220703125
    .word 0x2fa00000 ; bf 2.9103830456733704e-10, 0
v_lead2:
    .byte 43, 0x40, 0x30, p_lead-d_song, n_lead-d_song, 36+198, 0, 0
    .word 0x3e1036d0 ; bf 0.140625, 0.000006198883056640625
    .word 0x36b03a60 ; bf 0.000005245208740234375, 0.0008544921875
    .word 0x2f600000 ; bf 2.0372681319713593e-10, 0
v_pad:
    .byte 27, 0x20, 0x25, p_pad-d_song, n_zero-d_song, 36+198, 0, 0
    .word 0x3dc035d0 ; bf 0.09375, 0.0000015497207641601562
    .word 0x35b03860 ; bf 0.0000013113021850585938, 0.00005340576171875
    .word 0x2f100000 ; bf 1.3096723705530167e-10, 0
d_voices_end:
; taps: [delay samples] [.bf gain, pan]. Voices use a prefix of this list:
; 1 = dry, 3 = + 2 early reflections (pads, drums), 5 = + two ping-pong
; echoes (leads), 9 = everything (arp).
d_taps:
    .word 0
    .word 0x3f800000 ; bf 1, 0
    .word 1728
    .word 0x3ea03f30 ; bf 0.3125, 0.6875
    .word 2880
    .word 0x3e90bf30 ; bf 0.28125, -0.6875
    .word 16875
    .word 0x3ed0bf50 ; bf 0.40625, -0.8125
    .word 33750
    .word 0x3e803f50 ; bf 0.25, 0.8125
    .word 4096
    .word 0x3e803f20 ; bf 0.25, 0.625
    .word 5568
    .word 0x3e50bf20 ; bf 0.203125, -0.625
    .word 7936
    .word 0x3e203f00 ; bf 0.15625, 0.5
    .word 50625
    .word 0x3e20bf50 ; bf 0.15625, -0.8125
d_taps_end:
d_song_end:


; ---------------------------------------------------------------------
; GPU data (binding 1): text items, font, strings
; ---------------------------------------------------------------------
.align 4
d_base:
; text items: [.bf x0, y0 of the leading space's blank row] [.bf 1/scale,
;   scroll (font px / frame)] [.bfi 16 * wobble (font px), 6 * length]
;   [string offset]
d_items:
; ---- include font_n.s ----
; generated by tools/mfont.py -- 6 * string lengths

t_logo:
    .word 0xbf804150 ; bf -1, 13
    .word 0x3eac0000 ; bf 0.3359375, 0
    .word 0x00000030 ; bfi 0, 48
    .word s_logo - d_base
t_scroll:
    .word 0x431442ac ; bf 148, 86
    .word 0x3f003f00 ; bf 0.5, 0.5
    .word 0x424000a8 ; bfi 48, 168
    .word s_scroll - d_base
t_greet:
    .word 0x431442ac ; bf 148, 86
    .word 0x3f003f00 ; bf 0.5, 0.5
    .word 0x42400096 ; bfi 48, 150
    .word s_greet - d_base
; ---- include font.s ----
; generated by tools/mfont.py -- 5x5 font (bit (row+1)*5+col) and strings (glyph word offsets)
d_font:
    .word 0x00000000 ; ' '
    .word 0x231aee20 ; 'M'
    .word 0x3e1787e0 ; 'E'
    .word 0x3d1c87c0 ; 'G'
    .word 0x231fc5c0 ; 'A'
    .word 0x3e4213e0 ; 'I'
    .word 0x22a22a20 ; 'X'
    .word 0x1d18c5c0 ; 'O'
    .word 0x0217c5e0 ; 'P'
    .word 0x1d18c620 ; 'U'
    .word 0x1f0707c0 ; 'S'
    .word 0x2297c5e0 ; 'R'
    .word 0x239ace20 ; 'N'
    .word 0x084213e0 ; 'T'
    .word 0x210fc620 ; '4'
    .word 0x2293a620 ; 'K'
    .word 0x1f18c5e0 ; 'D'
    .word 0x3e108420 ; 'L'
    .word 0x3c1087c0 ; 'C'
s_logo: ; " MEGAMIX"
    .byte 12, 13, 14, 15, 16, 13, 17, 18
s_scroll: ; " OPUS PRESENTS A 4K MEGADEMO"
    .byte 12, 19, 20, 21, 22, 12, 20, 23, 14, 22, 14, 24, 25, 22, 12, 16
    .byte 12, 26, 27, 12, 13, 14, 15, 16, 28, 14, 13, 19
s_greet: ; " GREETINGS TO ALL SCENERS"
    .byte 12, 15, 23, 14, 14, 25, 17, 24, 15, 22, 12, 25, 19, 12, 16, 29
    .byte 29, 12, 22, 30, 14, 24, 14, 23, 22

d_end:

; ---------------------------------------------------------------------
; parts, 450 frames (4 bars) each: [type] [text items] [.bf flash, palette
; spread] [three part parameters]
; ---------------------------------------------------------------------
.align 4
parts:
    .word 0, 0x0201             ; crack intro: copper bars, logo, scroller
    .word 0x00000000 ; bf 0, 0
    .word 0, 0, 0
    .word 1, 0                  ; Boing ball
    .word 0x3f800000 ; bf 1, 0
    .word 1
    .word 0x400cc0d0 ; bf 2.1875, -6.5
    .word 0xc14042dc ; bf -12, 110
    .word 2, 0                  ; plasma
    .word 0x3f803ea8 ; bf 1, 0.328125
    .float 0.03515625 
    .word 0, 0
    .word 3, 0                  ; tunnel
    .word 0x3f803e4c ; bf 1, 0.19921875
    .float 3.0 
    .word 0, 0
    .word 1, 0                  ; vector balls
    .word 0x3f800000 ; bf 1, 0
    .word 64
    .word 0x4040c108 ; bf 3, -8.5
    .word 0xc0c042c8 ; bf -6, 100
    .word 4, 0                  ; Menger flight, breakdown
    .word 0x3f803e38 ; bf 1, 0.1796875
    .float 0.40625, 0.0029296875, 0.01171875 
    .word 4, 0                  ; Menger flight, drop
    .word 0x3f803ea8 ; bf 1, 0.328125
    .float 1.0, -0.0078125, 0.01953125 
    .word 0, 0x0301             ; outro
    .word 0x3f800000 ; bf 1, 0
    .word 0, 0, 0

; MMIO configuration script: [dest, count, words...], 0 terminates
cfg:
    .word 0xf3040, 15, FB0, 57600, 3, 0, d_base, d_end - d_base, 1, 0, TABLE, TABSZ, 1, 0, FB1, 57600, 1
    .word 0xf6040, 5, spu_k, spu_k_end - spu_k, 64, 4, AOUT
    .word 0xf6100, 7, AOUT, 2048, 3, 0, d_song, d_song_end - d_song, 1
    .word 0xf6204, 3, 7, 23, 3
    .word 0xf6000, 1, 1
    .word 0xf5004, 4, 480, 4, 0, 1
    .word 0xf3120, 1, 0x3ea00000
    .word 0xf3128, 6, 0x3f000000, 0x3f800000, 0x3d000000, 0x3d400000, 0x3e200000, 0x3e600000
    .word 0
h_pre:
    .word pre_k, pre_k_end - pre_k, 64, 1
h_render:
    .word render_k, render_k_end - render_k, 160, 40

