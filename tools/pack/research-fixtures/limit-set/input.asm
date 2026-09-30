; LOAD 0x2CA00
; =====================================================================
;  LIMIT SET -- a 4K intro for DB32 (dynamic-1, packed).
;  A flight through regular honeycombs of hyperbolic space, from flat
;  Euclidean cubes to the fractal limit set at infinity.
;  RAM: FB0 0x10000, FB1 0x1E100 (RGB888 pages, image rows 15..104),
;  SPU output 0x2C200, image LOAD..0x30000.
; =====================================================================
.profile dynamic-1
.entry start
.equ FB0,   0x10000
.equ FB1,   0x1E100
.equ AOUT,  0x2C200
.equ LOOP,  3600
.equ SCENE, 450

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
    lui r10, 0x10               ; back buffer
    li r11, FB1                 ; front buffer
    lw r9, 24(r14)              ; frame counter at the demo start
    addi r15, r0, -1            ; scene whose parameters are loaded
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
    ; scene r8 = frame / 450, frame in the scene -> U1
    addi r3, r0, -1
    mov r8, r3
    addi r2, r0, SCENE
find:
    addi r8, r8, 1
    sub r1, r1, r2
    blt r3, r1, find
    add r5, r1, r2
    sw r5, 0x104(r13)           ; U1
    ; new scene: rebuild the parameter block from scene 0's record on,
    ; each record = [field mask] + the fields that change
    beq r8, r15, same
    mov r15, r8
    li r1, scenes
    addi r3, r8, 1
    addi r12, r0, 1
rec:
    lw r2, 0(r1)
    addi r1, r1, 4
    li r4, pblock
fld:
    andi r6, r2, 1
    beq r6, r0, fskip
    lw r6, 0(r1)
    addi r1, r1, 4
    sw r6, 0(r4)
fskip:
    addi r4, r4, 4
    shr r2, r2, r12
    bne r2, r0, fld
    addi r3, r3, -1
    bne r3, r0, rec
    ; U2 = cell table offset, U4 = 3 / faces: 1.0 for the cube (offset 0), 0.5
    li r4, pblock
    lw r1, 0(r4)
    sw r1, 0x108(r13)
    sltu r2, r0, r1
    lui r3, 0x800
    mul r2, r2, r3
    lui r3, 0x3f800
    sub r3, r3, r2
    sw r3, 0x110(r13)
same:
    ; block words 7..17: [start | end] bf16 pairs -> U5..U15, interpolated
    ; through the scene on the bit patterns (geometric for positive values)
    addi r4, r0, 146            ; 65536 / 449
    mul r4, r4, r5
    li r1, pblock + 28
    addi r2, r13, 0x114
    addi r3, r0, 11
    addi r12, r0, 16
unpack:
    lw r6, 0(r1)
    shr r7, r6, r12
    andi r6, r6, 0xffff
    sub r6, r6, r7
    mul r6, r6, r4
    sar r6, r6, r12
    add r7, r7, r6
    shl r7, r7, r12
    sw r7, 0(r2)
    addi r1, r1, 4
    addi r2, r2, 4
    addi r3, r3, -1
    bne r3, r0, unpack
    ; renderer in strips of 30 rows; the fourth draws the bottom bar
    mov r6, r0
strip:
    sw r6, 0x10c(r13)           ; U3 = first row
    addi r2, r0, 1
    sw r2, 16(r13)              ; START
wgpu:
    wfi
    lw r3, 20(r13)
    beq r3, r2, wgpu
    addi r6, r6, 30
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

; ---- include render.s ----
; ---------------------------------------------------------------------
; Renderer: one invocation per pixel of a strip (grid 160 x 30), image
; rows 0..89 of the 160x90 letterbox.
; Flight through a regular hyperbolic honeycomb in the Klein model. Every
; ray bounces inside ONE cell: leaving through a face is a Lorentz
; reflection, which maps the neighbouring cell back onto this one. The
; state is kept in face coordinates k_j = n_j.K, s_j = n_j.D for six face
; normals (the cube pads with zero normals), so the exit search and the
; reflection s_j += m s_a (sigma c k_j - G_aj) need no vector algebra.
; bindings: 0 back buffer, 1 data, 3 the frame on screen.
; ---------------------------------------------------------------------
; uniforms: 0 demo frame, 1 frame in the scene, 2 cell table offset,
;   3 first row, 4 FR = 3 / faces (|K|^2 = FR * sum k_j^2), 5..12 the
;   scene's per-bounce parameters, interpolated through the scene by the CPU.
; The rest of the scene's parameters are in the block PB (binding 1).
.equ U_FR,  4
.equ U_WID, 5       ; beam half width (Klein)
.equ U_GL,  6       ; glow gain
.equ U_TINT, 7      ; glass emission per face crossing
.equ U_TR,  8       ; glass transmission
.equ U_FOG, 9       ; fog density
.equ U_HS,  10      ; hue step per reflection
.equ U_ORB, 11      ; orb (cell centre light) gain
.equ U_EXP, 12      ; exposure
.equ U_PUL, 13      ; beat pulse
.equ U_SP,  14      ; palette spread
.equ U_TB,  15      ; temporal blend with the frame on screen
.equ PB, pblock - d_base

; -sin(2 pi p) / 16, parabolic, p > -256 (R: scratch)
; tanh(x) ~ x (15 + x^2) / (15 + 6 x^2) (R, R2: scratch)
; D = a + (b - a) s for a bf16 pair W = [a | b] (R: scratch)
; next record word


render_k:
    g.fli g25, 1.0
    g.fli g26, 0.5
    g.id g12, 1
    g.uniform g13, 3
    g.add g12, g12, g13
    g.li g13, 105
    g.slt g14, g12, g13
    g.bz g14, done               ; below the bottom bar
    g.li g13, 90
    g.slt g14, g12, g13
    g.bz g14, post               ; bottom bar: text on black
; ---------------------------------------------------------------------
; camera: position and ray in the Klein model, then face coordinates
; ---------------------------------------------------------------------
    g.li g5, 4
    g.li g28, 16
    g.li g30, 0xffff0000
    g.li g4, PB
    g.uniform g6, 1
    g.itof g6, g6
    g.fli g1, 0.002227783203125
    g.fmul g6, g6, g1
    g.fmul g1, g6, g6
    g.fadd g2, g6, g6
    g.fli g3, 3.0
    g.fsub g2, g3, g2
    g.fmul g6, g1, g2              ; smoothstep of the scene progress
    ; forward F = norm(1, fy, fz)
    ; <nextw W>
    g.add g4, g4, g5
    g.ld g7, g4, 1
    ; <lerpbf H, W, S>
    g.and g8, g7, g30
    g.shl g1, g7, g28
    g.fsub g1, g1, g8
    g.fmul g1, g1, g6
    g.fadd g8, g8, g1
    ; <tanhp C, H>
    g.fmul g1, g8, g8
    g.fli g2, 6.0
    g.fmul g2, g2, g1
    g.fli g31, 15.0
    g.fadd g2, g2, g31
    g.fadd g1, g1, g31
    g.fmul g1, g1, g8
    g.fdiv g31, g1, g2
    ; <nextw W>
    g.add g4, g4, g5
    g.ld g7, g4, 1
    ; <lerpbf F.y, W, S>
    g.and g10, g7, g30
    g.shl g1, g7, g28
    g.fsub g1, g1, g10
    g.fmul g1, g1, g6
    g.fadd g10, g10, g1
    ; <nextw W>
    g.add g4, g4, g5
    g.ld g7, g4, 1
    ; <lerpbf F.z, W, S>
    g.and g11, g7, g30
    g.shl g1, g7, g28
    g.fsub g1, g1, g11
    g.fmul g1, g1, g6
    g.fadd g11, g11, g1
    g.mov g9, g25
    g.norm3 g9, g9
    ; up = (0, 1, tilt)
    ; <nextw W>
    g.add g4, g4, g5
    g.ld g7, g4, 1
    ; <lerpbf UP.z, W, S>
    g.and g17, g7, g30
    g.shl g1, g7, g28
    g.fsub g1, g1, g17
    g.fmul g1, g1, g6
    g.fadd g17, g17, g1
    g.mov g16, g25
    ; right = norm(F x up), up = norm(up - (up.F) F)   (up.x = 0)
    g.fmul g1, g10, g17
    g.fmul g2, g11, g16
    g.fsub g12, g1, g2
    g.fmul g1, g9, g17
    g.fsub g13, g0, g1
    g.fmul g14, g9, g16
    g.norm3 g12, g12
    g.dot3 g1, g15, g9
    g.vscale g1, g9, g1
    g.vsub g15, g15, g1
    g.norm3 g15, g15
    ; screen: u = (x - 79.5) * fov, v = (44.5 - y) * fov
    g.fli g7, 0.012451171875
    g.id g24, 0
    g.itof g24, g24
    g.fli g1, 80.0
    g.fsub g24, g24, g1
    g.fmul g24, g24, g7
    g.vscale g12, g12, g24
    g.id g24, 1
    g.uniform g1, 3
    g.add g24, g24, g1
    g.itof g24, g24
    g.fli g1, 44.5
    g.fsub g24, g1, g24
    g.fmul g24, g24, g7
    g.vscale g15, g15, g24
    g.vadd g18, g9, g12
    g.vadd g18, g18, g15
    ; distance flown d = d0 + speed * frame; wrap: k = floor(d / 2h + 1/2)
    ; <nextw W>
    g.add g4, g4, g5
    g.ld g7, g4, 1
    g.shl g1, g7, g28
    g.uniform g2, 1
    g.itof g2, g2
    g.fmul g1, g1, g2
    g.and g2, g7, g30
    g.flt g3, g2, g0
    g.bnz g3, ext                ; d0 < 0: the ball seen from outside
    g.fadd g24, g1, g2              ; d
    g.fadd g1, g8, g8
    g.fdiv g2, g24, g1
    g.fadd g2, g2, g26
    g.ftoi g2, g2
    g.itof g3, g2
    g.fmul g3, g3, g1
    g.fsub g24, g24, g3              ; dd in [-h, h)
    ; each wrap is a screw: translation by 2h and a half turn about x
    ; <nextw W>
    g.add g4, g4, g5
    g.ld g7, g4, 1
    g.and g22, g7, g30
    g.shl g23, g7, g28
    g.li g1, 1
    g.and g2, g2, g1
    g.bz g2, no_flip
    g.fsub g22, g0, g22
    g.fsub g23, g0, g23
    g.fsub g19, g0, g19
    g.fsub g20, g0, g20
no_flip:
    ; boost along x: T = tanh dd, S = sqrt(1 - T^2)
    g.mov g3, g24
    ; <tanhp T, E>
    g.fmul g1, g3, g3
    g.fli g2, 6.0
    g.fmul g2, g2, g1
    g.fli g24, 15.0
    g.fadd g2, g2, g24
    g.fadd g1, g1, g24
    g.fmul g1, g1, g3
    g.fdiv g24, g1, g2
    g.fmul g1, g24, g24
    g.fsub g1, g25, g1
    g.sqrt g27, g1
    ; eye K0 = (T, p0y S, p0z S); ray D = (vx S, vy - vx T p0y, vz - vx T p0z)
    g.fmul g1, g18, g24
    g.fmul g2, g1, g22
    g.fsub g7, g19, g2
    g.fmul g2, g1, g23
    g.fsub g8, g20, g2
    g.fmul g6, g18, g27
    g.mov g21, g24
    g.fmul g22, g22, g27
    g.fmul g23, g23, g27
    g.norm3 g6, g6
    ; face coordinates k_j = n_j . K0, s_j = n_j . D (normals at the cell
    ; table): six times shift g1..g6 and g7..g12 down one, the new face at the end
    g.uniform g4, 2
    g.li g24, 24
facec:
    g.vscale g9, g10, g25
    g.vscale g12, g13, g25
    g.vscale g15, g16, g25
    g.vscale g18, g19, g25
    g.ld g1, g4, 1
    g.add g4, g4, g5
    g.ld g2, g4, 1
    g.add g4, g4, g5
    g.ld g3, g4, 1
    g.add g4, g4, g5
    g.dot3 g14, g1, g21
    g.dot3 g20, g1, g6
    g.sub g24, g24, g5
    g.bnz g24, facec
    g.jmp cm_setup
ext:
    ; eye O = d0 F behind the unit ball; K = entry point at radius ~1
    g.vscale g21, g9, g2
    g.norm3 g18, g18
    g.dot3 g1, g21, g18
    g.dot3 g3, g21, g21
    g.fli g2, 0.984375
    g.fsub g3, g3, g2
    g.fmul g2, g1, g1
    g.fsub g2, g2, g3
    g.fmax g2, g2, g0             ; a miss grazes: no light there anyway
    g.sqrt g2, g2
    g.fadd g1, g1, g2
    g.vscale g6, g18, g1
    g.vsub g9, g21, g6            ; K
    ; light: 0.15 + diffuse + rim^2 (n = K)
    g.fli g12, 0.484375
    g.fli g13, 0.640625
    g.fli g14, -0.6015625
    g.dot3 g1, g9, g12
    g.fmax g1, g1, g0
    g.dot3 g2, g9, g18
    g.fadd g2, g2, g25
    g.fmul g2, g2, g2
    g.fadd g1, g1, g2
    g.fli g2, 0.150390625
    g.fadd g21, g1, g2
    ; outside the ball (|K|^2 > 1): no light, and K = 0 folds nowhere
    g.dot3 g1, g9, g9
    g.fle g1, g1, g25
    g.bnz g1, cm_setup
    g.mov g21, g0
    g.mov g9, g0
    g.mov g10, g0
    g.mov g11, g0
cm_setup:
    ; the trace keeps c in g18 and m = 2 / (1 - c^2) in g19
    g.mov g8, g31
    g.fmul g1, g31, g31
    g.fsub g1, g25, g1
    g.fli g2, 2.0
    g.fdiv g31, g2, g1

; ---------------------------------------------------------------------
; trace
; ---------------------------------------------------------------------
    ; hue at the start: hue0 + rate * frame
    g.li g26, PB + 72
    g.ld g1, g26, 1              ; [hue0 | hue rate per frame] (word 18)
    g.li g2, 16
    g.shl g2, g1, g2
    g.uniform g3, 1
    g.itof g3, g3
    g.fmul g2, g2, g3
    g.li g3, 0xffff0000
    g.and g1, g1, g3
    g.fadd g7, g1, g2
    g.mov g6, g25
    g.li g26, PB + 20
    g.ld g1, g26, 1
    g.slt g1, g1, g0
    g.bnz g1, ext_fold
    g.mov g21, g0
    ; |K|^2 and normalised ray
    g.dot3 g1, g9, g9
    g.dot3 g2, g12, g12
    g.fadd g1, g1, g2
    g.uniform g2, U_FR
    g.fmul g28, g1, g2
    g.fli g5, 40.0
bounce:
    ; ---- exit face: t_j = (c |s| - k s) / s^2, minimum over the faces ----
    g.fli g24, 4.0
    ; <exitf KA.x, SA.x, 72>
    g.fsub g1, g0, g15
    g.fmax g1, g1, g15
    g.fmul g1, g1, g8
    g.fmul g2, g9, g15
    g.fsub g1, g1, g2
    g.fmul g2, g15, g15
    g.fmul g3, g24, g2
    g.flt g3, g1, g3
    g.bz g3, ex_12
    g.fdiv g24, g1, g2
    g.li g27, 72
    g.mov g4, g15
ex_12:
    ; <exitf KA.y, SA.y, 96>
    g.fsub g1, g0, g16
    g.fmax g1, g1, g16
    g.fmul g1, g1, g8
    g.fmul g2, g10, g16
    g.fsub g1, g1, g2
    g.fmul g2, g16, g16
    g.fmul g3, g24, g2
    g.flt g3, g1, g3
    g.bz g3, ex_13
    g.fdiv g24, g1, g2
    g.li g27, 96
    g.mov g4, g16
ex_13:
    ; <exitf KA.z, SA.z, 120>
    g.fsub g1, g0, g17
    g.fmax g1, g1, g17
    g.fmul g1, g1, g8
    g.fmul g2, g11, g17
    g.fsub g1, g1, g2
    g.fmul g2, g17, g17
    g.fmul g3, g24, g2
    g.flt g3, g1, g3
    g.bz g3, ex_14
    g.fdiv g24, g1, g2
    g.li g27, 120
    g.mov g4, g17
ex_14:
    g.uniform g1, 2
    g.bz g1, ex_cube
    ; <exitf KB.x, SB.x, 144>
    g.fsub g1, g0, g18
    g.fmax g1, g1, g18
    g.fmul g1, g1, g8
    g.fmul g2, g12, g18
    g.fsub g1, g1, g2
    g.fmul g2, g18, g18
    g.fmul g3, g24, g2
    g.flt g3, g1, g3
    g.bz g3, ex_15
    g.fdiv g24, g1, g2
    g.li g27, 144
    g.mov g4, g18
ex_15:
    ; <exitf KB.y, SB.y, 168>
    g.fsub g1, g0, g19
    g.fmax g1, g1, g19
    g.fmul g1, g1, g8
    g.fmul g2, g13, g19
    g.fsub g1, g1, g2
    g.fmul g2, g19, g19
    g.fmul g3, g24, g2
    g.flt g3, g1, g3
    g.bz g3, ex_16
    g.fdiv g24, g1, g2
    g.li g27, 168
    g.mov g4, g19
ex_16:
    ; <exitf KB.z, SB.z, 192>
    g.fsub g1, g0, g20
    g.fmax g1, g1, g20
    g.fmul g1, g1, g8
    g.fmul g2, g14, g20
    g.fsub g1, g1, g2
    g.fmul g2, g20, g20
    g.fmul g3, g24, g2
    g.flt g3, g1, g3
    g.bz g3, ex_17
    g.fdiv g24, g1, g2
    g.li g27, 192
    g.mov g4, g20
ex_17:
ex_cube:
    ; ---- K.D; orb at the cell centre: closest approach t* = -K.D ----
    g.dot3 g1, g9, g15
    g.dot3 g2, g12, g18
    g.fadd g30, g1, g2
    g.uniform g1, U_FR
    g.fmul g30, g30, g1
    g.fsub g1, g0, g30
    g.flt g2, g1, g0
    g.bnz g2, no_orb
    g.flt g2, g24, g1
    g.bnz g2, no_orb
    g.fmul g2, g30, g30
    g.fsub g2, g28, g2             ; squared distance of the closest point
    g.fli g3, 300.0
    g.fmul g2, g2, g3
    g.fadd g2, g2, g25
    g.fmul g2, g2, g2
    g.uniform g3, U_ORB
    g.fdiv g3, g3, g2
    g.fmul g3, g3, g6
    g.fadd g21, g21, g3
no_orb:
    ; ---- K.K' = |K|^2 + t K.D, then move ----
    g.fmul g30, g30, g24
    g.fadd g30, g30, g28
    g.vscale g1, g15, g24
    g.vadd g9, g9, g1
    g.vscale g1, g18, g24
    g.vadd g12, g12, g1
    g.dot3 g1, g9, g9
    g.dot3 g2, g12, g12
    g.fadd g1, g1, g2
    g.uniform g2, U_FR
    g.fmul g1, g1, g2              ; |K'|^2
    g.fle g2, g25, g1
    g.bnz g2, escaped
    ; ---- fog: cosh L = (1 - K.K') / sqrt((1 - |K|^2)(1 - |K'|^2)), F = e^-L ----
    g.fsub g2, g25, g28
    g.mov g28, g1
    g.fsub g1, g25, g1
    g.fmul g1, g1, g2
    g.rsqrt g1, g1
    g.fsub g2, g25, g30
    g.fmul g1, g1, g2
    g.fmul g2, g1, g1
    g.fsub g2, g2, g25
    g.fmax g2, g2, g0
    g.sqrt g2, g2
    g.fsub g1, g1, g2              ; e^-L
    g.fsub g1, g1, g25
    g.uniform g2, U_FOG
    g.fmul g1, g1, g2
    g.fadd g1, g1, g25
    g.fmul g6, g6, g1
    ; ---- edge distance: second smallest face slack c - |k_j| ----
    g.mov g24, g8
    g.mov g3, g8
    ; <slack KA.x>
    g.fsub g1, g0, g9
    g.fmax g1, g1, g9
    g.fsub g1, g8, g1
    g.fmax g2, g24, g1
    g.fmin g3, g3, g2
    g.fmin g24, g24, g1
    ; <slack KA.y>
    g.fsub g1, g0, g10
    g.fmax g1, g1, g10
    g.fsub g1, g8, g1
    g.fmax g2, g24, g1
    g.fmin g3, g3, g2
    g.fmin g24, g24, g1
    ; <slack KA.z>
    g.fsub g1, g0, g11
    g.fmax g1, g1, g11
    g.fsub g1, g8, g1
    g.fmax g2, g24, g1
    g.fmin g3, g3, g2
    g.fmin g24, g24, g1
    g.uniform g1, 2
    g.bz g1, sl_cube
    ; <slack KB.x>
    g.fsub g1, g0, g12
    g.fmax g1, g1, g12
    g.fsub g1, g8, g1
    g.fmax g2, g24, g1
    g.fmin g3, g3, g2
    g.fmin g24, g24, g1
    ; <slack KB.y>
    g.fsub g1, g0, g13
    g.fmax g1, g1, g13
    g.fsub g1, g8, g1
    g.fmax g2, g24, g1
    g.fmin g3, g3, g2
    g.fmin g24, g24, g1
    ; <slack KB.z>
    g.fsub g1, g0, g14
    g.fmax g1, g1, g14
    g.fsub g1, g8, g1
    g.fmax g2, g24, g1
    g.fmin g3, g3, g2
    g.fmin g24, g24, g1
sl_cube:
    g.uniform g1, U_WID
    g.flt g2, g3, g1
    g.bnz g2, beam
    ; glow ATT * gain / (1 + (e / width)^2), glass
    g.fli g2, 40.0
    g.fmul g2, g3, g2
    g.fmul g2, g2, g2
    g.fadd g2, g2, g25
    g.uniform g1, U_GL
    g.fdiv g1, g1, g2
    ; glass: brighter at grazing angles and near infinity (rims of the
    ; limit set's discs): tint * (1.25 - |n.D| + 3 |K|^16)
    g.fsub g22, g0, g4
    g.fmax g22, g22, g4
    g.fli g2, 1.25
    g.fsub g22, g2, g22
    g.fmul g2, g28, g28
    g.fmul g2, g2, g2
    g.fmul g2, g2, g2
    g.fadd g22, g22, g2
    g.fadd g22, g22, g2
    g.fadd g22, g22, g2
    g.uniform g2, U_TINT
    g.fmul g2, g2, g22
    g.fadd g1, g1, g2
    g.fmul g1, g1, g6
    g.fadd g21, g21, g1
    g.uniform g1, U_TR
    g.fmul g6, g6, g1
    g.fli g1, 0.0302734375
    g.flt g1, g6, g1
    g.bnz g1, shade              ; lost in the fog
    ; ---- reflect: s_j += m s_a (sigma c k_j - G_aj) ----
    g.flt g1, g4, g0
    g.itof g1, g1
    g.fadd g1, g1, g1
    g.fsub g1, g25, g1           ; sigma
    g.fmul g29, g1, g8
    g.fmul g23, g31, g4
    g.uniform g2, U_HS
    g.fmul g1, g1, g2
    g.itof g2, g27
    g.fmul g1, g1, g2
    g.fadd g7, g7, g1
    g.uniform g26, 2
    g.add g26, g26, g27
    g.li g24, 4
    ; <gram KA, SA>
    g.vscale g1, g9, g29
    g.ld g22, g26, 1
    g.fsub g1, g1, g22
    g.add g26, g26, g24
    g.ld g22, g26, 1
    g.fsub g2, g2, g22
    g.add g26, g26, g24
    g.ld g22, g26, 1
    g.fsub g3, g3, g22
    g.add g26, g26, g24
    g.vscale g1, g1, g23
    g.vadd g15, g15, g1
    ; <gram KB, SB>
    g.vscale g1, g12, g29
    g.ld g22, g26, 1
    g.fsub g1, g1, g22
    g.add g26, g26, g24
    g.ld g22, g26, 1
    g.fsub g2, g2, g22
    g.add g26, g26, g24
    g.ld g22, g26, 1
    g.fsub g3, g3, g22
    g.add g26, g26, g24
    g.vscale g1, g1, g23
    g.vadd g18, g18, g1
    ; renormalise the ray
    g.dot3 g1, g15, g15
    g.dot3 g2, g18, g18
    g.fadd g1, g1, g2
    g.uniform g2, U_FR
    g.fmul g1, g1, g2
    g.rsqrt g1, g1
    g.vscale g15, g15, g1
    g.vscale g18, g18, g1
    g.fsub g5, g5, g25
    g.bnz g5, bounce
    g.jmp shade
ext_fold:
    ; fold the ideal point by the cube's own mirrors (abs, largest to x),
    ; then reflect in the face x = c while beyond it:
    ; x -= m (x - c), K /= 1 - m (x - c) c. The count is the depth of the
    ; point's disc; the limit set is where it runs out.
    g.fli g5, 24.0
    g.mov g23, g0
efold:
    g.fsub g1, g0, g9
    g.fmax g9, g9, g1
    g.fsub g1, g0, g10
    g.fmax g10, g10, g1
    g.fsub g1, g0, g11
    g.fmax g11, g11, g1
    g.fmax g1, g9, g10
    g.fmin g10, g9, g10
    g.fmax g9, g1, g11
    g.fmin g11, g1, g11
    g.fsub g1, g9, g8
    g.fle g2, g1, g0
    g.bnz g2, efold_done
    g.fmul g1, g1, g31
    g.fsub g9, g9, g1
    g.fmul g1, g1, g8
    g.fsub g1, g25, g1
    g.fdiv g1, g25, g1
    g.vscale g9, g9, g1
    g.fadd g23, g23, g25
    g.fsub g5, g5, g25
    g.bnz g5, efold
efold_done:
    ; rim of the disc: glow 1 / (1 + (40 (c - x))^2); hue by depth
    g.fsub g1, g8, g9
    g.fli g2, 40.0
    g.fmul g1, g1, g2
    g.fmul g1, g1, g1
    g.fadd g1, g1, g25
    g.fli g2, 3.0
    g.fdiv g1, g2, g1
    g.fadd g1, g1, g25
    g.fmul g21, g21, g1
    g.uniform g2, U_HS
    g.fmul g1, g23, g2
    g.fadd g7, g7, g1
    g.jmp shade
beam:
    ; rounded profile sqrt(1 - (e/w)^2), lit by the cell centre (1 - |K|^2),
    ; white core (1 - (e/w)^2)^8
    g.fdiv g1, g3, g1
    g.fmul g1, g1, g1
    g.fsub g1, g25, g1
    g.fmax g1, g1, g0
    g.sqrt g2, g1
    g.fmul g1, g1, g1
    g.fmul g1, g1, g1
    g.fmul g1, g1, g1
    g.fmul g23, g1, g6
    g.fsub g3, g25, g28
    g.fmul g2, g2, g3
    g.fli g3, 0.25
    g.fadd g2, g2, g3
    g.fmul g2, g2, g6
    g.fadd g21, g21, g2
    g.mov g22, g0
    g.jmp shade3
escaped:
    ; the sky through a hole of the limit set: brighter towards the hole's
    ; centre, X = ATT * (0.7 + 12 (c - max |k_j|))
    g.fsub g1, g0, g9
    g.fmax g1, g1, g9
    g.fsub g2, g0, g10
    g.fmax g2, g2, g10
    g.fmax g1, g1, g2
    g.fsub g2, g0, g11
    g.fmax g2, g2, g11
    g.fmax g1, g1, g2
    g.fsub g1, g8, g1
    g.fli g2, 12.0
    g.fmul g1, g1, g2
    g.fli g2, 0.703125
    g.fadd g1, g1, g2
    g.fmul g22, g6, g1
    g.jmp shade2
shade:
    g.mov g22, g0
shade2:
    g.mov g23, g0
shade3:

; ---------------------------------------------------------------------
; colour: palette(hue) * emission + sky * X + fog * ATT
; ---------------------------------------------------------------------
    g.fli g26, 0.5
    g.li g28, 16
    g.li g30, 0xffff0000
    g.uniform g27, U_SP
    ; exposure * (1 + pulse (1 - beat phase)^2), 28.125 frames per beat
    g.uniform g5, 0
    g.itof g5, g5
    g.fli g4, 0.035555556  ; exact
    g.fmul g5, g5, g4
    g.ftoi g4, g5
    g.itof g4, g4
    g.fsub g5, g5, g4
    g.fsub g5, g25, g5
    g.fmul g5, g5, g5
    g.uniform g4, U_PUL
    g.fmul g5, g5, g4
    g.fadd g5, g5, g25
    g.uniform g2, U_EXP
    g.fmul g2, g2, g5
    g.fmul g21, g21, g2
    g.li g24, 3
pal:
    ; <sinb S, HUE>
    g.fli g1, 256.0
    g.fadd g4, g7, g1
    g.ftoi g1, g4
    g.itof g1, g1
    g.fsub g4, g4, g1
    g.fsub g4, g4, g26
    g.fsub g1, g0, g4
    g.fmax g1, g1, g4
    g.fsub g1, g26, g1
    g.fmul g4, g4, g1
    g.fli g5, -8.0
    g.fmul g4, g4, g5
    g.fadd g4, g4, g26
    g.fmul g4, g4, g4
    g.fmul g4, g4, g21
    g.mov g9, g10
    g.mov g10, g11
    g.mov g11, g4
    g.fadd g7, g7, g27
    g.li g5, 1
    g.sub g24, g24, g5
    g.bnz g24, pal
    ; sky [r | g] [b | fog level]; + sky * (X + fog level * (1 - ATT))
    g.li g3, PB + 76
    g.ld g2, g3, 1
    g.and g12, g2, g30
    g.shl g13, g2, g28
    g.li g5, 4
    g.add g3, g3, g5
    g.ld g2, g3, 1
    g.and g14, g2, g30
    g.shl g15, g2, g28
    g.fsub g5, g25, g6
    g.fmul g5, g5, g15
    g.fadd g22, g22, g5
    g.vscale g12, g12, g22
    g.vadd g9, g9, g12
    g.fli g5, 0.703125
    g.fmul g23, g23, g5
    g.fadd g9, g9, g23
    g.fadd g10, g10, g23
    g.fadd g11, g11, g23

; ---------------------------------------------------------------------
; post: fade / flash (block word 21), the scene's text item (word 22),
; gamma, store at row + 15
; text item: [delay/32 : 4 | scale shift : 4 | row : 8 | length : 4 |
;   string offset : 12]; strings hold data word offsets of 5x5 glyphs
;   (bit (row + 1) * 5 + col), centred, fading in after the delay and
;   out at the scene's end.
; ---------------------------------------------------------------------
post:
    g.li g6, 1
    g.li g7, 4
    g.uniform g12, 1
    g.id g13, 0
    g.id g14, 1
    g.uniform g19, 3
    g.add g14, g14, g19
    g.li g15, PB + 84
    g.li g19, 90
    g.slt g19, g14, g19
    g.bz g19, no_flash
    ; fade-out: * min(1, (end - frame) / 64); flash: + max(0, flash - frame / 12)
    g.ld g16, g15, 1                ; [flash | fade end frame] (word 21)
    g.li g19, 16
    g.shl g20, g16, g19
    g.itof g17, g12
    g.fsub g20, g20, g17
    g.fli g19, 0.015625
    g.fmul g20, g20, g19
    g.fmin g20, g20, g25
    g.fmax g20, g20, g0
    g.vscale g9, g9, g20
    g.li g19, 0xffff0000
    g.and g16, g16, g19
    g.fli g19, 0.083984375
    g.fmul g19, g19, g17
    g.fsub g16, g16, g19
    g.fmax g16, g16, g0
    g.fadd g9, g9, g16
    g.fadd g10, g10, g16
    g.fadd g11, g11, g16
no_flash:
    g.add g15, g15, g7
    g.ld g16, g15, 1
    g.bz g16, tnext
    ; alpha = clamp((frame - delay) / 24) * clamp((450 - frame) / 24)
    g.li g19, 28
    g.shr g19, g16, g19
    g.li g20, 5
    g.shl g19, g19, g20
    g.sub g19, g12, g19
    g.li g20, 450
    g.sub g20, g20, g12
    g.slt g17, g20, g19
    g.bz g17, t_min
    g.mov g19, g20
t_min:
    g.itof g22, g19
    g.fli g19, 0.0419921875
    g.fmul g22, g22, g19
    g.fmin g22, g22, g25
    g.fle g19, g22, g0
    g.bnz g19, tnext
    ; scale shift K, pixel width = 6 * length << K, left edge 80 - width / 2
    g.li g19, 24
    g.shr g23, g16, g19
    g.li g19, 15
    g.and g23, g23, g19
    g.li g19, 12
    g.shr g20, g16, g19
    g.li g19, 15
    g.and g20, g20, g19
    g.li g19, 6
    g.mul g20, g20, g19
    g.shl g20, g20, g23
    g.shr g19, g20, g6
    g.li g17, 80
    g.sub g17, g17, g19
    g.sub g17, g13, g17              ; x in the text box
    g.sltu g19, g17, g20
    g.bz g19, tnext
    g.li g19, 16
    g.shr g18, g16, g19
    g.li g19, 255
    g.and g18, g18, g19
    g.sub g18, g14, g18
    g.shr g18, g18, g23               ; glyph row (unsigned: above -> huge)
    g.li g19, 5
    g.sltu g19, g18, g19
    g.bz g19, tnext
    g.shr g17, g17, g23               ; font x
    g.itof g19, g17
    g.fli g20, 0.16666667  ; exact
    g.fmul g19, g19, g20
    g.ftoi g19, g19                 ; character
    g.li g20, 6
    g.mul g20, g19, g20
    g.sub g17, g17, g20               ; column 0..5
    g.li g20, 5
    g.sltu g20, g17, g20
    g.bz g20, tnext
    g.li g20, 4095
    g.and g20, g16, g20
    g.add g20, g20, g19
    g.ldb g20, g20, 1               ; glyph word offset
    g.li g19, 4
    g.mul g20, g20, g19
    g.ld g20, g20, 1
    g.add g18, g18, g6
    g.li g19, 5
    g.mul g18, g18, g19
    g.add g18, g18, g17
    g.shr g20, g20, g18
    g.and g20, g20, g6
    g.bz g20, tnext
    ; letters: mix towards warm white
    g.fsub g19, g25, g22
    g.vscale g9, g9, g19
    g.fadd g9, g9, g22
    g.fadd g10, g10, g22
    g.fli g19, 0.84375
    g.fmul g19, g19, g22
    g.fadd g11, g11, g19
tnext:
    ; blend with the frame on screen (binding 3, sqrt gamma), gamma, store
    ; at row + 15
    g.li g19, 15
    g.add g14, g14, g19
    g.li g19, 160
    g.mul g14, g14, g19
    g.add g13, g14, g13
    g.li g19, 3
    g.mul g15, g13, g19
    g.uniform g23, U_TB
    g.mov g21, g19
tblend:
    g.ldb g20, g15, 3
    g.itof g20, g20
    g.fli g19, 0.00390625
    g.fmul g20, g20, g19
    g.fmul g20, g20, g20
    g.fsub g20, g20, g9
    g.fmul g20, g20, g23
    g.fadd g20, g20, g9
    g.mov g9, g10
    g.mov g10, g11
    g.sqrt g11, g20
    g.add g15, g15, g6
    g.sub g21, g21, g6
    g.bnz g21, tblend
    g.rgb g9, g13, 0
done:
    g.end
render_k_end:

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
    g.slt g2, g4, g0
    g.bz g2, t_pos
    g.add g4, g4, g1
t_pos:
    g.slt g2, g4, g1
    g.bnz g2, t_in
    g.sub g4, g4, g1
t_in:
    g.id g10, 5                  ; grid height = 4
    g.sltu g19, g0, g10
    g.mul g13, g10, g10
    g.li g14, 0xffff0000
    g.li g20, 5625
    g.fli g12, 1.0
    g.fli g11, 4.656613e-10      ; 2^-31 (exact)
    g.li g15, d_taps_end - d_taps
tap_loop:
    g.li g16, d_taps - 8 - d_song
    g.add g16, g16, g15
    g.ld g1, g16, 1                ; tap delay in samples
    g.sub g5, g4, g1
    g.slt g2, g5, g0             ; echoes of the loop's end at its start
    g.bz g2, tt_pos
    g.li g2, SONG
    g.add g5, g5, g2
tt_pos:
    ; musical position of TT: 16th step, bar, samples into step
    g.itof g1, g5
    g.itof g2, g20
    g.fdiv g1, g1, g2
    g.ftoi g2, g1
    g.mul g1, g2, g20
    g.sub g26, g5, g1
    g.shr g6, g2, g10
    g.shl g1, g6, g10
    g.sub g25, g2, g1             ; step in bar
    g.li g1, 31
    g.and g6, g6, g1           ; song loops every 32 bars
    g.ldb g29, g6, 1           ; bar flags live at data offset 0
    g.uniform g1, U_3
    g.and g22, g6, g1
    g.shl g22, g22, g10              ; (bar & 3) * 16
    g.li g23, d_voices - d_song
voice_loop:
    g.ldb g31, g23, 1             ; taps*8 | poly
    g.sltu g1, g31, g15
    g.bnz g1, next_voice
    g.add g16, g23, g19
    g.ldb g1, g16, 1
    g.and g1, g1, g29             ; voice enabled in this bar?
    g.bz g1, next_voice
    g.add g16, g16, g19
    g.ldb g17, g16, 1
    g.add g16, g16, g19
    g.ldb g8, g16, 1               ; trigger mask offset
    g.add g16, g16, g19
    g.ldb g9, g16, 1               ; note array offset
    g.and g1, g17, g13          ; four-bar pattern?
    g.bz g1, one_bar
    g.add g8, g8, g22
    g.add g9, g9, g22
one_bar:
    g.ld g3, g8, 1                ; trigger mask
    g.add g1, g25, g19
    g.shl g1, g19, g1
    g.sub g1, g1, g19
    g.and g2, g3, g1               ; triggers at or before POS
    g.bz g2, next_voice
    g.sub g3, g3, g2               ; triggers after POS
    g.shl g1, g19, g13
    g.or g3, g3, g1
    g.sub g1, g0, g3
    g.and g3, g3, g1               ; lowest later trigger
    g.itof g2, g2
    g.itof g3, g3
    g.uniform g1, U_23
    g.shr g2, g2, g1               ; 127 + j0 (float exponent of highest bit)
    g.shr g3, g3, g1               ; 127 + j1
    g.sub g3, g3, g2
    g.mul g27, g3, g20        ; note length in samples
    g.li g1, 127
    g.sub g2, g2, g1               ; j0
    g.sub g1, g25, g2
    g.mul g1, g1, g20
    g.add g21, g1, g26            ; samples since note on
    g.itof g28, g21
    g.add g9, g9, g2
    g.ldb g9, g9, 1               ; note byte
    g.and g1, g17, g19
    g.bnz g1, chord_rel
    g.bz g9, next_voice          ; absolute-note rest
chord_rel:
    g.uniform g1, U_7
    g.and g31, g31, g1             ; poly count
    g.mov g24, g0
poly_loop:
    ; ---- note number ----
    g.mov g1, g9
    g.and g2, g17, g19
    g.bz g2, abs_note
    g.add g1, g9, g24
    g.uniform g2, U_7
    g.and g1, g1, g2
    g.shr g2, g22, g19
    g.add g1, g1, g2
    g.li g2, d_chords - d_song
    g.add g1, g1, g2
    g.ldb g1, g1, 1
abs_note:
    g.add g2, g16, g19
    g.ldb g2, g2, 1               ; base note (+36 bias, folded into pitch constant)
    g.add g1, g1, g2
    g.li g2, d_trans - d_song
    g.add g2, g2, g6
    g.ldb g2, g2, 1               ; key of the bar
    g.add g1, g1, g2
    ; ---- phase increment = 2^((16n + j)/192 + c) ----
    g.shl g1, g1, g10
    g.add g1, g1, g24
    g.itof g1, g1
    g.fli g2, 0.0052083333       ; 1/192 (exact)
    g.fmul g1, g1, g2
    g.ftoi g3, g1
    g.itof g2, g3
    g.fsub g1, g1, g2
    g.fli g2, 0.07738064  ; exact
    g.fmul g2, g2, g1
    g.fli g8, 0.22694011  ; exact
    g.fadd g2, g2, g8
    g.fmul g2, g2, g1
    g.fli g8, 0.69543002  ; exact
    g.fadd g2, g2, g8
    g.fmul g2, g2, g1
    g.fadd g2, g2, g12
    g.uniform g1, U_23
    g.shl g3, g3, g1
    g.add g2, g2, g3
    g.ftoi g18, g2
    g.mul g18, g18, g21          ; carrier phase
    ; ---- modulator: sin(ratio * phase + 90deg) ----
    g.li g1, 5
    g.shr g1, g17, g1
    g.mul g2, g18, g1
    g.bnz g1, fm_ratio
    g.li g2, 0x40000000          ; ratio 0: constant modulator -> pitch sweep
fm_ratio:
    g.itof g2, g2
    g.fsub g3, g0, g2
    g.fmax g3, g3, g2
    g.fmul g3, g3, g11
    g.fsub g3, g3, g12
    g.fmul g2, g2, g3
    g.add g8, g16, g10
    g.ld g9, g8, 1                ; [index*2^-3 | index decay]
    g.shl g1, g9, g13
    g.fmul g1, g1, g28
    g.fadd g1, g1, g12
    g.fmul g1, g1, g1
    g.fmul g1, g1, g1              ; (1 + k t)^4
    g.and g3, g9, g14
    g.fmul g3, g3, g2
    g.fdiv g3, g3, g1
    g.ftoi g3, g3
    g.shl g3, g3, g10
    g.add g18, g18, g3
    ; ---- carrier ----
    g.itof g2, g18
    g.fsub g3, g0, g2
    g.fmax g3, g3, g2
    g.fmul g3, g3, g11
    g.fsub g3, g3, g12
    g.fmul g2, g2, g3
    ; ---- noise mix ----
    g.add g8, g8, g10
    g.add g8, g8, g10
    g.ld g9, g8, 1                ; [gain*2^-31 | noise]
    g.shl g3, g9, g13
    g.bz g3, no_noise
    g.li g1, 0x9E3779B1
    g.mul g1, g5, g1
    g.mul g1, g1, g1
    g.itof g1, g1
    g.fsub g1, g1, g2
    g.fmul g1, g1, g3
    g.fadd g2, g2, g1
no_noise:
    g.and g9, g9, g14
    g.fmul g2, g2, g9
    ; ---- envelope: min(1, attack ramp, release ramp) / (1 + k t)^4 ----
    g.sub g8, g8, g10
    g.ld g9, g8, 1                ; [amp decay | attack rate]
    g.shl g1, g9, g13
    g.fmul g1, g1, g28
    g.sub g3, g27, g21
    g.itof g3, g3
    g.fli g8, 0.0040283203125
    g.fmul g3, g3, g8
    g.fmin g1, g1, g3
    g.fmin g1, g1, g12
    g.fmul g2, g2, g1
    g.and g1, g9, g14
    g.fmul g1, g1, g28
    g.fadd g1, g1, g12
    g.fmul g1, g1, g1
    g.fmul g1, g1, g1
    g.fdiv g2, g2, g1
    ; ---- sidechain duck (voice mode bit 2 and kick flag bit 2) ----
    g.and g1, g17, g29
    g.and g1, g1, g10
    g.bz g1, no_duck
    g.uniform g1, U_3
    g.and g1, g25, g1
    g.mul g1, g1, g20
    g.add g1, g1, g26
    g.itof g1, g1
    g.fli g3, 0.0001201629638671875
    g.fmul g1, g1, g3
    g.fli g3, 0.25
    g.fadd g1, g1, g3
    g.fmin g1, g1, g12
    g.fmul g2, g2, g1
no_duck:
    ; ---- tap gain / pan, accumulate mid & side ----
    g.li g8, d_taps - 4 - d_song
    g.add g8, g8, g15
    g.ld g9, g8, 1                ; [gain | pan]
    g.and g1, g9, g14
    g.fmul g2, g2, g1
    g.fadd g7, g7, g2
    g.shl g9, g9, g13
    g.fmul g1, g9, g2
    g.fadd g30, g30, g1
    g.add g24, g24, g19
    g.sub g1, g24, g31
    g.bnz g1, poly_loop
next_voice:
    g.li g1, 20
    g.add g23, g23, g1
    g.li g1, d_voices_end - d_song
    g.sub g1, g23, g1
    g.bnz g1, voice_loop
next_tap:
    g.sub g15, g15, g10
    g.sub g15, g15, g10
    g.bnz g15, tap_loop
    ; ---- output ----
    g.fadd g1, g7, g30
    g.fsub g2, g7, g30
    ; soft limiter x / sqrt(1 + x^2)
    g.fmul g3, g1, g1
    g.fadd g3, g3, g12
    g.rsqrt g3, g3
    g.fmul g1, g1, g3
    g.fmul g3, g2, g2
    g.fadd g3, g3, g12
    g.rsqrt g3, g3
    g.fmul g2, g2, g3
    g.id g16, 2
    g.mul g16, g16, g10
    g.add g16, g16, g16
    g.st g1, g16, 0
    g.add g16, g16, g10
    g.st g2, g16, 0
    g.end
spu_k_end:

; ---- include song.s ----
; ---------------------------------------------------------------------
; Song (SPU binding 1 = d_song .. d_song_end)
; 128 BPM, 16th = 5625 samples, bar = 16 steps, 32 bars = 60 s, looping.
; D minor: Dm | Bb | F | C; the Schottky section (bars 24-27) a whole step up.
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
    .byte 0x20,0x20,0x28,0x28   ; flat space: pad, arp
    .byte 0x29,0x29,0x29,0xA9   ; space curves: bass; roll
    .byte 0xBF,0x3F,0x3F,0x3F   ; {4,3,5}: drums, chip lead
    .byte 0xFF,0x7F,0x7F,0x7F   ; {5,3,4}: big lead
    .byte 0xB8,0x38,0x38,0xB8   ; {4,3,6}: breakdown; roll
    .byte 0xFF,0x7F,0x7F,0x7F   ; the limit set opens: drop
    .byte 0xFF,0x7F,0x7F,0x7F   ; Schottky: a whole step up
    .byte 0xA8,0x28,0x28,0x20   ; outro
d_trans:
    .byte 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0
    .byte 0,0,0,0, 0,0,0,0, 2,2,2,2, 0,0,0,0
; trigger masks, 16-byte rows: [lead bar k] [crash bar k] [roll bar k] [1-bar]
p_lead:  .word 0x6949
p_crash: .word 0x0001
p_roll:  .word 0
p_kick:  .word 0x1111
         .word 0x4941, 0, 0
p_snare: .word 0x1010
         .word 0x6949, 0, 0
p_hat:   .word 0xFFFF
         .word 0x4941, 0, 0xFF55
p_bass:  .word 0xEEEE
p_arp:   .word 0xFFFF
p_pad:   .word 0x0001
; lead notes: 4 bars x 16 steps (MIDI, 0 = rest)
n_lead:
    .byte 69,0,0,74, 0,0,76,0, 77,0,0,76, 0,74,72,0
    .byte 74,0,0,0, 0,0,70,0, 69,0,0,65, 0,0,67,0
    .byte 69,0,0,72, 0,0,77,0, 81,0,0,79, 0,77,76,0
    .byte 76,0,0,0, 0,0,74,0, 72,0,0,67, 0,0,69,0
; chord-relative notes: degree 0..7 (two octaves of 4 chord tones)
n_bass:  .byte 0,0,4,0, 0,0,4,0, 0,0,4,0, 0,0,4,0
n_arp:   .byte 0,1,2,3, 4,5,6,7, 6,5,4,3, 2,3,4,5
n_zero:  .byte 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0
; chords, 8 tones each: Dm Bb F C
d_chords:
    .byte 50,53,57,62, 62,65,69,74
    .byte 46,50,53,58, 58,62,65,70
    .byte 53,57,60,65, 65,69,72,77
    .byte 48,52,55,60, 60,64,67,72
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
    .byte 73, 0x08, 0x65, p_arp-d_song, n_arp-d_song, 36+198, 0, 0
    .word 0x3da037e0 ; bf 0.078125, 0.000026702880859375
    .word 0x38303c50 ; bf 0.000041961669921875, 0.0126953125
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
    .byte 27, 0x20, 0x25, p_pad-d_song, n_zero-d_song, 48+198, 0, 0
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
; GPU data (binding 1): the cube table at offset 0 (the renderer tests
; for it), the font within the first 1 KB, cell tables, scenes
; ---------------------------------------------------------------------
.align 4
d_base:
; ---- include cells.s ----
; generated by limit/cells.py -- face normals (6 x vec3) + Gram rows (6 x 6)
c_cube:
    .float 1, 0, 0  ; exact
    .float 0, 1, 0  ; exact
    .float 0, 0, 1  ; exact
    .float 0, 0, 0  ; exact
    .float 0, 0, 0  ; exact
    .float 0, 0, 0  ; exact
    .float 1, 0, 0, 0, 0, 0  ; exact
    .float 0, 1, 0, 0, 0, 0  ; exact
    .float 0, 0, 1, 0, 0, 0  ; exact
    .float 0, 0, 0, 0, 0, 0  ; exact
    .float 0, 0, 0, 0, 0, 0  ; exact
    .float 0, 0, 0, 0, 0, 0  ; exact
c_dodec:
    .float 1, 0, 0  ; exact
    .float -0.4472136, 0.89442719, 0  ; exact
    .float 0.4472136, 0.7236068, -0.52573111  ; exact
    .float -0.4472136, -0.7236068, -0.52573111  ; exact
    .float 0.4472136, -0.2763932, -0.85065081  ; exact
    .float 0.4472136, -0.2763932, 0.85065081  ; exact
    .float 1, -0.4472136, 0.4472136, -0.4472136, 0.4472136, 0.4472136  ; exact
    .float -0.4472136, 1, 0.4472136, -0.4472136, -0.4472136, -0.4472136  ; exact
    .float 0.4472136, 0.4472136, 1, -0.4472136, 0.4472136, -0.4472136  ; exact
    .float -0.4472136, -0.4472136, -0.4472136, 1, 0.4472136, -0.4472136  ; exact
    .float 0.4472136, -0.4472136, 0.4472136, 0.4472136, 1, -0.4472136  ; exact
    .float 0.4472136, -0.4472136, -0.4472136, -0.4472136, -0.4472136, 1  ; exact

; ---- include font.s ----
; generated by limit/font.py -- 5x5 glyphs (bit (row+1)*5+col), strings of glyph word offsets
d_font:
    .word 0x00000000 ; ' '
    .word 0x3e108420 ; 'L'
    .word 0x3e4213e0 ; 'I'
    .word 0x231aee20 ; 'M'
    .word 0x084213e0 ; 'T'
    .word 0x1f0707c0 ; 'S'
    .word 0x3e1787e0 ; 'E'
    .word 0x18431180 ; '{'
    .word 0x210fc620 ; '4'
    .word 0x04400000 ; ','
    .word 0x1f0741e0 ; '3'
    .word 0x1f0787e0 ; '5'
    .word 0x0c4610c0 ; '}'
    .word 0x1d1785c0 ; '6'
    .word 0x00aaa800 ; '~'
    .word 0x1d18c5c0 ; 'O'
    .word 0x0217c5e0 ; 'P'
    .word 0x1d18c620 ; 'U'
s_title: ; "LIMIT SET"
    .byte 109, 110, 111, 110, 112, 108, 113, 114, 112
s_435: ; "{4,3,5}"
    .byte 115, 116, 117, 118, 117, 119, 120
s_534: ; "{5,3,4}"
    .byte 115, 119, 117, 118, 117, 116, 120
s_436: ; "{4,3,6}"
    .byte 115, 116, 117, 118, 117, 121, 120
s_43i: ; "{4,3,~}"
    .byte 115, 116, 117, 118, 117, 122, 120
s_opus: ; "OPUS"
    .byte 123, 124, 125, 113

; ---- include scenes.s ----
; generated by limit/scenes.py -- scene records: [field mask] + changed block words
.align 4
scenes:
    ; scene 0: 23 fields
    .word 0x7fffff
    .word c_cube - d_base
    .word 0x3e613e61 ; bf 0.22, 0.22
    .word 0x3e183d50 ; bf 0.1484375, 0.05078125
    .word 0x3dd03e50 ; bf 0.1015625, 0.203125
    .word 0x00003dd0 ; bf 0, 0.1015625
    .word 0x3e803c00 ; bf 0.25, 0.0078125
    .word 0x3cf03ca0 ; bf 0.029296875, 0.01953125
    .word 0x3c203c20 ; bf 0.009765625, 0.009765625
    .word 0x3d503d50 ; bf 0.05078125, 0.05078125
    .word 0x3a003a00 ; bf 0.00048828125, 0.00048828125
    .word 0x3f503f50 ; bf 0.8125, 0.8125
    .word 0x3f183f18 ; bf 0.59375, 0.59375
    .word 0x37283728 ; bf 0.000010013580322265625, 0.000010013580322265625
    .word 0x3a803a80 ; bf 0.0009765625, 0.0009765625
    .word 0x3ca03fa0 ; bf 0.01953125, 1.25
    .word 0x00000000 ; bf 0, 0
    .word 0x3da03da0 ; bf 0.078125, 0.078125
    .word 0x3e983e98 ; bf 0.296875, 0.296875
    .word 0x3f700000 ; bf 0.9375, 0
    .word 0x3e983ed0 ; bf 0.296875, 0.40625
    .word 0x3f183d70 ; bf 0.59375, 0.05859375
    .word 0x00004480 ; bf 0, 1024
    .word 0x21289000 + s_title - d_base
    ; scene 1: 18 fields
    .word 0x5d7fbe
    .word 0x3e613f08 ; bf 0.22, 0.530638
    .word 0x3d503e80 ; bf 0.05078125, 0.25
    .word 0x3e500000 ; bf 0.203125, 0
    .word 0x3dd0bdd0 ; bf 0.1015625, -0.1015625
    .word 0x40713c00 ; bf 3.765625, 0.0078125
    .word 0x3c203d10 ; bf 0.009765625, 0.03515625
    .word 0x3d503d90 ; bf 0.05078125, 0.0703125
    .word 0x3a003ca0 ; bf 0.00048828125, 0.01953125
    .word 0x3f503f60 ; bf 0.8125, 0.875
    .word 0x3f183f60 ; bf 0.59375, 0.875
    .word 0x37283a80 ; bf 0.000010013580322265625, 0.0009765625
    .word 0x3a803d70 ; bf 0.0009765625, 0.05859375
    .word 0x3fa03fd0 ; bf 1.25, 1.625
    .word 0x3da03e98 ; bf 0.078125, 0.296875
    .word 0x3f703a80 ; bf 0.9375, 0.0009765625
    .word 0x3ed03ed0 ; bf 0.40625, 0.40625
    .word 0x3f503d50 ; bf 0.8125, 0.05078125
    .word 0xa0607000 + s_435 - d_base
    ; scene 2: 20 fields
    .word 0x6dfffe
    .word 0x3f083f08 ; bf 0.530638, 0.530638
    .word 0x3e98be50 ; bf 0.296875, -0.203125
    .word 0x3dd03e98 ; bf 0.1015625, 0.296875
    .word 0x3e98bed0 ; bf 0.296875, -0.40625
    .word 0x3f083d1b ; bf 0.53063753, 0.037734224
    .word 0x3dd03d50 ; bf 0.1015625, 0.05078125
    .word 0x3d103d10 ; bf 0.03515625, 0.03515625
    .word 0x3d703d70 ; bf 0.05859375, 0.05859375
    .word 0x3ca03ca0 ; bf 0.01953125, 0.01953125
    .word 0x3f603f60 ; bf 0.875, 0.875
    .word 0x3f603f60 ; bf 0.875, 0.875
    .word 0x3aa03aa0 ; bf 0.001220703125, 0.001220703125
    .word 0x3da03da0 ; bf 0.078125, 0.078125
    .word 0x3fe03fe0 ; bf 1.75, 1.75
    .word 0x3f003f00 ; bf 0.5, 0.5
    .word 0x3ea83ea8 ; bf 0.328125, 0.328125
    .word 0x3ed03950 ; bf 0.40625, 0.0001983642578125
    .word 0x3f003e98 ; bf 0.5, 0.296875
    .word 0x3f804480 ; bf 1, 1024
    .word 0x00607000 + s_435 - d_base
    ; scene 3: 13 fields
    .word 0x5d303f
    .word c_dodec - d_base
    .word 0x3f4f3f4f ; bf 0.808461, 0.808461
    .word 0x3e50bdd0 ; bf 0.203125, -0.1015625
    .word 0x3e183e80 ; bf 0.1484375, 0.25
    .word 0x3dd0be50 ; bf 0.1015625, -0.203125
    .word 0x3f4f3ceb ; bf 0.80846083, 0.028745274
    .word 0x39a039a0 ; bf 0.00030517578125, 0.00030517578125
    .word 0x3df03df0 ; bf 0.1171875, 0.1171875
    .word 0x3e183e18 ; bf 0.1484375, 0.1484375
    .word 0x3df038d0 ; bf 0.1171875, 0.00009918212890625
    .word 0x3f503f00 ; bf 0.8125, 0.5
    .word 0x3e503d50 ; bf 0.203125, 0.05078125
    .word 0x00607000 + s_534 - d_base
    ; scene 4: 13 fields
    .word 0x5da03f
    .word c_cube - d_base
    .word 0x3f293f29 ; bf 0.658479, 0.658479
    .word 0x3f603f80 ; bf 0.875, 1
    .word 0x3f603f88 ; bf 0.875, 1.0625
    .word 0x00003f80 ; bf 0, 1
    .word 0x3f293cc0 ; bf 0.65847895, 0.023412585
    .word 0x3e503e50 ; bf 0.203125, 0.203125
    .word 0x00000000 ; bf 0, 0
    .word 0x3e803e80 ; bf 0.25, 0.25
    .word 0x3f1038d0 ; bf 0.5625, 0.00009918212890625
    .word 0x3e983ed0 ; bf 0.296875, 0.40625
    .word 0x3f803d50 ; bf 1, 0.05078125
    .word 0x00607000 + s_436 - d_base
    ; scene 5: 15 fields
    .word 0x5db2be
    .word 0x3f393f62 ; bf 0.724537, 0.881374
    .word 0x3f003e98 ; bf 0.5, 0.296875
    .word 0x3f003f18 ; bf 0.5, 0.59375
    .word 0x3f00be98 ; bf 0.5, -0.296875
    .word 0x3e9a3d0f ; bf 0.3, 0.035
    .word 0x3d103ca0 ; bf 0.03515625, 0.01953125
    .word 0x3c203c20 ; bf 0.009765625, 0.009765625
    .word 0x39503950 ; bf 0.0001983642578125, 0.0001983642578125
    .word 0x3dd03dd0 ; bf 0.1015625, 0.1015625
    .word 0x3f003f00 ; bf 0.5, 0.5
    .word 0x3e183e18 ; bf 0.1484375, 0.1484375
    .word 0x3e6039a0 ; bf 0.21875, 0.00030517578125
    .word 0x3f983f60 ; bf 1.1875, 0.875
    .word 0x3f003ca0 ; bf 0.5, 0.01953125
    .word 0x00607000 + s_43i - d_base
    ; scene 6: 17 fields
    .word 0x5d3fbe
    .word 0x3f523f66 ; bf 0.82, 0.9
    .word 0x3f603f90 ; bf 0.875, 1.125
    .word 0x3f903f50 ; bf 1.125, 0.8125
    .word 0x00003f00 ; bf 0, 0.5
    .word 0x3e9a0000 ; bf 0.3, 0
    .word 0x38d038d0 ; bf 0.00009918212890625, 0.00009918212890625
    .word 0x38d038d0 ; bf 0.00009918212890625, 0.00009918212890625
    .word 0x3d503d50 ; bf 0.05078125, 0.05078125
    .word 0x3f303f30 ; bf 0.6875, 0.6875
    .word 0x3ed03ed0 ; bf 0.40625, 0.40625
    .word 0x3ac03ac0 ; bf 0.00146484375, 0.00146484375
    .word 0x3ed03ed0 ; bf 0.40625, 0.40625
    .word 0x3e503e50 ; bf 0.203125, 0.203125
    .word 0x3f103a00 ; bf 0.5625, 0.00048828125
    .word 0x3cf03d50 ; bf 0.029296875, 0.05078125
    .word 0x3e183e98 ; bf 0.1484375, 0.296875
    .word 0
    ; scene 7: 14 fields
    .word 0x7dd03e
    .word 0x3f6e3f48 ; bf 0.93, 0.78
    .word 0x3e98be50 ; bf 0.296875, -0.203125
    .word 0xbed03f00 ; bf -0.40625, 0.5
    .word 0x00003e50 ; bf 0, 0.203125
    .word 0xc0130000 ; bf -2.3, 0
    .word 0x3e003e00 ; bf 0.125, 0.125
    .word 0x3f983f98 ; bf 1.1875, 1.1875
    .word 0x00000000 ; bf 0, 0
    .word 0x3e803e80 ; bf 0.25, 0.25
    .word 0x3f1839a0 ; bf 0.59375, 0.00030517578125
    .word 0x3e503e98 ; bf 0.203125, 0.296875
    .word 0x3f180000 ; bf 0.59375, 0
    .word 0x3f8043e0 ; bf 1, 448
    .word 0x615c4000 + s_opus - d_base

pblock:                         ; the current scene's parameters (23 words)
    .word 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
d_end:

; MMIO configuration script: [dest, count, words...], 0 terminates
cfg:
    .word 0xf3000, 4, render_k, render_k_end - render_k, 160, 30
    .word 0xf3040, 15, FB0, 57600, 3, 0, d_base, d_end - d_base, 1, 0, 0, 0, 0, 0, FB1, 57600, 1
    .word 0xf6040, 5, spu_k, spu_k_end - spu_k, 64, 4, AOUT
    .word 0xf6100, 7, AOUT, 2048, 3, 0, d_song, d_song_end - d_song, 1
    .word 0xf6204, 3, 7, 23, 3
    .word 0xf6000, 1, 1
    .word 0xf5004, 4, 480, 4, 0, 1
    .word 0

