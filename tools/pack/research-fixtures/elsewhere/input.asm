; LOAD 0x2D500
; =====================================================================
;  ELSEWHERE -- a 4K intro for DB32 (dynamic-1, packed).
;  Flat polygons in the style of Another World: a span pass per
;  (row, polygon) and a resolve pass per pixel into 8-bit indexed pages,
;  with a 32-entry palette computed per frame (flashes, fades, blinks).
;  RAM: FB0 0x10000, FB1 0x14B00 (I8 160x120), palettes 0x19600,
;  spans 0x19C00 (160 polygons x 120 rows), SPU output 0x2C800,
;  draw list 0x2D000, image LOAD..
; =====================================================================
.profile dynamic-1
.entry start
.equ FB0,   0x10000
.equ PAL,   0x19600
.equ SPANS, 0x19C00
.equ AOUT,  0x2C800
.equ DLB,   0x2D000
.equ LOOP,  3456

start:
    lui r13, 0xf3
    lui r14, 0xf5
    li r1, cfg
    jal r7, script
    lw r9, 24(r14)              ; frame counter at the demo start
    addi r15, r0, -1            ; shot whose draw list is built
    mov r10, r0                 ; page being drawn
frame:
    lw r1, 24(r14)
    sub r1, r1, r9              ; demo frame
    addi r2, r0, LOOP
    blt r1, r2, inloop
    add r9, r9, r2
    sub r1, r1, r2
inloop:
    sw r1, 0x104(r13)           ; U1 = demo frame
    addi r2, r0, 800
    mul r2, r9, r2
    sw r2, 0x3200(r13)          ; SPU U0 = sample index of the demo start
    li r3, shots
find:
    lhu r2, 2(r3)               ; shot length in frames
    blt r1, r2, found
    sub r1, r1, r2
    addi r3, r3, 28
    j find
found:
    sw r1, 0x100(r13)           ; U0 = frame in the shot
    li r4, DLB
    beq r3, r15, same
    mov r15, r3
    addi r1, r3, 0              ; shot record -> U8..U14
    addi r2, r13, 0x120
    addi r12, r0, 7
ucopy:
    lw r11, 0(r1)
    sw r11, 0(r2)
    addi r1, r1, 4
    addi r2, r2, 4
    addi r12, r12, -1
    bne r12, r0, ucopy
    ; ---- new shot: draw list = every polygon of every instance, in order.
    ; entry 0 is the background; entries are [polygon, record | j << 16]
    lhu r5, 0(r3)
    add r5, r5, r4              ; first instance record
    addi r6, r4, 8
    addi r2, r0, 4
    sw r2, 0(r4)                ; background "polygon": the colour byte 0x80
    addi r2, r0, 0x80           ; (sky) is the low byte of the next word
    sw r2, 4(r4)
    lui r13, 0x10               ; j step 0x10000
rec:
    lhu r7, 0(r5)               ; shape | extension words (low 2 bits)
    beq r7, r0, built
    andi r1, r7, 3
    sub r7, r7, r1
    add r1, r1, r1
    add r1, r1, r1
    add r8, r5, r1
    addi r8, r8, 12             ; next record
    lbu r12, 3(r5)              ; count
    sub r5, r5, r4
    mov r3, r0
elem:
    add r2, r7, r4
poly:
    sub r11, r2, r4
    sw r11, 0(r6)
    or r11, r5, r3
    sw r11, 4(r6)
    addi r6, r6, 8
    lbu r1, 1(r2)               ; vertices
    add r1, r1, r1
    add r1, r1, r1
    add r1, r1, r2
    lbu r11, 2(r2)              ; kind: bit 7 = last polygon of the shape
    addi r2, r1, 4
    andi r11, r11, 0x80
    beq r11, r0, poly
    add r3, r3, r13
    addi r12, r12, -1
    bne r12, r0, elem
    mov r5, r8
    j rec
built:
    lui r13, 0xf3
    sub r1, r6, r4
    sw r1, 0x10c(r13)           ; U3 = 8 * entries
same:
    ; ---- lightning: frames since the latest strike beat up to now ----
    lw r1, 0x100(r13)           ; frame in the shot
    lhu r2, 18(r15)             ; strike beats
    addi r8, r0, 1
    mov r5, r0
    addi r6, r0, 999
flash:
    and r7, r2, r8
    beq r7, r0, fl_next
    sub r6, r1, r5
fl_next:
    add r8, r8, r8
    addi r5, r5, 36
    slt r7, r1, r5
    beq r7, r0, flash
    andi r2, r6, 4              ; flicker
    addi r7, r0, 9
    mul r6, r6, r7
    addi r5, r0, 255
    sub r5, r5, r6              ; 255 - 9 frames
    slt r7, r5, r0
    beq r7, r0, fl_pos
    mov r5, r0
fl_pos:
    beq r2, r0, fl_on
    addi r7, r0, 2
    shr r5, r5, r7
fl_on:
    sw r5, 0x108(r13)           ; U2 = lightning 0..255
    sw r10, 0x110(r13)          ; U4 = page
    li r1, pass_span
    jal r7, pass
    li r1, pass_draw
    jal r7, pass
    addi r2, r0, 19200
    mul r2, r10, r2
    lui r1, 0x10
    add r2, r2, r1
    sw r2, 0(r14)               ; framebuffer
    addi r2, r0, 768
    mul r2, r10, r2
    li r1, PAL
    add r2, r2, r1
    sw r2, 12(r14)              ; and its palette
    addi r2, r0, 1
    sw r2, 20(r14)              ; show them at the next vblank
wvbl:
    wfi
    lw r1, 20(r14)
    bne r1, r0, wvbl
    xori r10, r10, 1
    j frame

; run the GPU pass configured by the MMIO script at r1 and wait for it
pass:
    mov r8, r7
    jal r7, script
    addi r2, r0, 1
    sw r2, 16(r13)
wgpu:
    wfi
    lw r3, 20(r13)
    beq r3, r2, wgpu
    jalr r0, 0(r8)

; MMIO script at r1: [dest, count, words...], 0 terminates
script:
    lw r2, 0(r1)
s_next:
    lw r3, 4(r1)
    addi r1, r1, 8
s_copy:
    lw r12, 0(r1)
    sw r12, 0(r2)
    addi r1, r1, 4
    addi r2, r2, 4
    addi r3, r3, -1
    bne r3, r0, s_copy
    lw r2, 0(r1)
    bne r2, r0, s_next
    jalr r0, 0(r7)

; ---- include span.s ----
; ---------------------------------------------------------------------
; Span pass: one invocation per (polygon, row), grid 160 x 120.
; Animates the polygon's instance (shot script + time), cuts it with the
; row and stores the span it covers as the word
;   ((xr - 1 + 0x4000) << 16) | (0x4000 - xl)        (xl, xr unclipped)
; so the resolve pass tests a pixel with one add and one mask.
; Entry 0 is the background: a full span.
; bindings: 0 pages and palettes (RW), 1 data (RO), 2 spans (RW)
; uniforms: 0 frame in shot, 1 demo frame, 2 lightning 0..256,
;           3 8 * entries, 4 page, 8..14 the shot record:
;   [instances | frames], camera x, y, z [start | end], [strike beats |
;   palette], background [horizon row, band shift, lights, stars],
;   [rain, flags]; flags 2 fade in, 4 fade out, 8 fades are to white
; instance record: [shape | flags | count], [x | y], [z | scale], then an
;   extension word for each flag bit 0..3:
;   1 move [vx, vy, vz bytes / 256], 2 row [spacing | height variation],
;   4 swing [amplitude | per frame] (see below), 8 aspect [sx | sy];
;   16 wrap the row around the camera, 32 row along z (else x),
;   64 camera-fixed, 128 drawn only while lightning flashes.
;   A row lists its farthest element first; a wrapped row keeps its
;   elements in the window of count spacings ahead of the camera (along
;   z) or centred on it (along x).
; polygon: [colour, n, kind, 0] + n vertices [x, y, z, radius] (signed
;   bytes); kind 4 = ellipse (one vertex + radius), 128 = last polygon
;   of the shape. No culling: convex solids list their far faces first.
; ---------------------------------------------------------------------
.equ U_T,     0
.equ U_DEMO,  1
.equ U_FLASH, 2
.equ U_COUNT, 3
.equ U_PAGE,  4

; d = a + (b - a) s for the bf16 pair w = [a | b] (R: scratch)
; next word of the record at Q

span_k:
    g.li g1, 4
    g.add g13, g1, g1
    g.add g29, g13, g13
    g.add g31, g29, g13
    g.sltu g30, g0, g1
    g.li g28, 0xffff0000
    g.fli g3, 1.0
    g.id g2, 0                   ; polygon
    g.id g10, 1                   ; row
    g.itof g20, g10
    g.fli g12, 0.5
    g.fadd g20, g20, g12
    g.li g12, 640
    g.mul g4, g10, g12
    g.mul g10, g2, g1
    g.add g4, g4, g10
    g.li g18, 0x43e743e8          ; entry 0, the background, covers every row
    g.bnz g2, not_bg
    g.st g18, g4, 2
; ---------------------------------------------------------------------
; and its lanes for rows 0..31 compute that palette entry of the page:
; 12-bit base colours, 16..31 lit variants, lightning, fades
; ---------------------------------------------------------------------
    g.id g9, 1
    g.li g10, 32
    g.slt g10, g9, g10
    g.bz g10, done
    g.uniform g18, 12             ; [strike beats | palette]
    g.shl g18, g18, g29
    g.shr g18, g18, g29
    g.li g10, 15
    g.and g12, g9, g10
    g.mul g12, g12, g1
    g.add g12, g12, g18
    g.ld g21, g12, 1                ; one 12-bit entry per word
    g.and g7, g21, g10
    g.shr g21, g21, g1
    g.and g6, g21, g10
    g.shr g21, g21, g1
    g.and g5, g21, g10
    g.itof g5, g5
    g.itof g6, g6
    g.itof g7, g7
    g.fli g10, 0.06666667         ; 1/15 (exact)
    g.vscale g5, g5, g10
    g.and g10, g9, g29             ; lit: 1.5 c + 0.1
    g.bz g10, base
    g.fli g10, 1.5
    g.vscale g5, g5, g10
    g.fli g10, 0.099609375
    g.fadd g5, g5, g10
    g.fadd g6, g6, g10
    g.fadd g7, g7, g10
base:
    g.uniform g10, U_FLASH        ; lightning: x (1 + 3.6 flash), black stays
    g.itof g10, g10
    g.fli g12, 0.013916015625
    g.fmul g10, g10, g12
    g.fadd g10, g10, g3
    g.vscale g5, g5, g10
    ; level = min(1, t / 20 (flag 2), frames left / 20 (flag 4)) towards
    ; black, or white (flag 8)
    g.uniform g22, 14
    g.shr g22, g22, g13
    g.uniform g10, U_T
    g.itof g24, g10
    g.uniform g18, 8
    g.shr g18, g18, g29
    g.itof g18, g18
    g.fsub g18, g18, g24
    g.fli g11, 0.0498046875
    g.mov g23, g3
    g.shr g10, g22, g30
    g.and g10, g10, g30
    g.bz g10, no_in
    g.fmul g10, g24, g11
    g.fmin g23, g23, g10
no_in:
    g.and g10, g22, g1
    g.bz g10, no_out
    g.fmul g10, g18, g11
    g.fmin g23, g23, g10
no_out:
    g.vscale g5, g5, g23
    g.and g10, g22, g13
    g.bz g10, black
    g.fsub g10, g3, g23
    g.fadd g5, g5, g10
    g.fadd g6, g6, g10
    g.fadd g7, g7, g10
black:
    g.uniform g10, U_PAGE
    g.shl g10, g10, g13
    g.add g10, g10, g9
    g.li g12, 0x3200              ; palettes at 0x9600 in binding 0
    g.add g10, g10, g12
    g.rgb g5, g10, 0
done:
    g.end
not_bg:
    g.uniform g10, U_COUNT
    g.mul g16, g2, g13
    g.slt g10, g16, g10
    g.bz g10, empty
    ; ---- camera: [start | end] pairs, linear over the shot ----
    g.uniform g10, U_T
    g.itof g24, g10
    g.uniform g18, 8
    g.shr g18, g18, g29
    g.itof g18, g18
    g.fdiv g19, g24, g18
    g.uniform g18, 9
    ; <lerpbf CAM.x, W, U>
    g.and g25, g18, g28
    g.shl g9, g18, g29
    g.fsub g9, g9, g25
    g.fmul g9, g9, g19
    g.fadd g25, g25, g9
    g.uniform g18, 10
    ; <lerpbf CAM.y, W, U>
    g.and g26, g18, g28
    g.shl g9, g18, g29
    g.fsub g9, g9, g26
    g.fmul g9, g9, g19
    g.fadd g26, g26, g9
    g.uniform g18, 11
    ; <lerpbf CAM.z, W, U>
    g.and g27, g18, g28
    g.shl g9, g18, g29
    g.fsub g9, g9, g27
    g.fmul g9, g9, g19
    g.fadd g27, g27, g9
    ; ---- instance ----
    g.ld g15, g16, 1             ; draw list: polygon, record | j << 16
    ; <nextw W>
    g.add g16, g16, g1
    g.ld g18, g16, 1
    g.shr g2, g18, g29
    g.shl g16, g18, g29
    g.shr g16, g16, g29
    g.ld g17, g16, 1
    g.shr g17, g17, g29
    g.shr g19, g17, g13            ; count
    ; <nextw W>
    g.add g16, g16, g1
    g.ld g18, g16, 1
    g.and g5, g18, g28
    g.shl g6, g18, g29
    ; <nextw W>
    g.add g16, g16, g1
    g.ld g18, g16, 1
    g.and g7, g18, g28
    g.shl g23, g18, g29
    g.mov g21, g23
    g.mov g22, g23
    g.mov g8, g3
    g.mov g14, g0
    ; ---- move: velocity bytes / 256 per frame ----
    g.and g10, g17, g30
    g.bz g10, no_move
    ; <nextw W>
    g.add g16, g16, g1
    g.ld g18, g16, 1
    g.shl g9, g18, g31
    g.sar g9, g9, g31
    g.itof g9, g9
    g.shl g10, g18, g29
    g.sar g10, g10, g31
    g.itof g10, g10
    g.shl g11, g18, g13
    g.sar g11, g11, g31
    g.itof g11, g11
    g.fli g18, 0.00390625
    g.fmul g18, g18, g24
    g.vscale g9, g9, g18            ; (R, T, B) = g14..g16
    g.vadd g5, g5, g9
no_move:
    ; ---- row: element e = count - 1 - j at e spacings along x or z ----
    g.shr g17, g17, g30         ; now bit 3 wrap, bit 4 along z
    g.and g10, g17, g30
    g.bz g10, no_row
    ; <nextw W>
    g.add g16, g16, g1
    g.ld g18, g16, 1
    g.and g11, g18, g28            ; spacing
    g.sub g2, g19, g2
    g.sub g2, g2, g30
    g.itof g2, g2
    g.and g10, g17, g29
    g.bz g10, xaxis
    g.fsub g9, g27, g7      ; wrap window: count spacings ahead
    g.jmp axis
xaxis:
    g.itof g12, g19                 ; wrap window: centred on the camera
    g.fmul g12, g12, g11
    g.fli g10, 0.5
    g.fmul g12, g12, g10
    g.fsub g9, g25, g5
    g.fsub g9, g9, g12
axis:
    g.and g10, g17, g13
    g.bz g10, place
    g.fdiv g9, g9, g11              ; e += floor(offset / spacing) + 1
    g.fli g10, 1025.0             ; exact
    g.fadd g9, g9, g10
    g.ftoi g9, g9
    g.itof g9, g9
    g.fsub g9, g9, g10
    g.fadd g2, g2, g9
    g.fadd g2, g2, g3
place:
    g.fmul g9, g2, g11
    g.and g10, g17, g29
    g.bz g10, xplace
    g.fadd g7, g7, g9
    g.jmp rowvar
xplace:
    g.fadd g5, g5, g9
rowvar:
    g.ftoi g10, g2                 ; height *= 1 - variation * hash(e)
    g.li g12, 0x9E3779B1
    g.add g10, g10, g12
    g.mul g10, g10, g12
    g.mul g10, g10, g10
    g.shr g10, g10, g13
    g.itof g10, g10
    g.fli g12, 5.9604645e-08      ; 2^-24 (exact)
    g.fmul g10, g10, g12
    g.shl g12, g18, g29
    g.fmul g10, g10, g12
    g.fsub g10, g3, g10
    g.fmul g22, g22, g10
no_row:
    ; ---- rotate by 2 atan(u), u = amplitude * triangle(w t): a swing
    ; (a fast one passes for a spinning wheel);
    ; cos = (1 - u^2) / (1 + u^2), sin = 2u / (1 + u^2)
    g.shr g17, g17, g30
    g.and g10, g17, g30
    g.bz g10, no_rot
    ; <nextw W>
    g.add g16, g16, g1
    g.ld g18, g16, 1
    g.shl g11, g18, g29
    g.fmul g11, g11, g24
    g.fli g12, 1024.0             ; exact
    g.fadd g11, g11, g12
    g.ftoi g10, g11
    g.itof g10, g10
    g.fsub g11, g11, g10
    g.fadd g11, g11, g11
    g.fsub g11, g11, g3
    g.fsub g10, g0, g11
    g.fmax g11, g11, g10
    g.fadd g11, g11, g11
    g.fsub g11, g11, g3
    g.and g12, g18, g28
    g.fmul g11, g11, g12
    g.fmul g10, g11, g11
    g.fadd g12, g3, g10
    g.fdiv g12, g3, g12
    g.fsub g8, g3, g10
    g.fmul g8, g8, g12
    g.fadd g14, g11, g11
    g.fmul g14, g14, g12
no_rot:
    ; ---- aspect ----
    g.shr g17, g17, g30
    g.and g10, g17, g30
    g.bz g10, no_asp
    ; <nextw W>
    g.add g16, g16, g1
    g.ld g18, g16, 1
    g.and g10, g18, g28
    g.fmul g21, g21, g10
    g.shl g10, g18, g29
    g.fmul g22, g22, g10
no_asp:
    ; ---- camera-fixed (now bit 3), lightning-only (bit 4) ----
    g.and g10, g17, g13
    g.bz g10, no_cam
    g.vadd g5, g5, g25
no_cam:
    g.and g10, g17, g29
    g.bz g10, no_fl
    g.uniform g10, U_FLASH
    g.li g12, 80
    g.sltu g10, g10, g12
    g.bnz g10, empty
no_fl:
    g.vsub g5, g5, g25
    ; columns of diag(sx, sy) R(theta): (SX cs, SY sn) and (-SX sn, SY cs)
    g.fmul g11, g21, g14
    g.fsub g11, g0, g11             ; B = g16 = COL1X
    g.fmul g12, g22, g8            ; A = g17 = COL1Y
    g.fmul g21, g21, g8
    g.fmul g22, g22, g14
    g.add g14, g15, g1          ; g4 = first vertex
; ---------------------------------------------------------------------
; polygon: the row is the plane y = RV z through the eye (view space);
; intersect it with every edge and project the crossings. When one end of
; the cut is behind the eye, the span runs to the screen edge on its side.
; x is pre-scaled by the focal length.
; ---------------------------------------------------------------------
    g.uniform g18, 13             ; background: the horizon row in byte 0
    g.shl g2, g18, g31
    g.sar g2, g2, g31
    g.itof g2, g2
    g.fsub g2, g2, g20
    g.fli g19, 100.0              ; focal length
    g.fdiv g2, g2, g19
    g.fmul g5, g5, g19
    g.fmul g21, g21, g19
    g.fmul g11, g11, g19
    g.mov g17, g0
    g.sub g18, g14, g1
    g.ld g18, g18, 1                ; header [colour, n, kind, 0]
    g.shl g30, g18, g29
    g.shr g30, g30, g31
    g.mul g30, g30, g1
    g.add g30, g30, g1          ; 4 (n + 1): v0 .. v(n-1), v0
    g.mov g28, g14
    g.mov g13, g1
    g.fli g25, 992.0
    g.fsub g26, g0, g25
vloop:
    g.ld g18, g28, 1
    g.shl g16, g18, g31
    g.sar g16, g16, g31
    g.itof g16, g16
    g.vscale g8, g21, g16         ; x byte
    g.shl g16, g18, g29
    g.sar g16, g16, g31
    g.itof g16, g16
    g.fmul g19, g11, g16          ; y byte
    g.fadd g8, g8, g19
    g.fmul g19, g12, g16
    g.fadd g9, g9, g19
    g.shr g16, g18, g29
    g.shl g16, g16, g31
    g.sar g16, g16, g31
    g.itof g16, g16
    g.fmul g10, g16, g23           ; z byte
    g.vadd g8, g8, g5
    g.fmul g3, g2, g10
    g.fsub g3, g9, g3
    g.bnz g13, nextv
    g.flt g19, g27, g0
    g.flt g16, g3, g0
    g.xor g19, g19, g16
    g.bz g19, nextv
    ; crossing P = VP + (V - VP) t, t = s0 / (s0 - s1)
    g.fsub g19, g27, g3
    g.fdiv g19, g27, g19
    g.fsub g16, g8, g24
    g.fmul g16, g16, g19
    g.fadd g16, g16, g24
    g.fsub g18, g10, g20
    g.fmul g18, g18, g19
    g.fadd g18, g18, g20
    g.fli g19, 0.0498046875
    g.flt g19, g18, g19
    g.bz g19, front
    g.fli g17, 992.0           ; behind the eye
    g.flt g19, g16, g0
    g.bz g19, nextv
    g.fsub g17, g0, g17
    g.jmp nextv
front:
    g.fdiv g16, g16, g18
    g.fli g19, 80.0
    g.fadd g16, g16, g19
    g.fmin g25, g25, g16
    g.fmax g26, g26, g16
nextv:
    g.mov g13, g0
    g.mov g27, g3
    g.mov g24, g8
    g.mov g15, g9
    g.mov g20, g10
    g.add g28, g28, g1
    g.sub g30, g30, g1
    g.sub g16, g30, g1
    g.bnz g16, nowrap
    g.mov g28, g14             ; the last edge closes on v0
nowrap:
    g.bnz g30, vloop
    g.sub g16, g14, g1
    g.ld g19, g16, 1
    g.shr g19, g19, g29             ; kind
    g.and g19, g19, g1
    g.bnz g19, ellipse
    g.bz g17, encode            ; no crossing behind the eye
    g.flt g16, g26, g25
    g.bnz g16, encode             ; nor in front: empty
    g.fmin g25, g25, g17
    g.fmax g26, g26, g17
    g.jmp encode
ellipse:
    ; centre V, radius byte 3, axes |SX|, |SY|; the row is s from the
    ; centre, so it cuts the ellipse at s / (r |SY|)
    g.fli g16, 0.0498046875
    g.flt g16, g10, g16
    g.bnz g16, empty
    g.shr g18, g18, g31
    g.itof g18, g18
    g.fmul g16, g22, g22
    g.fmul g19, g12, g12
    g.fadd g16, g16, g19
    g.sqrt g16, g16
    g.fmul g16, g16, g18
    g.fdiv g19, g3, g16
    g.fmul g19, g19, g19
    g.fli g16, 1.0
    g.fsub g19, g16, g19
    g.fle g16, g19, g0
    g.bnz g16, empty
    g.sqrt g19, g19
    g.fmul g16, g21, g21
    g.fmul g3, g11, g11
    g.fadd g16, g16, g3
    g.sqrt g16, g16
    g.fmul g16, g16, g18
    g.fmul g19, g19, g16              ; half width
    g.fdiv g19, g19, g10
    g.fdiv g16, g8, g10
    g.fli g18, 80.0
    g.fadd g16, g16, g18
    g.fsub g25, g16, g19
    g.fadd g26, g16, g19
encode:
    g.fli g16, -992.0
    g.fmax g25, g25, g16
    g.fsub g16, g0, g16
    g.fmin g26, g26, g16
    g.fli g16, 16384.5            ; exact
    g.fsub g19, g16, g25
    g.ftoi g19, g19                 ; 0x4000 - first pixel
    g.fli g16, 16383.5            ; exact
    g.fadd g18, g26, g16
    g.ftoi g18, g18                 ; 0x4000 + end pixel - 1
    g.shl g18, g18, g29
    g.or g18, g18, g19
store:
    g.st g18, g4, 2
    g.end
empty:
    g.mov g18, g0
    g.jmp store
span_k_end:

; ---- include draw.s ----
; ---------------------------------------------------------------------
; Resolve pass: one invocation per pixel, grid 160 x 120. Walks the row's
; spans from the front (last polygon) to the back: the first opaque
; polygon covering the pixel gives its palette index. A translucent one
; (colour bit 5) moves the pixel to the lit half of the palette and the
; walk continues; entry 0, the background, covers every pixel.
; colour byte: 0..31 palette index, 32 translucent, 64 lit windows, 128 sky
; bindings: 0 pages and palettes (RW), 1 data (RO), 2 spans (RO)
; ---------------------------------------------------------------------
; d = hash of the integer k, top bits meaningful

draw_k:
    g.id g18, 0
    g.id g8, 1
    g.li g2, 4
    g.add g3, g2, g2
    g.add g17, g3, g3
    g.add g31, g17, g3
    g.add g10, g17, g17
    g.sltu g28, g0, g2
    g.li g29, 0x9E3779B1
    g.shl g19, g18, g17
    g.sub g4, g18, g19
    g.li g19, 640
    g.mul g5, g8, g19
    g.uniform g19, U_COUNT
    g.shr g19, g19, g28
    g.add g6, g5, g19
    g.li g1, 0x40004000
    g.mov g25, g0
walk:
    g.sub g6, g6, g2
    g.ld g30, g6, 2
    g.add g30, g30, g4
    g.and g19, g30, g1
    g.xor g19, g19, g1
    g.bnz g19, walk
    ; covered: the colour byte of the polygon
    g.sub g19, g6, g5
    g.add g19, g19, g19
    g.ld g19, g19, 1
    g.ldb g11, g19, 1
    g.and g19, g11, g10
    g.bz g19, opaque
    g.mov g25, g17
    g.jmp walk
opaque:
    g.shr g24, g11, g2              ; 4 windows, 8 sky
    ; ---- lit windows: every other pixel from the polygon's left edge ----
    g.and g19, g24, g2
    g.bz g19, no_win
    g.shl g16, g30, g17
    g.shr g16, g16, g17             ; 0x4000 + x - left edge
    g.or g19, g16, g8
    g.and g19, g19, g28
    g.bnz g19, no_win
    g.shl g19, g8, g17
    g.add g16, g16, g19
    g.add g16, g16, g6
    ; <hash T, U>
    g.add g19, g16, g29
    g.mul g19, g19, g29
    g.mul g19, g19, g19
    g.mul g19, g19, g29
    g.shr g19, g19, g31
    g.li g20, 70
    g.sltu g19, g19, g20
    g.bz g19, no_win
    g.li g11, 7
no_win:
    ; ---- sky and ground ----
    g.and g19, g24, g3
    g.bz g19, no_sky
    g.uniform g30, 13             ; [horizon, band shift, lights, stars]
    g.shl g22, g30, g31
    g.sar g22, g22, g31
    g.sub g22, g8, g22               ; rows below the horizon
    g.shl g16, g8, g17
    g.add g16, g16, g18
    ; <hash U, U>
    g.add g16, g16, g29
    g.mul g16, g16, g29
    g.mul g16, g16, g16
    g.mul g16, g16, g29
    g.slt g19, g22, g0
    g.bz g19, ground
    ; bands above the horizon: 1 + (row above < 1 band) + (< 2 bands)
    g.sub g22, g0, g22
    g.sub g22, g22, g28
    g.shl g19, g30, g17
    g.shr g19, g19, g31
    g.shr g22, g22, g19
    g.sltu g19, g22, g28
    g.add g11, g19, g28
    g.add g20, g28, g28
    g.sltu g19, g22, g20
    g.add g11, g11, g19
    g.shr g19, g30, g31             ; stars
    g.shr g16, g16, g31
    g.sltu g19, g16, g19
    g.bz g19, no_sky
    g.mov g11, g3
    g.jmp no_sky
ground:
    ; city lights, densest at the horizon and gone 24 rows below it
    g.li g11, 5
    g.sub g19, g31, g22
    g.slt g20, g19, g0
    g.bnz g20, no_sky
    g.shl g20, g30, g3
    g.shr g20, g20, g31
    g.mul g19, g19, g20
    g.mul g19, g19, g3
    g.shr g20, g16, g17
    g.sltu g19, g20, g19
    g.bz g19, no_sky
    g.uniform g19, U_DEMO         ; twinkle: 7 or 8
    g.shr g19, g19, g2
    g.shr g20, g16, g31
    g.add g19, g19, g20
    g.and g19, g19, g28
    g.sub g11, g3, g19
no_sky:
    g.sub g19, g10, g28
    g.and g11, g11, g19
    g.or g11, g11, g25
    ; ---- rain: streaks falling 4 pixels a frame along a 1:2 slant ----
    g.uniform g30, 14
    g.shl g30, g30, g31
    g.shr g30, g30, g31
    g.bz g30, no_rain
    g.shr g19, g8, g28
    g.add g16, g18, g19
    g.uniform g19, U_DEMO
    g.mul g19, g19, g2
    g.sub g21, g8, g19
    g.sub g19, g2, g28
    g.sar g21, g21, g19
    g.shl g21, g21, g17
    g.add g16, g16, g21
    ; <hash T, U>
    g.add g19, g16, g29
    g.mul g19, g19, g29
    g.mul g19, g19, g19
    g.mul g19, g19, g29
    g.shr g19, g19, g31
    g.sltu g19, g19, g30
    g.bz g19, no_rain
    g.or g11, g11, g17
no_rain:
    g.id g19, 2
    g.uniform g20, U_PAGE
    g.li g16, 19200
    g.mul g20, g20, g16
    g.add g19, g19, g20
    g.stb g11, g19, 0
    g.end
draw_k_end:

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
.equ SONG, 2764800

spu_k:
    g.id g23, 2
    g.uniform g16, 14
    g.add g23, g23, g16
    g.uniform g16, 0
    g.sub g23, g23, g16               ; sample in the loop (the CPU moves the loop
    g.li g16, SONG                ; start once per drawn frame: wrap both ways)
    g.slt g19, g23, g0
    g.bz g19, t_pos
    g.add g23, g23, g16
t_pos:
    g.slt g19, g23, g16
    g.bnz g19, t_in
    g.sub g23, g23, g16
t_in:
    g.id g24, 5                  ; grid height = 4
    g.sltu g1, g0, g24
    g.mul g27, g24, g24
    g.li g12, 0xffff0000
    g.li g20, 7200
    g.fli g29, 1.0
    g.fli g13, 4.656613e-10      ; 2^-31 (exact)
    g.li g11, d_taps_end - d_taps
tap_loop:
    g.li g7, d_taps - 8 - d_song
    g.add g7, g7, g11
    g.ld g16, g7, 1                ; tap delay in samples
    g.sub g2, g23, g16
    g.slt g19, g2, g0             ; echoes of the loop's end at its start
    g.bz g19, tt_pos
    g.li g19, SONG
    g.add g2, g2, g19
tt_pos:
    ; musical position of TT: 16th step, bar, samples into step
    g.itof g16, g2
    g.itof g19, g20
    g.fdiv g16, g16, g19
    g.ftoi g19, g16
    g.mul g16, g19, g20
    g.sub g26, g2, g16
    g.shr g25, g19, g24
    g.shl g16, g25, g24
    g.sub g9, g19, g16             ; step in bar
    g.li g16, 31
    g.and g25, g25, g16           ; song loops every 32 bars
    g.ldb g28, g25, 1           ; bar flags live at data offset 0
    g.uniform g16, U_3
    g.and g17, g25, g16
    g.shl g17, g17, g24              ; (bar & 3) * 16
    g.li g5, d_voices - d_song
voice_loop:
    g.ldb g15, g5, 1             ; taps*8 | poly
    g.sltu g16, g15, g11
    g.bnz g16, next_voice
    g.add g7, g5, g1
    g.ldb g16, g7, 1
    g.and g16, g16, g28             ; voice enabled in this bar?
    g.bz g16, next_voice
    g.add g7, g7, g1
    g.ldb g22, g7, 1
    g.add g7, g7, g1
    g.ldb g10, g7, 1               ; trigger mask offset
    g.add g7, g7, g1
    g.ldb g8, g7, 1               ; note array offset
    g.and g16, g22, g27          ; four-bar pattern?
    g.bz g16, one_bar
    g.add g10, g10, g17
    g.add g8, g8, g17
one_bar:
    g.ld g18, g10, 1                ; trigger mask
    g.add g16, g9, g1
    g.shl g16, g1, g16
    g.sub g16, g16, g1
    g.and g19, g18, g16               ; triggers at or before POS
    g.bz g19, next_voice
    g.sub g18, g18, g19               ; triggers after POS
    g.shl g16, g1, g27
    g.or g18, g18, g16
    g.sub g16, g0, g18
    g.and g18, g18, g16               ; lowest later trigger
    g.itof g19, g19
    g.itof g18, g18
    g.uniform g16, U_23
    g.shr g19, g19, g16               ; 127 + j0 (float exponent of highest bit)
    g.shr g18, g18, g16               ; 127 + j1
    g.sub g18, g18, g19
    g.mul g21, g18, g20        ; note length in samples
    g.li g16, 127
    g.sub g19, g19, g16               ; j0
    g.sub g16, g9, g19
    g.mul g16, g16, g20
    g.add g14, g16, g26            ; samples since note on
    g.itof g31, g14
    g.add g8, g8, g19
    g.ldb g8, g8, 1               ; note byte
    g.and g16, g22, g1
    g.bnz g16, chord_rel
    g.bz g8, next_voice          ; absolute-note rest
chord_rel:
    g.uniform g16, U_7
    g.and g15, g15, g16             ; poly count
    g.mov g30, g0
poly_loop:
    ; ---- note number ----
    g.mov g16, g8
    g.and g19, g22, g1
    g.bz g19, abs_note
    g.add g16, g8, g30
    g.uniform g19, U_7
    g.and g16, g16, g19
    g.shr g19, g17, g1
    g.add g16, g16, g19
    g.li g19, d_chords - d_song
    g.add g16, g16, g19
    g.ldb g16, g16, 1
abs_note:
    g.add g19, g7, g1
    g.ldb g19, g19, 1               ; base note (+36 bias, folded into pitch constant)
    g.add g16, g16, g19
    g.li g19, d_trans - d_song
    g.add g19, g19, g25
    g.ldb g19, g19, 1               ; key of the bar
    g.add g16, g16, g19
    ; ---- phase increment = 2^((16n + j)/192 + c) ----
    g.shl g16, g16, g24
    g.add g16, g16, g30
    g.itof g16, g16
    g.fli g19, 0.0052083333       ; 1/192 (exact)
    g.fmul g16, g16, g19
    g.ftoi g18, g16
    g.itof g19, g18
    g.fsub g16, g16, g19
    g.fli g19, 0.34375      ; 2^x ~ 1 + x (0.6565 + 0.3435 x)
    g.fmul g19, g19, g16
    g.fli g10, 0.65625
    g.fadd g19, g19, g10
    g.fmul g19, g19, g16
    g.fadd g19, g19, g29
    g.uniform g16, U_23
    g.shl g18, g18, g16
    g.add g19, g19, g18
    g.ftoi g3, g19
    g.mul g3, g3, g14          ; carrier phase
    ; ---- modulator: sin(ratio * phase + 90deg) ----
    g.li g16, 5
    g.shr g16, g22, g16
    g.mul g19, g3, g16
    g.bnz g16, fm_ratio
    g.li g19, 0x40000000          ; ratio 0: constant modulator -> pitch sweep
fm_ratio:
    g.itof g19, g19
    g.fsub g18, g0, g19
    g.fmax g18, g18, g19
    g.fmul g18, g18, g13
    g.fsub g18, g18, g29
    g.fmul g19, g19, g18
    g.add g10, g7, g24
    g.ld g8, g10, 1                ; [index*2^-3 | index decay]
    g.shl g16, g8, g27
    g.fmul g16, g16, g31
    g.fadd g16, g16, g29
    g.fmul g16, g16, g16
    g.fmul g16, g16, g16              ; (1 + k t)^4
    g.and g18, g8, g12
    g.fmul g18, g18, g19
    g.fdiv g18, g18, g16
    g.ftoi g18, g18
    g.shl g18, g18, g24
    g.add g3, g3, g18
    ; ---- carrier ----
    g.itof g19, g3
    g.fsub g18, g0, g19
    g.fmax g18, g18, g19
    g.fmul g18, g18, g13
    g.fsub g18, g18, g29
    g.fmul g19, g19, g18
    ; ---- noise mix ----
    g.add g10, g10, g24
    g.add g10, g10, g24
    g.ld g8, g10, 1                ; [gain*2^-31 | noise]
    g.shl g18, g8, g27
    g.bz g18, no_noise
    g.li g16, 0x9E3779B1
    g.mul g16, g2, g16
    g.mul g16, g16, g16
    g.itof g16, g16
    g.fsub g16, g16, g19
    g.fmul g16, g16, g18
    g.fadd g19, g19, g16
no_noise:
    g.and g8, g8, g12
    g.fmul g19, g19, g8
    ; ---- envelope: min(1, attack ramp, release ramp) / (1 + k t)^4 ----
    g.sub g10, g10, g24
    g.ld g8, g10, 1                ; [amp decay | attack rate]
    g.shl g16, g8, g27
    g.fmul g16, g16, g31
    g.sub g18, g21, g14
    g.itof g18, g18
    g.fli g10, 0.0040283203125
    g.fmul g18, g18, g10
    g.fmin g16, g16, g18
    g.fmin g16, g16, g29
    g.fmul g19, g19, g16
    g.and g16, g8, g12
    g.fmul g16, g16, g31
    g.fadd g16, g16, g29
    g.fmul g16, g16, g16
    g.fmul g16, g16, g16
    g.fdiv g19, g19, g16
    ; ---- tap gain / pan, accumulate mid & side ----
    g.li g10, d_taps - 4 - d_song
    g.add g10, g10, g11
    g.ld g8, g10, 1                ; [gain | pan]
    g.and g16, g8, g12
    g.fmul g19, g19, g16
    g.fadd g6, g6, g19
    g.shl g8, g8, g27
    g.fmul g16, g8, g19
    g.fadd g4, g4, g16
    g.add g30, g30, g1
    g.sub g16, g30, g15
    g.bnz g16, poly_loop
next_voice:
    g.li g16, 20
    g.add g5, g5, g16
    g.li g16, d_voices_end - d_song
    g.sub g16, g5, g16
    g.bnz g16, voice_loop
next_tap:
    g.sub g11, g11, g24
    g.sub g11, g11, g24
    g.bnz g11, tap_loop
    ; ---- output ----
    g.fadd g16, g6, g4
    g.fsub g19, g6, g4
    ; soft limiter on the mid level: 1 / sqrt(1 + m^2)
    g.fmul g18, g6, g6
    g.fadd g18, g18, g29
    g.rsqrt g18, g18
    g.fmul g16, g16, g18
    g.fmul g19, g19, g18
    g.id g7, 2
    g.mul g7, g7, g24
    g.add g7, g7, g7
    g.st g16, g7, 0
    g.add g7, g7, g24
    g.st g19, g7, 0
    g.end
spu_k_end:

; ---- include song.s ----
; ---------------------------------------------------------------------
; Song (SPU binding 1 = d_song .. d_song_end)
; 100 BPM, 16th = 7200 samples, bar = 16 steps, 24 bars = 57.6 s, looping.
; A minor: Am | F | Dm | E; the alien world (bars 14-23) a fourth up.
; voice: [taps*8|poly, bar flags mask, mode, mask offset, notes offset, base+234-36, 0, 0]
;        .bf index*2^-3, index decay/4/SR ; .bf amp decay/4/SR, attack/SR
;        .bf gain*2^-29, noise
; mode: 1 chord-relative, 16 four-bar pattern, ratio<<5
; bar flags: 1 bass, 2 snare+hats, 4 kick, 8 arp, 16 lead, 32 pad,
;   64 thunder
; The thunder pattern (bars 1, 9, 11, 13) is the lightning of the shots.
; ---------------------------------------------------------------------
.align 4
d_song:
d_flags:
    .byte 0x20,0x60,0x20,0x21   ; city: pad, thunder
    .byte 0xAD,0x2D,0x3F,0x3F   ; drive: bass, kick, arp; + hats, lead
    .byte 0xBF,0x7F,0x3F,0x7F   ; lab: full, thunder
    .byte 0xBF,0x7F             ; the strike
    .byte 0x28,0x28             ; elsewhere: pad, arp
    .byte 0x29,0x39,0x3D,0x3F   ;   + bass, lead, kick, hats
    .byte 0xBF,0x3F,0x28,0x20   ;   climax, outro
d_trans:
    .byte 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,5,5
    .byte 5,5,5,5, 5,5,5,5
; trigger masks, 16-byte rows: [lead bar k] [unused] [thunder bar k] [1-bar]
p_lead:  .word 0x1151
         .word 0
p_thun:  .word 0
p_kick:  .word 0x1111
         .word 0x1115, 0, 0x1100
p_snare: .word 0x1010
         .word 0x1151, 0, 0
p_hat:   .word 0x4444
         .word 0x1515, 0, 0x0001
p_bass:  .word 0x5555
p_arp:   .word 0xFFFF
p_pad:   .word 0x0001
; lead notes: 4 bars x 16 steps (MIDI at the onsets)
n_lead:
    .byte 76,0,0,0, 74,0,72,0, 71,0,0,0, 69,0,0,0
    .byte 69,0,72,0, 77,0,0,0, 76,0,0,0, 72,0,0,0
    .byte 74,0,0,0, 77,0,76,0, 74,0,0,0, 69,0,0,0
    .byte 68,0,71,0, 76,0,0,0, 74,0,72,0, 71,0,0,0
; chord-relative notes: degree 0..7 (two octaves of 4 chord tones)
n_bass:  .byte 0,0,0,0, 4,0,0,0, 0,0,0,0, 4,0,2,0
n_arp:   .byte 0,1,2,3, 4,5,6,7, 6,5,4,3, 2,3,4,5
n_zero:  .byte 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0
; chords, 8 tones each: Am F Dm E
d_chords:
    .byte 45,48,52,57, 57,60,64,69
    .byte 41,45,48,53, 53,57,60,65
    .byte 50,53,57,62, 62,65,69,74
    .byte 40,44,47,52, 52,56,59,64
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
    .word 0x30003ea0 ; bf 4.656612873077393e-10, 0.3125
v_hat:
    .byte 25, 0x02, 0x01, p_hat-d_song, n_zero-d_song, 36+198, 0, 0
    .word 0x00000000 ; bf 0, 0
    .word 0x3a003d30 ; bf 0.00048828125, 0.04296875
    .word 0x2e903f80 ; bf 6.548361852765083e-11, 1
v_thunder:
    .byte 41, 0x40, 0x11, p_thun-d_song, n_zero-d_song, 36-36+198, 0, 0
    .word 0x3fc03730 ; bf 1.5, 0.00001049041748046875
    .word 0x36d03bd0 ; bf 0.000006198883056640625, 0.00634765625
    .word 0x2f803f10 ; bf 2.3283064365386963e-10, 0.5625
v_bass:
    .byte 9, 0x01, 0x21, p_bass-d_song, n_bass-d_song, 36-12+198, 0, 0
    .word 0x3e803840 ; bf 0.25, 0.0000457763671875
    .word 0x37e03c08 ; bf 0.000026702880859375, 0.00830078125
    .word 0x30100000 ; bf 5.238689482212067e-10, 0
v_arp:
    .byte 73, 0x08, 0x61, p_arp-d_song, n_arp-d_song, 36+198, 0, 0
    .word 0x3da037e0 ; bf 0.078125, 0.000026702880859375
    .word 0x38303c50 ; bf 0.000041961669921875, 0.0126953125
    .word 0x2f400000 ; bf 1.7462298274040222e-10, 0
v_lead:
    .byte 41, 0x10, 0x50, p_lead-d_song, n_lead-d_song, 36+198, 0, 0
    .word 0x3db03690 ; bf 0.0859375, 0.000004291534423828125
    .word 0x36b03aa0 ; bf 0.000005245208740234375, 0.001220703125
    .word 0x2fa00000 ; bf 2.9103830456733704e-10, 0
v_pad:
    .byte 28, 0x20, 0x21, p_pad-d_song, n_zero-d_song, 48+198, 0, 0
    .word 0x3dc035d0 ; bf 0.09375, 0.0000015497207641601562
    .word 0x35b03860 ; bf 0.0000013113021850585938, 0.00005340576171875
    .word 0x2f000000 ; bf 1.1641532182693481e-10, 0
d_voices_end:
; taps: [delay samples] [.bf gain, pan]. Voices use a prefix of this list:
; 1 = dry, 3 = + 2 early reflections (pads, drums), 5 = + two ping-pong
; dotted-eighth echoes (lead, thunder), 9 = everything (arp).
d_taps:
    .word 0
    .word 0x3f800000 ; bf 1, 0
    .word 1728
    .word 0x3ea03f30 ; bf 0.3125, 0.6875
    .word 2880
    .word 0x3e90bf30 ; bf 0.28125, -0.6875
    .word 21600
    .word 0x3ed0bf50 ; bf 0.40625, -0.8125
    .word 43200
    .word 0x3e803f50 ; bf 0.25, 0.8125
    .word 4096
    .word 0x3e803f20 ; bf 0.25, 0.625
    .word 5568
    .word 0x3e50bf20 ; bf 0.203125, -0.625
    .word 7936
    .word 0x3e203f00 ; bf 0.15625, 0.5
    .word 64800
    .word 0x3e20bf50 ; bf 0.15625, -0.8125
d_taps_end:
d_song_end:


; ---------------------------------------------------------------------
; GPU data (binding 1 = DLB .. d_end): draw list below the image, then
; shapes, instance records, shots and palettes
; ---------------------------------------------------------------------
.align 4
; ---- include scenes.s ----
; generated by scenes.py -- do not edit
.align 4
; ---- shots: 7 words each (see span.s) ----
shots:
    .word il_city - DLB + 0x02400000
    .word 0x00000000
    .word 0x40a84094
    .word 0x00004080
    .word pal_city - DLB + 0x00c00000
    .byte 42, 3, 90, 0, 12, 2, 0, 0
    .word il_drive - DLB + 0x01200000
    .word 0x00003e9a
    .word 0x3fb43f9a
    .word 0x00000000
    .word pal_city - DLB + 0x00000000
    .byte 58, 3, 40, 0, 14, 0, 0, 0
    .word il_drive - DLB + 0x01200000
    .word 0x3e4cbecc
    .word 0x3f683f4c
    .word 0x409040a0
    .word pal_city - DLB + 0x00000000
    .byte 56, 3, 40, 0, 14, 0, 0, 0
    .word il_lab - DLB + 0x02400000
    .word 0x00000000
    .word 0x3fc04020
    .word 0xc180c120
    .word pal_city - DLB + 0x10c00000
    .byte 100, 3, 60, 0, 16, 0, 0, 0
    .word il_lab - DLB + 0x01200000
    .word 0x00000000
    .word 0x4000401a
    .word 0xc100c080
    .word pal_city - DLB + 0x00c00000
    .byte 112, 3, 60, 0, 16, 12, 0, 0
    .word il_alien - DLB + 0x02400000
    .word 0x00003f80
    .word 0x3ff43ff4
    .word 0x00004000
    .word pal_alien - DLB + 0x00000000
    .byte 70, 3, 0, 8, 0, 10, 0, 0
    .word il_alien - DLB + 0x01b00000
    .word 0x40e04120
    .word 0x40604060
    .word 0x41604170
    .word pal_alien - DLB + 0x00000000
    .byte 70, 3, 0, 8, 0, 0, 0, 0
    .word il_alien - DLB + 0x01b00000
    .word 0xbfe8bfb4
    .word 0x3f803f68
    .word 0x40204040
    .word pal_alien - DLB + 0x00000000
    .byte 70, 3, 0, 8, 0, 4, 0, 0
; ---- palettes: 16 x 12-bit, a word each ----
pal_city:
    .word 0x000, 0x124, 0x136, 0x347, 0x235, 0x013, 0x001, 0x852, 0xdb4, 0xd22, 0xfea, 0xfff, 0x402, 0xa33, 0x569, 0xe11
pal_alien:
    .word 0x000, 0x113, 0x325, 0x758, 0x236, 0x102, 0x001, 0xa86, 0xfed, 0xd22, 0xfc8, 0xfff, 0x214, 0x436, 0xfb7, 0xc42
; ---- instance lists ----
il_city:
    .word sh_bldg - DLB + 0x1a0a0002, 0xc3500000, 0x43803e50, 0x41883f50, 0x3f904040
    .word sh_tower - DLB + 0x060a0002, 0xc1f00000, 0x43803e50, 0x41403f00, 0x3f9840c0
    .word sh_slab - DLB + 0x01080001, 0x00000000, 0xc1a04010, 0x3c083f80
    .word sh_box - DLB + 0x052a0002, 0xc0880000, 0x41003dd0, 0x41103f00, 0x3f303ee0
    .word sh_box - DLB + 0x052a0002, 0x40900000, 0x41203de0, 0x41083f10, 0xbf183ed0
    .word sh_lamp - DLB + 0x08320001, 0xbfc00000, 0x40403cf0, 0x40c00000
    .word sh_lamp - DLB + 0x083a0002, 0x3fc00000, 0x40c03cf0, 0x40c00000, 0xbf803f80
    .word sh_carb - DLB + 0x01010001, 0x3e980000, 0x41103d10, 0x001f0000
    .word 0
il_drive:
    .word sh_bldg - DLB + 0x141b0003, 0x00000000, 0x43183df0, 0x0000009a, 0x41203f50, 0x3f984080
    .word sh_bldg - DLB + 0x0c1b0003, 0x00000000, 0x42083d70, 0x0000009a, 0x41003f00, 0x3fe03f98
    .word sh_slab - DLB + 0x01080001, 0x00000000, 0x40c03df0, 0x41503f80
    .word sh_lamp - DLB + 0x05130002, 0x00000000, 0x41403d50, 0x0000009a, 0x41100000
    .word sh_slab - DLB + 0x0a1b0003, 0x00003c20, 0x41183c00, 0x0000009a, 0x40800000, 0x3f983f80
    .word sh_car - DLB + 0x01000000, 0xbed00000, 0x41103d08
    .word sh_wheel - DLB + 0x01040001, 0xbfd83e70, 0x41103d08, 0x0000bda4
    .word sh_wheel - DLB + 0x01040001, 0x3f703e70, 0x41103d08, 0x0000bda4
    .word 0
il_lab:
    .word sh_bldg - DLB + 0x1a0a0002, 0xc3500000, 0x43803e50, 0x41883f50, 0x3f904040
    .word sh_tower - DLB + 0x060a0002, 0xc1f00000, 0x43803e50, 0x41403f00, 0x3f9840c0
    .word sh_cloud - DLB + 0x01090002, 0xc1d04278, 0x42b03f00, 0x00000008, 0x3f803ee0
    .word sh_cloud - DLB + 0x01090002, 0x42084260, 0x42a03ed0, 0x000000fb, 0xbf803f00
    .word sh_slab - DLB + 0x01080001, 0x00000000, 0x41003f50, 0x3f803f80
    .word sh_labbox - DLB + 0x01080001, 0xc1b00000, 0x42383e80, 0x3fa83eb0
    .word sh_labbox - DLB + 0x01080001, 0x41b00000, 0x42383e80, 0xbfa83e98
    .word sh_labbox - DLB + 0x01080001, 0x00000000, 0x42203e50, 0x3f804010
    .word sh_mast - DLB + 0x01000000, 0x000041f0, 0x42103dd0
    .word sh_bolt - DLB + 0x01800000, 0xc0404260, 0x42103e08
    .word sh_car - DLB + 0x01010001, 0xc1600000, 0x41a03d08, 0x0000001a
    .word 0
il_alien:
    .word sh_planet - DLB + 0x01010001, 0x42b04308, 0x43983f80, 0x00000a00
    .word sh_butte - DLB + 0x0a0a0002, 0xc3080000, 0x43183e98, 0x41f03f18, 0x3f803f00
    .word sh_spire - DLB + 0x01000000, 0xc1c80000, 0x42703e18
    .word sh_mesa - DLB + 0x01000000, 0x41600000, 0x41f03e08
    .word sh_leg - DLB + 0x01050002, 0x410040a0, 0x41f03d50, 0x00000005, 0x3eb43cf8
    .word sh_leg - DLB + 0x01050002, 0x40c040a0, 0x41f03d50, 0x00000005, 0xbeb43cf8
    .word sh_beast - DLB + 0x01010001, 0x40e04088, 0x41f03d50, 0x00000005
    .word sh_cliff - DLB + 0x01000000, 0xc0000000, 0x40c03d20
    .word sh_man - DLB + 0x01000000, 0xc0180000, 0x40c03cf0
    .word 0
; ---- shapes: [colour, n, kind, 0] + vertices [x, y, z, r] ----
sh_box:
    .word 0x00000406, 0x00e000e0, 0x00e040e0, 0x002040e0, 0x002000e0
    .word 0x00000406, 0x00e00020, 0x00e04020, 0x00204020, 0x00200020
    .word 0x00000404, 0x00e040e0, 0x00e04020, 0x00204020, 0x002040e0
    .word 0x00800400, 0x00e000e0, 0x00e00020, 0x00e04020, 0x00e040e0
sh_labbox:
    .word 0x00000446, 0x00e000e0, 0x00e040e0, 0x002040e0, 0x002000e0
    .word 0x00000446, 0x00e00020, 0x00e04020, 0x00204020, 0x00200020
    .word 0x00000404, 0x00e040e0, 0x00e04020, 0x00204020, 0x002040e0
    .word 0x00800440, 0x00e000e0, 0x00e00020, 0x00e04020, 0x00e040e0
sh_slab:
    .word 0x00800404, 0x000000c0, 0x00000040, 0x00400040, 0x004000c0
sh_lamp:
    .word 0x00000400, 0x000000fe, 0x00000002, 0x00004002, 0x000040fe
    .word 0x00000600, 0x00003d00, 0x00003e14, 0x00003c1a, 0x00003e1a, 0x00004014, 0x00004000
    .word 0x00040120, 0x07003a18
    .word 0x0080040a, 0x00003a15, 0x00003a1b, 0x00003c1b, 0x00003c15
sh_bldg:
    .word 0x00800440, 0x000000e0, 0x00000020, 0x00004020, 0x000040e0
sh_tower:
    .word 0x00000440, 0x000000e0, 0x00000020, 0x00004020, 0x000040e0
    .word 0x00800409, 0x000040fb, 0x00004005, 0x00004205, 0x000042fb
sh_carb:
    .word 0x00000420, 0x000000e2, 0x0000001e, 0x007f0032, 0x007f00ce
    .word 0x0000060c, 0x000004e0, 0x00000420, 0x00001020, 0x00001a16, 0x00001aea, 0x000010e0
    .word 0x0004010f, 0x04000be8
    .word 0x0084010f, 0x04000b18
sh_car:
    .word 0x00000420, 0x00000b3f, 0x0000047f, 0x0000fc7f, 0x0000083f
    .word 0x0000070c, 0x000005c2, 0x0000053c, 0x00000a40, 0x00000e3a, 0x00001216, 0x000014ce, 0x000010c1
    .word 0x0000040c, 0x000014d4, 0x00001218, 0x00001d04, 0x00001eec
    .word 0x0000040e, 0x000014da, 0x00001312, 0x00001b03, 0x00001cee
    .word 0x0000040d, 0x00000fc6, 0x00000c36, 0x00000d36, 0x000011c6
    .word 0x0000040b, 0x0000093a, 0x0000093f, 0x00000c3f, 0x00000c3a
    .word 0x0080040f, 0x00000cc1, 0x00000cc4, 0x000010c4, 0x000010c1
sh_wheel:
    .word 0x00040100, 0x0b000000
    .word 0x0004010e, 0x06000000
    .word 0x00800400, 0x0000faff, 0x0000fa01, 0x00000601, 0x000006ff
sh_bolt:
    .word 0x00800c0b, 0x00007d05, 0x000050f9, 0x00001e0d, 0x0000ecff, 0x0000ba0e, 0x00008307, 0x000083fd, 0x0000ba04, 0x0000ecf5, 0x00001e03, 0x000050ef, 0x00007dfb
sh_mast:
    .word 0x00000400, 0x000000fc, 0x00000004, 0x00006404, 0x000064fc
    .word 0x00000400, 0x000046f2, 0x0000460e, 0x0000490e, 0x000049f2
    .word 0x00800409, 0x000064fd, 0x00006403, 0x00006803, 0x000068fd
sh_cloud:
    .word 0x00040106, 0x320000ba
    .word 0x00040106, 0x3c00043c
    .word 0x00840106, 0x460014f6
sh_planet:
    .word 0x00040120, 0x78000000
    .word 0x00040107, 0x64000000
    .word 0x0084010e, 0x460014ec
sh_butte:
    .word 0x00800600, 0x000000c4, 0x0000003c, 0x00003228, 0x0000401e, 0x000040de, 0x000032d4
sh_spire:
    .word 0x00800500, 0x000081ec, 0x00008114, 0x00003c08, 0x00005000, 0x000040fa
sh_mesa:
    .word 0x00800400, 0x00008181, 0x0000817f, 0x00001e6e, 0x0000229c
sh_cliff:
    .word 0x00800500, 0x00008181, 0x0000813c, 0x0000ec28, 0x0000000a, 0x00000681
sh_leg:
    .word 0x00800400, 0x000002fd, 0x00000203, 0x0000f002, 0x0000f0fe
sh_beast:
    .word 0x00000400, 0x000016e0, 0x000020cc, 0x00001cc6, 0x000010dc
    .word 0x00000600, 0x00000ee2, 0x00000c16, 0x0000161e, 0x00001e08, 0x00001ce6, 0x000016de
    .word 0x00000500, 0x00001416, 0x00001628, 0x00001e30, 0x00002624, 0x00002018
    .word 0x0080040f, 0x00001d26, 0x00001d2a, 0x0000202a, 0x00002026
sh_man:
    .word 0x00000400, 0x000000fa, 0x000000fe, 0x00001eff, 0x00001ef8
    .word 0x00000400, 0x00000002, 0x00000006, 0x00001e07, 0x00001e00
    .word 0x00000400, 0x00001ef7, 0x00001e08, 0x00003409, 0x000034f6
    .word 0x00000400, 0x000032f6, 0x00001ef3, 0x00001cf6, 0x000030f9
    .word 0x00840100, 0x06003a00

d_end:

.align 4
cfg:
    .word 0xf6040, 5, spu_k, spu_k_end - spu_k, 64, 4, AOUT
    .word 0xf6100, 7, AOUT, 2048, 3, 0, d_song, d_song_end - d_song, 1
    .word 0xf6204, 3, 7, 23, 3
    .word 0xf6000, 1, 1
    .word 0xf5004, 4, 160, 3, PAL, 1
    .word 0xf3008, 2, 160, 120
    .word 0xf3040, 11, FB0, 0x9C00, 3, 0, DLB, d_end - DLB, 1, 0, SPANS, 76800, 3
    .word 0
pass_span:                      ; spans writable
    .word 0xf3000, 1, span_k
    .word 0xf3004, 1, span_k_end - span_k
    .word 0xf3068, 1, 3
    .word 0
pass_draw:                      ; spans read-only
    .word 0xf3000, 1, draw_k
    .word 0xf3004, 1, draw_k_end - draw_k
    .word 0xf3068, 1, 1
    .word 0

