; Backdrop: the tiling 3D wallpaper behind the DemoBench homepage.
; A checkerboard of tumbling cubes rides a travelling wave over a ground plane, ray
; traced per pixel on the GPU. The orthographic camera looks down 48.6 degrees
; along (1, -1.6036, 1): at that angle a world repeating every 4 cells in x and
; z projects onto exactly 160x120 screen pixels, so the frame tiles seamlessly.
; Each frame the CPU runs two GPU jobs: 16 lanes compute every cube's height,
; rotation and colour from the frame clock, then 19,200 lanes trace the image.
; Primary rays walk the grid cells front to back (each cube stays inside its
; cell); ground hits trace a shadow ray toward the sun through the same walk.
.profile gpu-1
.equ GPU, 0xf3000
.equ VIDEO, 0xf5000
.equ SYS, 0xf0000
.equ FB_A, 0x10000
.equ FB_B, 0x1e100
.equ STATE, 0x2c200            ; 16 cube records of 64 bytes, after FB_B
.equ RGB_BYTES, 57600
.entry start

start:
    li r1, FB_A                ; render target, then displayed page
    li r2, FB_B                ; other page
    li r3, GPU
    li r5, VIDEO
    li r6, SYS
    li r4, 480
    sw r4, 4(r5)               ; stride
    li r4, 4
    sw r4, 8(r5)               ; RGB888
    li r4, 1
    sw r4, 16(r5)              ; enable scanout

frame:
    ; Job 1: cube states. Binding 0 = state records (RW), 1 = colours (ROM).
    li r4, prep
    sw r4, 0(r3)
    li r4, prep_end-prep
    sw r4, 4(r3)
    li r4, 16
    sw r4, 8(r3)
    li r4, 1
    sw r4, 12(r3)
    li r4, STATE
    sw r4, 0x40(r3)
    li r4, 1024
    sw r4, 0x44(r3)
    li r4, 3
    sw r4, 0x48(r3)
    li r4, colours
    sw r4, 0x50(r3)
    li r4, colours_end-colours
    sw r4, 0x54(r3)
    li r4, 1
    sw r4, 0x58(r3)
    lw r4, 16(r6)              ; completed video frames: the animation clock
    sw r4, 0x100(r3)
    li r4, 1
    sw r4, 16(r3)
    jal r15, wait_gpu

    ; Job 2: trace. Binding 0 = back buffer (RW), 1 = state records (RO).
    li r4, trace
    sw r4, 0(r3)
    li r4, trace_end-trace
    sw r4, 4(r3)
    li r4, 160
    sw r4, 8(r3)
    li r4, 120
    sw r4, 12(r3)
    sw r1, 0x40(r3)
    li r4, RGB_BYTES
    sw r4, 0x44(r3)
    li r4, STATE
    sw r4, 0x50(r3)
    li r4, 1024
    sw r4, 0x54(r3)
    li r4, 1
    sw r4, 16(r3)
    jal r15, wait_gpu

    sw r1, 0(r5)               ; queue the finished page for the next vblank
    li r4, 1
    sw r4, 20(r5)
    wfi                        ; the committing vblank
    mov r4, r1
    mov r1, r2
    mov r2, r4
    j frame

wait_gpu:
    lw r4, 20(r3)
    li r9, 3
    beq r4, r9, gpu_fault
    li r9, 2
    beq r4, r9, gpu_done
    wfi                        ; wakes on GPU completion or vblank
    j wait_gpu
gpu_done:
    jalr r0, 0(r15)
gpu_fault:
    halt

; ---------------------------------------------------------------------------
; Job 1, one lane per cube s = i + 4j. Writes a 64-byte record:
; +0 centre height, +4/+16/+32 rotation rows m0/m1/m2 (world -> cube space),
; +48 colour. Angles are in turns; sin(2 pi f) uses a parabola with one
; refinement step (max error about 0.001).
; ---------------------------------------------------------------------------
prep:
    g.id g1, 0                 ; s
    g.li g2, 3
    g.and g3, g1, g2           ; i
    g.li g2, 2
    g.shr g4, g1, g2           ; j
    g.uniform g5, 0
    g.itof g5, g5
    g.fli g2, 0.016666668
    g.fmul g5, g5, g2          ; t in seconds
    g.itof g6, g1
    g.fli g14, 1.0
    g.fli g15, 4.0
    g.fli g16, 0.225
    g.fli g17, 8.0             ; keeps every angle positive for truncation
    ; wave: a diagonal crest every 4 s, a quarter turn behind per cell
    g.add g7, g3, g4
    g.itof g7, g7
    g.fli g2, 0.25
    g.fmul g7, g7, g2
    g.fmul g8, g5, g2
    g.fsub g7, g8, g7
    g.fadd g7, g7, g17
    ; tumble about y (theta) and x (phi), each cube with its own phase
    g.fli g2, 0.13
    g.fmul g8, g5, g2
    g.fli g2, 0.37
    g.fmul g9, g6, g2
    g.fadd g8, g8, g9
    g.fadd g8, g8, g17
    g.fli g2, 0.09
    g.fmul g9, g5, g2
    g.fli g2, 0.23
    g.fmul g10, g6, g2
    g.fadd g9, g9, g10
    g.fadd g9, g9, g17

    ; g18 = sin(wave)
    g.mov g13, g7
    g.fli g2, 0.0
    g.jmp sin_a
sin_a_ret:
    g.mov g18, g12
    ; g19 = sin(theta), g20 = cos(theta)
    g.mov g13, g8
    g.jmp sin_b
sin_b_ret:
    g.mov g19, g12
    g.fli g2, 0.25
    g.fadd g13, g8, g2
    g.jmp sin_c
sin_c_ret:
    g.mov g20, g12
    ; g21 = sin(phi), g22 = cos(phi)
    g.mov g13, g9
    g.jmp sin_d
sin_d_ret:
    g.mov g21, g12
    g.fli g2, 0.25
    g.fadd g13, g9, g2
    g.jmp sin_e
sin_e_ret:
    g.mov g22, g12
    g.jmp record

; One shared sine body; g23 selects where it returns (no calls on this GPU).
sin_a:
    g.li g23, 0
    g.jmp sine
sin_b:
    g.li g23, 1
    g.jmp sine
sin_c:
    g.li g23, 2
    g.jmp sine
sin_d:
    g.li g23, 3
    g.jmp sine
sin_e:
    g.li g23, 4
sine:
    g.ftoi g10, g13
    g.itof g10, g10
    g.fsub g10, g13, g10       ; f = fract(angle)
    g.fadd g10, g10, g10
    g.fsub g10, g10, g14       ; u = 2f - 1, sin(2 pi f) = -sin(pi u)
    g.fsub g11, g0, g10
    g.fmax g11, g11, g10
    g.fmul g11, g10, g11
    g.fsub g11, g10, g11
    g.fmul g11, g11, g15       ; y = 4(u - u|u|)
    g.fsub g12, g0, g11
    g.fmax g12, g12, g11
    g.fmul g12, g11, g12
    g.fsub g12, g12, g11
    g.fmul g12, g12, g16
    g.fadd g12, g12, g11       ; y + 0.225(y|y| - y)
    g.fsub g12, g0, g12
    g.bz g23, sin_a_ret
    g.li g24, 1
    g.sub g23, g23, g24
    g.bz g23, sin_b_ret
    g.sub g23, g23, g24
    g.bz g23, sin_c_ret
    g.sub g23, g23, g24
    g.bz g23, sin_d_ret
    g.jmp sin_e_ret

record:
    g.li g2, 6
    g.shl g24, g1, g2          ; record offset
    g.li g25, 4                ; address step
    ; height: 0.75 + 0.22 sin(wave), so the cube never touches the ground
    g.fli g2, 0.22
    g.fmul g26, g18, g2
    g.fli g2, 0.75
    g.fadd g26, g26, g2
    g.add g27, g3, g4          ; cells with odd i + j stay empty (height -1)
    g.li g2, 1
    g.and g27, g27, g2
    g.bz g27, occupied
    g.fli g26, -1.0
occupied:
    g.st g26, g24, 0
    ; m0 = (cos t, 0, sin t)
    g.add g24, g24, g25
    g.st g20, g24, 0
    g.add g24, g24, g25
    g.st g0, g24, 0
    g.add g24, g24, g25
    g.st g19, g24, 0
    ; m1 = (sin p sin t, cos p, -sin p cos t)
    g.add g24, g24, g25
    g.fmul g26, g21, g19
    g.st g26, g24, 0
    g.add g24, g24, g25
    g.st g22, g24, 0
    g.add g24, g24, g25
    g.fmul g26, g21, g20
    g.fsub g26, g0, g26
    g.st g26, g24, 0
    ; m2 = (-cos p sin t, sin p, cos p cos t)
    g.add g24, g24, g25
    g.add g24, g24, g25
    g.fmul g26, g22, g19
    g.fsub g26, g0, g26
    g.st g26, g24, 0
    g.add g24, g24, g25
    g.st g21, g24, 0
    g.add g24, g24, g25
    g.fmul g26, g22, g20
    g.st g26, g24, 0
    ; colour (i + 3j) mod 4 from the ROM table
    g.add g24, g24, g25
    g.add g24, g24, g25
    g.li g2, 3
    g.mul g26, g4, g2
    g.add g26, g26, g3
    g.and g26, g26, g2
    g.li g2, 12
    g.mul g26, g26, g2
    g.ld g27, g26, 1
    g.st g27, g24, 0
    g.add g24, g24, g25
    g.add g26, g26, g25
    g.ld g27, g26, 1
    g.st g27, g24, 0
    g.add g24, g24, g25
    g.add g26, g26, g25
    g.ld g27, g26, 1
    g.st g27, g24, 0
    g.end
prep_end:

; ---------------------------------------------------------------------------
; Job 2, one lane per pixel.
; g1..3 ray origin, g4..6 direction, g7 ray length to leave the slab,
; g8/g9 cell ix/iz, g10 ground factor, g11 record offset, g12/g13 distance to
; the next x/z cell edge, g14/g15 distance per cell, g16 0 = camera ray,
; 1 = shadow ray, g17..20 bounding sphere, g21.. cube test and shading.
; ---------------------------------------------------------------------------
trace:
    g.id g21, 0
    g.itof g21, g21
    g.fli g22, -79.5
    g.fadd g21, g21, g22
    g.fli g22, 0.035355339     ; 1/28.28 world units per pixel
    g.fmul g21, g21, g22       ; su, along R = (0.7071, 0, -0.7071)
    g.id g23, 1
    g.itof g23, g23
    g.fli g24, 59.5
    g.fsub g23, g24, g23
    g.fmul g23, g23, g22       ; sv, along Up = (0.5303, 0.6614, 0.5303)
    g.fli g24, 0.70710678
    g.fmul g24, g21, g24
    g.fli g25, 0.53033009
    g.fmul g25, g23, g25
    g.fli g26, 64.0            ; look at (64, 0.75, 64), clear of zero
    g.fadd g1, g26, g24
    g.fadd g1, g1, g25
    g.fsub g3, g26, g24
    g.fadd g3, g3, g25
    g.fli g26, 0.66143783
    g.fmul g2, g23, g26
    g.fli g26, 0.75
    g.fadd g2, g2, g26
    g.fli g4, 0.46770717       ; view direction (1, -k, 1) / n, k/n = 0.75
    g.fli g5, -0.75
    g.mov g6, g4
    g.fli g26, 1.5             ; slide the origin to y = 1.5, above every cube
    g.fsub g26, g26, g2
    g.fdiv g26, g26, g5
    g.vscale g21, g4, g26
    g.vadd g1, g1, g21
    g.fli g7, 2.0              ; y 1.5 -> 0
    g.mov g16, g0

; Walk the cells the ray crosses (Amanatides-Woo), nearest first.
walk:
    g.ftoi g8, g1
    g.ftoi g9, g3
    g.fli g29, 1.0
    g.fsub g14, g0, g4
    g.fmax g14, g14, g4
    g.fdiv g14, g29, g14
    g.itof g12, g8
    g.fsub g12, g1, g12
    g.flt g30, g0, g4
    g.bz g30, walk_x
    g.fsub g12, g29, g12
walk_x:
    g.fmul g12, g12, g14
    g.fsub g15, g0, g6
    g.fmax g15, g15, g6
    g.fdiv g15, g29, g15
    g.itof g13, g9
    g.fsub g13, g3, g13
    g.flt g30, g0, g6
    g.bz g30, walk_z
    g.fsub g13, g29, g13
walk_z:
    g.fmul g13, g13, g15

cell:
    g.li g30, 3
    g.and g11, g8, g30
    g.and g30, g9, g30
    g.li g31, 2
    g.shl g30, g30, g31
    g.add g11, g11, g30
    g.li g30, 6
    g.shl g11, g11, g30
    g.ld g18, g11, 1           ; cube centre height; negative = empty cell
    g.flt g30, g18, g0
    g.bnz g30, step
    g.itof g17, g8
    g.fli g30, 0.5
    g.fadd g17, g17, g30
    g.itof g19, g9
    g.fadd g19, g19, g30
    g.fli g20, 0.47            ; bounding sphere: half-size 0.27 * sqrt 3
    g.sphere g21, g1, g4, g17
    g.flt g21, g21, g0
    g.bnz g21, step

    ; Slab test in cube space: o' = M (O - c), d' = M D, half-size 0.27.
    g.vsub g21, g1, g17
    g.fli g31, -1000.0         ; t near
    g.fli g20, 1000.0          ; t far
    g.li g17, 0                ; entry face: row offset, +256 when d' < 0

    g.li g18, 4
    g.add g18, g18, g11
    g.ld g24, g18, 1
    g.li g19, 4
    g.add g18, g18, g19
    g.ld g25, g18, 1
    g.add g18, g18, g19
    g.ld g26, g18, 1
    g.dot3 g27, g24, g21
    g.dot3 g28, g24, g4
    g.fsub g30, g0, g28
    g.fmax g30, g30, g28
    g.bnz g30, slab0
    g.fli g28, 0.000001
slab0:
    g.fli g19, 0.27
    g.fsub g30, g19, g27
    g.fdiv g30, g30, g28
    g.fsub g29, g0, g19
    g.fsub g29, g29, g27
    g.fdiv g29, g29, g28
    g.fmin g19, g29, g30
    g.fmax g29, g29, g30
    g.fmin g20, g20, g29
    g.flt g30, g31, g19
    g.bz g30, slab0_done
    g.mov g31, g19
    g.li g17, 4
    g.flt g30, g28, g0
    g.bz g30, slab0_done
    g.li g17, 260
slab0_done:

    g.li g18, 16
    g.add g18, g18, g11
    g.ld g24, g18, 1
    g.li g19, 4
    g.add g18, g18, g19
    g.ld g25, g18, 1
    g.add g18, g18, g19
    g.ld g26, g18, 1
    g.dot3 g27, g24, g21
    g.dot3 g28, g24, g4
    g.fsub g30, g0, g28
    g.fmax g30, g30, g28
    g.bnz g30, slab1
    g.fli g28, 0.000001
slab1:
    g.fli g19, 0.27
    g.fsub g30, g19, g27
    g.fdiv g30, g30, g28
    g.fsub g29, g0, g19
    g.fsub g29, g29, g27
    g.fdiv g29, g29, g28
    g.fmin g19, g29, g30
    g.fmax g29, g29, g30
    g.fmin g20, g20, g29
    g.flt g30, g31, g19
    g.bz g30, slab1_done
    g.mov g31, g19
    g.li g17, 16
    g.flt g30, g28, g0
    g.bz g30, slab1_done
    g.li g17, 272
slab1_done:

    g.li g18, 32
    g.add g18, g18, g11
    g.ld g24, g18, 1
    g.li g19, 4
    g.add g18, g18, g19
    g.ld g25, g18, 1
    g.add g18, g18, g19
    g.ld g26, g18, 1
    g.dot3 g27, g24, g21
    g.dot3 g28, g24, g4
    g.fsub g30, g0, g28
    g.fmax g30, g30, g28
    g.bnz g30, slab2
    g.fli g28, 0.000001
slab2:
    g.fli g19, 0.27
    g.fsub g30, g19, g27
    g.fdiv g30, g30, g28
    g.fsub g29, g0, g19
    g.fsub g29, g29, g27
    g.fdiv g29, g29, g28
    g.fmin g19, g29, g30
    g.fmax g29, g29, g30
    g.fmin g20, g20, g29
    g.flt g30, g31, g19
    g.bz g30, slab2_done
    g.mov g31, g19
    g.li g17, 32
    g.flt g30, g28, g0
    g.bz g30, slab2_done
    g.li g17, 288
slab2_done:

    g.fle g30, g31, g20        ; hit when near <= far and far > 0
    g.bz g30, step
    g.flt g30, g0, g20
    g.bz g30, step
    g.bz g16, shade_cube
    g.jmp ground_shadowed

step:
    g.flt g30, g12, g13
    g.bz g30, step_z
    g.mov g21, g12
    g.fadd g12, g12, g14
    g.li g30, 1
    g.flt g31, g0, g4
    g.bnz g31, step_x
    g.sub g30, g0, g30
step_x:
    g.add g8, g8, g30
    g.jmp stepped
step_z:
    g.mov g21, g13
    g.fadd g13, g13, g15
    g.li g30, 1
    g.flt g31, g0, g6
    g.bnz g31, step_z2
    g.sub g30, g0, g30
step_z2:
    g.add g9, g9, g30
stepped:
    g.flt g30, g7, g21         ; left the slab?
    g.bz g30, cell
    g.bz g16, ground
    g.jmp ground_lit

shade_cube:
    ; normal = row of the entry face, facing the ray
    g.li g30, 255
    g.and g18, g17, g30
    g.add g18, g18, g11
    g.ld g21, g18, 1
    g.li g19, 4
    g.add g18, g18, g19
    g.ld g22, g18, 1
    g.add g18, g18, g19
    g.ld g23, g18, 1
    g.li g30, 256
    g.and g30, g17, g30
    g.bnz g30, lit_face
    g.fli g30, -1.0
    g.vscale g21, g21, g30
lit_face:
    g.li g18, 48
    g.add g18, g18, g11
    g.ld g24, g18, 1
    g.add g18, g18, g19
    g.ld g25, g18, 1
    g.add g18, g18, g19
    g.ld g26, g18, 1
    g.fli g27, -0.617          ; sun direction
    g.fli g28, 0.772
    g.fli g29, 0.154
    g.dot3 g30, g21, g27
    g.fmax g30, g30, g0
    g.fli g31, 0.8
    g.fmul g30, g30, g31
    g.fli g31, 0.24
    g.fadd g30, g30, g31
    g.vscale g24, g24, g30
    g.reflect3 g8, g4, g21
    g.dot3 g30, g8, g27
    g.fmax g30, g30, g0
    g.fmul g30, g30, g30
    g.fmul g30, g30, g30
    g.fmul g30, g30, g30
    g.fli g31, 0.35
    g.fmul g30, g30, g31
    g.fadd g24, g24, g30
    g.fadd g25, g25, g30
    g.fadd g26, g26, g30
    g.jmp store

ground:
    g.vscale g21, g4, g7
    g.vadd g1, g1, g21         ; ground point
    g.ftoi g21, g1
    g.itof g21, g21
    g.fsub g21, g1, g21        ; position within the cell
    g.ftoi g23, g3
    g.itof g23, g23
    g.fsub g23, g3, g23
    ; contact darkening under each cube, and faint cell lines
    g.fli g30, 0.5
    g.fsub g24, g21, g30
    g.fsub g25, g23, g30
    g.fmul g24, g24, g24
    g.fmul g25, g25, g25
    g.fadd g24, g24, g25
    g.sqrt g24, g24
    g.fli g30, 1.1
    g.fmul g24, g24, g30
    g.fli g30, 0.6
    g.fadd g24, g24, g30
    g.fli g30, 1.0
    g.fmin g10, g24, g30
    g.fsub g25, g30, g21
    g.fmin g25, g25, g21
    g.fsub g26, g30, g23
    g.fmin g26, g26, g23
    g.fmin g25, g25, g26
    g.fli g26, 0.025
    g.flt g26, g25, g26
    g.bz g26, sun_ray
    g.fli g26, 0.9
    g.fmul g10, g10, g26
sun_ray:
    g.fli g2, 0.001
    g.fli g4, -0.617
    g.fli g5, 0.772
    g.fli g6, 0.154
    g.fli g7, 1.95             ; y 0 -> 1.5 along the sun direction
    g.li g16, 1
    g.jmp walk

ground_shadowed:
    g.fli g30, 0.62
    g.jmp ground_shade
ground_lit:
    g.fli g30, 1.0
ground_shade:
    g.fmul g30, g30, g10
    g.fli g31, 0.5             ; open ground is exactly mid grey
    g.fmul g24, g30, g31
    g.mov g25, g24
    g.mov g26, g24
store:
    g.id g30, 2
    g.rgb g24, g30, 0
    g.end
trace_end:

colours:
    .float 1.0, 0.42, 0.26     ; the site's orange
    .float 0.2, 0.62, 0.6      ; GPU teal
    .float 0.92, 0.9, 0.86     ; paper
    .float 0.52, 0.42, 0.92    ; SPU violet
colours_end:
