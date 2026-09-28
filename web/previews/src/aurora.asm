; DB32 bootstrap I8 demo: a CPU-painted night landscape.
; r1 framebuffer, r2 RGB palette, r3 video MMIO. Nothing is host generated.
.equ FB, 0x10000
.equ PAL, 0x28000
.equ VIDEO, 0xf5000
.entry start

start:
    li r1, FB
    li r2, PAL
    li r3, VIDEO
    mov r4, r0                 ; palette index
    mov r6, r2                 ; palette write pointer
    li r11, 64
    li r12, 128
    li r13, 192
    li r14, 240
    li r15, 256
palette_loop:
    bltu r4, r11, palette_sky
    bltu r4, r12, palette_aurora
    bltu r4, r13, palette_mountain
    bltu r4, r14, palette_water
    li r7, 255
    li r8, 230
    li r9, 190
    j palette_write
palette_sky:
    li r10, 1
    shr r7, r4, r10
    addi r7, r7, 6
    addi r8, r4, 12
    add r9, r4, r4
    addi r9, r9, 48
    j palette_write
palette_aurora:
    addi r10, r4, -64
    li r9, 160
    add r9, r9, r10
    li r7, 90
    add r7, r7, r10
    add r7, r7, r10
    li r8, 60
    add r8, r8, r10
    add r8, r8, r10
    j palette_write
palette_mountain:
    addi r10, r4, -128
    li r7, 2
    shr r7, r10, r7
    addi r7, r7, 12
    li r8, 1
    shr r8, r10, r8
    addi r8, r8, 20
    addi r9, r10, 44
    j palette_write
palette_water:
    addi r10, r4, -192
    li r7, 1
    shr r7, r10, r7
    addi r7, r7, 10
    addi r8, r10, 40
    add r9, r10, r10
    addi r9, r9, 90
palette_write:
    sb r7, 0(r6)
    sb r8, 1(r6)
    sb r9, 2(r6)
    addi r6, r6, 3
    addi r4, r4, 1
    bltu r4, r15, palette_loop

    ; Video latches this pending configuration at the next vblank.
    sw r1, 0(r3)
    li r10, 160
    sw r10, 4(r3)
    li r10, 3               ; I8
    sw r10, 8(r3)
    sw r2, 12(r3)
    li r10, 1
    sw r10, 16(r3)
    sw r10, 20(r3)

    mov r4, r0              ; y
    mov r6, r1              ; framebuffer byte pointer
    li r11, 160
    li r12, 120
draw_row:
    mov r5, r0              ; x
draw_pixel:
    ; Dark blue-to-teal sky, with wavering ribbons.
    li r8, 1
    shr r7, r4, r8
    li r8, 5
    shr r8, r5, r8
    add r7, r7, r8
    li r8, 58
    bltu r4, r8, check_aurora
    j check_mountain
check_aurora:
    li r8, 12
    bltu r4, r8, check_stars
    li r8, 2
    shr r8, r5, r8
    li r9, 4
    shr r9, r5, r9
    xor r8, r8, r9
    andi r8, r8, 15
    add r8, r8, r4
    andi r8, r8, 31
    li r9, 9
    bltu r8, r9, ribbon
    j check_stars
ribbon:
    add r7, r5, r4
    andi r7, r7, 63
    addi r7, r7, 64
check_stars:
    li r8, 13
    mul r8, r5, r8
    li r9, 31
    mul r9, r4, r9
    add r8, r8, r9
    andi r8, r8, 255
    bne r8, r0, check_moon
    li r7, 250
check_moon:
    ; Tiny cream diamond moon above the right-hand ridge.
    li r8, 44
    bltu r8, r4, check_mountain
    addi r8, r5, -124
    blt r8, r0, moon_negative_x
moon_x_ready:
    li r9, 11
    bltu r9, r8, check_mountain
    addi r9, r4, -24
    blt r9, r0, moon_negative_y
moon_distance:
    add r8, r8, r9
    li r9, 12
    bltu r8, r9, moon_fill
    j check_mountain
moon_negative_x:
    sub r8, r0, r8
    j moon_x_ready
moon_negative_y:
    sub r9, r0, r9
    j moon_distance
moon_fill:
    li r7, 250
check_mountain:
    ; Jagged silhouette, with a deep blue lake below line 90.
    li r8, 3
    shr r8, r5, r8
    xor r8, r8, r5
    andi r8, r8, 31
    addi r8, r8, 58
    bltu r4, r8, write_pixel
    add r7, r5, r4
    andi r7, r7, 63
    addi r7, r7, 128
    li r8, 90
    bltu r4, r8, write_pixel
    add r7, r4, r4
    add r7, r7, r4
    add r7, r7, r5
    andi r7, r7, 31
    addi r7, r7, 192
    li r8, 3
    shr r8, r5, r8
    add r8, r8, r4
    andi r8, r8, 15
    bne r8, r0, write_pixel
    li r7, 246             ; silver ripples
write_pixel:
    sb r7, 0(r6)
    addi r6, r6, 1
    addi r5, r5, 1
    bltu r5, r11, draw_pixel
    addi r4, r4, 1
    bltu r4, r12, draw_row

    mov r13, r0             ; animation phase
animate:
    wfi                     ; palette changes in the blanking interval
    addi r13, r13, 1
    andi r13, r13, 63
    mov r4, r0
    li r6, PAL+192          ; palette entry 64
    li r11, 64
palette_wave:
    add r10, r4, r13
    andi r10, r10, 63
    li r7, 90
    add r7, r7, r10
    add r7, r7, r10
    li r8, 60
    add r8, r8, r10
    add r8, r8, r10
    addi r9, r10, 160
    sb r7, 0(r6)
    sb r8, 1(r6)
    sb r9, 2(r6)
    addi r6, r6, 3
    addi r4, r4, 1
    bltu r4, r11, palette_wave
    j animate
