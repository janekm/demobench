; CPU Whitted ray tracer: three reflective spheres and a checkerboard.
; Three surface hits per pixel; every hit casts a finite ray to a point light.
; Positions/distances use Q4; unit directions/normals Q10; colours/weights Q8.
; Integer normalization, square root and division run on the guest CPU.
; r15 is scratch RAM; no image assets, host shading, or GPU instructions.
; Scratch offsets: O 0, D 12, N 24, hit 36, t 40, skip 44, pixel state 48..76,
; material 80..92, light 96..104, reflected D 108, call/math workspace 120..148.
.equ FB, 0x10000
.equ VIDEO, 0xf5000
.equ SCRATCH, 0x2f000
.equ MAX_HITS, 3
.equ SHADOWS, 1
.entry start
start:
    li r15, SCRATCH
    li r1, FB
    sw r1, 48(r15)
    li r7, VIDEO
    sw r1, 0(r7)
    addi r8, r0, 480
    sw r8, 4(r7)
    addi r8, r0, 4
    sw r8, 8(r7)
    addi r8, r0, 1
    sw r8, 16(r7)
    sw r8, 20(r7)
    sw r0, 56(r15)
row:
    sw r0, 52(r15)
pixel:
    sw r0, 0(r15)
    sw r0, 4(r15)
    sw r0, 8(r15)
    sw r0, 44(r15)
    sw r0, 68(r15)
    sw r0, 72(r15)
    sw r0, 76(r15)
    addi r1, r0, MAX_HITS
    sw r1, 60(r15)
    addi r1, r0, 256
    sw r1, 64(r15)
    lw r1, 52(r15)
    addi r1, r1, -80
    addi r3, r0, 4
    shl r1, r1, r3
    sw r1, 12(r15)
    lw r1, 56(r15)
    addi r2, r0, 40
    sub r1, r2, r1
    shl r1, r1, r3
    sw r1, 16(r15)
    addi r1, r0, 2048
    sw r1, 20(r15)
    addi r7, r15, 12
    jal r14, normalize
bounce:
    addi r1, r0, 8192       ; far plane: 512 world units
    sw r1, 40(r15)
    jal r14, trace
    lw r7, 36(r15)
    beq r7, r0, sky
    sw r7, 44(r15)         ; convex surface cannot hit itself on next ray
    ; Move the ray origin to the closest hit.
    lw r2, 40(r15)
    addi r3, r0, 10
    lw r1, 12(r15)
    mul r1, r1, r2
    sar r1, r1, r3
    lw r4, 0(r15)
    add r1, r1, r4
    sw r1, 0(r15)
    lw r1, 16(r15)
    mul r1, r1, r2
    sar r1, r1, r3
    lw r4, 4(r15)
    add r1, r1, r4
    sw r1, 4(r15)
    lw r1, 20(r15)
    mul r1, r1, r2
    sar r1, r1, r3
    lw r4, 8(r15)
    add r1, r1, r4
    sw r1, 8(r15)
    addi r1, r0, 1
    beq r7, r1, floor_material
    ; Sphere normals are normalized again to bound fixed-point error.
    lw r1, 0(r15)
    lw r2, 0(r7)
    sub r1, r1, r2
    sw r1, 24(r15)
    lw r1, 4(r15)
    lw r2, 4(r7)
    sub r1, r1, r2
    sw r1, 28(r15)
    lw r1, 8(r15)
    lw r2, 8(r7)
    sub r1, r1, r2
    sw r1, 32(r15)
    lw r1, 16(r7)
    sw r1, 92(r15)
    lw r8, 20(r7)
    addi r7, r15, 24
    sw r8, 148(r15)
    jal r14, normalize
    lw r8, 148(r15)
    j unpack_material
floor_material:
    sw r0, 24(r15)
    sw r0, 32(r15)
    addi r1, r0, 1024
    sw r1, 28(r15)
    addi r1, r0, 88
    sw r1, 92(r15)
    lw r1, 0(r15)
    lw r2, 8(r15)
    addi r3, r0, 7         ; eight-unit checkerboard squares
    sar r1, r1, r3
    sar r2, r2, r3
    xor r1, r1, r2
    andi r1, r1, 1
    li r8, 0xb4c7d2
    bne r1, r0, unpack_material
    li r8, 0x34495c
unpack_material:
    addi r1, r0, 16
    shr r2, r8, r1
    sw r2, 80(r15)
    addi r1, r0, 8
    shr r2, r8, r1
    andi r2, r2, 255
    sw r2, 84(r15)
    andi r2, r8, 255
    sw r2, 88(r15)
    ; Reflect the incoming direction: R = D - 2*dot(D,N)*N.
    mov r4, r0
    lw r1, 12(r15)
    lw r2, 24(r15)
    mul r1, r1, r2
    add r4, r4, r1
    lw r1, 16(r15)
    lw r2, 28(r15)
    mul r1, r1, r2
    add r4, r4, r1
    lw r1, 20(r15)
    lw r2, 32(r15)
    mul r1, r1, r2
    add r4, r4, r1
    addi r3, r0, 9
    sar r4, r4, r3
    addi r3, r0, 10
    lw r1, 24(r15)
    mul r1, r1, r4
    sar r1, r1, r3
    lw r2, 12(r15)
    sub r2, r2, r1
    sw r2, 108(r15)
    lw r1, 28(r15)
    mul r1, r1, r4
    sar r1, r1, r3
    lw r2, 16(r15)
    sub r2, r2, r1
    sw r2, 112(r15)
    lw r1, 32(r15)
    mul r1, r1, r4
    sar r1, r1, r3
    lw r2, 20(r15)
    sub r2, r2, r1
    sw r2, 116(r15)
    addi r7, r15, 108
    jal r14, normalize
    ; Point light (-30, 12, 18). Normalize its hit-to-light direction.
    addi r1, r0, -480
    lw r2, 0(r15)
    sub r1, r1, r2
    sw r1, 12(r15)
    addi r1, r0, 192
    lw r2, 4(r15)
    sub r1, r1, r2
    sw r1, 16(r15)
    addi r1, r0, 288
    lw r2, 8(r15)
    sub r1, r1, r2
    sw r1, 20(r15)
    addi r7, r15, 12
    jal r14, normalize
    lw r1, 136(r15)
    sw r1, 96(r15)         ; finite shadow-ray limit, in Q4
    mov r4, r0
    mov r5, r0
    lw r1, 12(r15)
    lw r2, 24(r15)
    mul r2, r2, r1
    add r4, r4, r2
    lw r2, 108(r15)
    mul r2, r2, r1
    add r5, r5, r2
    lw r1, 16(r15)
    lw r2, 28(r15)
    mul r2, r2, r1
    add r4, r4, r2
    lw r2, 112(r15)
    mul r2, r2, r1
    add r5, r5, r2
    lw r1, 20(r15)
    lw r2, 32(r15)
    mul r2, r2, r1
    add r4, r4, r2
    lw r2, 116(r15)
    mul r2, r2, r1
    add r5, r5, r2
    sw r0, 100(r15)
    sw r0, 104(r15)
    blt r4, r0, lighting_ready
    addi r3, r0, 12
    sar r4, r4, r3
    sw r4, 100(r15)        ; Lambert cosine, Q8
    blt r5, r0, specular_ready
    addi r3, r0, 10
    sar r5, r5, r3
    addi r1, r0, 1024
    bltu r5, r1, specular_power
    mov r5, r1
specular_power:
    mul r5, r5, r5
    shr r5, r5, r3
    mul r5, r5, r5
    shr r5, r5, r3
    mul r5, r5, r5
    shr r5, r5, r3
    mul r5, r5, r5
    shr r5, r5, r3
    addi r3, r0, 3
    shr r5, r5, r3
    sw r5, 104(r15)
specular_ready:
    addi r1, r0, SHADOWS
    beq r1, r0, unoccluded
    lw r1, 96(r15)
    sw r1, 40(r15)
    jal r14, trace         ; same geometry for lighting and reflected rays
    lw r1, 36(r15)
    beq r1, r0, unoccluded
    sw r0, 100(r15)
    sw r0, 104(r15)
    j lighting_ready
unoccluded:
    ; Point-light intensity falls as 4800/(2400+d*d).
    lw r1, 96(r15)
    addi r2, r0, 4
    shr r1, r1, r2
    mul r11, r1, r1
    addi r11, r11, 2400
    li r10, 1228800
    jal r13, divide
    addi r3, r0, 8
    lw r1, 100(r15)
    mul r1, r1, r12
    shr r1, r1, r3
    sw r1, 100(r15)
    lw r1, 104(r15)
    mul r1, r1, r12
    shr r1, r1, r3
    sw r1, 104(r15)
lighting_ready:
    lw r4, 100(r15)
    addi r4, r4, 28        ; small constant ambient term, not GI
    lw r5, 104(r15)
    lw r6, 92(r15)
    lw r7, 64(r15)
    addi r1, r0, 256
    sub r1, r1, r6
    mul r8, r7, r1
    addi r3, r0, 8
    shr r8, r8, r3
    lw r1, 60(r15)
    addi r2, r0, 1
    bne r1, r2, local_weight
    mov r8, r7            ; at the depth cap, use the terminal surface shade
local_weight:
    lw r1, 80(r15)
    mul r1, r1, r4
    shr r1, r1, r3
    add r1, r1, r5
    mul r1, r1, r8
    shr r1, r1, r3
    lw r2, 68(r15)
    add r1, r1, r2
    sw r1, 68(r15)
    lw r1, 84(r15)
    mul r1, r1, r4
    shr r1, r1, r3
    add r1, r1, r5
    mul r1, r1, r8
    shr r1, r1, r3
    lw r2, 72(r15)
    add r1, r1, r2
    sw r1, 72(r15)
    lw r1, 88(r15)
    mul r1, r1, r4
    shr r1, r1, r3
    add r1, r1, r5
    mul r1, r1, r8
    shr r1, r1, r3
    lw r2, 76(r15)
    add r1, r1, r2
    sw r1, 76(r15)
    lw r1, 60(r15)
    addi r1, r1, -1
    sw r1, 60(r15)
    beq r1, r0, write_pixel
    mul r7, r7, r6
    shr r7, r7, r3
    sw r7, 64(r15)
    lw r1, 108(r15)
    sw r1, 12(r15)
    lw r1, 112(r15)
    sw r1, 16(r15)
    lw r1, 116(r15)
    sw r1, 20(r15)
    j bounce
sky:
    ; Direction-dependent blue environment, also visible in curved mirrors.
    lw r4, 16(r15)
    addi r4, r4, 1024
    addi r3, r0, 6
    sar r4, r4, r3
    addi r1, r4, 14
    sw r1, 80(r15)
    add r1, r4, r4
    addi r1, r1, 25
    sw r1, 84(r15)
    addi r1, r1, 28
    sw r1, 88(r15)
    lw r7, 64(r15)
    addi r3, r0, 8
    lw r1, 80(r15)
    mul r1, r1, r7
    shr r1, r1, r3
    lw r2, 68(r15)
    add r1, r1, r2
    sw r1, 68(r15)
    lw r1, 84(r15)
    mul r1, r1, r7
    shr r1, r1, r3
    lw r2, 72(r15)
    add r1, r1, r2
    sw r1, 72(r15)
    lw r1, 88(r15)
    mul r1, r1, r7
    shr r1, r1, r3
    lw r2, 76(r15)
    add r1, r1, r2
    sw r1, 76(r15)
write_pixel:
    lw r7, 48(r15)
    addi r2, r0, 255
    lw r1, 68(r15)
    bltu r1, r2, channel_0
    mov r1, r2
channel_0:
    mul r10, r1, r2       ; gamma ~= 2: sqrt(linear * 255)
    jal r13, square_root
    sb r12, 0(r7)
    lw r1, 72(r15)
    bltu r1, r2, channel_1
    mov r1, r2
channel_1:
    mul r10, r1, r2
    jal r13, square_root
    sb r12, 1(r7)
    lw r1, 76(r15)
    bltu r1, r2, channel_2
    mov r1, r2
channel_2:
    mul r10, r1, r2
    jal r13, square_root
    sb r12, 2(r7)
    addi r7, r7, 3
    sw r7, 48(r15)
    lw r1, 52(r15)
    addi r1, r1, 1
    sw r1, 52(r15)
    addi r2, r0, 160
    bltu r1, r2, pixel
    lw r1, 56(r15)
    addi r1, r1, 1
    sw r1, 56(r15)
    addi r2, r0, 120
    bltu r1, r2, row
    halt

; Nearest hit from one Q4 step up to (excluding) tMax; floor y=-9.
; Unit-direction intersection: b=dot(C-O,D), disc=b*b-|C-O|^2+r*r.
; Q10 normalization is approximate; Q4 hit positions bound scene precision.
; Convex source object is skipped to avoid quantized surface self-intersections.
trace:
    sw r14, 120(r15)
    sw r0, 36(r15)
    li r7, spheres
trace_sphere:
    lw r1, 44(r15)
    beq r1, r7, trace_next
    mov r4, r0
    mov r5, r0
    addi r3, r0, 10
    lw r1, 0(r7)
    lw r2, 0(r15)
    sub r1, r1, r2
    mul r2, r1, r1
    add r5, r5, r2
    lw r2, 12(r15)
    mul r1, r1, r2
    add r4, r4, r1
    lw r1, 4(r7)
    lw r2, 4(r15)
    sub r1, r1, r2
    mul r2, r1, r1
    add r5, r5, r2
    lw r2, 16(r15)
    mul r1, r1, r2
    add r4, r4, r1
    lw r1, 8(r7)
    lw r2, 8(r15)
    sub r1, r1, r2
    mul r2, r1, r1
    add r5, r5, r2
    lw r2, 20(r15)
    mul r1, r1, r2
    add r4, r4, r1
    sar r4, r4, r3
    blt r4, r0, trace_next
    sw r4, 128(r15)
    mul r10, r4, r4
    sub r10, r10, r5
    lw r1, 12(r7)
    add r10, r10, r1
    blt r10, r0, trace_next
    jal r13, square_root
    lw r1, 128(r15)
    sub r12, r1, r12
    addi r1, r0, 1
    blt r12, r1, trace_next
    lw r1, 40(r15)
    sltu r2, r12, r1
    beq r2, r0, trace_next
    sw r12, 40(r15)
    sw r7, 36(r15)
trace_next:
    addi r7, r7, 24
    li r1, spheres_end
    bltu r7, r1, trace_sphere
    lw r1, 44(r15)
    addi r2, r0, 1
    beq r1, r2, trace_return
    lw r11, 16(r15)
    blt r11, r0, trace_floor
    j trace_return
trace_floor:
    lw r10, 4(r15)
    addi r10, r10, 144
    blt r10, r0, trace_return
    beq r10, r0, trace_return
    addi r1, r0, 10
    shl r10, r10, r1
    sub r11, r0, r11
    jal r13, divide
    lw r1, 40(r15)
    sltu r2, r12, r1
    beq r2, r0, trace_return
    sw r12, 40(r15)
    addi r1, r0, 1
    sw r1, 36(r15)
trace_return:
    lw r14, 120(r15)
    jalr r0, 0(r14)

; Normalize a signed three-vector at r7 in place to Q10.
; Original length is returned at scratch +136 (Q4 for the light vector).
normalize:
    sw r14, 140(r15)
    lw r1, 0(r7)
    lw r2, 4(r7)
    lw r3, 8(r7)
    mul r1, r1, r1
    mul r2, r2, r2
    mul r3, r3, r3
    add r10, r1, r2
    add r10, r10, r3
    jal r13, square_root
    bne r12, r0, norm_length
    addi r12, r0, 1
norm_length:
    sw r12, 136(r15)
    mov r6, r0
norm_axis:
    add r5, r7, r6
    lw r10, 0(r5)
    slt r8, r10, r0
    beq r8, r0, norm_positive
    sub r10, r0, r10
norm_positive:
    addi r1, r0, 10
    shl r10, r10, r1
    lw r11, 136(r15)
    jal r13, divide
    beq r8, r0, norm_store
    sub r12, r0, r12
norm_store:
    sw r12, 0(r5)
    addi r6, r6, 4
    addi r1, r0, 12
    bltu r6, r1, norm_axis
    lw r14, 140(r15)
    jalr r0, 0(r14)

; Integer square root of nonnegative r10 -> r12, clobbers r9..r14.
square_root:
    li r11, 0x40000000
    mov r12, r0
sqrt_loop:
    add r9, r12, r11
    bltu r10, r9, sqrt_skip
    sub r10, r10, r9
    addi r14, r0, 1
    shr r12, r12, r14
    add r12, r12, r11
    j sqrt_shift
sqrt_skip:
    addi r14, r0, 1
    shr r12, r12, r14
sqrt_shift:
    addi r14, r0, 2
    shr r11, r11, r14
    bne r11, r0, sqrt_loop
    jalr r0, 0(r13)

; Positive unsigned r10/r11 -> r12. Scene numerators stay below 2^28.
; All callers provide r11>0, so shift/subtract always terminates.
divide:
    mov r12, r0
    addi r9, r0, 1
    addi r14, r0, 1
div_grow:
    bltu r10, r11, div_bit
    shl r11, r11, r14
    shl r9, r9, r14
    j div_grow
div_bit:
    shr r11, r11, r14
    shr r9, r9, r14
    beq r9, r0, div_done
    bltu r10, r11, div_bit
    sub r10, r10, r11
    add r12, r12, r9
    j div_bit
div_done:
    jalr r0, 0(r13)

; Sphere data: center xyz Q4, radius squared Q8, reflectivity Q8, RGB.
spheres:
    .word -160, -16, 600, 16384, 144, 0x48dec5
    .word 192, -16, 740, 16384, 136, 0xf0a05b
    .word 0, -80, 432, 4096, 184, 0xb5c8ef
spheres_end:
