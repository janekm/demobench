; =====================================================================
;  CARPET -- a procedural island world and a ray-marched carpet flight,
;  in homage to Bullfrog's Magic Carpet (1994). DB32 dynamic-1, packed:
;  the whole program is a compressed image unpacked to 0x2E380.
;  Per frame: terrain pass (heightmap), then the ray-marched frame.
;  RAM: two 160x120 RGB888 pages drawn letterboxed (rows 12..107); the
;  second page starts at the first one's bottom bar, so they share 12
;  black rows and 5760 bytes: 0x10000-0x2AB80. Heightmap 0x2AB80-0x2DB80,
;  SPU output 0x2DB80-0x2E380, program image 0x2E380-0x30000.
; =====================================================================
.profile dynamic-1
.entry start
.equ FB0,   0x10000
.equ FB1,   0x1CA80           ; FB0 + 108 rows
.equ HMAP,  0x2AB80           ; 128 x 96 heightmap (bytes)
.equ AOUT,  0x2DB80

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
    lui r10, 0x10               ; FB0
    li r11, FB1
    addi r8, r0, 2880           ; the flight loops every 48 s
frame:
    lw r1, 24(r14)
    sub r1, r1, r9              ; frames since the loop started
    blt r1, r8, inloop
    add r9, r9, r8
    sub r1, r1, r8
inloop:
    sw r1, 0x100(r13)           ; U0 = frame within the loop
    addi r2, r0, 800
    mul r2, r9, r2
    sw r2, 0x3200(r13)          ; SPU U0 (0xf6200) = first sample of the loop
    ; prep: heightmap (b1) writable
    addi r1, r0, 3
    sw r1, 0x58(r13)
    li r1, h_prep
    jal r7, pass
    ; render: b0 = back buffer rows 12..107, heightmap read-only
    addi r3, r10, 5760
    sw r3, 0x40(r13)
    addi r3, r0, 1
    sw r3, 0x58(r13)
    jal r7, pass                ; (r1 = h_full: the header after h_prep)
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

; pass(r1 = [code, len, w, h]): dispatch and wait
pass:
    add r2, r13, r0
    addi r3, r0, 4
    jal r15, copy
    addi r2, r0, 1
    sw r2, 16(r13)
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

; ---- include gen.s ----
; ---------------------------------------------------------------------
; Terrain: 128 x 96 byte heightmap (binding 1) from 6 octaves of value
; noise, pushed under the sea towards the map edges, peaks sharpened.
; ---------------------------------------------------------------------

gen:
    g.li g26, 1
    g.li g16, 0x8DA6B343
    g.li g17, 0xD8163841
    g.li g18, 0x2C1B3C6D
    g.li g19, 8
    g.li g20, 15
    g.fli g21, 3.0
    g.fli g22, 1.0
    g.fli g23, 4096.0  ; exact
    g.fli g24, 1.703125
    g.fli g25, 0.5
    g.id g1, 0
    g.id g2, 1
    g.itof g1, g1
    g.itof g2, g2
    g.fli g14, 0.0400390625
    g.fmul g3, g1, g14
    g.fmul g4, g2, g14
    g.mov g5, g0
    g.fli g6, 2.9802322e-08    ; 0.5 / 2^24
    g.mov g8, g0
    g.li g7, 6
octave:
    g.fadd g14, g3, g23
    g.ftoi g11, g14
    g.itof g9, g11
    g.fsub g9, g14, g9
    g.fadd g14, g4, g23
    g.ftoi g12, g14
    g.itof g10, g12
    g.fsub g10, g14, g10
    g.mul g11, g11, g16
    g.mul g12, g12, g17
    g.add g11, g11, g12
    g.add g11, g11, g8
    g.fadd g14, g9, g9            ; smoothstep weights
    g.fsub g14, g21, g14
    g.fmul g14, g14, g9
    g.fmul g9, g14, g9
    g.fadd g14, g10, g10
    g.fsub g14, g21, g14
    g.fmul g14, g14, g10
    g.fmul g10, g14, g10
    g.li g27, 2                   ; two rows of two corners
row:
    ; <hash A, C>
    g.shr g14, g11, g20
    g.xor g14, g14, g11
    g.mul g14, g14, g18
    g.shr g14, g14, g19
    g.itof g12, g14
    g.add g13, g11, g16
    ; <hash B, B>
    g.shr g14, g13, g20
    g.xor g14, g14, g13
    g.mul g14, g14, g18
    g.shr g14, g14, g19
    g.itof g13, g14
    g.fsub g13, g13, g12
    g.fmul g13, g13, g9
    g.mov g15, g28
    g.fadd g28, g12, g13
    g.add g11, g11, g17
    g.sub g27, g27, g26
    g.bnz g27, row
    g.fsub g12, g28, g15
    g.fmul g12, g12, g10
    g.fadd g12, g15, g12
    g.fmul g12, g12, g6
    g.fadd g5, g5, g12
    ; next octave: rotate by 30 degrees, scale by 2
    g.fmul g14, g3, g24
    g.fadd g14, g14, g4
    g.fmul g4, g4, g24
    g.fsub g4, g4, g3
    g.mov g3, g14
    g.fmul g6, g6, g25
    g.add g8, g8, g18
    g.sub g7, g7, g26
    g.bnz g7, octave
    ; islands: fade to sea floor within 14 cells of the map edge
    g.fli g14, 127.0  ; exact
    g.fsub g14, g14, g1
    g.fmul g14, g14, g1
    g.fli g15, 95.0  ; exact
    g.fsub g15, g15, g2
    g.fmul g15, g15, g2
    g.fmul g14, g14, g15
    g.fli g15, 2.7939677238464355e-07
    g.fmul g14, g14, g15
    g.fmin g14, g14, g22           ; edge mask
    g.fli g15, 0.359375
    g.fsub g5, g5, g15
    g.fmul g5, g5, g14
    g.fli g15, 0.150390625
    g.fsub g5, g5, g15             ; h = m (n - 0.32) - 0.15
    g.fmax g14, g5, g0
    g.fmul g14, g14, g14
    g.fli g15, 4.0
    g.fmul g14, g14, g15
    g.fadd g5, g5, g14              ; sharpen peaks
    g.fli g15, 255.0  ; exact
    g.fmul g5, g5, g15
    g.fli g14, 70.0
    g.fadd g5, g5, g14
    ; volcano at (94, 64): rises from 20 s to 26 s into the loop; its top
    ; clips at 255 into a flat crater (lava in the renderer)
    g.uniform g14, 0
    g.itof g14, g14
    g.fli g12, 0.002777099609375
    g.fmul g14, g14, g12
    g.fli g12, 3.34375
    g.fsub g14, g14, g12
    g.fmax g14, g14, g0
    g.fmin g14, g14, g22
    g.fli g12, 94.0
    g.fsub g12, g1, g12
    g.fmul g12, g12, g12
    g.fli g13, 64.0
    g.fsub g13, g2, g13
    g.fmul g13, g13, g13
    g.fadd g12, g12, g13
    g.fli g13, 0.015625
    g.fmul g12, g12, g13
    g.fsub g12, g22, g12
    g.fmax g12, g12, g0
    g.fmul g12, g12, g12
    g.fmul g12, g12, g14
    g.fli g13, 260.0
    g.fmul g12, g12, g13
    g.fadd g5, g5, g12
    g.fmax g5, g5, g0
    g.fmin g5, g5, g15
    g.ftoi g5, g5
    g.id g12, 2
    g.stb g5, g12, 1
    g.end
gen_end:

; ---- include render.s ----
; ---------------------------------------------------------------------
; Renderer, one invocation per pixel; frame count in uniform 0.
; Binding 0: frame buffer, binding 1: heightmap, binding 3: tables.
; ---------------------------------------------------------------------
render_k:
; ---- include cam.s ----
; ---------------------------------------------------------------------
; Camera, evaluated by every pixel: uniform cubic B-spline through the
; looping waypoint table (x, z, y/10 bytes; binding 3), sampled at s,
; s+.1, s+.2 for position, heading and banking (from the lateral
; acceleration). Leaves the unit ray in g1..g3, the eye in g4..g6.
; ---------------------------------------------------------------------
    g.li g28, 1
    g.li g30, 2
    g.fli g29, 1.0
    g.uniform g31, 0
    g.itof g31, g31
    g.fli g22, 0.0072916667       ; 21 waypoints per 2880 frames (exact)
    g.fmul g13, g31, g22
    g.li g21, 3
samp:
    g.ftoi g19, g13
    g.itof g14, g19
    g.fsub g14, g13, g14
    g.fsub g15, g29, g14
    g.fmul g18, g15, g15
    g.fmul g15, g18, g15
    g.fmul g23, g14, g14              ; u^2
    g.fmul g18, g23, g14             ; u^3
    g.fli g22, 0.5  ; exact
    g.fmul g16, g18, g22
    g.fsub g16, g16, g23
    g.fli g22, 0.6666667  ; exact
    g.fadd g16, g16, g22            ; u^3/2 - u^2 + 2/3
    g.fli g22, 0.16666667  ; exact
    g.fmul g15, g15, g22            ; (1-u)^3 / 6
    g.fmul g18, g18, g22            ; u^3 / 6
    g.fsub g17, g29, g15
    g.fsub g17, g17, g16
    g.fsub g17, g17, g18
    g.vadd g1, g25, g25
    g.li g20, 4
cp:
    g.shl g24, g19, g30
    g.ldb g22, g24, 3
    g.itof g22, g22
    g.fmul g22, g22, g15
    g.fadd g1, g1, g22
    g.add g24, g24, g28
    g.ldb g22, g24, 3
    g.itof g22, g22
    g.fmul g22, g22, g15
    g.fadd g3, g3, g22
    g.add g24, g24, g28
    g.ldb g22, g24, 3
    g.itof g22, g22
    g.fmul g22, g22, g15
    g.fadd g2, g2, g22
    g.add g19, g19, g28
    g.mov g15, g16
    g.mov g16, g17
    g.mov g17, g18
    g.sub g20, g20, g28
    g.bnz g20, cp
    g.vadd g4, g7, g25
    g.vadd g7, g10, g25
    g.vadd g10, g1, g25
    g.fli g22, 0.099609375
    g.fadd g13, g13, g22
    g.sub g21, g21, g28
    g.bnz g21, samp
    g.vsub g13, g10, g4
    g.vadd g16, g10, g4
    g.vsub g16, g16, g7
    g.vsub g16, g16, g7
    g.fmul g8, g8, g22        ; waypoint heights are in tenths (X = 0.1)
    g.fmul g14, g14, g22
    g.fmul g17, g17, g22
    g.norm3 g1, g13
    g.fli g22, -0.220703125              ; look slightly down
    g.fadd g2, g2, g22
    g.norm3 g1, g1
    g.mov g19, g3
    g.fsub g21, g0, g1
    g.norm3 g19, g19
    ; up = F x R
    g.fmul g25, g2, g21
    g.fmul g22, g3, g19
    g.fmul g23, g1, g21
    g.fsub g26, g22, g23
    g.fmul g27, g2, g19
    g.fsub g27, g0, g27
    ; bank into the turn: (c, s) = atan(k * lateral acceleration), scaled
    ; to one pixel; screen y grows downwards
    g.dot3 g22, g16, g19
    g.fli g23, 2.203125
    g.fmul g17, g22, g23
    g.mov g16, g29
    g.mov g18, g0
    g.norm3 g16, g16
    g.fli g22, 0.010009765625
    g.vscale g16, g16, g22
    g.vscale g13, g19, g16
    g.vscale g10, g25, g17
    g.vadd g13, g13, g10             ; R' = c R + s U
    g.vscale g25, g25, g16
    g.vscale g10, g19, g17
    g.vsub g25, g10, g25           ; U' = s R - c U
    ; F' = F - 80 R' - 60 U': ray = F' + x R' + y U'
    g.fli g22, -80.0
    g.vscale g10, g13, g22
    g.vadd g1, g1, g10
    g.fli g22, -48.0
    g.vscale g10, g25, g22
    g.vadd g1, g1, g10
    ; this pixel's ray: D = F' + x R' + y U'; camera position -> g4..g6
    g.id g22, 0
    g.itof g22, g22
    g.vscale g13, g13, g22
    g.vadd g1, g1, g13
    g.id g23, 1
    g.itof g23, g23
    g.vscale g25, g25, g23
    g.vadd g1, g1, g25
    g.norm3 g1, g1
    g.vscale g4, g7, g29
    g.mov g12, g22                ; screen x, y for the carpet
    g.mov g13, g23

    ; ---- the carpet: a rippling rug below the rider, in screen space ----
    g.fli g29, 26.5
    g.fsub g14, g13, g29            ; rows below the rug's vanishing line
    g.flt g21, g14, g29
    g.bnz g21, nocarpet
    g.uniform g17, 0
    g.itof g17, g17
    g.fli g29, 0.150390625
    g.fmul g17, g17, g29
    g.fli g29, 60.0
    g.fdiv g15, g29, g14
    g.fadd g17, g17, g15           ; ripple phase: waves run back along the rug
    g.ftoi g21, g17
    g.itof g21, g21
    g.fsub g17, g17, g21
    g.fli g29, 0.5
    g.fsub g17, g17, g29
    g.fsub g21, g0, g17
    g.fmax g17, g17, g21            ; triangle wave 0..0.5
    g.fli g21, 0.099609375
    g.fmul g21, g17, g21
    g.fadd g21, g21, g29              ; eye height 0.5 .. 0.55
    g.fdiv g21, g21, g14
    g.fli g29, 100.0
    g.fmul g15, g21, g29             ; distance along the rug
    g.fli g29, 80.0
    g.fsub g16, g12, g29
    g.fmul g16, g16, g21
    g.fsub g21, g0, g16
    g.fmax g16, g16, g21          ; |x| across the rug
    g.fli g29, 0.359375
    g.fsub g18, g29, g16
    g.flt g21, g18, g0
    g.bnz g21, nocarpet
    g.fli g29, 1.15625
    g.fsub g21, g29, g15
    g.fmin g18, g18, g21            ; distance to the nearest edge
    ; gold: fringe threads, border line, medallion lattice
    g.fli g19, 0.71875
    g.fli g20, 0.4609375
    g.fli g21, 0.080078125
    g.flt g21, g18, g0
    g.bz g21, rug
    g.fli g29, -0.099609375
    g.flt g21, g18, g29
    g.bnz g21, nocarpet
    g.fli g29, 30.0
    g.fmul g29, g16, g29
    g.ftoi g29, g29
    g.and g29, g29, g28             ; (g28 = 1 from the camera)
    g.bnz g29, nocarpet           ; gaps between the threads
    g.jmp rugout
rug:
    g.fli g29, 0.044921875
    g.flt g21, g18, g29
    g.bnz g21, rugblue
    g.fli g29, 0.0703125
    g.flt g21, g18, g29
    g.bnz g21, rugout
    ; field: red, with a gold diamond lattice
    g.fli g29, 3.0
    g.fmul g21, g15, g29
    g.ftoi g29, g21
    g.itof g29, g29
    g.fsub g21, g21, g29
    g.fli g29, 0.5
    g.fsub g21, g21, g29
    g.fsub g29, g0, g21
    g.fmax g21, g21, g29
    g.fadd g21, g21, g16
    g.fadd g21, g21, g16
    g.fli g29, 0.19921875
    g.flt g21, g21, g29
    g.bnz g21, rugout
    g.fli g19, 0.359375
    g.fli g20, 0.0302734375
    g.fli g21, 0.0400390625
    g.jmp rugout
rugblue:
    g.fli g19, 0.0400390625
    g.fli g20, 0.060546875
    g.fli g21, 0.2578125
rugout:
    g.fli g29, 2.0
    g.fmul g17, g17, g29
    g.fli g29, 0.546875
    g.fadd g17, g17, g29            ; ripple shading
    g.vscale g18, g19, g17         ; -> COL
    g.jmp out
nocarpet:
    g.li g26, 1
    g.li g24, 7
    g.li g25, 127
    g.fli g22, 126.99  ; exact
    g.fli g23, 94.99  ; exact
    g.fli g27, 0.0498046875
    g.fli g28, 0.0302734375
    ; march in heightmap units: y in bytes (1 byte = 0.08 cells)
    g.fli g29, 12.5
    g.fmul g5, g5, g29
    g.fmul g11, g2, g29
    g.fli g29, 1.0058283805847168e-07
    g.fadd g11, g11, g29
    ; stop at the sea surface (going down) or above the highest peak
    g.fli g29, 256
    g.flt g31, g11, g0
    g.bz g31, ceiling
    g.fli g29, 70.5               ; sea level between two byte heights (exact)
ceiling:
    g.fsub g29, g29, g5
    g.fdiv g8, g29, g11
    g.fli g29, 60.0
    g.flt g21, g8, g29
    g.and g31, g31, g21         ; sea beyond the fog limit counts as sky
    g.fmin g8, g8, g29
    g.fli g7, 0.30078125
    g.mov g9, g7
    g.mov g10, g0
    g.mov g30, g0
march:
    g.fmul g12, g1, g7
    g.fadd g12, g12, g4
    g.fmul g14, g3, g7
    g.fadd g14, g14, g6
sample:                         ; bilinear height at (PX, PZ) -> H0
    g.fmax g12, g12, g0
    g.fmin g12, g12, g22
    g.fmax g14, g14, g0
    g.fmin g14, g14, g23
    g.ftoi g15, g12
    g.itof g19, g15
    g.fsub g19, g12, g19
    g.ftoi g21, g14
    g.itof g20, g21
    g.fsub g20, g14, g20
    g.shl g21, g21, g24
    g.add g21, g21, g15
    g.ldb g15, g21, 1
    g.add g21, g21, g26
    g.ldb g16, g21, 1
    g.add g21, g21, g25
    g.ldb g17, g21, 1
    g.add g21, g21, g26
    g.ldb g18, g21, 1
    g.itof g15, g15
    g.itof g16, g16
    g.itof g17, g17
    g.itof g18, g18
    g.fsub g16, g16, g15
    g.fmul g16, g16, g19
    g.fadd g15, g15, g16
    g.fsub g18, g18, g17
    g.fmul g18, g18, g19
    g.fadd g17, g17, g18
    g.fsub g17, g17, g15
    g.fmul g17, g17, g20
    g.fadd g15, g15, g17
    g.bnz g30, sampled
    g.fmul g13, g11, g7
    g.fadd g13, g13, g5
    g.fsub g13, g13, g15           ; height above the terrain
    g.flt g29, g13, g0
    g.bnz g29, hit
    g.mov g9, g7
    g.mov g10, g13
    g.fmul g29, g7, g28
    g.fadd g29, g29, g28
    g.fmul g13, g13, g27
    g.fmax g29, g29, g13
    g.fadd g7, g7, g29
    g.flt g29, g7, g8
    g.bnz g29, march
    ; nothing hit: sea surface when going down, else sky
    g.mov g7, g8
    g.jmp objects
hit:                            ; secant refinement between the last two samples
    g.fsub g29, g7, g9
    g.fsub g16, g10, g13
    g.fdiv g29, g29, g16
    g.fmul g29, g29, g10
    g.fadd g7, g9, g29
    g.li g31, -1
; ---- objects: castle towers (vertical cylinders), domes and mana orbs ----
; records (binding 3): x, z, y * 10, 4 * (radius * 10) + type (0 orb, 1 tower, 2 dome)
objects:
    g.mov g13, g0
    g.fli g12, 0.080078125
    g.fmul g9, g5, g12
    g.mov g8, g4
    g.mov g10, g6
    g.li g14, d_obj - d_base
    g.li g19, 18
    g.li g30, 3
objdec:
    g.ldb g15, g14, 3
    g.itof g15, g15
    g.add g21, g14, g26
    g.ldb g17, g21, 3
    g.itof g17, g17
    g.add g21, g21, g26
    g.ldb g16, g21, 3
    g.itof g16, g16
    g.fli g12, 0.099609375
    g.fmul g16, g16, g12
    g.add g21, g21, g26
    g.ldb g20, g21, 3
    g.and g29, g20, g30           ; type
    g.sub g28, g30, g26
    g.shr g20, g20, g28
    g.itof g18, g20
    g.fmul g18, g18, g12      ; radius
    g.bz g19, objshade
    g.sub g28, g29, g30             ; balloon: gone once the fireball hits
    g.bnz g28, notballoon
    g.uniform g28, 0
    g.li g27, 2448
    g.slt g28, g28, g27
    g.bz g28, onext
notballoon:
    g.sub g27, g29, g26
    g.bnz g27, osph
    g.mov g27, g16             ; tower: circle test in the horizontal plane
    g.mov g16, g9
    g.mov g28, g2
    g.mov g2, g0
    g.sphere g29, g8, g1, g15
    g.mov g2, g28
    g.fmul g28, g2, g29
    g.fadd g28, g28, g9
    g.flt g28, g27, g28
    g.bnz g28, onext             ; passes above the tower top
    g.jmp otest
osph:
    g.sphere g29, g8, g1, g15
otest:
    g.flt g28, g29, g0
    g.bnz g28, onext
    g.flt g28, g29, g7
    g.bz g28, onext
    g.mov g7, g29
    g.mov g13, g14
onext:
    g.add g14, g21, g26
    g.sub g19, g19, g26
    g.bnz g19, objdec
    ; ---- fire spell: a fireball from the carpet homes onto the balloon
    ; (39.6 - 40.8 s), then the blast grows and fades until 42 s ----
    g.mov g11, g0
    g.uniform g29, 0
    g.itof g29, g29
    g.fli g28, 2368
    g.fsub g29, g29, g28
    g.fli g28, 0.013916015625
    g.fmul g12, g29, g28             ; 0 at launch, 1 at impact
    g.flt g28, g12, g0
    g.bnz g28, nofire
    g.fli g28, 2.0
    g.flt g28, g12, g28
    g.bz g28, nofire
    g.fli g28, 1.0
    g.fmin g29, g12, g28
    g.fli g15, 108
    g.fli g16, 8.0
    g.fli g17, 17.5
    g.vsub g18, g15, g8
    g.fadd g19, g19, g28       ; launched from the carpet, a cell below the eye
    g.vscale g18, g18, g29
    g.vadd g15, g8, g18
    g.fsub g16, g16, g28
    g.fsub g29, g12, g28             ; blast: radius 0.4 + 5 (u - 1), fading
    g.fmax g29, g29, g0
    g.fsub g27, g28, g29
    g.fli g28, 5.0
    g.fmul g29, g29, g28
    g.fli g28, 0.3984375
    g.fadd g29, g29, g28
    g.fmul g29, g29, g29              ; R^2
    g.vsub g18, g15, g8           ; glow I R^2 / (d^2 + 0.3 R^2), d from the ray
    g.dot3 g28, g18, g1
    g.flt g21, g28, g0
    g.bnz g21, nofire
    g.flt g21, g7, g28              ; behind the terrain or an object
    g.bnz g21, nofire
    g.fmul g28, g28, g28
    g.dot3 g21, g18, g18
    g.fsub g21, g21, g28
    g.fli g28, 0.30078125
    g.fmul g28, g28, g29
    g.fadd g21, g21, g28
    g.fmul g29, g29, g27
    g.fdiv g11, g29, g21
nofire:
    g.bnz g13, shade
    g.bnz g31, surf
    g.jmp shade
surf:                           ; heights at P + x, P + z, P
    g.fmul g9, g1, g7
    g.fadd g9, g9, g4
    g.fmul g10, g3, g7
    g.fadd g10, g10, g6
    g.li g30, 3
    g.fli g29, 1.0
    g.fadd g12, g9, g29
    g.mov g14, g10
    g.jmp sample
sampled:
    g.mov g27, g28
    g.mov g28, g8
    g.mov g8, g15
    g.sub g30, g30, g26
    g.bz g30, shade
    g.sub g29, g30, g26
    g.itof g29, g29
    g.fadd g14, g10, g29
    g.mov g12, g9
    g.jmp sample
objshade:                       ; P = eye + t D; N from the centre; albedo
    g.vscale g21, g1, g7
    g.vadd g21, g21, g8
    g.vsub g12, g21, g15
    g.sub g29, g29, g26
    g.bnz g29, oround
    g.mov g13, g0               ; towers: horizontal normal
oround:
    g.norm3 g12, g12
    g.fli g31, 1.0             ; TYPE = FONE: object
    g.fli g18, 2.1875              ; gleaming gold orbs and domes
    g.fli g19, 1.40625
    g.fli g20, 0.3515625
    g.li g28, 2                  ; balloon: red
    g.sub g28, g29, g28
    g.bnz g28, notred
    g.fli g18, 0.90625
    g.fli g19, 0.080078125
    g.fli g20, 0.0498046875
notred:
    g.bnz g29, shade2
    g.fli g18, 0.421875             ; stone towers
    g.fli g19, 0.3984375
    g.fli g20, 0.359375
    g.jmp shade2
shade:
    g.bz g13, shade2
    g.mov g14, g13
    g.mov g19, g0
    g.jmp objdec
shade2:
    g.fli g24, 1.0
    g.vscale g4, g1, g24
    g.fli g1, 0.25
    g.fli g2, 0.421875
    g.fli g3, 0.75
    g.fli g15, 0.6015625
    g.fli g16, 0.5
    g.fli g17, 0.625
    g.fli g25, 0.90625
    g.fli g26, 0.71875
    g.mov g30, g24
    g.bz g31, skycol
    ; fog: t^2 / (t^2 + 2500)
    g.fmul g29, g7, g7
    g.fli g30, 0.000278472900390625   ; fog (t / 60)^2
    g.fmul g30, g29, g30
    g.sub g29, g31, g24
    g.bz g29, light
    ; normal from the three heights
    g.fsub g12, g8, g27
    g.fsub g14, g8, g28
    g.fli g29, 0.080078125
    g.fmul g12, g12, g29
    g.fmul g14, g14, g29
    g.mov g13, g24
    g.norm3 g12, g12
    g.slt g29, g31, g0
    g.bz g29, water
    ; terrain albedo: grass; rock on steep or high ground; sand at the shore
    g.fli g18, 0.099609375
    g.fli g19, 0.25
    g.fli g20, 0.0400390625
    g.fli g29, 4.625
    g.fli g28, 5.0
    g.fmul g28, g13, g28
    g.fsub g29, g29, g28              ; rock where N.y < 0.92
    g.fmax g29, g29, g0
    g.fmin g29, g29, g24
    g.fli g21, 0.19921875
    g.fli g22, 0.0498046875
    g.fli g23, 0.140625
    g.vscale g21, g21, g29
    g.vadd g18, g18, g21
    g.fli g29, 76.0
    g.fsub g29, g29, g8
    g.fli g28, 0.25
    g.fmul g29, g29, g28
    g.fmax g29, g29, g0
    g.fmin g29, g29, g24
    g.fli g21, 0.453125
    g.fli g22, 0.30078125
    g.fli g23, 0.2578125
    g.vscale g21, g21, g29
    g.vadd g18, g18, g21
    ; light: sun colour * N.L + sky * (1 + N.y) / 2
light:
    g.dot3 g29, g12, g15
    g.fmax g29, g29, g0
    g.vscale g21, g24, g29
    g.fadd g28, g13, g24
    g.fli g29, 0.30078125
    g.fmul g28, g28, g29
    g.vscale g12, g1, g28
    g.vadd g21, g21, g12
    g.fmul g18, g18, g21
    g.fmul g19, g19, g22
    g.fmul g20, g20, g23
    ; lava: the volcano's clipped top glows
    g.fli g29, 244.0
    g.fsub g29, g8, g29
    g.fmax g29, g29, g0
    g.fli g21, 0.30078125
    g.fli g22, 0.060546875
    g.fli g23, 0.0050048828125
    g.vscale g21, g21, g29
    g.vadd g18, g18, g21
    g.mov g31, g0
    g.jmp skycol
water:
    ; waves: normal tilted by two travelling parabolic sines
    g.uniform g28, 0
    g.itof g28, g28
    g.fli g29, 0.011962890625
    g.fmul g28, g28, g29              ; time phase
    g.fli g29, 0.6015625
    g.fmul g27, g9, g29
    g.fadd g27, g27, g10
    g.fadd g27, g27, g28
    g.fli g29, 0.90625
    g.fmul g10, g10, g29
    g.fadd g10, g10, g28
    g.fadd g10, g10, g28
    g.fli g29, 0.5
    g.ftoi g21, g27
    g.itof g21, g21
    g.fsub g27, g27, g21
    g.fsub g27, g27, g29
    g.fsub g21, g0, g27
    g.fmax g21, g21, g27
    g.fsub g21, g21, g29
    g.fmul g12, g27, g21             ; ~ -sin / 16
    g.ftoi g21, g10
    g.itof g21, g21
    g.fsub g10, g10, g21
    g.fsub g10, g10, g29
    g.fsub g21, g0, g10
    g.fmax g21, g21, g10
    g.fsub g21, g21, g29
    g.fmul g14, g10, g21
    g.fli g13, 2.0              ; waves flatten with distance (no shimmer)
    g.fmul g13, g7, g13
    g.fadd g13, g13, g29
    g.norm3 g12, g12
    ; colour by depth: turquoise shallows, deep blue sea
    g.fli g29, 70.5               ; exact
    g.fsub g29, g29, g8
    g.fmax g29, g29, g0
    g.fli g28, 0.19921875
    g.fmul g29, g29, g28
    g.fadd g29, g29, g24
    g.fdiv g29, g24, g29           ; 1 / (1 + depth / 5 bytes)
    g.vscale g18, g1, g28        ; deep water: dark sky blue
    g.fli g21, 0.099609375
    g.fli g22, 0.3984375
    g.fli g23, 0.3515625
    g.vscale g21, g21, g29
    g.vadd g18, g18, g21
    g.fmul g10, g29, g29
    g.fmul g10, g10, g10
    g.fmul g10, g10, g10
    g.fmul g10, g10, g10           ; foam at the shoreline
    ; fresnel reflection of the sky
    g.dot3 g27, g4, g12
    g.fadd g27, g27, g24         ; 1 - cos
    g.fmul g27, g27, g27
    g.fmul g27, g27, g27
    g.reflect3 g21, g4, g12
    g.vscale g12, g4, g24        ; keep the view ray
    g.vscale g4, g21, g24        ; TYPE = 1: skycol returns to water2
skycol:                         ; sky along IN -> V; then COL += (V - COL) FOGF
    g.fli g7, 0.7421875
    g.fli g8, 0.796875
    g.fli g9, 0.875
    g.fmax g29, g5, g0
    g.fli g28, 2.1875
    g.fmul g29, g29, g28
    g.fmin g29, g29, g24
    g.vsub g21, g1, g7
    g.vscale g21, g21, g29
    g.vadd g21, g21, g7
    g.dot3 g29, g4, g15
    g.fmax g29, g29, g0
    g.fmul g29, g29, g29
    g.fmul g29, g29, g29
    g.fmul g29, g29, g29
    g.fmul g29, g29, g29              ; ^16
    g.fli g28, 0.30078125
    g.fmul g28, g29, g28
    g.fmul g29, g29, g29
    g.fmul g29, g29, g29
    g.fmul g29, g29, g29
    g.fmul g29, g29, g29
    g.fmul g29, g29, g29
    g.fmul g29, g29, g29
    g.fmul g29, g29, g29              ; ^2048
    g.fadd g29, g29, g29
    g.fadd g29, g29, g29
    g.fadd g29, g29, g28
    g.vscale g7, g24, g29
    g.vadd g21, g21, g7
    g.bnz g31, water2
    g.vsub g21, g21, g18
    g.vscale g21, g21, g30
    g.vadd g18, g18, g21
    g.fli g21, 1.0                ; fire glow
    g.fli g22, 0.453125
    g.fli g23, 0.12109375
    g.vscale g21, g21, g11
    g.vadd g18, g18, g21
out:
    g.sqrt g18, g18
    g.sqrt g19, g19
    g.sqrt g20, g20
    g.id g21, 2
    g.rgb g18, g21, 0
    g.end
water2:
    g.vsub g21, g21, g18
    g.vscale g21, g21, g27
    g.vadd g18, g18, g21
    g.fli g29, 0.703125
    g.fmul g10, g10, g29
    g.fadd g18, g18, g10
    g.fadd g19, g19, g10
    g.fadd g20, g20, g10
    g.vscale g4, g12, g24
    g.mov g31, g0
    g.jmp skycol
render_k_end:

; ---- include spu.s ----
; ---------------------------------------------------------------------
; Soundtrack: 100 BPM, D hijaz, 20 bars = 48 s, locked to the flight.
; One invocation per stereo sample (grid 64 x 4), stateless: every voice
; is recomputed from the sample index. Uniform 0 = first sample of the
; current loop (set by the CPU). Binding 1: song tables (d_song).
;   drone   D2 + A2, four harmonics each, slow swell, fades in and out
;   wind    smoothed value noise, gusting; loud over the sea
;   oud     plucked hijaz arpeggio over D | Eb | D | Cm
;   darbuka maqsum: doum (pitch-dropping thump) and tek (noise click)
;   ney     breathy flute melody with vibrato and two echo taps
;   boom    volcano and fireball impacts
; ---------------------------------------------------------------------
; sin of a 32-bit phase (parabola)
; sin of a phase in turns (>= 0), * 1/16
; signed noise in [-2^31, 2^31)
; semitone (int) above C3 -> 32-bit phase increment, 2^(s/12) by a cubic


; bar flags
.equ OUD,    1
.equ DRUMS,  2
.equ NEY,    4
.equ BOOM,   8
.equ WIND,   16
.equ ORN,    32
.equ WHOOSH, 64

spu_k:
    g.li g20, 1
    g.li g24, 4
    g.fli g21, 1.0
    g.fli g22, 1.8626451e-9      ; 2^-29
    g.fli g23, 8.6736174e-19     ; 2^-60
    g.li g26, 0x9E3779B1
    g.li g29, 7200            ; samples per 16th
    g.id g1, 2
    g.uniform g9, 14
    g.add g1, g1, g9
    g.uniform g9, 0
    g.sub g2, g1, g9              ; the CPU moves the loop start once per drawn
    g.li g9, 2304000             ; frame, so wrap either way across the seam
    g.slt g10, g2, g0
    g.bz g10, sinpos
    g.add g2, g2, g9
sinpos:
    g.slt g10, g2, g9
    g.bnz g10, sinloop
    g.sub g2, g2, g9
sinloop:
    g.itof g9, g2
    g.fli g10, 0.00013888889  ; exact
    g.fmul g9, g9, g10
    g.ftoi g3, g9
    g.mul g9, g3, g29
    g.sub g4, g2, g9
    g.slt g9, g4, g0
    g.bz g9, stepok
    g.sub g3, g3, g20
    g.add g4, g4, g29
stepok:
    g.shr g28, g3, g24
    g.li g9, 15
    g.and g5, g3, g9
    g.ldb g6, g28, 1

    ; ---- drone ----
    g.li g13, d_drone - d_song
    g.fli g25, 0.30078125
    g.li g17, 2
dstr:
    g.ld g15, g13, 1
    g.add g13, g13, g24
    g.mul g14, g1, g15
    g.mov g12, g14
    g.fli g18, 0.0703125        ; drone level (the A2 octave beats slowly
    g.mov g11, g0                 ; against the D2 twelfth)
    g.li g16, 4
dharm:
    ; <isin Y, W>
    g.itof g10, g12
    g.fsub g30, g0, g10
    g.fmax g30, g30, g10
    g.fmul g30, g30, g23
    g.fsub g30, g22, g30
    g.fmul g10, g10, g30
    g.fmul g10, g10, g18
    g.fadd g11, g11, g10
    g.add g12, g12, g14
    g.fli g9, 0.546875
    g.fmul g18, g18, g9
    g.sub g16, g16, g20
    g.bnz g16, dharm
    g.fadd g7, g7, g11
    g.fmul g11, g11, g25
    g.fadd g8, g8, g11
    g.fsub g25, g0, g25
    g.sub g17, g17, g20
    g.bnz g17, dstr

    ; ---- wind: value noise at 750 Hz, gusts ----
    g.li g9, 6
    g.shr g12, g1, g9
    g.li g9, 63
    g.and g10, g1, g9
    g.itof g10, g10
    g.fli g9, 0.015625
    g.fmul g10, g10, g9
    ; <hash Z, W>
    g.mul g11, g12, g26
    g.shr g30, g11, g26            ; (HM & 31 = 17)
    g.xor g11, g11, g30
    g.mul g11, g11, g26
    g.itof g11, g11
    g.add g12, g12, g20
    ; <hash A, W>
    g.mul g13, g12, g26
    g.shr g30, g13, g26            ; (HM & 31 = 17)
    g.xor g13, g13, g30
    g.mul g13, g13, g26
    g.itof g13, g13
    g.fsub g12, g13, g11              ; side: a decorrelated difference
    g.fmul g9, g12, g10
    g.fadd g11, g11, g9              ; smooth noise (mid)
    g.li g9, 7158                ; gusts, 0.08 Hz
    g.mul g9, g1, g9
    ; <isin Y, X>
    g.itof g10, g9
    g.fsub g30, g0, g10
    g.fmax g30, g30, g10
    g.fmul g30, g30, g23
    g.fsub g30, g22, g30
    g.fmul g10, g10, g30
    g.fmul g10, g10, g10
    g.fli g9, 0.150390625
    g.fadd g10, g10, g9
    g.li g9, WIND
    g.and g9, g6, g9
    g.itof g9, g9
    g.fli g13, 1.1937117960769683e-12
    g.fmul g9, g9, g13              ; loud in WIND bars
    g.fli g13, 3.979039320256561e-12
    g.fadd g9, g9, g13
    g.fmul g10, g10, g9
    g.fmul g18, g11, g10            ; (keep the noise for the boom)
    g.fadd g7, g7, g18
    g.fmul g12, g12, g10
    g.fadd g8, g8, g12
    ; fireball whoosh: the wind swells over the second half of the bar
    g.li g9, WHOOSH
    g.and g9, g6, g9
    g.bz g9, nowhoosh
    g.li g9, 8
    g.sub g9, g5, g9
    g.slt g10, g9, g0
    g.bnz g10, nowhoosh
    g.mul g9, g9, g29
    g.add g9, g9, g4
    g.itof g9, g9
    g.fli g10, 8.0108642578125e-05
    g.fmul g9, g9, g10
    g.fmul g9, g9, g9
    g.fmul g9, g18, g9
    g.fadd g7, g7, g9
    g.fadd g8, g8, g9
nowhoosh:

    ; ---- darbuka tek (this 16th and the one before) ----
    g.li g9, DRUMS
    g.and g9, g6, g9
    g.bz g9, notek
    g.mov g19, g4
    g.mov g16, g5
    g.li g17, 2
tek:
    g.li g9, 0x1044              ; off-beats
    g.shr g9, g9, g16
    g.and g9, g9, g20
    g.bz g9, tekoff
    g.itof g10, g19
    g.fli g9, 0.0040283203125
    g.fmul g9, g10, g9
    g.fadd g9, g9, g21
    g.fmul g9, g9, g9
    ; <hash Z, T>
    g.mul g11, g1, g26
    g.shr g30, g11, g26            ; (HM & 31 = 17)
    g.xor g11, g11, g30
    g.mul g11, g11, g26
    g.itof g11, g11
    g.fdiv g11, g11, g9
    g.fli g9, 5.002220859751105e-11
    g.fmul g11, g11, g9
    g.fadd g7, g7, g11
    g.fli g9, 0.3984375
    g.fmul g11, g11, g9
    g.fsub g8, g8, g11
tekoff:
    g.add g19, g19, g29
    g.sub g16, g16, g20
    g.li g9, 15
    g.and g16, g16, g9
    g.sub g17, g17, g20
    g.bnz g17, tek
notek:

    ; ---- thumps. J = 3: boom (volcano, fireball) from the bar's downbeat;
    ; J = 2, 1: darbuka doum on 1 and 3, this 16th and the one before.
    ; f = f0 + df / (1 + a k)^2 (integrated), level / (1 + a d)^2, rumble
    g.li g17, 3
thump:
    g.li g13, d_thump - d_song
    g.li g9, 3
    g.sub g9, g9, g17
    g.bnz g9, tdoum
    g.li g9, BOOM
    g.and g9, g6, g9
    g.bz g9, tnext
    g.mul g19, g5, g29
    g.add g19, g19, g4
    g.li g9, 20
    g.add g13, g13, g9
    g.jmp tsyn
tdoum:
    g.sub g9, g9, g20             ; 0: this 16th, 1: the one before
    g.mul g19, g9, g29
    g.add g19, g19, g4
    g.sub g16, g5, g9
    g.li g10, 15
    g.and g16, g16, g10
    g.li g10, 0x0101
    g.shr g10, g10, g16
    g.and g10, g10, g20
    g.bz g10, tnext
    g.li g9, DRUMS
    g.and g9, g6, g9
    g.bz g9, tnext
tsyn:
    g.itof g10, g19
    g.ld g9, g13, 1                ; k
    g.add g13, g13, g24
    g.fmul g11, g10, g9
    g.fadd g11, g11, g21
    g.fdiv g11, g21, g11
    g.fsub g12, g21, g11
    g.ld g9, g13, 1                ; df / k, turns
    g.add g13, g13, g24
    g.fmul g12, g12, g9
    g.ld g9, g13, 1                ; f0, turns per sample
    g.add g13, g13, g24
    g.fmul g9, g10, g9
    g.fadd g12, g12, g9
    ; <fsin W, W>
    g.ftoi g30, g12
    g.itof g30, g30
    g.fsub g12, g12, g30
    g.fli g31, 0.5
    g.fsub g12, g12, g31
    g.fsub g30, g0, g12
    g.fmax g30, g30, g12
    g.fsub g30, g31, g30
    g.fmul g12, g12, g30
    g.ld g9, g13, 1                ; d
    g.add g13, g13, g24
    g.fmul g9, g10, g9
    g.fadd g9, g9, g21
    g.fmul g9, g9, g9
    g.ld g11, g13, 1                ; level
    g.fmul g12, g12, g11
    g.fdiv g12, g12, g9
    g.fadd g7, g7, g12
tnext:
    g.sub g17, g17, g20
    g.bnz g17, thump

    ; ---- melodic voices. VI = 5, 4: oud pluck of this 16th and of the one
    ; before (still ringing); VI = 3, 2, 1: the ney and its two echo taps ----
    g.li g17, 5
voice:
    g.li g9, 3
    g.slt g9, g9, g17
    g.bz g9, vney
    g.and g9, g6, g20            ; OUD
    g.bz g9, vnext
    g.li g9, 5
    g.sub g9, g9, g17
    g.mul g19, g9, g29
    g.add g19, g19, g4
    g.sub g16, g5, g9
    g.li g9, 15
    g.and g16, g16, g9
    g.li g13, d_arp - d_song
    g.add g13, g13, g16
    g.ldb g10, g13, 1               ; chord tone 0..5
    g.li g9, 3
    g.slt g11, g10, g9
    g.bnz g11, oudlow
    g.sub g10, g10, g9
oudlow:
    g.and g13, g28, g9             ; chord of the bar: D, Eb, D, Cm
    g.mul g13, g13, g9
    g.add g13, g13, g10
    g.li g9, d_chords - d_song
    g.add g13, g13, g9
    g.ldb g10, g13, 1               ; semitone above C3
    g.li g9, 12
    g.mul g11, g11, g9
    g.sub g11, g9, g11               ; + octave for tones 3..5
    g.add g10, g10, g11
    g.fli g16, 4.9591064453125e-05
    g.mov g25, g0
    g.fli g18, 0.060546875
    g.fli g3, 0.3984375
    g.jmp vsyn
vney:                           ; melody in 8ths, bars 6-17 (14-17 repeat 10-13)
    g.li g13, 12                  ; taps are stored last-first
    g.mul g13, g17, g13
    g.li g9, d_taps - 12 - d_song
    g.add g13, g13, g9
    g.ld g9, g13, 1                ; delay
    g.add g13, g13, g24
    g.ld g18, g13, 1
    g.add g13, g13, g24
    g.ld g3, g13, 1
    g.sub g19, g2, g9
    g.slt g9, g19, g0
    g.bnz g9, vnext
    g.itof g9, g19
    g.fli g10, 0.000069444446     ; 1 / 14400 (exact)
    g.fmul g9, g9, g10
    g.ftoi g16, g9                 ; 8th in the loop
    g.li g9, 14400
    g.mul g10, g16, g9
    g.sub g19, g19, g10
    g.li g10, 48
    g.sub g16, g16, g10
    g.slt g10, g16, g0
    g.bnz g10, vnext
    g.li g10, 96
    g.slt g10, g16, g10
    g.bz g10, vnext
    g.li g10, 64
    g.slt g10, g16, g10
    g.bnz g10, vfind
    g.li g10, 32
    g.sub g16, g16, g10
vfind:
    g.li g10, d_mel - d_song
    g.add g10, g10, g16
    g.ldb g10, g10, 1
    g.li g11, 255
    g.sub g11, g10, g11
    g.bnz g11, vnote
    g.sub g16, g16, g20             ; held: the note started one 8th earlier
    g.add g19, g19, g9
    g.jmp vfind
vnote:
    g.bz g10, vnext               ; rest
    g.fli g16, 1.0013580322265625e-05
    g.fli g25, 6.0
vsyn:
    ; <pitch F, Y>
    g.itof g15, g10
    g.fli g30, 0.083333336  ; exact
    g.fmul g15, g15, g30
    g.ftoi g27, g15
    g.itof g30, g27
    g.fsub g15, g15, g30
    g.fli g30, 0.0780875  ; exact
    g.fmul g30, g30, g15
    g.fli g31, 0.2261675  ; exact
    g.fadd g30, g30, g31
    g.fmul g30, g30, g15
    g.fli g31, 0.6951043  ; exact
    g.fadd g30, g30, g31
    g.fmul g30, g30, g15
    g.fadd g15, g30, g21
    g.li g30, 23
    g.shl g27, g27, g30
    g.add g15, g15, g27
    g.fli g30, 11704931.0         ; C3 (exact)
    g.fmul g15, g15, g30
    g.ftoi g15, g15
    ; vibrato (ney): 5 Hz, fading in over 0.25 s, ~7 cents
    g.li g9, 447392
    g.mul g9, g19, g9
    ; <isin Y, X>
    g.itof g10, g9
    g.fsub g30, g0, g10
    g.fmax g30, g30, g10
    g.fmul g30, g30, g23
    g.fsub g30, g22, g30
    g.fmul g10, g10, g30
    g.itof g9, g19
    g.fli g12, 6.29425048828125e-05
    g.fmul g9, g9, g12
    g.fmin g9, g9, g21
    g.fmul g10, g10, g9
    g.itof g9, g15
    g.fmul g10, g10, g9
    g.fmul g10, g10, g25
    g.ftoi g10, g10
    g.mul g14, g19, g15
    g.add g14, g14, g10
    ; attack (oud 2 ms, ney 50 ms) times gain -> harmonic weight
    g.fli g9, 0.0015869140625
    g.fmul g9, g25, g9
    g.fli g30, 0.010009765625
    g.fsub g9, g30, g9
    g.itof g30, g19
    g.fmul g9, g9, g30
    g.fmin g9, g9, g21
    g.fmul g13, g9, g18
    ; breath (ney only)
    ; <hash X, T>
    g.mul g9, g1, g26
    g.shr g30, g9, g26            ; (HM & 31 = 17)
    g.xor g9, g9, g30
    g.mul g9, g9, g26
    g.itof g9, g9
    g.fmul g9, g9, g25
    g.fmul g9, g9, g13
    g.fli g30, 2.5011104298755527e-12
    g.fmul g9, g9, g30
    g.fadd g7, g7, g9
    ; harmonics 1..3: weights 1, .28, .08; decay 1 / (1 + a DEC k)^2
    g.itof g12, g19
    g.fmul g12, g12, g16
    g.mov g11, g12
    g.mov g10, g14
    g.li g27, 3
vharm:
    ; <isin X, Y>
    g.itof g9, g10
    g.fsub g30, g0, g9
    g.fmax g30, g30, g9
    g.fmul g30, g30, g23
    g.fsub g30, g22, g30
    g.fmul g9, g9, g30
    g.fadd g31, g11, g21
    g.fmul g31, g31, g31
    g.fdiv g9, g9, g31
    g.fmul g9, g9, g13
    g.fadd g7, g7, g9
    g.fmul g9, g9, g3
    g.fadd g8, g8, g9
    g.add g10, g10, g14
    g.fadd g11, g11, g12
    g.fli g30, 0.28125
    g.fmul g13, g13, g30
    g.sub g27, g27, g20
    g.bnz g27, vharm
vnext:
    g.sub g17, g17, g20
    g.bnz g17, voice

    ; ---- soft limiter x / sqrt(1 + x^2), store L, R ----
    g.fadd g9, g7, g8
    g.fsub g10, g7, g8
    g.fmul g11, g9, g9
    g.fadd g11, g11, g21
    g.rsqrt g11, g11
    g.fmul g9, g9, g11
    g.fmul g11, g10, g10
    g.fadd g11, g11, g21
    g.rsqrt g11, g11
    g.fmul g10, g10, g11
    g.id g13, 2
    g.add g13, g13, g13
    g.add g13, g13, g13
    g.add g13, g13, g13
    g.st g9, g13, 0
    g.add g13, g13, g24
    g.st g10, g13, 0
    g.end
spu_k_end:


.align 4
d_base:
; flight path: x, z, height / 10, pad; 21 waypoints + 4 repeated
d_path:
    .byte 122, 8, 77, 0, 102, 12, 75, 0, 82, 16, 85, 0, 70, 26, 80, 0, 58, 32, 178, 0, 42, 24, 157, 0, 24, 26, 140, 0, 14, 42, 145, 0, 18, 62, 92, 0, 26, 80, 152, 0, 42, 76, 89, 0, 55, 73, 89, 0, 67, 70, 194, 0, 79, 67, 144, 0, 96, 84, 105, 0, 114, 76, 76, 0, 120, 58, 152, 0, 108, 46, 144, 0, 92, 40, 73, 0, 98, 26, 77, 0, 112, 16, 76, 0
    .byte 122, 8, 77, 0, 102, 12, 75, 0, 82, 16, 85, 0, 70, 26, 80, 0
; castle (keep and four towers with golden domes) and mana orbs:
; x, z, y * 10, 4 * (radius * 10) + type (type 0 orb, 1 tower, 2 dome)
d_obj:
    .byte 46, 33, 156, 53, 46, 33, 156, 54
    .byte 43, 30, 140, 29, 43, 30, 140, 30, 49, 30, 140, 29, 49, 30, 140, 30
    .byte 43, 36, 140, 29, 43, 36, 140, 30, 49, 36, 140, 29, 49, 36, 140, 30
    .byte 37, 79, 90, 12, 40, 72, 73, 12, 49, 71, 66, 12
    .byte 50, 63, 75, 12, 55, 68, 101, 12, 62, 65, 130, 12
    .byte 108, 18, 80, 51, 108, 18, 64, 15      ; balloon (type 3) and basket
d_end:
; ---- include song.s ----
; ---------------------------------------------------------------------
; song tables (SPU binding 1)
; ---------------------------------------------------------------------
.align 4
d_song:
; bar flags: 1 oud, 2 darbuka, 4 ney (informational), 8 boom, 16 wind, 64 whoosh
d_bars:
    .byte 16, 17, 1, 3, 3, 35, 7, 39, 15, 15, 47, 7, 7, 39, 7, 39, 67, 11, 17, 16
; oud arpeggio: chord tone per 16th (3..5 an octave up)
d_arp:
    .byte 0, 1, 2, 3, 4, 3, 2, 1, 0, 1, 2, 3, 5, 4, 3, 2
; chords by bar mod 4, semitones above C3: D, Eb, D, Cm
d_chords:
    .byte 2, 6, 9, 3, 7, 10, 2, 6, 9, 0, 3, 7
; ney melody in 8ths (semitones above C3; 255 hold, 0 rest), bars 6-13
d_mel:
    .byte 21, 255, 255, 22, 21, 19, 18, 255
    .byte 19, 255, 18, 15, 14, 255, 255, 0
    .byte 14, 15, 18, 19, 21, 255, 22, 21
    .byte 19, 18, 15, 18, 14, 255, 255, 255
    .byte 26, 255, 255, 24, 22, 255, 21, 255
    .byte 22, 24, 26, 24, 22, 21, 19, 255
    .byte 21, 22, 21, 19, 18, 19, 18, 15
    .byte 14, 255, 255, 255, 255, 255, 0, 0
.align 4
; drone strings D2, A2 (32-bit phase per sample)
d_drone:
    .word 6569169, 9842633
; thumps: k, df / k (turns), f0 (turns / sample), decay, level: doum, boom
d_thump:
    .float 0.0011138916015625, 1.3125, 0.0011444091796875, 0.0002498626708984375, 3
    .float 0.000400543212890625, 3.65625, 0.00079345703125, 6.246566772460938e-05, 6
; ney taps: delay (samples), gain, pan
d_taps:
    .word 43200
    .float 0.02001953125, -0.703125
    .word 21600
    .float 0.03515625, 0.703125
    .word 0
    .float 0.080078125, 0
d_song_end:

.align 4
cfg:
    .word 0xf3040, 7, FB0 + 5760, 46080, 3, 0, HMAP, 12288, 3
    .word 0xf3070, 3, d_base, d_end - d_base, 1
    .word 0xf6040, 5, spu_k, spu_k_end - spu_k, 64, 4, AOUT
    .word 0xf6100, 7, AOUT, 2048, 3, 0, d_song, d_song_end - d_song, 1
    .word 0xf6000, 1, 1
    .word 0xf5004, 4, 480, 4, 0, 1
    .word 0
h_prep:
    .word gen, gen_end - gen, 128, 96
h_full:
    .word render_k, render_k_end - render_k, 160, 96

