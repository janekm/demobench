; dynamic-1: the CPU edits a GPU literal between dispatches.
; Valid as a regular cartridge, or pack with --load 0x2d000.
.profile dynamic-1
.entry start
.equ GPU, 0xf3000
.equ VIDEO, 0xf5000
.equ KERNEL_RAM, 0x2c000
.equ FB, 0x10000
start:
    li r1, kernel
    li r2, KERNEL_RAM
    li r3, kernel_end-kernel
copy_kernel:
    lw r4, 0(r1)
    sw r4, 0(r2)
    addi r1, r1, 4
    addi r2, r2, 4
    addi r3, r3, -4
    bne r3, r0, copy_kernel
    li r10, GPU
    li r11, VIDEO
    li r13, KERNEL_RAM+phase-kernel+4
    li r1, KERNEL_RAM
    sw r1, 0(r10)
    li r1, kernel_end-kernel
    sw r1, 4(r10)
    li r1, 160
    sw r1, 8(r10)
    li r1, 120
    sw r1, 12(r10)
    li r1, FB
    sw r1, 64(r10)
    sw r1, 0(r11)
    li r1, 57600
    sw r1, 68(r10)
    addi r1, r0, 3
    sw r1, 72(r10)
    li r1, 480
    sw r1, 4(r11)
    addi r1, r0, 4
    sw r1, 8(r11)
    addi r1, r0, 1
    sw r1, 16(r11)
frame:
    ; This changes the instruction literal, rather than a uniform.
    sw r12, 0(r13)
    sw r1, 16(r10)
wait_gpu:
    wfi
    lw r2, 20(r10)
    beq r2, r1, wait_gpu
    sw r1, 20(r11)
wait_flip:
    wfi
    lw r2, 20(r11)
    bne r2, r0, wait_flip
    addi r12, r12, 3
    andi r12, r12, 255
    j frame
kernel:
    g.id g1, 0
    g.id g2, 1
phase:
    g.li g3, 0
    g.add g1, g1, g3
    g.xor g2, g2, g3
    g.id g4, 2
    g.li g5, 3
    g.mul g4, g4, g5
    g.stb g1, g4, 0
    g.li g5, 1
    g.add g4, g4, g5
    g.stb g2, g4, 0
    g.add g4, g4, g5
    g.li g6, 255
    g.sub g6, g6, g1
    g.stb g6, g4, 0
    g.end
kernel_end:
