; PELICAN PEDAL CLUB — all scene traversal, motion and audio execute in DB32.
; RAM: pages 10000..196ff, PCM 1a000..1a7ff, image at 24000.
; Analytic transformed ellipsoid rays; CSG wheel annuli; bounded object loop.
.profile dynamic-1
.entry start
.equ FB0, 0x10000
.equ FB1, 0x15000
.equ PCM, 0x1a000
start:
 ; Generate the full 256-colour lighting palette in guest RAM.
 li r5, 0x1a800
 li r8, palette
 li r9, palette_end
 li r14, 5
 li r13, 255
palette_row:
 lbu r10, 0(r8)
 lbu r11, 1(r8)
 lbu r12, 2(r8)
 addi r7, r0, 8
palette_shade:
 mul r2, r10, r7
 shr r2, r2, r14
 bltu r2, r13, red_ok
 mov r2, r13
red_ok:
 sb r2, 0(r5)
 mul r2, r11, r7
 shr r2, r2, r14
 bltu r2, r13, green_ok
 mov r2, r13
green_ok:
 sb r2, 1(r5)
 mul r2, r12, r7
 shr r2, r2, r14
 bltu r2, r13, blue_ok
 mov r2, r13
blue_ok:
 sb r2, 2(r5)
 addi r5, r5, 3
 addi r7, r7, 2
 addi r2, r0, 40
 bltu r7, r2, palette_shade
 addi r8, r8, 3
 bltu r8, r9, palette_row
 li r1, 0xf5000
 li r2, FB0
 sw r2, 0(r1)
 li r2, 160
 sw r2, 4(r1)
 li r2, 3
 sw r2, 8(r1)
 li r2, 0x1a800
 sw r2, 12(r1)
 addi r2, r0, 1
 sw r2, 16(r1)
 sw r2, 20(r1)
 li r3, 0xf3000
 li r1, 0xf6000
 li r2, synth
 sw r2, 64(r1)
 li r2, synth_end-synth
 sw r2, 68(r1)
 addi r2, r0, 128
 sw r2, 72(r1)
 addi r2, r0, 2
 sw r2, 76(r1)
 li r2, PCM
 sw r2, 80(r1)
 sw r2, 256(r1)
 li r2, 2048
 sw r2, 260(r1)
 addi r2, r0, 3
 sw r2, 264(r1)
 li r2, notes
 sw r2, 272(r1)
 li r2, notes_end-notes
 sw r2, 276(r1)
 addi r2, r0, 1
 sw r2, 280(r1)
 li r2, 0x1b000
 sw r2, 288(r1)
 li r2, 32768
 sw r2, 292(r1)
 addi r2, r0, 3
 sw r2, 296(r1)
 addi r2, r0, 1
 sw r2, 0(r1)
 li r6, FB1
loop:
 li r1, 0xf0000
 lw r7, 16(r1)
 sw r7, 256(r3)
 li r2, animate
 sw r2, 0(r3)
 li r2, animate_end-animate
 sw r2, 4(r3)
 addi r2, r0, 1
 sw r2, 8(r3)
 sw r2, 12(r3)
 li r2, scene
 sw r2, 64(r3)
 li r2, scene_end-scene
 sw r2, 68(r3)
 addi r2, r0, 3
 sw r2, 72(r3)
 sw r0, 80(r3)
 sw r0, 84(r3)
 sw r0, 88(r3)
 addi r2, r0, 1
 sw r2, 16(r3)
wait_anim:
 lw r2, 20(r3)
 addi r4, r0, 1
 beq r2, r4, wait_anim
 li r2, render
 sw r2, 0(r3)
 li r2, render_end-render
 sw r2, 4(r3)
 addi r2, r0, 160
 sw r2, 8(r3)
 addi r2, r0, 120
 sw r2, 12(r3)
 sw r6, 64(r3)
 li r2, 19200
 sw r2, 68(r3)
 addi r2, r0, 3
 sw r2, 72(r3)
 li r2, scene
 sw r2, 80(r3)
 li r2, scene_end-scene
 sw r2, 84(r3)
 addi r2, r0, 1
 sw r2, 88(r3)
 sw r2, 16(r3)
wait_render:
 wfi
 lw r2, 20(r3)
 addi r4, r0, 1
 beq r2, r4, wait_render
 li r1, 0xf5000
 sw r6, 0(r1)
 addi r2, r0, 1
 sw r2, 20(r1)
 wfi
 li r2, 0x5000
 xor r6, r6, r2
 j loop
animate:
 g.uniform g1, 0
 g.itof g1, g1
 g.fli g2, 0.01666667
 g.fmul g1, g1, g2

g.fli g2, 0.05
g.fmul g2, g1, g2
g.ftoi g28, g2
g.itof g28, g28
g.fsub g3, g2, g28
g.fli g28, 2
g.fmul g3, g3, g28
g.fli g28, 1
g.fsub g3, g3, g28
g.fli g29, -1
g.fmul g29, g3, g29
g.fmax g29, g3, g29
g.fsub g29, g28, g29
g.fmul g3, g3, g29
g.fli g28, 4
g.fmul g3, g3, g28
g.fli g4, 0.25
g.fadd g2, g2, g4
g.ftoi g28, g2
g.itof g28, g28
g.fsub g5, g2, g28
g.fli g28, 2
g.fmul g5, g5, g28
g.fli g28, 1
g.fsub g5, g5, g28
g.fli g29, -1
g.fmul g29, g5, g29
g.fmax g29, g5, g29
g.fsub g29, g28, g29
g.fmul g5, g5, g29
g.fli g28, 4
g.fmul g5, g5, g28
g.fli g6, 2.5
g.fmul g6, g3, g6
g.fli g7, 0.24
g.fmul g7, g5, g7
g.fli g8, 2.8
g.fadd g7, g7, g8
g.fli g8, 4.6
g.li g31, 0
g.st g6, g31, 0
g.li g31, 4
g.st g7, g31, 0
g.li g31, 8
g.st g8, g31, 0
g.vscale g9, g6, g0
g.fsub g9, g0, g6
g.fli g10, 1.67
g.fsub g10, g10, g7
g.fsub g11, g0, g8
g.norm3 g9, g9
g.li g31, 16
g.st g9, g31, 0
g.li g31, 20
g.st g10, g31, 0
g.li g31, 24
g.st g11, g31, 0
g.mov g12, g8
g.mov g13, g0
g.fsub g14, g0, g6
g.norm3 g12, g12
g.li g31, 32
g.st g12, g31, 0
g.li g31, 36
g.st g13, g31, 0
g.li g31, 40
g.st g14, g31, 0
g.fmul g15, g14, g10
g.fsub g15, g0, g15
g.fmul g16, g14, g9
g.fmul g17, g12, g11
g.fsub g16, g16, g17
g.fmul g17, g12, g10
g.li g31, 48
g.st g15, g31, 0
g.li g31, 52
g.st g16, g31, 0
g.li g31, 56
g.st g17, g31, 0
g.li g31, 64
g.st g1, g31, 0
g.fli g2, 0.25
g.fadd g2, g1, g2
g.ftoi g28, g1
g.itof g28, g28
g.fsub g4, g1, g28
g.fli g28, 2
g.fmul g4, g4, g28
g.fli g28, 1
g.fsub g4, g4, g28
g.fli g29, -1
g.fmul g29, g4, g29
g.fmax g29, g4, g29
g.fsub g29, g28, g29
g.fmul g4, g4, g29
g.fli g28, 4
g.fmul g4, g4, g28
g.ftoi g28, g2
g.itof g28, g28
g.fsub g5, g2, g28
g.fli g28, 2
g.fmul g5, g5, g28
g.fli g28, 1
g.fsub g5, g5, g28
g.fli g29, -1
g.fmul g29, g5, g29
g.fmax g29, g5, g29
g.fsub g29, g28, g29
g.fmul g5, g5, g29
g.fli g28, 4
g.fmul g5, g5, g28
g.fsub g4, g0, g4 ; Clockwise rotation for forward travel along +X.
g.li g31, 184
g.st g5, g31, 0
g.li g31, 188
g.st g4, g31, 0
g.fsub g6, g0, g4
g.li g31, 224
g.st g6, g31, 0
g.li g31, 228
g.st g5, g31, 0
g.li g31, 384
g.st g5, g31, 0
g.li g31, 388
g.st g4, g31, 0
g.fsub g6, g0, g4
g.li g31, 424
g.st g6, g31, 0
g.li g31, 428
g.st g5, g31, 0
g.fli g6, 0.28
g.fmul g7, g5, g6
g.fli g8, -0.02
g.fadd g7, g7, g8
g.fmul g8, g4, g6
g.fli g9, 0.72
g.fadd g8, g8, g9
g.fli g6, 0.11
g.fmul g9, g5, g6
g.fli g10, 0.03
g.fadd g9, g9, g10
g.fmul g10, g4, g6
g.fli g11, 1.32
g.fadd g10, g10, g11
g.li g31, 1440
g.st g7, g31, 0
g.li g31, 1444
g.st g8, g31, 0
g.fli g12, -0.12
g.fli g13, 1.87
g.mov g14, g9
g.mov g15, g10
g.fsub g16, g14, g12
g.fsub g17, g15, g13
g.fmul g18, g16, g16
g.fmul g19, g17, g17
g.fadd g18, g18, g19
g.sqrt g18, g18
g.fdiv g19, g16, g18
g.fdiv g20, g17, g18
g.fli g21, 0.5
g.fmul g18, g18, g21
g.fli g22, 0.045
g.fadd g18, g18, g22
g.fli g22, 1
g.fdiv g18, g22, g18
g.fadd g12, g12, g14
g.fmul g12, g12, g21
g.fadd g13, g13, g15
g.fmul g13, g13, g21
g.li g31, 1360
g.st g12, g31, 0
g.li g31, 1364
g.st g13, g31, 0
g.li g31, 1372
g.st g18, g31, 0
g.li g31, 1384
g.st g19, g31, 0
g.li g31, 1388
g.st g20, g31, 0
g.mov g12, g9
g.mov g13, g10
g.mov g14, g7
g.mov g15, g8
g.fsub g16, g14, g12
g.fsub g17, g15, g13
g.fmul g18, g16, g16
g.fmul g19, g17, g17
g.fadd g18, g18, g19
g.sqrt g18, g18
g.fdiv g19, g16, g18
g.fdiv g20, g17, g18
g.fli g21, 0.5
g.fmul g18, g18, g21
g.fli g22, 0.039
g.fadd g18, g18, g22
g.fli g22, 1
g.fdiv g18, g22, g18
g.fadd g12, g12, g14
g.fmul g12, g12, g21
g.fadd g13, g13, g15
g.fmul g13, g13, g21
g.li g31, 1400
g.st g12, g31, 0
g.li g31, 1404
g.st g13, g31, 0
g.li g31, 1412
g.st g18, g31, 0
g.li g31, 1424
g.st g19, g31, 0
g.li g31, 1428
g.st g20, g31, 0
g.fli g6, -0.28
g.fmul g7, g5, g6
g.fli g8, -0.02
g.fadd g7, g7, g8
g.fmul g8, g4, g6
g.fli g9, 0.72
g.fadd g8, g8, g9
g.fli g6, -0.11
g.fmul g9, g5, g6
g.fli g10, 0.03
g.fadd g9, g9, g10
g.fmul g10, g4, g6
g.fli g11, 1.32
g.fadd g10, g10, g11
g.li g31, 1560
g.st g7, g31, 0
g.li g31, 1564
g.st g8, g31, 0
g.fli g12, -0.12
g.fli g13, 1.87
g.mov g14, g9
g.mov g15, g10
g.fsub g16, g14, g12
g.fsub g17, g15, g13
g.fmul g18, g16, g16
g.fmul g19, g17, g17
g.fadd g18, g18, g19
g.sqrt g18, g18
g.fdiv g19, g16, g18
g.fdiv g20, g17, g18
g.fli g21, 0.5
g.fmul g18, g18, g21
g.fli g22, 0.045
g.fadd g18, g18, g22
g.fli g22, 1
g.fdiv g18, g22, g18
g.fadd g12, g12, g14
g.fmul g12, g12, g21
g.fadd g13, g13, g15
g.fmul g13, g13, g21
g.li g31, 1480
g.st g12, g31, 0
g.li g31, 1484
g.st g13, g31, 0
g.li g31, 1492
g.st g18, g31, 0
g.li g31, 1504
g.st g19, g31, 0
g.li g31, 1508
g.st g20, g31, 0
g.mov g12, g9
g.mov g13, g10
g.mov g14, g7
g.mov g15, g8
g.fsub g16, g14, g12
g.fsub g17, g15, g13
g.fmul g18, g16, g16
g.fmul g19, g17, g17
g.fadd g18, g18, g19
g.sqrt g18, g18
g.fdiv g19, g16, g18
g.fdiv g20, g17, g18
g.fli g21, 0.5
g.fmul g18, g18, g21
g.fli g22, 0.039
g.fadd g18, g18, g22
g.fli g22, 1
g.fdiv g18, g22, g18
g.fadd g12, g12, g14
g.fmul g12, g12, g21
g.fadd g13, g13, g15
g.fmul g13, g13, g21
g.li g31, 1520
g.st g12, g31, 0
g.li g31, 1524
g.st g13, g31, 0
g.li g31, 1532
g.st g18, g31, 0
g.li g31, 1544
g.st g19, g31, 0
g.li g31, 1548
g.st g20, g31, 0
g.fli g2, 0.0390625
g.fmul g2, g1, g2
g.ftoi g3, g2
g.itof g3, g3
g.fsub g2, g2, g3
g.fli g3, 32
g.fmul g2, g2, g3
g.fli g3, 16
g.fsub g2, g3, g2
g.fli g3, -0.1
g.fadd g3, g3, g2
g.li g31, 1600
g.st g3, g31, 0
g.fli g3, 0
g.fadd g3, g3, g2
g.li g31, 1640
g.st g3, g31, 0
g.fli g3, -0.46
g.fadd g3, g3, g2
g.li g31, 1680
g.st g3, g31, 0
g.fli g3, 0.46
g.fadd g3, g3, g2
g.li g31, 1720
g.st g3, g31, 0
g.fli g3, 0
g.fadd g3, g3, g2
g.li g31, 1760
g.st g3, g31, 0
g.fli g3, 16
g.fadd g2, g2, g3
g.flt g4, g2, g3
g.bnz g4, beach_wrap_done
g.fli g3, 32
g.fsub g2, g2, g3
beach_wrap_done:
g.li g31, 1800
g.st g2, g31, 0
g.li g31, 1840
g.st g2, g31, 0
g.li g31, 1880
g.st g2, g31, 0
g.end
animate_end:
render:
g.li g31, 0
g.ld g1, g31, 1
g.li g31, 4
g.ld g2, g31, 1
g.li g31, 8
g.ld g3, g31, 1
g.li g31, 16
g.ld g4, g31, 1
g.li g31, 20
g.ld g5, g31, 1
g.li g31, 24
g.ld g6, g31, 1
g.id g7, 0
g.itof g7, g7
g.fli g8, 79.5
g.fsub g7, g7, g8
g.fli g8, 0.00806452
g.fmul g7, g7, g8
g.li g31, 32
g.ld g9, g31, 1
g.li g31, 36
g.ld g10, g31, 1
g.li g31, 40
g.ld g11, g31, 1
g.vscale g9, g9, g7
g.vadd g4, g4, g9
g.id g7, 1
g.itof g7, g7
g.fli g8, 59.5
g.fsub g7, g8, g7
g.fli g8, 0.00806452
g.fmul g7, g7, g8
g.li g31, 48
g.ld g9, g31, 1
g.li g31, 52
g.ld g10, g31, 1
g.li g31, 56
g.ld g11, g31, 1
g.vscale g9, g9, g7
g.vadd g4, g4, g9
g.norm3 g4, g4
g.fli g7, 999
g.fli g9, 4
g.fmul g10, g5, g9
g.fli g9, 13
g.fsub g10, g9, g10
g.ftoi g8, g10
g.li g9, 0
g.fli g10, -0.001
g.flt g31, g5, g10
g.bz g31, objects_begin
g.fsub g10, g0, g2
g.fdiv g7, g10, g5
g.vscale g11, g4, g7
g.vadd g11, g11, g1
g.li g8, 62
g.fli g14, -2.8
g.flt g31, g13, g14
g.bnz g31, ocean
g.fli g14, -1.5
g.flt g31, g13, g14
g.bnz g31, sand
g.fli g14, 1.5
g.flt g31, g14, g13
g.bnz g31, sand
g.li g8, 77
; Seaside promenade stripes slide beneath the rider.

g.li g31, 64
g.ld g14, g31, 1
g.fli g15, 1.25
g.fmul g14, g14, g15
g.fadd g14, g11, g14
g.fli g15, 0.5
g.fmul g14, g14, g15
g.fli g30, 128
g.fadd g14, g14, g30
g.ftoi g15, g14
g.itof g15, g15
g.fsub g14, g14, g15
g.fli g15, 0.15
g.flt g31, g14, g15
g.bz g31, ground_shadow
g.fli g15, 1.25
g.flt g31, g15, g13
g.bz g31, ground_shadow
g.li g8, 237
g.jmp ground_shadow
sand:
g.li g8, 62
g.jmp ground_shadow
ocean:
g.li g8, 28

g.li g31, 64
g.ld g14, g31, 1
g.fli g15, 0.3
g.fmul g14, g14, g15
g.fli g15, 0.21
g.fmul g15, g11, g15
g.fadd g14, g14, g15
g.fli g15, 0.68
g.fmul g15, g13, g15
g.fadd g14, g14, g15
g.fli g15, 128
g.fadd g14, g14, g15
g.ftoi g28, g14
g.itof g28, g28
g.fsub g17, g14, g28
g.fli g28, 2
g.fmul g17, g17, g28
g.fli g28, 1
g.fsub g17, g17, g28
g.fli g29, -1
g.fmul g29, g17, g29
g.fmax g29, g17, g29
g.fsub g29, g28, g29
g.fmul g17, g17, g29
g.fli g28, 4
g.fmul g17, g17, g28
g.fli g15, 0.25
g.fadd g14, g14, g15
g.ftoi g28, g14
g.itof g28, g28
g.fsub g19, g14, g28
g.fli g28, 2
g.fmul g19, g19, g28
g.fli g28, 1
g.fsub g19, g19, g28
g.fli g29, -1
g.fmul g29, g19, g29
g.fmax g29, g19, g29
g.fsub g29, g28, g29
g.fmul g19, g19, g29
g.fli g28, 4
g.fmul g19, g19, g28
g.fli g15, 0.04
g.fmul g17, g17, g15
g.fli g15, 0.075
g.fmul g19, g19, g15
g.fli g18, 1
g.norm3 g17, g17
g.reflect3 g20, g4, g17
; Fresnel-like brightening toward the water horizon.
g.fli g14, 6
g.fmul g14, g5, g14
g.fli g15, 30
g.fadd g14, g14, g15
g.ftoi g8, g14
g.fli g15, 0.072
g.flt g31, g15, g19
g.bz g31, water_crest_done
g.li g8, 31
water_crest_done:
g.fli g26, -4.2
g.fli g27, 4.1
g.fli g28, -20
g.vsub g14, g11, g26
g.fli g23, 0.35546875
g.fli g24, 2.6328125
g.fli g25, 1.5390625
g.fmul g14, g14, g23
g.fmul g15, g15, g24
g.fmul g16, g16, g25
g.fmul g23, g20, g23
g.fmul g24, g21, g24
g.fmul g25, g22, g25
g.mov g26, g0
g.mov g27, g0
g.mov g28, g0
g.fli g29, 1
g.sphere g30, g14, g23, g26
g.flt g31, g0, g30
g.bz g31, reflection_cloud_west
g.li g8, 43
reflection_cloud_west:
g.fli g26, -3.4
g.fli g27, 4.25
g.fli g28, -20
g.vsub g14, g11, g26
g.fli g23, 0.69140625
g.fli g24, 2.08203125
g.fli g25, 1.5390625
g.fmul g14, g14, g23
g.fmul g15, g15, g24
g.fmul g16, g16, g25
g.fmul g23, g20, g23
g.fmul g24, g21, g24
g.fmul g25, g22, g25
g.mov g26, g0
g.mov g27, g0
g.mov g28, g0
g.fli g29, 1
g.sphere g30, g14, g23, g26
g.flt g31, g0, g30
g.bz g31, reflection_cloud_puff
g.li g8, 43
reflection_cloud_puff:
g.fli g26, 3.2
g.fli g27, 4.05
g.fli g28, -22
g.vsub g14, g11, g26
g.fli g23, 0.3984375
g.fli g24, 3.125
g.fli g25, 2
g.fmul g14, g14, g23
g.fmul g15, g15, g24
g.fmul g16, g16, g25
g.fmul g23, g20, g23
g.fmul g24, g21, g24
g.fmul g25, g22, g25
g.mov g26, g0
g.mov g27, g0
g.mov g28, g0
g.fli g29, 1
g.sphere g30, g14, g23, g26
g.flt g31, g0, g30
g.bz g31, reflection_cloud_east
g.li g8, 43
reflection_cloud_east:
g.fli g23, 5.2
g.fli g24, 4.6
g.fli g25, -22
g.vsub g23, g23, g11
g.norm3 g23, g23
g.dot3 g14, g20, g23
g.fmax g14, g14, g0
g.fmul g14, g14, g14
g.fmul g14, g14, g14
g.fmul g14, g14, g14
g.fmul g14, g14, g14
g.fmul g14, g14, g14
g.fmul g14, g14, g14
g.fli g15, 0.45
g.flt g31, g15, g14
g.bz g31, water_foam
g.li g8, 158
water_foam:

g.fli g15, -3.12
g.flt g31, g15, g13
g.bz g31, objects_begin
g.li g8, 46
g.jmp objects_begin
ground_shadow:
; Soft analytic contact shadow stretched by the sun.
g.fli g14, 0.48
g.fmul g14, g11, g14
g.fmul g14, g14, g14
g.fli g15, 1.8
g.fmul g15, g13, g15
g.fmul g15, g15, g15
g.fadd g14, g14, g15
g.fli g15, 1
g.flt g31, g14, g15
g.bz g31, cast_shadow
g.li g15, 5
g.sub g8, g8, g15
g.jmp objects_begin
cast_shadow:
; Directional shadow rays against the body ellipsoid and head sphere.
g.fli g17, -0.23
g.fli g18, 2.06
g.fli g19, 0
g.vsub g20, g11, g17
g.fli g23, 1.61290323
g.fli g24, 2.17391304
g.fli g25, 2.63157895
g.fmul g20, g20, g23
g.fmul g21, g21, g24
g.fmul g22, g22, g25
g.fli g17, -0.67741935
g.fli g18, 1.7826087
g.fli g19, 1
g.mov g26, g0
g.mov g27, g0
g.mov g28, g0
g.fli g29, 1
g.sphere g30, g20, g17, g26
g.flt g31, g0, g30
g.bnz g31, cast_shadow_hit
g.fli g26, 0.53
g.fli g27, 2.99
g.fli g29, 0.3
g.fli g17, -0.42
g.fli g18, 0.82
g.fli g19, 0.38
g.sphere g30, g11, g17, g26
g.flt g31, g0, g30
g.bz g31, objects_begin
cast_shadow_hit:
g.li g15, 4
g.sub g8, g8, g15
objects_begin:
; One conservative bound culls all bicycle/bird primitives.
g.fli g26, 0.15
g.fli g27, 1.73
g.fli g28, 0
g.fli g29, 2.25
g.sphere g30, g1, g4, g26
g.flt g31, g0, g30
g.li g10, 80
g.bnz g31, hero_bound_hit
g.li g10, 1600
hero_bound_hit:
g.li g9, 0
g.mov g26, g0
g.mov g27, g0
g.mov g28, g0
g.fli g29, 1
intersect:

g.mov g31, g10
g.ld g11, g31, 1
g.li g30, 4
g.add g31, g31, g30
g.ld g12, g31, 1
g.add g31, g31, g30
g.ld g13, g31, 1
g.add g31, g31, g30
g.ld g15, g31, 1
g.add g31, g31, g30
g.ld g16, g31, 1
g.add g31, g31, g30
g.ld g17, g31, 1
g.add g31, g31, g30
g.ld g18, g31, 1
g.add g31, g31, g30
g.ld g19, g31, 1
g.vsub g20, g1, g11
g.bnz g19, rotated_ray
g.mov g23, g4
g.mov g24, g5
g.jmp scaled_ray
rotated_ray:
g.fmul g30, g20, g18
g.fmul g31, g21, g19
g.fadd g30, g30, g31
g.fmul g31, g20, g19
g.fmul g21, g21, g18
g.fsub g21, g21, g31
g.mov g20, g30
g.fmul g30, g4, g18
g.fmul g31, g5, g19
g.fadd g23, g30, g31
g.fmul g30, g4, g19
g.fmul g31, g5, g18
g.fsub g24, g31, g30
scaled_ray:
g.fmul g20, g20, g15
g.fmul g21, g21, g16
g.fmul g22, g22, g17
g.fmul g23, g23, g15
g.fmul g24, g24, g16
g.fmul g25, g6, g17
g.sphere g30, g20, g23, g26
g.flt g31, g0, g30
g.bz g31, next_object
g.flt g31, g30, g7
g.bz g31, next_object
; Annular CSG clips the two wheel ellipsoids; exact ray points.
g.li g31, 36
g.add g31, g10, g31
g.ld g14, g31, 1
g.bz g14, accept_hit
; Retain both quadratic roots when a near hit falls inside the wheel hole.
g.dot3 g14, g20, g23
g.dot3 g31, g23, g23
g.fdiv g14, g14, g31
g.fadd g14, g14, g14
g.fsub g14, g0, g14
g.fsub g14, g14, g30
g.fmul g15, g23, g30
g.fadd g15, g15, g20
g.fmul g16, g24, g30
g.fadd g16, g16, g21
g.fmul g15, g15, g15
g.fmul g16, g16, g16
g.fadd g15, g15, g16
g.fli g16, 0.76
g.flt g31, g16, g15
g.bnz g31, accept_hit
g.flt g31, g0, g14
g.bz g31, next_object
g.flt g31, g14, g7
g.bz g31, next_object
g.mov g30, g14
g.fmul g15, g23, g30
g.fadd g15, g15, g20
g.fmul g16, g24, g30
g.fadd g16, g16, g21
g.fmul g15, g15, g15
g.fmul g16, g16, g16
g.fadd g15, g15, g16
g.fli g16, 0.76
g.flt g31, g16, g15
g.bz g31, next_object
accept_hit:
g.mov g7, g30
g.mov g9, g10
next_object:
g.li g30, 40
g.add g10, g10, g30
g.li g30, 2080
g.sltu g31, g10, g30
g.bnz g31, intersect
g.bz g9, write_pixel
; Recover the selected ellipsoid and its exact gradient normal.
g.mov g31, g9
g.ld g11, g31, 1
g.li g30, 4
g.add g31, g31, g30
g.ld g12, g31, 1
g.add g31, g31, g30
g.ld g13, g31, 1
g.add g31, g31, g30
g.ld g15, g31, 1
g.add g31, g31, g30
g.ld g16, g31, 1
g.add g31, g31, g30
g.ld g17, g31, 1
g.add g31, g31, g30
g.ld g18, g31, 1
g.add g31, g31, g30
g.ld g19, g31, 1
g.add g31, g31, g30
g.ld g8, g31, 1
g.vscale g20, g4, g7
g.vadd g20, g20, g1
g.vsub g20, g20, g11
g.fmul g30, g20, g18
g.fmul g31, g21, g19
g.fadd g30, g30, g31
g.fmul g31, g20, g19
g.fmul g21, g21, g18
g.fsub g21, g21, g31
g.mov g20, g30
g.fmul g20, g20, g15
g.fmul g20, g20, g15
g.fmul g21, g21, g16
g.fmul g21, g21, g16
g.fmul g22, g22, g17
g.fmul g22, g22, g17
g.fmul g30, g20, g18
g.fmul g31, g21, g19
g.fsub g30, g30, g31
g.fmul g31, g20, g19
g.fmul g21, g21, g18
g.fadd g21, g21, g31
g.mov g20, g30
g.norm3 g20, g20
g.fli g23, -0.42
g.fli g24, 0.82
g.fli g25, 0.38
g.vsub g26, g23, g4
g.norm3 g26, g26
g.dot3 g14, g20, g26
g.fmax g14, g14, g0
g.fmul g14, g14, g14
g.fmul g14, g14, g14
g.fmul g14, g14, g14
g.fmul g14, g14, g14
g.fli g30, 3
g.fmul g14, g14, g30
g.dot3 g30, g20, g23
g.fmax g30, g30, g0
g.fli g31, 8
g.fmul g30, g30, g31
g.fli g31, 6
g.fadd g30, g30, g31
g.fadd g30, g30, g14
g.fli g31, 15
g.fmin g30, g30, g31
g.ftoi g30, g30
g.li g31, 4
g.shl g8, g8, g31
g.add g8, g8, g30
write_pixel:
g.id g31, 2
g.stb g8, g31, 0
g.end
render_end:

synth:
g.id g1, 2
g.uniform g2, 14
g.add g1, g1, g2
g.itof g2, g1
g.fli g3, 0.00008333
g.fmul g3, g2, g3
g.ftoi g4, g3
g.itof g5, g4
g.fsub g5, g3, g5
g.li g6, 31
g.and g6, g4, g6
g.li g7, 2
g.shl g6, g6, g7
g.ld g6, g6, 1
g.fli g7, 0.00002083
g.fmul g2, g2, g7
g.fmul g7, g2, g6
g.ftoi g28, g7
g.itof g28, g28
g.fsub g8, g7, g28
g.fli g28, 2
g.fmul g8, g8, g28
g.fli g28, 1
g.fsub g8, g8, g28
g.fli g29, -1
g.fmul g29, g8, g29
g.fmax g29, g8, g29
g.fsub g29, g28, g29
g.fmul g8, g8, g29
g.fli g28, 4
g.fmul g8, g8, g28
g.fli g9, 1
g.fsub g9, g9, g5
g.fmul g10, g9, g9
g.fmul g10, g10, g9
g.fli g11, 0.22
g.fmul g10, g10, g11
g.fmul g8, g8, g10
; A quieter octave overtone softens the triangular pluck.
g.fli g11, 2
g.fmul g7, g7, g11
g.ftoi g28, g7
g.itof g28, g28
g.fsub g12, g7, g28
g.fli g28, 2
g.fmul g12, g12, g28
g.fli g28, 1
g.fsub g12, g12, g28
g.fli g29, -1
g.fmul g29, g12, g29
g.fmax g29, g12, g29
g.fsub g29, g28, g29
g.fmul g12, g12, g29
g.fli g28, 4
g.fmul g12, g12, g28
g.fli g11, 0.23
g.fmul g12, g12, g11
g.fmul g12, g12, g10
g.fadd g8, g8, g12
; Four-bar walking bass.
g.li g6, 3
g.shr g6, g4, g6
g.li g7, 3
g.and g6, g6, g7
g.li g7, 2
g.shl g6, g6, g7
g.li g7, 128
g.add g6, g6, g7
g.ld g6, g6, 1
g.fli g20, 4
g.fmul g21, g6, g20
g.fmul g21, g2, g21
g.ftoi g28, g21
g.itof g28, g28
g.fsub g26, g21, g28
g.fli g28, 2
g.fmul g26, g26, g28
g.fli g28, 1
g.fsub g26, g26, g28
g.fli g29, -1
g.fmul g29, g26, g29
g.fmax g29, g26, g29
g.fsub g29, g28, g29
g.fmul g26, g26, g29
g.fli g28, 4
g.fmul g26, g26, g28
g.fli g20, 6.015
g.fmul g21, g6, g20
g.fmul g21, g2, g21
g.ftoi g28, g21
g.itof g28, g28
g.fsub g27, g21, g28
g.fli g28, 2
g.fmul g27, g27, g28
g.fli g28, 1
g.fsub g27, g27, g28
g.fli g29, -1
g.fmul g29, g27, g29
g.fmax g29, g27, g29
g.fsub g29, g28, g29
g.fmul g27, g27, g29
g.fli g28, 4
g.fmul g27, g27, g28
g.li g20, 7
g.and g20, g4, g20
g.itof g20, g20
g.fadd g20, g20, g5
g.fli g21, 0.125
g.fmul g20, g20, g21
g.fli g21, 1
g.fsub g22, g21, g20
g.fli g23, 8
g.fmul g20, g20, g23
g.fmul g22, g22, g23
g.fmin g20, g20, g21
g.fmin g22, g22, g21
g.fmul g20, g20, g22
g.fli g21, 0.025
g.fmul g20, g20, g21
g.fmul g26, g26, g20
g.fmul g27, g27, g20
g.fmul g7, g2, g6
g.ftoi g28, g7
g.itof g28, g28
g.fsub g12, g7, g28
g.fli g28, 2
g.fmul g12, g12, g28
g.fli g28, 1
g.fsub g12, g12, g28
g.fli g29, -1
g.fmul g29, g12, g29
g.fmax g29, g12, g29
g.fsub g29, g28, g29
g.fmul g12, g12, g29
g.fli g28, 4
g.fmul g12, g12, g28
g.fli g11, 0.13
g.fmul g12, g12, g11
g.fmul g12, g12, g9
g.fadd g8, g8, g12
; Bright offbeat chord tone.
g.li g6, 7
g.and g6, g4, g6
g.li g7, 2
g.shl g6, g6, g7
g.li g7, 144
g.add g6, g6, g7
g.ld g6, g6, 1
g.fmul g7, g2, g6
g.ftoi g28, g7
g.itof g28, g28
g.fsub g13, g7, g28
g.fli g28, 2
g.fmul g13, g13, g28
g.fli g28, 1
g.fsub g13, g13, g28
g.fli g29, -1
g.fmul g29, g13, g29
g.fmax g29, g13, g29
g.fsub g29, g28, g29
g.fmul g13, g13, g29
g.fli g28, 4
g.fmul g13, g13, g28
g.fli g11, 0.045
g.fmul g13, g13, g11
g.fmul g13, g13, g9
; Kick phase is a decelerating oscillator, reset every quarter note.
g.li g6, 1
g.and g6, g4, g6
g.itof g6, g6
g.fadd g6, g6, g5
g.fli g7, 0.5
g.fmul g6, g6, g7
g.fli g7, 1
g.fsub g10, g7, g6
g.fmul g10, g10, g10
g.fmul g10, g10, g10
g.fmul g10, g10, g10
g.fli g7, 23
g.fmul g7, g6, g7
g.fli g11, 13
g.fmul g11, g6, g11
g.fmul g11, g11, g6
g.fsub g7, g7, g11
g.ftoi g28, g7
g.itof g28, g28
g.fsub g14, g7, g28
g.fli g28, 2
g.fmul g14, g14, g28
g.fli g28, 1
g.fsub g14, g14, g28
g.fli g29, -1
g.fmul g29, g14, g29
g.fmax g29, g14, g29
g.fsub g29, g28, g29
g.fmul g14, g14, g29
g.fli g28, 4
g.fmul g14, g14, g28
g.fli g11, 0.22
g.fmul g14, g14, g11
g.fmul g14, g14, g10
g.fadd g8, g8, g14
; Deterministic sample hash makes brushed hats and a backbeat.
g.li g6, 1664525
g.mul g6, g1, g6
g.li g7, 1013904223
g.xor g6, g6, g7
g.li g7, 13
g.shr g7, g6, g7
g.xor g6, g6, g7
g.li g7, 65535
g.and g6, g6, g7
g.itof g6, g6
g.fli g7, 0.00003052
g.fmul g6, g6, g7
g.fli g7, 1
g.fsub g6, g6, g7
g.fmul g10, g9, g9
g.fmul g10, g10, g10
g.fmul g10, g10, g10
g.fli g11, 0.024
g.fmul g10, g10, g11
g.fmul g14, g6, g10
g.li g7, 3
g.and g7, g4, g7
g.li g11, 2
g.sub g7, g7, g11
g.bnz g7, no_snare
g.fli g11, 0.11
g.fmul g15, g6, g11
g.fmul g15, g15, g9
g.fmul g15, g15, g9
g.fadd g14, g14, g15
no_snare:
g.fadd g8, g8, g14
; Stereo chord spread; lead and rhythm centered.
g.fadd g16, g8, g13
g.fli g11, -0.7
g.fmul g13, g13, g11
g.fadd g17, g8, g13
g.fadd g16, g16, g26
g.fadd g17, g17, g27
; Stereo slapback: 85.3 ms, low-gain cross feedback in persistent guest RAM.
g.id g19, 2
g.uniform g18, 14
g.add g19, g19, g18
g.li g18, 4095
g.and g19, g19, g18
g.li g18, 3
g.shl g19, g19, g18
g.ld g20, g19, 2
g.li g18, 4
g.add g19, g19, g18
g.ld g21, g19, 2
g.fli g22, 0.22
g.fmul g20, g20, g22
g.fmul g21, g21, g22
g.fadd g16, g16, g21
g.fadd g17, g17, g20
g.st g17, g19, 2
g.sub g19, g19, g18
g.st g16, g19, 2
g.id g1, 2
g.li g2, 3
g.shl g1, g1, g2
g.st g16, g1, 0
g.li g2, 4
g.add g1, g1, g2
g.st g17, g1, 0
g.end
synth_end:
.align 4
scene:
.float 0,2.8,5.9,0, 0,0,-1,0, 1,0,0,0, 0,1,0,0, 0,0,0,0

; tire
.float -0.94140625,0.66015625,0,1.5625,1.5625,12.5,1,0
.word 6,1
; rim
.float -0.94140625,0.66015625,0.0078125,1.73828125,1.73828125,15.3828125,1,0
.word 8,2
; spoke
.float -0.94140625,0.66015625,0.01171875,1.8515625,55.5546875,55.5546875,1,0
.word 8,0
; spoke
.float -0.94140625,0.66015625,0.01171875,1.8515625,55.5546875,55.5546875,0,1
.word 8,0
; hub
.float -0.94140625,0.66015625,0.046875,11.765625,11.765625,14.28515625,1,0
.word 8,0
; tire
.float 0.94140625,0.66015625,0,1.5625,1.5625,12.5,1,0
.word 6,1
; rim
.float 0.94140625,0.66015625,0.0078125,1.73828125,1.73828125,15.3828125,1,0
.word 8,2
; spoke
.float 0.94140625,0.66015625,0.01171875,1.8515625,55.5546875,55.5546875,1,0
.word 8,0
; spoke
.float 0.94140625,0.66015625,0.01171875,1.8515625,55.5546875,55.5546875,0,1
.word 8,0
; hub
.float 0.94140625,0.66015625,0.046875,11.765625,11.765625,14.28515625,1,0
.word 8,0
; frame
.float -0.640625,1.078125,0,1.78125,22.22265625,22.22265625,0.58203125,0.8125
.word 7,0
; frame
.float -0.1796875,1.109375,0,2.14453125,22.22265625,22.22265625,0.37890625,-0.92578125
.word 7,0
; frame
.float -0.48046875,0.69140625,0,1.9765625,22.22265625,22.22265625,-0.99609375,-0.06640625
.word 7,0
; frame
.float 0.14453125,1.48046875,0,1.88671875,22.22265625,22.22265625,1,-0.04296875
.word 7,0
; frame
.float 0.3046875,1.08984375,0,1.859375,22.22265625,22.22265625,-0.66015625,-0.75
.word 7,0
; frame
.float 0.78515625,1.05859375,0,2.109375,22.22265625,22.22265625,0.359375,-0.93359375
.word 7,0
; stem
.float 0.66015625,1.671875,0,4.046875,28.5703125,28.5703125,0.140625,0.98828125
.word 8,0
; handle
.float 0.8515625,1.88671875,0,4.875,22.22265625,22.22265625,1,0.03125
.word 11,0
; saddle
.float -0.3515625,1.6015625,0,3.2265625,13.33203125,5.8828125,1,0
.word 11,0
; body
.float -0.23046875,2.05859375,0,1.61328125,2.17578125,2.6328125,0.9921875,-0.12890625
.word 5,0
; tail
.float -0.83984375,2.05078125,0,2.85546875,7.69140625,5.5546875,0.97265625,-0.2265625
.word 6,0
; wing
.float -0.4296875,2.0703125,0.3203125,2.08203125,5,10,0.97265625,-0.23828125
.word 6,0
; wing cover
.float -0.23828125,2.171875,0.37890625,2.32421875,4.76171875,12.5,0.96484375,-0.265625
.word 5,0
; neck base
.float 0.21875,2.37109375,0,4.34765625,2.3828125,4.546875,0.96875,-0.24609375
.word 5,0
; neck
.float 0.390625,2.6796875,0,6.66796875,3.03125,5.8828125,1,0.05859375
.word 5,0
; head
.float 0.53125,2.98828125,0,3.33203125,4,4,1,0
.word 5,0
; pouch
.float 1.01171875,2.78125,0.015625,1.640625,6.8984375,8,1,-0.01953125
.word 9,0
; bill
.float 1.0390625,2.8984375,0.015625,1.5390625,14.4921875,7.69140625,0.99609375,-0.0703125
.word 9,0
; eye
.float 0.58984375,3.03515625,0.23828125,24.390625,21.73828125,43.4765625,1,0
.word 15,0
; eye glint
.float 0.6015625,3.05078125,0.2578125,83.33203125,71.4296875,111.109375,1,0
.word 5,0
; cap
.float 0.51171875,3.1796875,0,3.2265625,8.33203125,3.84765625,1,0
.word 12,0
; cap visor
.float 0.76171875,3.16015625,0.05859375,4.76171875,31.25,4.546875,1,0
.word 12,0
; upper leg
.float -0.03515625,1.59375,0.1796875,3.00390625,22.22265625,22.22265625,0.296875,-0.95703125
.word 10,0
; lower leg
.float 0.125,1.01953125,0.1796875,2.87109375,25.640625,25.640625,0.2421875,-0.96875
.word 10,0
; webbed foot
.float 0.19921875,0.71875,0.1796875,5.5546875,18.18359375,10,1,0
.word 10,0
; upper leg
.float -0.03515625,1.59375,-0.1796875,3.00390625,22.22265625,22.22265625,0.296875,-0.95703125
.word 10,0
; lower leg
.float 0.125,1.01953125,-0.1796875,2.87109375,25.640625,25.640625,0.2421875,-0.96875
.word 10,0
; webbed foot
.float 0.19921875,0.71875,-0.1796875,5.5546875,18.18359375,10,1,0
.word 10,0
; palm trunk
.float -2.6015625,1.0234375,-2.1015625,0.9140625,15.3828125,15.3828125,0.09765625,0.99609375
.word 11,0
; palm crown
.float -2.5,2.078125,-2.1015625,5,5.5546875,5,1,0
.word 13,0
; palm left
.float -2.9609375,2.03125,-2.1015625,1.5390625,9.08984375,4.76171875,0.97265625,0.2265625
.word 13,0
; palm right
.float -2.0390625,2.03125,-2.1015625,1.5390625,9.08984375,4.76171875,0.97265625,-0.2265625
.word 13,0
; palm frond
.float -2.5,2.05859375,-2.1015625,6.66796875,10,1.37109375,1,0
.word 13,0
; parasol pole
.float 2.69921875,0.80078125,-2.03125,37.03515625,1.25,37.03515625,1,0
.word 8,0
; parasol
.float 2.69921875,1.58984375,-2.03125,1.3515625,4.546875,1.46875,1,0
.word 12,0
; parasol stripe
.float 2.69921875,1.6015625,-2.03125,6.66796875,4.46484375,1.46875,1,0
.word 14,0
; cloud west
.float -4.19921875,4.1015625,-20,0.35546875,2.6328125,1.5390625,1,0
.word 5,0
; cloud puff
.float -3.3984375,4.25,-20,0.69140625,2.08203125,1.5390625,1,0
.word 5,0
; cloud east
.float 3.19921875,4.05078125,-22,0.3984375,3.125,2,1,0
.word 5,0
; sun
.float 5.19921875,4.6015625,-22,1.46875,1.46875,1.46875,1,0
.word 9,0
scene_end:
notes:
.float 523.251131,659.255114,783.990872,880.000000,783.990872,659.255114,587.329536,391.995436,440.000000,523.251131,659.255114,783.990872,659.255114,523.251131,493.883301,391.995436,349.228231,440.000000,523.251131,659.255114,587.329536,523.251131,440.000000,349.228231,391.995436,493.883301,587.329536,783.990872,698.456463,587.329536,493.883301,391.995436
.float 130.812783,110.000000,87.307058,97.998859
.float 261.625565,329.627557,391.995436,523.251131,220.000000,261.625565,329.627557,440.000000
notes_end:
palette:
.byte 110,194,245,15,145,168,204,245,237,250,212,143,184,120,92,252,250,230,28,41,54,18,196,173,176,214,222,255,181,43,245,94,31,64,43,41,255,84,74,46,133,89,255,240,186,5,20,36
palette_end:
