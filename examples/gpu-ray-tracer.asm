; GPU-1 Whitted ray tracer. One invocation traces a ray into RGB888 output.
; Three primary/reflected surface hits, with finite point-light shadow rays
; from every surface (the floor and all three spheres). All scene traversal,
; normals, material selection, lighting, and reflection live in this kernel.
; The CPU owns only dispatch, a small triangular light animation, and page flips.
.profile gpu-1
.equ GPU, 0xf3000
.equ VIDEO, 0xf5000
.equ FB_A, 0x10000
.equ FB_B, 0x1e100
.equ RGB_BYTES, 57600
; 0: one ray per pixel (160x120); 1: 80x60 rays, each fills a 2x2 block.
.equ PIXEL_SHIFT, 0
.entry start

start:
    li r1, FB_A              ; render target, then displayed page
    li r2, FB_B              ; other page
    li r3, GPU
    li r4, kernel
    sw r4, 0(r3)
    li r4, kernel_end-kernel
    sw r4, 4(r3)
    li r4, 160
    li r10, PIXEL_SHIFT
    shr r4, r4, r10
    sw r4, 8(r3)
    li r4, 120
    shr r4, r4, r10
    sw r4, 12(r3)
    li r4, RGB_BYTES
    sw r4, 0x44(r3)
    li r4, 3
    sw r4, 0x48(r3)        ; binding 0: RGB888 output, RAM read/write
    li r4, scene
    sw r4, 0x50(r3)
    li r4, scene_end-scene
    sw r4, 0x54(r3)
    li r4, 1
    sw r4, 0x58(r3)        ; binding 1: counted ROM scene, read-only

    li r5, VIDEO
    li r4, 480
    sw r4, 4(r5)
    li r4, 4
    sw r4, 8(r5)           ; RGB888
    li r4, 1
    sw r4, 16(r5)          ; enable scanout
    mov r6, r0             ; animation frame

frame:
    sw r1, 0x40(r3)        ; lease only the current back buffer
    andi r8, r6, 63
    li r9, 32
    bltu r8, r9, triangle_ready
    li r9, 63
    sub r8, r9, r8
triangle_ready:
    addi r8, r8, -16
    sw r8, 0x100(r3)       ; uniform 0: signed light displacement
    li r4, 1
    sw r4, 16(r3)          ; START exactly once
wait_gpu:
    lw r4, 20(r3)
    li r9, 3
    beq r4, r9, gpu_fault
    li r9, 2
    beq r4, r9, gpu_done
    wfi                    ; gpu-1 wakes on completion or vblank
    j wait_gpu
gpu_done:
    sw r1, 0(r5)           ; queue completed page for next vblank
    li r4, 1
    sw r4, 20(r5)          ; COMMIT
    wfi                    ; this wake is the committing vblank
    mov r4, r1
    mov r1, r2
    mov r2, r4
    addi r6, r6, 1
    j frame
gpu_fault:
    halt

; Register map across the bounce loop:
; g1..3 ray origin / later finite shadow direction; g4..6 ray direction;
; g7 throughput; g8..10 accumulated radiance; g11 hits remaining;
; g12 nearest t / shadow flag; g13 hit ID (1 floor, 2..4 spheres);
; g19..21 hit point; g22..24 normal; g25..27 material colour.
kernel:
    g.mov g1, g0
    g.mov g2, g0
    g.mov g3, g0
    g.id g4, 0
    g.li g28, PIXEL_SHIFT
    g.shl g4, g4, g28
    g.itof g4, g4
    g.bz g28, camera_x_ready
    g.fli g29, 0.5       ; sample the centre of each 2x2 output block
    g.fadd g4, g4, g29
camera_x_ready:
    g.fli g28, 80.0
    g.fsub g4, g4, g28
    g.fli g28, 0.015625
    g.fmul g4, g4, g28
    g.id g5, 1
    g.li g28, PIXEL_SHIFT
    g.shl g5, g5, g28
    g.itof g5, g5
    g.bz g28, camera_y_ready
    g.fadd g5, g5, g29
camera_y_ready:
    g.fli g28, 40.0
    g.fsub g5, g28, g5
    g.fli g28, 0.015625
    g.fmul g5, g5, g28
    g.fli g6, 2.0
    g.norm3 g4, g4
    g.fli g7, 1.0
    g.mov g8, g0
    g.mov g9, g0
    g.mov g10, g0
    g.li g11, 3

bounce:
    g.fli g12, 200.0
    g.mov g13, g0
    ; Plane y=-9. Only forward intersections nearer than the current hit.
    g.flt g14, g5, g0
    g.bz g14, trace_spheres
    g.fli g14, -9.0
    g.fsub g14, g14, g2
    g.fdiv g14, g14, g5
    g.fli g15, 0.001
    g.flt g16, g15, g14
    g.bz g16, trace_spheres
    g.flt g16, g14, g12
    g.bz g16, trace_spheres
    g.mov g12, g14
    g.li g13, 1

trace_spheres:
    g.li g27, 4            ; byte stride between float fields
    g.mov g28, g0          ; scene record offset
    g.li g29, 2            ; first sphere hit ID
    g.li g30, 5            ; exclusive hit ID end
    g.li g31, 16           ; last-field to next-record offset
sphere_loop:
    g.ld g15, g28, 1
    g.add g28, g28, g27
    g.ld g16, g28, 1
    g.add g28, g28, g27
    g.ld g17, g28, 1
    g.add g28, g28, g27
    g.ld g18, g28, 1
    g.sphere g14, g1, g4, g15
    g.flt g18, g0, g14
    g.bz g18, sphere_next
    g.flt g18, g14, g12
    g.bz g18, sphere_next
    g.mov g12, g14
    g.mov g13, g29
sphere_next:
    g.add g28, g28, g31
    g.li g17, 1
    g.add g29, g29, g17
    g.slt g17, g29, g30
    g.bnz g17, sphere_loop
    g.bz g13, sky

    ; P = O + tD. Reflections from this P re-enter the same scene traversal.
    g.vscale g19, g4, g12
    g.vadd g19, g1, g19
    g.li g14, 1
    g.sub g14, g13, g14
    g.bz g14, floor_material

    ; Sphere normal and material from the selected counted scene record.
    g.li g28, 2
    g.sub g28, g13, g28
    g.li g29, 28
    g.mul g28, g28, g29
    g.li g29, 4
    g.ld g15, g28, 1
    g.add g28, g28, g29
    g.ld g16, g28, 1
    g.add g28, g28, g29
    g.ld g17, g28, 1
    g.vsub g22, g19, g15
    g.norm3 g22, g22
    g.add g28, g28, g29
    g.add g28, g28, g29
    g.ld g25, g28, 1
    g.add g28, g28, g29
    g.ld g26, g28, 1
    g.add g28, g28, g29
    g.ld g27, g28, 1
    g.jmp material_ready

floor_material:
    g.mov g22, g0
    g.fli g23, 1.0
    g.mov g24, g0
    ; Offset by an even tile count before truncation, giving floor-style
    ; checker indices for every visible negative world coordinate.
    g.fli g28, 0.125
    g.fli g29, 256.0
    g.fadd g30, g21, g29
    g.fadd g29, g19, g29
    g.fmul g29, g29, g28
    g.fmul g30, g30, g28
    g.ftoi g29, g29
    g.ftoi g30, g30
    g.xor g29, g29, g30
    g.li g30, 1
    g.and g29, g29, g30
    g.bz g29, floor_dark
    g.fli g25, 0.68
    g.fli g26, 0.76
    g.fli g27, 0.86
    g.jmp material_ready
floor_dark:
    g.fli g25, 0.16
    g.fli g26, 0.22
    g.fli g27, 0.29

material_ready:
    ; Dshadow = light-P: t in (0,1) is a finite point-light occluder.
    ; The same test runs for floor and sphere hits, including self-shadowing
    ; on a sphere's far side. GPU uniform animation is converted in kernel.
    g.uniform g1, 0
    g.itof g1, g1
    g.fli g15, 0.18
    g.fmul g1, g1, g15
    g.fli g15, -5.0
    g.fadd g1, g1, g15
    g.fsub g1, g1, g19
    g.fli g2, 10.0
    g.fsub g2, g2, g20
    g.fli g3, 16.0
    g.fsub g3, g3, g21
    ; Mild inverse-square point-light falloff, kept for diffuse and specular.
    g.dot3 g31, g1, g1
    g.fli g15, 0.001
    g.fmul g31, g31, g15
    g.fli g15, 1.0
    g.fadd g31, g31, g15
    g.fdiv g31, g15, g31
    g.mov g12, g0          ; no occluder yet
    g.mov g28, g0
    g.li g29, 4
    g.li g30, 16
shadow_loop:
    g.ld g15, g28, 1
    g.add g28, g28, g29
    g.ld g16, g28, 1
    g.add g28, g28, g29
    g.ld g17, g28, 1
    g.add g28, g28, g29
    g.ld g18, g28, 1
    g.sphere g14, g19, g1, g15
    g.flt g18, g0, g14
    g.bz g18, shadow_next
    g.fli g18, 1.0
    g.flt g18, g14, g18
    g.bz g18, shadow_next
    g.li g12, 1
    g.jmp shadow_done
shadow_next:
    g.add g28, g28, g30
    g.li g18, 84
    g.slt g18, g28, g18
    g.bnz g18, shadow_loop
shadow_done:
    g.norm3 g1, g1
    g.dot3 g14, g22, g1
    g.fmax g14, g14, g0
    g.bz g12, lit
    g.mov g14, g0
lit:
    g.fli g15, 0.82
    g.fmul g14, g14, g15
    g.fmul g14, g14, g31
    g.fli g15, 0.18
    g.fadd g14, g14, g15
    g.fmul g14, g14, g7
    g.fli g15, 0.55
    g.fmul g14, g14, g15
    g.vscale g28, g25, g14
    g.vadd g8, g8, g28
    g.bnz g12, no_specular
    ; A narrow white highlight from the reflected view ray.
    g.reflect3 g15, g4, g22
    g.dot3 g18, g15, g1
    g.fmax g18, g18, g0
    g.fmul g18, g18, g18
    g.fmul g18, g18, g18
    g.fmul g18, g18, g18
    g.fli g15, 0.32
    g.fmul g18, g18, g15
    g.fmul g18, g18, g31
    g.fmul g18, g18, g7
    g.fadd g8, g8, g18
    g.fadd g9, g9, g18
    g.fadd g10, g10, g18
no_specular:

    g.li g15, 1
    g.sub g11, g11, g15
    g.bz g11, store_pixel
    ; Shift the new ray origin a little along N to avoid self-intersection.
    g.reflect3 g4, g4, g22
    g.fli g15, 0.002
    g.vscale g28, g22, g15
    g.vadd g1, g19, g28
    g.fli g15, 0.45
    g.fmul g7, g7, g15
    g.jmp bounce

sky:
    g.fli g25, 0.055
    g.fli g26, 0.11
    g.fli g27, 0.22
    g.vscale g28, g25, g7
    g.vadd g8, g8, g28
store_pixel:
    ; Display transfer: sqrt brightens linear radiance before RGB888 clamp.
    g.sqrt g8, g8
    g.sqrt g9, g9
    g.sqrt g10, g10
    g.li g15, PIXEL_SHIFT
    g.bz g15, store_single
    ; At half ray resolution, four disjoint RGB888 writes fill the full
    ; output surface. Every lane owns one block, so no lanes overlap.
    g.id g14, 0
    g.id g15, 1
    g.li g16, 1
    g.shl g14, g14, g16
    g.shl g15, g15, g16
    g.li g16, 160
    g.mul g15, g15, g16
    g.add g14, g14, g15
    g.rgb g8, g14, 0
    g.li g16, 1
    g.add g17, g14, g16
    g.rgb g8, g17, 0
    g.li g16, 160
    g.add g17, g14, g16
    g.rgb g8, g17, 0
    g.li g16, 1
    g.add g17, g17, g16
    g.rgb g8, g17, 0
    g.end
store_single:
    g.id g14, 2
    g.rgb g8, g14, 0
    g.end
kernel_end:

; xyz, radius, RGB in IEEE binary32. The 84 bytes count toward the cap.
scene:
    .float -10.0, -1.0, 37.5, 8.0, 0.28, 0.75, 0.78
    .float 12.0, -1.0, 46.25, 8.0, 0.94, 0.45, 0.27
    .float 0.0, -5.0, 27.0, 4.0, 0.72, 0.79, 0.96
scene_end:
