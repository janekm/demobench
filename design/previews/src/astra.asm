; ASTRA / an original 4K audiovisual cartridge for DB32
; All pixels, instruments, sequencing and typography execute in the guest.
; 128 BPM, 32 bars, 60-second looping score. No host assets.
.profile spu-1
.entry start
start:
    lui r10, 0xf3
    lui r11, 0xf5
    lui r12, 0xf6
    addi r1, r0, visual
    sw r1, 0(r10)
    addi r1, r0, visual_end-visual
    sw r1, 4(r10)
    addi r1, r0, 160
    sw r1, 8(r10)
    addi r1, r0, 120
    sw r1, 12(r10)
    li r1, 57600
    sw r1, 68(r10)
    addi r1, r0, 3
    sw r1, 72(r10)
    sw r0, 80(r10)
    addi r1, r0, rom_end
    sw r1, 84(r10)
    addi r1, r0, 1
    sw r1, 88(r10)
    sw r1, 16(r11)
    addi r1, r0, 480
    sw r1, 4(r11)
    addi r1, r0, 4
    sw r1, 8(r11)
    addi r1, r0, music
    sw r1, 64(r12)
    addi r1, r0, music_end-music
    sw r1, 68(r12)
    addi r1, r0, 128
    sw r1, 72(r12)
    addi r1, r0, 2
    sw r1, 76(r12)
    li r1, 0x2c200
    sw r1, 80(r12)
    sw r1, 256(r12)
    addi r1, r0, 2048
    sw r1, 260(r12)
    addi r1, r0, 3
    sw r1, 264(r12)
    sw r0, 272(r12)
    addi r1, r0, rom_end
    sw r1, 276(r12)
    addi r1, r0, 1
    sw r1, 280(r12)
    sw r1, 0(r12)
    lui r8, 0x10
    li r9, 0x1e100
frame:
    sw r8, 64(r10)
    lw r1, 20(r12)
    sw r1, 256(r10)
    addi r2, r0, 1
    sw r2, 16(r10)
wait_gpu:
    wfi
    lw r1, 20(r10)
    beq r1, r2, wait_gpu
    sw r8, 0(r11)
    sw r2, 20(r11)
wait_flip:
    wfi
    lw r1, 20(r11)
    bne r1, r0, wait_flip
    mov r1, r8
    mov r8, r9
    mov r9, r1
    j frame

; ---------- Visual kernel ----------
; g1/g2 screen, g3 beat, g4 chapter; g5-7 ray; g8 travel.
; g9 step count, g10-12 point, g13-15 scratch, g16 distance.
; g20/21 camera rotation, g22-24 RGB, g25 glow, g30 one.
visual:
    g.fli g30, 1.0
    g.id g1, 0
    g.id g2, 1
    g.li g31, 9
    g.sltu g26, g2, g31
    g.bnz g26, black
    g.li g31, 111
    g.sltu g26, g2, g31
    g.bz g26, black
    g.uniform g3, 0
    g.itof g3, g3
    g.fli g31, 0.0000444444444
    g.fmul g3, g3, g31
    g.fli g31, 0.0078125
    g.fmul g4, g3, g31
    g.ftoi g4, g4
    g.itof g4, g4
    g.fli g31, 128.0
    g.fmul g4, g4, g31
    g.fsub g3, g3, g4
    g.fli g31, 0.0625
    g.fmul g4, g3, g31
    g.ftoi g4, g4
    g.itof g5, g1
    g.itof g6, g2
    g.fli g31, 79.5
    g.fsub g5, g5, g31
    g.fli g31, 59.5
    g.fsub g6, g31, g6
    g.fli g31, 0.017
    g.fmul g5, g5, g31
    g.fmul g6, g6, g31
    g.fli g7, 1.8
    g.norm3 g5, g5
    g.fli g31, 0.03125
    g.fmul g19, g3, g31

g.ftoi g28, g19
g.itof g28, g28
g.fsub g20, g19, g28
g.fadd g20, g20, g20
g.fsub g20, g20, g30
g.fsub g29, g0, g20
g.fmax g29, g20, g29
g.fsub g29, g30, g29
g.fmul g20, g20, g29
g.fli g28, 4.0
g.fmul g20, g20, g28

g.fli g31, 0.25
g.fadd g19, g19, g31

g.ftoi g28, g19
g.itof g28, g28
g.fsub g21, g19, g28
g.fadd g21, g21, g21
g.fsub g21, g21, g30
g.fsub g29, g0, g21
g.fmax g29, g21, g29
g.fsub g29, g30, g29
g.fmul g21, g21, g29
g.fli g28, 4.0
g.fmul g21, g21, g28

g.li g31, 3
    g.and g18, g4, g31
    ; Normalize the parabolic rotation pair.
    g.fmul g26, g20, g20
    g.fmul g27, g21, g21
    g.fadd g26, g26, g27
    g.rsqrt g26, g26
    g.fmul g20, g20, g26
    g.fmul g21, g21, g26
    g.li g31, 3
    g.sub g31, g18, g31
    g.bz g31, julia
    g.fli g8, 0.05
    g.mov g9, g0
    g.mov g25, g0
    g.li g31, 2
    g.sltu g31, g18, g31
    g.bz g31, march
    ; Analytic bounding sphere prevents expensive empty-space traversal.
    g.mov g10, g0
    g.mov g11, g0
    g.fli g12, -3.5
    g.mov g13, g0
    g.mov g14, g0
    g.mov g15, g0
    g.itof g16, g18
    g.fli g31, 0.4
    g.fmul g16, g16, g31
    g.fli g31, 1.5
    g.fadd g16, g16, g31
    g.sphere g8, g10, g5, g13
    g.flt g31, g8, g0
    g.bz g31, march
    g.fli g8, 22.0
    g.fli g16, 1.0
    g.jmp shade
march:
    g.vscale g10, g5, g8
    g.li g31, 2
    g.sltu g31, g18, g31
    g.bz g31, corridor
    g.fli g31, 3.5
    g.fsub g12, g12, g31
    ; Two animated rotations, preserving a coherent camera.
    g.fmul g13, g10, g20
    g.fmul g14, g12, g21
    g.fadd g13, g13, g14
    g.fmul g14, g10, g21
    g.fmul g12, g12, g20
    g.fsub g12, g12, g14
    g.fmul g10, g13, g21
    g.fmul g14, g11, g20
    g.fsub g10, g10, g14
    g.fmul g11, g11, g21
    g.fmul g14, g13, g20
    g.fadd g11, g11, g14
    g.bnz g18, crystal
    ; Torus with circular ribs.
    g.fmul g13, g10, g10
    g.fmul g14, g12, g12
    g.fadd g13, g13, g14
    g.sqrt g13, g13
    g.fli g31, 1.1
    g.fsub g13, g13, g31
    g.fmul g13, g13, g13
    g.fmul g14, g11, g11
    g.fadd g16, g13, g14
    g.sqrt g16, g16
    g.fli g31, 0.32
    g.fsub g16, g16, g31
    g.li g31, 4
    g.sltu g31, g4, g31
    g.bnz g31, field_done
    g.fmul g13, g10, g10
    g.fmul g14, g11, g11
    g.fadd g13, g13, g14
    g.sqrt g13, g13
    g.fli g31, 1.1
    g.fsub g13, g13, g31
    g.fmul g13, g13, g13
    g.fmul g14, g12, g12
    g.fadd g13, g13, g14
    g.sqrt g13, g13
    g.fli g31, 0.17
    g.fsub g13, g13, g31
    g.fmin g16, g16, g13
    g.jmp field_done
crystal:
    ; Three fold/scale iterations form a recursive cluster of 64 jewels.
    g.mov g26, g0
fold:
    g.vsub g13, g0, g10
    g.fmax g10, g10, g13
    g.fmax g11, g11, g14
    g.fmax g12, g12, g15
    g.fadd g13, g10, g11
    g.fsub g11, g10, g11
    g.fli g31, 1.41421356
    g.fmul g10, g13, g31
    g.fmul g11, g11, g31
    g.fadd g12, g12, g12
    g.fli g31, 1.2
    g.fsub g10, g10, g31
    g.fli g31, 0.7
    g.fsub g11, g11, g31
    g.fli g31, 0.5
    g.fsub g12, g12, g31
    g.li g31, 1
    g.add g26, g26, g31
    g.li g31, 3
    g.sltu g31, g26, g31
    g.bnz g31, fold
    g.dot3 g16, g10, g10
    g.sqrt g16, g16
    g.fli g31, 0.6
    g.fsub g16, g16, g31
    g.fli g31, 0.125
    g.fmul g16, g16, g31
    g.jmp field_done
corridor:
    ; Flying through an endless lattice of octahedral neon rings.
    g.fli g31, 0.65
    g.fmul g13, g3, g31
    g.fadd g12, g12, g13
    g.fli g31, 0.333333333
    g.fmul g13, g12, g31
    g.ftoi g14, g13
    g.itof g14, g14
    g.fsub g13, g13, g14
    g.fli g31, 3.0
    g.fmul g12, g13, g31
    g.fli g31, 1.5
    g.fsub g12, g12, g31
    g.fmul g13, g10, g20
    g.fmul g14, g11, g21
    g.fadd g13, g13, g14
    g.fmul g14, g10, g21
    g.fmul g11, g11, g20
    g.fsub g11, g11, g14
    g.mov g10, g13
    g.li g31, 4
    g.sltu g31, g4, g31
    g.bz g31, round_tunnel
    g.fsub g13, g0, g10
    g.fmax g13, g13, g10
    g.fsub g14, g0, g11
    g.fmax g14, g14, g11
    g.fadd g13, g13, g14
    g.jmp ring
round_tunnel:
    g.fmul g13, g10, g10
    g.fmul g14, g11, g11
    g.fadd g13, g13, g14
    g.sqrt g13, g13
ring:
    g.fli g31, 1.6
    g.fsub g13, g13, g31
    g.fmul g13, g13, g13
    g.fmul g14, g12, g12
    g.fadd g16, g13, g14
    g.sqrt g16, g16
    g.fli g31, 0.12
    g.fsub g16, g16, g31
field_done:
    ; Near-surface scattering, accumulated independently of the hit.
    g.fsub g17, g0, g16
    g.fmax g17, g17, g16
    g.fli g31, 0.025
    g.fadd g17, g17, g31
    g.fli g31, 0.006
    g.fdiv g17, g31, g17
    g.fadd g25, g25, g17
    g.fli g31, 0.012
    g.flt g31, g16, g31
    g.bnz g31, shade
    g.fli g31, 0.9
    g.fmul g16, g16, g31
    g.fadd g8, g8, g16
    g.li g31, 1
    g.add g9, g9, g31
    g.li g31, 28
    g.sltu g31, g9, g31
    g.bz g31, shade
    g.fli g31, 22.0
    g.li g27, 2
    g.sltu g27, g18, g27
    g.bz g27, far_plane
    g.fli g31, 5.6
far_plane:
    g.flt g31, g8, g31
    g.bnz g31, march
    g.jmp shade
julia:
    ; Orbit-trapped Julia set: two different journeys through complex space.
    g.fli g31, 2.1
    g.fmul g10, g5, g31
    g.fmul g11, g6, g31
    g.li g31, 4
    g.sltu g31, g4, g31
    g.bnz g31, julia_camera
    g.fli g31, 0.55
    g.fmul g10, g10, g31
    g.fmul g11, g11, g31
    g.fli g31, 0.38
    g.fadd g10, g10, g31
    g.fli g31, 0.44
    g.fadd g11, g11, g31
julia_camera:
    g.fli g31, 0.1
    g.fmul g12, g20, g31
    g.fli g31, -0.74
    g.fadd g12, g12, g31
    g.fli g31, 0.13
    g.fmul g13, g21, g31
    g.fli g31, 0.2
    g.fadd g13, g13, g31
    g.mov g9, g0
    g.fli g25, 5.0
julia_loop:
    g.fmul g14, g10, g10
    g.fmul g15, g11, g11
    g.fmul g11, g10, g11
    g.fadd g11, g11, g11
    g.fadd g11, g11, g13
    g.fsub g10, g14, g15
    g.fadd g10, g10, g12
    g.fadd g16, g14, g15
    g.fmin g25, g25, g16
    g.li g31, 1
    g.add g9, g9, g31
    g.li g31, 48
    g.sltu g31, g9, g31
    g.bz g31, julia_color
    g.fli g31, 16.0
    g.flt g31, g16, g31
    g.bnz g31, julia_loop
julia_color:
    g.itof g8, g9
    g.fli g31, 0.7
    g.fmul g8, g8, g31
    g.fli g31, 2.0
    g.fmul g25, g25, g31
    g.fadd g25, g25, g30
    g.fdiv g25, g30, g25
    g.fli g31, 2.5
    g.fmul g25, g25, g31
    g.mov g11, g0
    g.fli g16, 1.0
shade:
    ; Metallic spectral bands, edge glow and depth attenuation.
    g.fli g31, 0.13
    g.fmul g19, g8, g31
    g.fli g31, 0.07
    g.fmul g17, g3, g31
    g.fadd g19, g19, g17
    g.fli g31, 0.35
    g.fmul g17, g11, g31
    g.fadd g19, g19, g17
g.fli g31, 128.0
    g.fadd g19, g19, g31

g.ftoi g28, g19
g.itof g28, g28
g.fsub g22, g19, g28
g.fadd g22, g22, g22
g.fsub g22, g22, g30
g.fsub g29, g0, g22
g.fmax g29, g22, g29
g.fsub g29, g30, g29
g.fmul g22, g22, g29
g.fli g28, 4.0
g.fmul g22, g22, g28

g.fli g31, 0.3333333
g.fadd g19, g19, g31

g.ftoi g28, g19
g.itof g28, g28
g.fsub g23, g19, g28
g.fadd g23, g23, g23
g.fsub g23, g23, g30
g.fsub g29, g0, g23
g.fmax g29, g23, g29
g.fsub g29, g30, g29
g.fmul g23, g23, g29
g.fli g28, 4.0
g.fmul g23, g23, g28

g.fli g31, 0.3333333
g.fadd g19, g19, g31

g.ftoi g28, g19
g.itof g28, g28
g.fsub g24, g19, g28
g.fadd g24, g24, g24
g.fsub g24, g24, g30
g.fsub g29, g0, g24
g.fmax g29, g24, g29
g.fsub g29, g30, g29
g.fmul g24, g24, g29
g.fli g28, 4.0
g.fmul g24, g24, g28

g.fli g31, 0.5
    g.vscale g22, g22, g31
    g.fadd g22, g22, g31
    g.fadd g23, g23, g31
    g.fadd g24, g24, g31
    g.fli g31, 0.3
    g.fmul g25, g25, g31
    g.mov g27, g0
    g.fli g31, 0.015
    g.flt g31, g16, g31
    g.bz g31, lit
    g.bnz g18, normal
    ; Analytic torus normal supplies highlights across the actual surface.
    g.fmul g13, g10, g10
    g.fmul g14, g12, g12
    g.fadd g13, g13, g14
    g.sqrt g13, g13
    g.fli g31, 1.1
    g.fdiv g13, g31, g13
    g.fsub g13, g30, g13
    g.fmul g10, g10, g13
    g.fmul g12, g12, g13
normal:
    g.norm3 g10, g10
    g.fli g13, 0.4
    g.fli g14, 0.7
    g.fli g15, -0.6
    g.dot3 g26, g10, g13
    g.fmax g26, g26, g0
    g.fli g31, 0.22
    g.fadd g26, g26, g31
    g.fadd g25, g25, g26
    g.fli g14, 0.4
    g.fli g15, -0.82
    g.dot3 g27, g10, g13
    g.fmax g27, g27, g0
    g.fmul g27, g27, g27
    g.fmul g27, g27, g27
    g.fmul g27, g27, g27
    g.fmul g27, g27, g27
lit:
    g.vscale g22, g22, g25
    g.fadd g22, g22, g27
    g.fadd g23, g23, g27
    g.fadd g24, g24, g27
    ; Deep blue ambience and a sparse, deterministic star field.
    g.fli g31, 0.012
    g.fadd g22, g22, g31
    g.fli g31, 0.018
    g.fadd g23, g23, g31
    g.fli g31, 0.04
    g.fadd g24, g24, g31
    g.id g26, 2
    g.li g31, 0x45d9f3b
    g.mul g26, g26, g31
    g.li g31, 13
    g.shr g27, g26, g31
    g.xor g26, g26, g27
    g.li g31, 2047
    g.and g26, g26, g31
    g.bnz g26, pulse
    g.fli g31, 0.3
    g.fadd g22, g22, g31
    g.fadd g23, g23, g31
    g.fadd g24, g24, g31
pulse:
    ; Beat pulse with a smooth falloff.
    g.ftoi g17, g3
    g.itof g17, g17
    g.fsub g17, g3, g17
    g.fsub g17, g30, g17
    g.fmul g17, g17, g17
    g.fli g31, 0.3
    g.fmul g17, g17, g31
    g.fli g31, 0.8
    g.fadd g17, g17, g31
    g.vscale g22, g22, g17
    ; Fade every chapter across a short black splice.
    g.fli g31, 0.0625
    g.fmul g17, g3, g31
    g.ftoi g26, g17
    g.itof g26, g26
    g.fsub g17, g17, g26
    g.fsub g26, g30, g17
    g.fmin g17, g17, g26
    g.fli g31, 24.0
    g.fmul g17, g17, g31
    g.fmin g17, g17, g30
    g.vscale g22, g22, g17
    ; ASTRA logotype, packed 25 by 5 bitmap, fourfold scale.
    g.fli g31, 6.0
    g.flt g26, g3, g31
    g.fli g31, 122.0
    g.flt g31, g31, g3
    g.or g31, g31, g26
    g.bz g31, bars
    g.li g31, 30
    g.sub g26, g1, g31
    g.li g31, 100
    g.sltu g31, g26, g31
    g.bz g31, bars
    g.li g31, 48
    g.sub g27, g2, g31
    g.li g31, 20
    g.sltu g31, g27, g31
    g.bz g31, bars
    g.li g31, 2
    g.shr g26, g26, g31
    g.shr g27, g27, g31
    g.shl g27, g27, g31
    g.li g31, logo
    g.add g27, g27, g31
    g.ld g27, g27, 1
    g.shr g27, g27, g26
    g.li g31, 1
    g.and g27, g27, g31
    g.bz g27, bars
    g.fli g22, 0.9
    g.fli g23, 0.96
    g.fli g24, 1.0
bars:
    g.li g31, 9
    g.sltu g26, g2, g31
    g.li g31, 111
    g.sltu g27, g2, g31
    g.bz g27, black
    g.bz g26, pixel
black:
    g.mov g22, g0
    g.mov g23, g0
    g.mov g24, g0
pixel:
    g.id g31, 2
    g.rgb g22, g31, 0
    g.end
visual_end:

; ---------- Music kernel ----------
; 128 BPM / sixteenth = 5625 samples. Each invocation produces one stereo frame.
music:
    g.fli g30, 1.0
    g.id g1, 2
    g.uniform g2, 14
    g.add g2, g2, g1
    g.itof g3, g2
    g.fli g31, 0.0001777777778
    g.fmul g3, g3, g31
    g.ftoi g4, g3
    g.itof g5, g4
    g.fsub g5, g3, g5
    g.fli g31, 0.1171875
    g.fmul g6, g5, g31
    ; Bar/chord address, one of four minor-key harmony changes.
    g.li g31, 4
    g.shr g7, g4, g31
    g.li g31, 3
    g.and g7, g7, g31
    g.li g31, 2
    g.shl g8, g7, g31
    g.li g31, roots
    g.add g8, g8, g31
    g.ld g8, g8, 1
    ; Plucked bass, continuous decay within eighth notes.
    g.fli g31, 0.5
    g.fmul g9, g3, g31
    g.ftoi g10, g9
    g.itof g10, g10
    g.fsub g9, g9, g10
    g.fli g31, 0.234375
    g.fmul g19, g9, g31
    g.fmul g19, g19, g8

g.ftoi g28, g19
g.itof g28, g28
g.fsub g11, g19, g28
g.fadd g11, g11, g11
g.fsub g11, g11, g30
g.fsub g29, g0, g11
g.fmax g29, g11, g29
g.fsub g29, g30, g29
g.fmul g11, g11, g29
g.fli g28, 4.0
g.fmul g11, g11, g28

g.fadd g29, g29, g29
    g.fsub g29, g29, g30
    g.fli g31, 0.18
    g.fmul g29, g29, g31
    g.fadd g11, g11, g29
    g.fsub g10, g30, g9
    g.fmul g10, g10, g10
    g.fli g31, 0.22
    g.fmul g10, g10, g31
    g.fmul g11, g11, g10
    ; Sixteenth arpeggio with stereo detuning.
    g.li g31, 2
    g.shl g7, g7, g31
    g.li g31, 3
    g.and g12, g4, g31
    g.li g31, 32
    g.and g26, g4, g31
    g.bz g26, arp_up
    g.li g31, 3
    g.sub g12, g31, g12
arp_up:
    g.add g12, g12, g7
    g.li g31, 2
    g.shl g12, g12, g31
    g.li g31, notes
    g.add g12, g12, g31
    g.ld g12, g12, 1
    g.fmul g19, g6, g12

g.ftoi g28, g19
g.itof g28, g28
g.fsub g13, g19, g28
g.fadd g13, g13, g13
g.fsub g13, g13, g30
g.fsub g29, g0, g13
g.fmax g29, g13, g29
g.fsub g29, g30, g29
g.fmul g13, g13, g29
g.fli g28, 4.0
g.fmul g13, g13, g28

g.fli g31, 1.006
    g.fmul g19, g19, g31

g.ftoi g28, g19
g.itof g28, g28
g.fsub g14, g19, g28
g.fadd g14, g14, g14
g.fsub g14, g14, g30
g.fsub g29, g0, g14
g.fmax g29, g14, g29
g.fsub g29, g30, g29
g.fmul g14, g14, g29
g.fli g28, 4.0
g.fmul g14, g14, g28

g.fsub g15, g30, g5
    g.fmul g15, g15, g15
    g.fmul g15, g15, g15
    g.fli g31, 0.16
    g.fmul g15, g15, g31
    g.fmul g13, g13, g15
    g.fmul g14, g14, g15
    g.fadd g22, g11, g13
    g.fadd g23, g11, g14
    ; A dotted-eighth echo of the arpeggiator, panned across the dry pair.
    g.li g31, 3
    g.sub g26, g4, g31
    g.and g27, g26, g31
    g.li g31, 2
    g.shr g26, g26, g31
    g.li g31, 12
    g.and g26, g26, g31
    g.add g26, g26, g27
    g.li g31, 2
    g.shl g26, g26, g31
    g.li g31, notes
    g.add g26, g26, g31
    g.ld g26, g26, 1
    g.fmul g19, g6, g26

g.ftoi g28, g19
g.itof g28, g28
g.fsub g26, g19, g28
g.fadd g26, g26, g26
g.fsub g26, g26, g30
g.fsub g29, g0, g26
g.fmax g29, g26, g29
g.fsub g29, g30, g29
g.fmul g26, g26, g29
g.fli g28, 4.0
g.fmul g26, g26, g28

g.fli g31, 0.35
    g.fmul g26, g26, g15
    g.fmul g26, g26, g31
    g.fadd g23, g23, g26
    g.fli g31, 0.4
    g.fmul g26, g26, g31
    g.fadd g22, g22, g26
    ; Airy sustained fifth, slowly breathing across each chord.
    g.fli g31, 0.0625
    g.fmul g16, g3, g31
    g.ftoi g17, g16
    g.itof g17, g17
    g.fsub g16, g16, g17
    g.fli g31, 1.875
    g.fmul g19, g16, g31
    g.fmul g19, g19, g8
    g.fli g31, 5.9932283
    g.fmul g19, g19, g31

g.ftoi g28, g19
g.itof g28, g28
g.fsub g17, g19, g28
g.fadd g17, g17, g17
g.fsub g17, g17, g30
g.fsub g29, g0, g17
g.fmax g29, g17, g29
g.fsub g29, g30, g29
g.fmul g17, g17, g29
g.fli g28, 4.0
g.fmul g17, g17, g28

g.fsub g18, g30, g16
    g.fmul g18, g18, g16
    g.fli g31, 0.35
    g.fmul g18, g18, g31
    g.fmul g17, g17, g18
    g.fadd g22, g22, g17
    g.fadd g23, g23, g17
    ; Four-on-the-floor kick: downward chirp, fourth-power envelope.
    g.fli g31, 0.25
    g.fmul g16, g3, g31
    g.ftoi g17, g16
    g.itof g17, g17
    g.fsub g16, g16, g17
    g.fli g31, 12.0
    g.fmul g19, g16, g31
    g.fadd g19, g19, g30
    g.fdiv g19, g30, g19
    g.fli g31, 4.0
    g.fmul g19, g19, g31
    g.fli g31, 25.0
    g.fmul g17, g16, g31
    g.fsub g19, g17, g19
    g.fli g31, 5.0
    g.fadd g19, g19, g31

g.ftoi g28, g19
g.itof g28, g28
g.fsub g17, g19, g28
g.fadd g17, g17, g17
g.fsub g17, g17, g30
g.fsub g29, g0, g17
g.fmax g29, g17, g29
g.fsub g29, g30, g29
g.fmul g17, g17, g29
g.fli g28, 4.0
g.fmul g17, g17, g28

g.fsub g18, g30, g16
    g.fmul g18, g18, g18
    g.fmul g18, g18, g18
    g.fmul g18, g18, g18
    g.fli g31, 0.52
    g.fmul g18, g18, g31
    g.fmul g17, g17, g18
    ; Deterministic bipolar noise, closed hats and backbeat snare.
    g.li g31, 0x45d9f3b
    g.mul g24, g2, g31
    g.li g31, 13
    g.shr g25, g24, g31
    g.xor g24, g24, g25
    g.li g31, 0x45d9f3b
    g.mul g24, g24, g31
    g.li g31, 65535
    g.and g24, g24, g31
    g.itof g24, g24
    g.fli g31, 0.0000305180438
    g.fmul g24, g24, g31
    g.fsub g24, g24, g30
    g.fsub g25, g30, g5
    g.fmul g25, g25, g25
    g.fmul g25, g25, g25
    g.fmul g25, g25, g25
    g.fli g31, 0.045
    g.fmul g25, g25, g31
    g.li g31, 4
    g.and g26, g4, g31
    g.bz g26, drums
    g.fsub g26, g30, g16
    g.fmul g26, g26, g26
    g.fmul g26, g26, g26
    g.fli g31, 0.19
    g.fmul g26, g26, g31
    g.fadd g25, g25, g26
drums:
    g.fmul g24, g24, g25
    g.fadd g17, g17, g24
    ; Sparse opening and mid-piece breakdown.
    g.li g31, 6
    g.shr g26, g4, g31
    g.li g31, 7
    g.and g26, g26, g31
    g.bz g26, master
    g.li g31, 4
    g.sub g26, g26, g31
    g.bz g26, master
    g.fadd g22, g22, g17
    g.fadd g23, g23, g17
master:
    ; Symmetric soft saturation keeps transients within output headroom.
    g.fmul g24, g22, g22
    g.fadd g24, g24, g30
    g.fdiv g22, g22, g24
    g.fmul g24, g23, g23
    g.fadd g24, g24, g30
    g.fdiv g23, g23, g24
    g.li g31, 3
    g.shl g1, g1, g31
    g.st g22, g1, 0
    g.li g31, 4
    g.add g1, g1, g31
    g.st g23, g1, 0
    g.end
music_end:
roots:
    .float 55.0, 43.653529, 65.406391, 48.999429
notes:
    .float 440.0, 523.25113, 659.25511, 880.0
    .float 349.22823, 440.0, 523.25113, 659.25511
    .float 523.25113, 659.25511, 783.99087, 1046.5023
    .float 391.99544, 493.88330, 587.32954, 783.99087
logo:

.word 0x63bde6

.word 0x949829

.word 0xf398cf

.word 0x929909

.word 0x9498e9

rom_end:
