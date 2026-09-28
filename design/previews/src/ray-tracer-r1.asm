; Three spheres, directional shadows, and a reflective checkerboard.
; Every RGB888 pixel is ray traced by DB32 instructions. No image assets.
; Camera at (0,0,0), ray D=(x-80,40-y,128), floor at y=-36.
; Intersections solve A*t*t - 2*B*t + C = 0; t uses 12 fraction bits.
; Reflections intersect spheres mirrored across the floor (one bounce).
; r1=framebuffer, r2/r3=pixel x/y, r4/r5=ray x/y, r6=dot(D,D).
; r15 points to 64 bytes of scratch RAM, r7..r14 are temporary.
.equ FB, 0x10000
.equ VIDEO, 0xf5000
.equ SCRATCH, 0x2f000
.entry start

start:
    li r15, SCRATCH
    li r1, FB
    li r7, VIDEO
    sw r1, 0(r7)
    addi r8, r0, 480
    sw r8, 4(r7)
    addi r8, r0, 4
    sw r8, 8(r7)
    addi r8, r0, 1
    sw r8, 16(r7)
    sw r8, 20(r7)          ; show the image as rays are computed
    mov r3, r0
row:
    mov r2, r0
pixel:
    addi r4, r2, -80
    addi r5, r0, 40
    sub r5, r5, r3
    mul r6, r4, r4
    mul r8, r5, r5
    add r6, r6, r8
    addi r6, r6, 16384
    sw r0, 16(r15)        ; direct rays
    jal r14, trace
    lw r7, 4(r15)
    beq r7, r0, miss
    jal r14, shade
    j write_pixel
miss:
    blt r5, r0, floor
    ; Sky gradient meets the distant floor's fog colour.
    addi r14, r0, 1
    shr r9, r3, r14
    addi r9, r9, 8
    add r10, r3, r3
    add r10, r10, r3
    addi r14, r0, 2
    shr r10, r10, r14
    addi r10, r10, 18
    addi r11, r3, 36
    j write_pixel

floor:
    ; Analytic plane intersection: t=(36*4096)/(-D.y).
    li r10, 147456
    sub r11, r0, r5
    jal r13, divide
    mul r9, r4, r12
    addi r14, r0, 12
    sar r9, r9, r14
    sw r9, 20(r15)        ; integer world-space floor x
    addi r14, r0, 5
    shr r10, r12, r14     ; world z = t*128/4096
    sw r10, 24(r15)
    sar r9, r9, r14
    shr r10, r10, r14
    xor r9, r9, r10
    andi r9, r9, 1
    beq r9, r0, dark_tile
    addi r9, r0, 128
    addi r10, r0, 153
    addi r11, r0, 164
    j tile_ready
dark_tile:
    addi r9, r0, 40
    addi r10, r0, 65
    addi r11, r0, 82
tile_ready:
    sw r9, 28(r15)
    sw r10, 32(r15)
    sw r11, 36(r15)
    jal r14, shadow
    beq r8, r0, reflection
    ; Ambient light remains inside a directional-light shadow.
    lw r9, 28(r15)
    lw r10, 32(r15)
    lw r11, 36(r15)
    addi r14, r0, 2
    shr r9, r9, r14
    shr r10, r10, r14
    shr r11, r11, r14
    sw r9, 28(r15)
    sw r10, 32(r15)
    sw r11, 36(r15)
reflection:
    addi r7, r0, 1
    sw r7, 16(r15)
    jal r14, trace
    lw r7, 4(r15)
    beq r7, r0, floor_only
    jal r14, shade
    lw r7, 28(r15)
    add r9, r9, r7
    lw r7, 32(r15)
    add r10, r10, r7
    lw r7, 36(r15)
    add r11, r11, r7
    addi r14, r0, 1
    shr r9, r9, r14
    shr r10, r10, r14
    shr r11, r11, r14
    j fog
floor_only:
    lw r9, 28(r15)
    lw r10, 32(r15)
    lw r11, 36(r15)
fog:
    lw r12, 24(r15)
    addi r14, r0, 1
    shr r12, r12, r14
    addi r7, r0, 200
    bltu r12, r7, fog_amount
    mov r12, r7
fog_amount:
    addi r13, r0, 256
    sub r13, r13, r12
    addi r14, r0, 8
    mul r9, r9, r13
    addi r7, r0, 28
    mul r8, r12, r7
    add r9, r9, r8
    shr r9, r9, r14
    mul r10, r10, r13
    addi r7, r0, 48
    mul r8, r12, r7
    add r10, r10, r8
    shr r10, r10, r14
    mul r11, r11, r13
    addi r7, r0, 76
    mul r8, r12, r7
    add r11, r11, r8
    shr r11, r11, r14
write_pixel:
    sb r9, 0(r1)
    sb r10, 1(r1)
    sb r11, 2(r1)
    addi r1, r1, 3
    addi r2, r2, 1
    addi r7, r0, 160
    bltu r2, r7, pixel
    addi r3, r3, 1
    addi r7, r0, 120
    bltu r3, r7, row
    halt

; Nearest positive ray-sphere hit. Returns t in r8, sphere pointer at +4.
; Mode +16 selects real spheres or their y=-36 mirror images.
trace:
    sw r14, 0(r15)
    sw r0, 4(r15)
    li r7, spheres
    li r8, 0x7fffffff
trace_sphere:
    lw r9, 0(r7)
    mul r9, r9, r4
    lw r10, 4(r7)
    lw r11, 16(r15)
    beq r11, r0, trace_real_y
    addi r11, r0, -72
    sub r10, r11, r10
trace_real_y:
    mul r10, r10, r5
    add r9, r9, r10
    lw r10, 8(r7)
    addi r11, r0, 7
    shl r10, r10, r11
    add r9, r9, r10       ; B = dot(D,C)
    blt r9, r0, trace_next
    sw r9, 8(r15)
    mul r10, r9, r9
    lw r11, 16(r15)
    beq r11, r0, trace_real_c
    lw r11, 20(r7)
    j discriminant
trace_real_c:
    lw r11, 16(r7)
discriminant:
    mul r11, r6, r11
    sub r10, r10, r11
    blt r10, r0, trace_next
    jal r13, square_root
    lw r10, 8(r15)
    sub r10, r10, r12
    blt r10, r0, trace_next
    beq r10, r0, trace_next
    addi r11, r0, 12
    shl r10, r10, r11
    mov r11, r6
    jal r13, divide
    bltu r8, r12, trace_next
    mov r8, r12
    sw r7, 4(r15)
trace_next:
    addi r7, r7, 32
    li r9, spheres_end
    bltu r7, r9, trace_sphere
    lw r14, 0(r15)
    jalr r0, 0(r14)

; Restoring integer square root. r10 >= 0 -> floor(sqrt(r10)) in r12.
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

; Unsigned division r10/r11 -> r12. Scene bounds: numerator < 2^28,
; denominator > 0. Shift/subtract needs no hardware divide instruction.
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

; Sphere shading: diffuse light plus a compact glossy highlight.
; r8 is tQ12. Returns RGB in r9,r10,r11; preserves the primary ray.
shade:
    sw r14, 0(r15)
    lw r7, 4(r15)
    mul r9, r4, r8
    mul r10, r5, r8
    addi r12, r0, 4
    sar r9, r9, r12
    sar r10, r10, r12
    addi r12, r0, 3
    shl r11, r8, r12      ; hit point, with 8 fraction bits
    addi r12, r0, 8
    lw r13, 0(r7)
    shl r13, r13, r12
    sub r9, r9, r13
    lw r13, 8(r7)
    shl r13, r13, r12
    sub r11, r11, r13
    lw r13, 4(r7)
    lw r14, 16(r15)
    beq r14, r0, shade_real_y
    addi r14, r0, -72
    sub r13, r14, r13
shade_real_y:
    shl r13, r13, r12
    sub r10, r10, r13
    lw r14, 16(r15)
    beq r14, r0, normal_ready
    sub r10, r0, r10      ; unmirror the normal for physical lighting
normal_ready:
    ; dot(normal, (-2,4,-3)) / scale, plus ambient illumination.
    add r12, r10, r10
    add r12, r12, r12
    sub r12, r12, r9
    sub r12, r12, r9
    sub r12, r12, r11
    sub r12, r12, r11
    sub r12, r12, r11
    lw r14, 24(r7)
    sar r12, r12, r14
    blt r0, r12, lit
    mov r12, r0
lit:
    addi r12, r12, 32
    ; A sharp lobe around half-vector (-1,2,-4).
    add r13, r10, r10
    sub r13, r13, r9
    sub r13, r13, r11
    sub r13, r13, r11
    sub r13, r13, r11
    sub r13, r13, r11
    sar r13, r13, r14
    addi r13, r13, -120
    blt r0, r13, highlight
    mov r13, r0
    j material
highlight:
    addi r14, r0, 3
    shl r13, r13, r14
    addi r14, r0, 192
    bltu r13, r14, material
    mov r13, r14
material:
    lw r8, 28(r7)
    addi r14, r0, 16
    shr r9, r8, r14
    addi r14, r0, 8
    shr r10, r8, r14
    andi r10, r10, 255
    andi r11, r8, 255
    mul r9, r9, r12
    mul r10, r10, r12
    mul r11, r11, r12
    shr r9, r9, r14
    shr r10, r10, r14
    shr r11, r11, r14
    add r9, r9, r13
    add r10, r10, r13
    add r11, r11, r13
    addi r14, r0, 255
    bltu r9, r14, green_limit
    mov r9, r14
green_limit:
    bltu r10, r14, blue_limit
    mov r10, r14
blue_limit:
    bltu r11, r14, shade_done
    mov r11, r14
shade_done:
    lw r14, 0(r15)
    jalr r0, 0(r14)

; Floor shadow ray toward directional light (-2,4,-3).
; Positive B and discriminant >= 0 means the ray meets a real sphere.
shadow:
    sw r14, 0(r15)
    li r7, spheres
    mov r8, r0
shadow_sphere:
    lw r9, 0(r7)
    lw r12, 20(r15)
    sub r9, r9, r12
    lw r10, 4(r7)
    addi r10, r10, 36
    lw r11, 8(r7)
    lw r12, 24(r15)
    sub r11, r11, r12
    add r12, r10, r10
    add r12, r12, r12
    sub r12, r12, r9
    sub r12, r12, r9
    sub r12, r12, r11
    sub r12, r12, r11
    sub r12, r12, r11
    blt r12, r0, shadow_next
    mul r13, r9, r9
    mul r14, r10, r10
    add r13, r13, r14
    mul r14, r11, r11
    add r13, r13, r14
    lw r14, 12(r7)
    sub r13, r13, r14
    addi r14, r0, 29
    mul r13, r13, r14
    mul r12, r12, r12
    sub r12, r12, r13
    blt r12, r0, shadow_next
    addi r8, r0, 1
    j shadow_done
shadow_next:
    addi r7, r7, 32
    li r9, spheres_end
    bltu r7, r9, shadow_sphere
shadow_done:
    lw r14, 0(r15)
    jalr r0, 0(r14)

; x, y, z, radius^2, dot(C,C)-radius^2, mirrored C term,
; normal scaling shift, 24-bit material. All scene data is counted.
spheres:
    .word -40, -4, 150, 1024, 23092, 27700, 8, 0x48dec5
    .word 48, -4, 185, 1024, 35521, 40129, 8, 0xf0a05b
    .word 0, -20, 108, 256, 11808, 14112, 7, 0xb5c8ef
spheres_end:
