; Backdrop: the tiling wallpaper behind the DemoBench homepage.
; The CPU draws a Truchet pattern of quarter-circle arcs once, into an I8
; framebuffer that tiles seamlessly at 160×120: 8×6 cells of 20×20 pixels,
; each cell's arcs meeting its neighbours at the edge midpoints. Every arc
; pixel stores a phase (0..39) along a diagonal running in the (3,4) direction.
; Afterwards the CPU only rewrites 40 palette entries each vblank, so a soft
; glow drifts across the arcs while the framebuffer never changes.
.equ FB, 0x10000
.equ PAL, 0x28000
.equ VIDEO, 0xf5000
.equ LO, 342                   ; arc band, in doubled coordinates: radius 20,
.equ BAND, 118                 ; squared distances LO..LO+BAND-1 (about 1.5 px)
.entry start

start:
    li r1, FB
    addi r2, r0, BAND
    addi r14, r0, 40           ; cell size in doubled coordinates
    addi r5, r0, 1             ; V: doubled pixel-centre y within the cell
    mov r7, r0                 ; cell row
    mov r9, r0                 ; phase at the start of the row, (4y) mod 480
row:
    lbu r12, orient(r7)        ; one orientation bit per cell in this row
    mov r6, r0                 ; cell column
    addi r4, r0, 1             ; U: doubled pixel-centre x within the cell
    mov r8, r9                 ; phase, (3x + 4y) mod 480
pixel:
    mov r3, r0                 ; background
    shr r10, r12, r6
    andi r10, r10, 1
    mov r11, r4
    beq r10, r0, arcs
    sub r11, r14, r4           ; mirrored cell: arcs about the other diagonal
arcs:
    mul r13, r11, r11          ; distance² to the near corner
    mul r15, r5, r5
    add r13, r13, r15
    addi r13, r13, -LO
    bltu r13, r2, hit
    sub r13, r14, r11          ; distance² to the far corner
    mul r13, r13, r13
    sub r15, r14, r5
    mul r15, r15, r15
    add r13, r13, r15
    addi r13, r13, -LO
    bltu r13, r2, hit
    j plot
hit:
    addi r10, r0, 85           ; phase / 12, as (phase * 85) >> 10
    mul r10, r8, r10
    addi r15, r0, 10
    shr r10, r10, r15
    addi r3, r10, 16           ; palette entries 16..55
plot:
    sb r3, 0(r1)
    addi r1, r1, 1
    addi r8, r8, 3
    addi r10, r8, -480
    blt r10, r0, next_x
    mov r8, r10
next_x:
    addi r4, r4, 2
    bltu r14, r4, next_cell
    j pixel
next_cell:
    addi r4, r0, 1
    addi r6, r6, 1
    andi r10, r6, 8
    beq r10, r0, pixel
    addi r9, r9, 4             ; end of a pixel row
    addi r10, r9, -480
    blt r10, r0, next_y
    mov r9, r10
next_y:
    addi r5, r5, 2
    bltu r14, r5, next_cell_row
    j row
next_cell_row:
    addi r5, r0, 1
    addi r7, r7, 1
    addi r10, r7, -6
    bne r10, r0, row

    ; Show the finished picture from the next vblank.
    li r3, VIDEO
    li r1, FB
    sw r1, 0(r3)
    addi r10, r0, 160
    sw r10, 4(r3)
    addi r10, r0, 3            ; I8
    sw r10, 8(r3)
    li r10, PAL
    sw r10, 12(r3)
    addi r10, r0, 1
    sw r10, 16(r3)
    sw r10, 20(r3)

    mov r13, r0                ; glow position, 0..639 in sixteenths of an entry
    addi r12, r0, 640
    addi r14, r0, 7
frame:
    li r1, PAL+48              ; palette entry 16
    mov r4, r0                 ; entry position, 16 * (index - 16)
entry:
    sub r10, r4, r13           ; circular distance from the glow, 0..320
    blt r10, r0, wrap_neg
    j distance
wrap_neg:
    add r10, r10, r12
distance:
    sub r15, r12, r10
    bltu r10, r15, near
    mov r10, r15
near:
    addi r10, r10, -96         ; glow = max(0, 96 - distance)
    sub r10, r0, r10
    blt r10, r0, dark
    mul r10, r10, r10          ; eased: glow² scaled to 0..128
    addi r15, r0, 114
    mul r10, r10, r15
    addi r15, r0, 13
    shr r10, r10, r15
    j colour
dark:
    mov r10, r0
colour:
    addi r15, r0, 215          ; red 40 → 255
    mul r15, r15, r10
    shr r15, r15, r14
    addi r15, r15, 40
    sb r15, 0(r1)
    addi r15, r0, 64           ; green 42 → 106
    mul r15, r15, r10
    shr r15, r15, r14
    addi r15, r15, 42
    sb r15, 1(r1)
    addi r15, r0, 16           ; blue 48 → 64
    mul r15, r15, r10
    shr r15, r15, r14
    addi r15, r15, 48
    sb r15, 2(r1)
    addi r1, r1, 3
    addi r4, r4, 16
    bltu r4, r12, entry
    addi r13, r13, 1           ; one full sweep every 640 frames
    bltu r13, r12, wait
    mov r13, r0
wait:
    wfi
    j frame

orient:
    .byte 0xb4, 0x6d, 0x2b, 0xd8, 0x57, 0x9a
