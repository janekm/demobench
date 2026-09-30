; ============================================================================
;  PELICAN ON A BICYCLE - a ray-traced beach ride, with a synthesised score
;  DB32 dynamic-1 cartridge.  Everything (animation, ray tracing, synth) is
;  guest code: CPU driver + GPU kernels (scene, tracer) + SPU kernel (music).
; ============================================================================
.profile dynamic-1
.equ FB0, 0x10000
.equ FB1, 0x1e100
.equ IMG, 0x2c200
.equ SCENE, 0x2ea00
.equ SCENE_SIZE, 0xc30
.equ AUDIO, 0x2f800
.equ IMGLEN, 0x2800
.equ GPU, 0xf3000
.equ VID, 0xf5000
.equ SYS, 0xf0000
.equ SPU, 0xf6000
.equ OFF_CAM, 1088
.equ OFF_BIKE, 128
.equ OFF_PTS, 64
.equ OFF_CAPS, 1152
.equ LEAD, 3

; ---- macros -------------------------------------------------------------
; load one word: d = mem[n][off]
; store one word
; load 3 consecutive words; tmp holds byte address; needs g31 = 4
; d = sin(a): parabola (sinq) + one refinement step (sinp).  a > -6000 rad.
; d = 2^a for -30 < a < 30 (cubic on the fraction, exponent by integer bits)
; d = sin(2*pi*a), a in cycles (> -1000), with one refinement step
; ---- CPU driver ------------------------------------------------------------
;  r13 = 0xf0000 : system page; GPU at +0x3000, video +0x5000, SPU +0x6000
;  r3 = 1 and r4 = 3 stay constant (flags); r11/r12 = grid size for dispatch
.entry start
start:
    li r13, 0xf0000
    li r1, IMG
    ori r2, r0, IMGLEN
    ori r3, r0, 1
    ori r4, r0, 3
    sw r1, 0x3050(r13)             ; GPU binding 1: tables (ro)
    sw r2, 0x3054(r13)
    sw r3, 0x3058(r13)
    li r5, AUDIO
    ori r6, r0, 2048
    sw r1, 0x6110(r13)             ; SPU binding 1: tables (ro)
    sw r2, 0x6114(r13)
    sw r3, 0x6118(r13)
    sw r5, 0x6100(r13)             ; SPU binding 0: audio block (rw)
    sw r6, 0x6104(r13)
    sw r4, 0x6108(r13)
    sw r5, 0x6050(r13)
    li r7, k_spu
    sw r7, 0x6040(r13)
    ori r7, r0, k_spu_end-k_spu
    sw r7, 0x6044(r13)
    ori r7, r0, 128
    sw r7, 0x6048(r13)
    ori r7, r0, 2
    sw r7, 0x604c(r13)
    sw r3, 0x6000(r13)             ; the score starts
    ori r7, r0, 480                ; video: RGB888 (FB0 shows black until frame 1)
    sw r7, 0x5004(r13)
    ori r7, r0, 4
    sw r7, 0x5008(r13)
    sw r3, 0x5010(r13)
    sw r3, 0x5014(r13)
    li r10, FB1
main:
    lw r9, 16(r13)                 ; frame counter = scene time
    sw r9, 0x3100(r13)
    li r15, SCENE                  ; kernels read only read-only bindings (WebGPU rule)
    sw r15, 0x3040(r13)            ; b0 = sine block (rw)
    ori r1, r0, 64
    sw r1, 0x3044(r13)
    sw r4, 0x3048(r13)
    li r1, k_params                ; clock
    ori r2, r0, k_params_end-k_params
    ori r11, r0, 1
    ori r12, r0, 1
    jal r14, dispatch
    sw r3, 0x3048(r13)             ; b0 read-only
    addi r6, r15, 64
    ori r7, r0, 1088
    sw r6, 0x3060(r13)             ; b2 = skeleton + camera (rw)
    sw r7, 0x3064(r13)
    sw r4, 0x3068(r13)
    li r1, k_points                ; skeleton + camera
    ori r2, r0, k_points_end-k_points
    ori r11, r0, N_PTS+1
    jal r14, dispatch
    sw r6, 0x3040(r13)             ; b0 = skeleton (ro)
    sw r7, 0x3044(r13)
    addi r1, r15, 1152
    sw r1, 0x3060(r13)             ; b2 = capsule records (rw)
    ori r1, r0, 1960
    sw r1, 0x3064(r13)
    li r1, k_caps
    ori r2, r0, k_caps_end-k_caps
    ori r11, r0, N_CAPS
    jal r14, dispatch
    sw r15, 0x3040(r13)            ; render: whole scene read-only
    ori r1, r0, SCENE_SIZE
    sw r1, 0x3044(r13)
    sw r10, 0x3060(r13)            ; b2 = framebuffer (rw)
    ori r1, r0, 57600
    sw r1, 0x3064(r13)
    ori r7, r0, 0
    ori r8, r0, 300
    li r1, k_render
    ori r2, r0, k_render_end-k_render
    ori r11, r0, 160
    ori r12, r0, 60
slice:                             ; 2 dispatches x 150 tiles of 8x8 pixels
    sw r7, 0x3104(r13)
    jal r14, dispatch
    addi r7, r7, 150
    bne r7, r8, slice
    sw r10, 0x5000(r13)            ; present the finished buffer
    sw r3, 0x5014(r13)
    wfi                            ; one picture per video frame (paces WebGPU too)
    li r1, FB0+FB1
    sub r10, r1, r10
    j main

dispatch:                          ; r1 kernel, r11/r12 grid; blocks until done
    sw r1, 0x3000(r13)
    sw r2, 0x3004(r13)
    sw r11, 0x3008(r13)
    sw r12, 0x300c(r13)
    sw r3, 0x3010(r13)
dwait:
    lw r5, 0x3014(r13)
    beq r5, r3, dwait
    jalr r0, 0(r14)
; ============================================================================
;  K0  animation clock.   grid 1x1.  b0 = A: sine block (rw), b1 = IMG (ro)
;  Evaluates a table of modulated sinusoids (own polynomial sine) into
;  the sine block (write-only: WebGPU cannot read writable bindings).
; ============================================================================
k_params:
    g.li g31, 4
    g.li g25, 24
    g.li g26, 8
    g.li g27, 255
    g.mov g20, g0
    g.uniform g1, 0
    g.itof g1, g1
    g.fli g2, 0.0166667
    g.fmul g1, g1, g2              ; t (seconds)
    g.li g2, sin_tab-IMG
    g.li g3, 0
    g.li g4, 60
    g.fli g21, 0.0245436926
    g.fli g22, 0.0625
lp_sin:
    g.ld g5, g2, 1
    g.shl g8, g5, g25
    g.sar g8, g8, g25
    g.itof g8, g8
    g.fmul g8, g8, g22             ; A
    g.fmul g8, g8, g1
    g.shr g6, g5, g26
    g.and g6, g6, g27
    g.itof g6, g6
    g.fmul g6, g6, g21             ; B
    g.fadd g8, g8, g6
    g.shl g10, g5, g26
    g.sar g10, g10, g25
    g.itof g10, g10
    g.fmul g10, g10, g22           ; C
    g.fmul g6, g20, g10
    g.fadd g8, g8, g6
    g.fli g9, 0.15915494
    g.fmul g8, g8, g9
    g.fli g9, 1000.5
    g.fadd g8, g8, g9
    g.ftoi g9, g8
    g.itof g9, g9
    g.fsub g8, g8, g9
    g.fli g9, 0.5
    g.fsub g8, g8, g9
    g.fsub g9, g0, g8
    g.fmax g9, g9, g8
    g.fli g6, -16.0
    g.fmul g9, g9, g6
    g.fli g6, 8.0
    g.fadd g9, g9, g6
    g.fmul g8, g8, g9
    g.fsub g9, g0, g8
    g.fmax g9, g9, g8
    g.fli g6, 0.225
    g.fmul g9, g9, g6
    g.fli g6, 0.775
    g.fadd g9, g9, g6
    g.fmul g8, g8, g9
    g.st g8, g3, 0
    g.bnz g10, lp_nl
    g.mov g20, g8
lp_nl:
    g.add g2, g2, g31
    g.add g3, g3, g31
    g.sltu g7, g3, g4
    g.bnz g7, lp_sin
    g.end
k_params_end:

; ============================================================================
;  K1  skeleton: one lane per joint -> world position.
;  joint word: x y z (signed, 2 cm) + class (0 rigid, 1 crank, 2/3 wheels, 4 knee)
; ============================================================================
k_points:
    g.li g31, 4
    g.li g5, 24
    g.li g8, 16
    g.li g9, 8
    g.id g1, 2
    g.li g3, 2
    g.shl g2, g1, g3
    g.li g3, pt_tab-IMG
    g.add g2, g2, g3
    g.ld g4, g2, 1
    g.li g30, 0
    g.ld g20, g30, 0
    g.li g30, 4
    g.ld g21, g30, 0
    g.li g2, N_PTS
    g.sub g2, g1, g2
    g.bz g2, pt_cam
    g.fli g22, 4.25
    g.fmul g23, g21, g22
    g.fsub g23, g0, g23           ; bike z on its circle
    g.fmul g22, g20, g22           ; bike x
    g.shr g6, g4, g5               ; class
    g.shl g10, g4, g5
    g.sar g10, g10, g5
    g.itof g10, g10
    g.shl g11, g4, g8
    g.sar g11, g11, g5
    g.itof g11, g11
    g.shl g12, g4, g9
    g.sar g12, g12, g5
    g.itof g12, g12
    g.fli g13, 0.02
    g.fmul g10, g10, g13
    g.fmul g11, g11, g13
    g.fmul g12, g12, g13
    g.shl g13, g6, g31
    g.li g14, piv_tab-IMG
    g.add g13, g13, g14
    g.ld g14, g13, 1               ; pivot x
    g.add g13, g13, g31
    g.ld g15, g13, 1               ; pivot y
    g.add g13, g13, g31
    g.ld g16, g13, 1               ; sine slot
    g.ld g17, g16, 0
    g.add g16, g16, g31
    g.ld g18, g16, 0
    g.fmul g24, g10, g18
    g.fmul g25, g11, g17
    g.fsub g24, g24, g25
    g.fmul g25, g10, g17
    g.fmul g26, g11, g18
    g.fadd g25, g25, g26
    g.fadd g10, g24, g14           ; x'
    g.fadd g28, g25, g15           ; y' (world y)
    g.fmul g24, g10, g21
    g.fmul g25, g12, g20
    g.fsub g24, g24, g25
    g.fadd g27, g24, g22           ; world x
    g.fmul g25, g10, g20
    g.fmul g26, g12, g21
    g.fadd g25, g25, g26
    g.fadd g29, g25, g23           ; world z
    g.add g13, g13, g31
    g.ld g13, g13, 1               ; scenery: z offset of the world-space class
    g.bz g13, pt_store
    g.mov g27, g10
    g.fadd g29, g12, g13
pt_store:
    g.shl g8, g1, g31
    g.st g27, g8, 2
    g.add g8, g8, g31
    g.st g28, g8, 2
    g.add g8, g8, g31
    g.st g29, g8, 2
    g.end
pt_cam:
    g.mov g10, g20
    g.mov g11, g21
    g.li g30, 0
    g.ld g10, g30, 0
    g.li g30, 4
    g.ld g11, g30, 0
    g.li g30, 28
    g.ld g12, g30, 0
    g.li g30, 32
    g.ld g13, g30, 0
    g.li g30, 40
    g.ld g14, g30, 0
    g.li g30, 44
    g.ld g15, g30, 0
    g.li g30, 48
    g.ld g16, g30, 0
    g.fli g2, 4.25
    g.fmul g20, g10, g2
    g.fmul g22, g11, g2
    g.fsub g22, g0, g22
    g.mov g21, g0
    g.fli g21, 0.95                ; camera target
    g.fli g2, 2.5
    g.fmul g3, g16, g2
    g.fli g2, 6.5
    g.fadd g3, g3, g2              ; distance
    g.fmul g4, g3, g15
    g.fmul g5, g3, g14
    g.fmul g25, g4, g12
    g.fsub g25, g20, g25
    g.fadd g26, g21, g5
    g.fli g2, 0.375
    g.fmax g26, g26, g2
    g.fmul g27, g4, g13
    g.fsub g27, g22, g27           ; camera position g25-27
    g.vsub g28, g20, g25
    g.norm3 g28, g28               ; forward g28-30
    g.fsub g4, g0, g30
    g.mov g5, g0
    g.mov g6, g28
    g.norm3 g4, g4                 ; right g4-6
    g.fmul g7, g6, g29
    g.fsub g7, g0, g7
    g.fmul g8, g6, g28
    g.fmul g2, g4, g30
    g.fsub g8, g8, g2
    g.fmul g9, g4, g29             ; up g7-9
    g.fli g3, 0.0078125            ; pixel scale (fov)
    g.vscale g4, g4, g3
    g.vscale g7, g7, g3
    g.li g1, 1024
    g.st g25, g1, 2
    g.add g1, g1, g31
    g.st g26, g1, 2
    g.add g1, g1, g31
    g.st g27, g1, 2
    g.li g1, 1040
    g.st g4, g1, 2
    g.add g1, g1, g31
    g.st g5, g1, 2
    g.add g1, g1, g31
    g.st g6, g1, 2
    g.li g1, 1056
    g.st g7, g1, 2
    g.add g1, g1, g31
    g.st g8, g1, 2
    g.add g1, g1, g31
    g.st g9, g1, 2
    g.li g1, 1072
    g.st g28, g1, 2
    g.add g1, g1, g31
    g.st g29, g1, 2
    g.add g1, g1, g31
    g.st g30, g1, 2
    g.end
k_points_end:

; ============================================================================
;  K2  capsule records for the tracer, one lane per capsule.
;  record: pa(3) ba(3) baba K=r^2*baba r^2 material   (10 words)
; ============================================================================
k_caps:
    g.li g31, 4
    g.li g5, 255
    g.li g7, 24
    g.id g1, 2
    g.li g3, 2
    g.shl g2, g1, g3
    g.li g3, cap_tab-IMG
    g.add g2, g2, g3
    g.ld g4, g2, 1
    g.and g6, g4, g5
    g.li g3, 8
    g.shr g8, g4, g3
    g.and g8, g8, g5
    g.li g3, 16
    g.shr g9, g4, g3
    g.and g9, g9, g5
    g.shr g10, g4, g7
    g.shl g6, g6, g31
    g.shl g8, g8, g31
    g.ld g11, g6, 0
    g.add g6, g6, g31
    g.ld g12, g6, 0
    g.add g6, g6, g31
    g.ld g13, g6, 0
    g.ld g14, g8, 0
    g.add g8, g8, g31
    g.ld g15, g8, 0
    g.add g8, g8, g31
    g.ld g16, g8, 0
    g.vsub g14, g14, g11
    g.dot3 g17, g14, g14
    g.fli g18, 0.00000001
    g.fadd g17, g17, g18
    g.itof g9, g9
    g.fli g18, 0.005
    g.fmul g9, g9, g18
    g.fmul g9, g9, g9
    g.fmul g18, g9, g17
    g.li g7, 40
    g.mul g7, g1, g7
    g.st g11, g7, 2
    g.add g7, g7, g31
    g.st g12, g7, 2
    g.add g7, g7, g31
    g.st g13, g7, 2
    g.add g7, g7, g31
    g.st g14, g7, 2
    g.add g7, g7, g31
    g.st g15, g7, 2
    g.add g7, g7, g31
    g.st g16, g7, 2
    g.add g7, g7, g31
    g.st g17, g7, 2
    g.add g7, g7, g31
    g.st g18, g7, 2
    g.add g7, g7, g31
    g.st g9, g7, 2
    g.add g7, g7, g31
    g.st g10, g7, 2
    g.end
k_caps_end:
; ============================================================================
;  K3  the ray tracer.  One wave = one 8x8 pixel tile (spatially coherent).
;  b0 = SCENE (ro), b1 = IMG (ro), b2 = framebuffer (rw)
;  persistent registers
;    g1-3 ray origin   g4-6 ray dir   g7-9 accumulated colour
;    g11 (pixel index<<4)|mode   g12-14 sun term awaiting the shadow result
;    g10 table ptr / weight   g15 nearest t   g16 nearest id
;    g17 record ptr   g31 = 4
; ============================================================================
; capsule intersection against record g17 (updates g15/g16)

k_render:
    g.li g31, 4
    g.id g2, 2
    g.uniform g3, 1
    g.li g4, 6
    g.shr g5, g2, g4
    g.add g5, g5, g3               ; tile index
    g.li g6, 7
    g.and g1, g2, g6               ; x inside tile
    g.li g4, 3
    g.shr g2, g2, g4
    g.and g2, g2, g6               ; y inside tile
    g.li g6, 205
    g.mul g6, g5, g6
    g.li g7, 12
    g.shr g6, g6, g7               ; tile row
    g.li g7, 20
    g.mul g7, g6, g7
    g.sub g5, g5, g7               ; tile column
    g.shl g5, g5, g4
    g.add g5, g5, g1               ; px
    g.shl g6, g6, g4
    g.add g6, g6, g2               ; py
    g.li g4, 160
    g.mul g7, g6, g4
    g.add g7, g7, g5
    g.shl g11, g7, g31             ; pixel << 4, mode 0
    g.itof g5, g5
    g.itof g6, g6
    g.fli g4, -79.5
    g.fadd g5, g5, g4
    g.fli g4, -59.5
    g.fadd g6, g6, g4
    g.li g4, OFF_CAM
    g.ld g1, g4, 0
    g.add g4, g4, g31
    g.ld g2, g4, 0
    g.add g4, g4, g31
    g.ld g3, g4, 0
    g.li g4, OFF_CAM+16
    g.ld g7, g4, 0
    g.add g4, g4, g31
    g.ld g8, g4, 0
    g.add g4, g4, g31
    g.ld g9, g4, 0
    g.vscale g7, g7, g5
    g.li g4, OFF_CAM+32
    g.ld g12, g4, 0
    g.add g4, g4, g31
    g.ld g13, g4, 0
    g.add g4, g4, g31
    g.ld g14, g4, 0
    g.vscale g12, g12, g6
    g.vsub g7, g7, g12
    g.li g12, OFF_CAM+48
    g.ld g4, g12, 0
    g.add g12, g12, g31
    g.ld g5, g12, 0
    g.add g12, g12, g31
    g.ld g6, g12, 0
    g.vadd g4, g4, g7
    g.norm3 g4, g4                 ; primary ray
    g.mov g7, g0
    g.mov g8, g0
    g.mov g9, g0
; ---------------------------------------------------------------- trace
rt_loop:
    g.fli g15, 1.0e30
    g.li g16, 0
    g.fli g18, -0.0001
    g.flt g19, g5, g18
    g.bz g19, rt_nog
    g.fsub g18, g0, g5
    g.fdiv g15, g2, g18            ; ground plane y = 0
rt_nog:
    g.li g10, cl_tab-IMG
rt_cl:
    g.ld g18, g10, 1
    g.add g30, g10, g31
    g.ld g22, g30, 1               ; bounding radius
    g.ld g19, g18, 0
    g.add g18, g18, g31
    g.ld g20, g18, 0
    g.add g18, g18, g31
    g.ld g21, g18, 0
    g.sphere g23, g1, g4, g19
    g.flt g24, g23, g0
    g.bnz g24, rt_cn
    g.add g30, g30, g31
    g.ld g17, g30, 1               ; first capsule (0 = torus)
    g.bz g17, rt_torus
rt_cap:
    g.ld g18, g17, 0
    g.add g30, g17, g31
    g.ld g19, g30, 0
    g.add g30, g30, g31
    g.ld g20, g30, 0
    g.vsub g18, g1, g18            ; oa
    g.add g30, g30, g31
    g.ld g21, g30, 0
    g.add g30, g30, g31
    g.ld g22, g30, 0
    g.add g30, g30, g31
    g.ld g23, g30, 0               ; ba
    g.dot3 g24, g21, g18           ; baoa
    g.dot3 g25, g21, g4            ; bard
    g.dot3 g26, g4, g18            ; rdoa
    g.dot3 g27, g18, g18           ; oaoa
    g.add g30, g30, g31
    g.ld g28, g30, 0               ; baba
    g.add g30, g30, g31
    g.ld g29, g30, 0               ; K
    g.fmul g27, g28, g27
    g.fsub g27, g27, g29
    g.fmul g29, g24, g24
    g.fsub g27, g27, g29           ; c
    g.fmul g26, g28, g26
    g.fmul g29, g24, g25
    g.fsub g26, g26, g29           ; b
    g.fmul g30, g25, g25
    g.fsub g30, g28, g30
    g.fli g29, 0.000000001
    g.fmax g30, g30, g29           ; a
    g.fmul g29, g26, g26
    g.fmul g27, g30, g27
    g.fsub g29, g29, g27           ; h
    g.flt g27, g29, g0
    g.bnz g27, cn_26
    g.sqrt g29, g29
    g.fsub g26, g0, g26
    g.fsub g29, g26, g29
    g.fdiv g29, g29, g30           ; t
    g.fmul g27, g29, g25
    g.fadd g27, g24, g27           ; y
    g.flt g26, g0, g27
    g.flt g30, g27, g28
    g.and g26, g26, g30
    g.bnz g26, cd_26
    g.flt g26, g0, g27
    g.itof g26, g26
    g.vscale g21, g21, g26
    g.vsub g18, g18, g21           ; oc
    g.li g30, 32
    g.add g30, g17, g30
    g.ld g25, g30, 0               ; r^2
    g.dot3 g24, g4, g18
    g.dot3 g27, g18, g18
    g.fsub g27, g27, g25
    g.fmul g26, g24, g24
    g.fsub g26, g26, g27
    g.flt g27, g0, g26
    g.bz g27, cn_26
    g.sqrt g26, g26
    g.fsub g29, g0, g24
    g.fsub g29, g29, g26
cd_26:
    g.sltu g27, g29, g15
    g.bz g27, cn_26
    g.mov g15, g29
    g.mov g16, g17
cn_26:
    g.li g18, 40
    g.add g17, g17, g18
    g.li g18, 12
    g.add g18, g10, g18
    g.ld g18, g18, 1
    g.sltu g18, g17, g18
    g.bnz g18, rt_cap
rt_cn:
    g.li g18, 16
    g.add g10, g10, g18
    g.li g18, cl_end-IMG
    g.sltu g18, g10, g18
    g.bnz g18, rt_cl
    g.li g18, 3
    g.and g19, g11, g18
    g.bnz g19, rt_shadow
    g.fli g18, 1.0e29
    g.flt g19, g15, g18
    g.bnz g19, rt_hit
    g.fli g10, 1.0
; ---------------------------------------------------------------- sky
rt_sky:
    g.fli g18, 0.6875
    g.fli g19, 0.3125
    g.fli g20, 0.65625
    g.dot3 g21, g4, g18
    g.fmax g21, g21, g0            ; sun alignment
    g.fmax g22, g5, g0
    g.sqrt g22, g22
    g.fli g12, -0.875
    g.fmul g12, g12, g22
    g.fli g23, 1.0
    g.fadd g12, g12, g23
    g.fli g13, -0.375
    g.fmul g13, g13, g22
    g.fli g23, 0.75
    g.fadd g13, g13, g23
    g.fli g14, 0.375
    g.fmul g14, g14, g22
    g.fli g23, 0.5
    g.fadd g14, g14, g23           ; horizon -> zenith gradient
    g.fmul g23, g21, g21
    g.fmul g23, g23, g23
    g.fmul g23, g23, g23           ; glow ^8
    g.fli g26, 0.9997
    g.flt g26, g26, g21
    g.itof g26, g26
    g.fli g24, 4.0
    g.fmul g26, g26, g24
    g.fadd g23, g23, g26           ; + sun disc
    g.fli g25, 1.0
    g.fmul g25, g25, g23
    g.fadd g12, g12, g25
    g.fli g25, 0.5
    g.fmul g25, g25, g23
    g.fadd g13, g13, g25
    g.fli g25, 0.25
    g.fmul g25, g25, g23
    g.fadd g14, g14, g25
    g.vscale g12, g12, g10
    g.vadd g7, g7, g12
    g.jmp rt_finish
; ---------------------------------------------------------------- shadow result
rt_shadow:
    g.fli g18, 1.0e29
    g.flt g19, g15, g18
    g.itof g19, g19
    g.fli g18, 1.0
    g.fsub g19, g18, g19
    g.vscale g12, g12, g19
    g.fli g18, 1.75
    g.fmul g12, g12, g18
    g.fli g18, 1.25
    g.fmul g13, g13, g18
    g.fli g18, 0.75
    g.fmul g14, g14, g18
    g.vadd g7, g7, g12
; ---------------------------------------------------------------- output
rt_finish:
    g.fmax g7, g7, g0
    g.sqrt g7, g7
    g.fmax g8, g8, g0
    g.sqrt g8, g8
    g.fmax g9, g9, g0
    g.sqrt g9, g9
    g.shr g19, g11, g31
    g.rgb g7, g19, 2
    g.end
; ---------------------------------------------------------------- torus (tyre)
rt_torus:
    g.fli g24, 1.0
    g.fadd g24, g23, g24           ; march limit
    g.ld g26, g0, 0
    g.ld g25, g31, 0               ; sin / cos of the bike heading
    g.li g17, 40
rt_tl:
    g.vscale g27, g4, g23
    g.vadd g27, g27, g1
    g.vsub g27, g27, g19
    g.fmul g30, g27, g25
    g.fmul g22, g29, g26
    g.fadd g30, g30, g22           ; u
    g.fmul g22, g27, g26
    g.fmul g27, g29, g25
    g.fsub g27, g27, g22           ; lateral
    g.fmul g22, g30, g30
    g.fmul g29, g28, g28
    g.fadd g22, g22, g29
    g.sqrt g22, g22
    g.fli g29, 0.34375
    g.fsub g22, g22, g29
    g.fmul g22, g22, g22
    g.fmul g27, g27, g27
    g.fadd g22, g22, g27
    g.sqrt g22, g22
    g.fli g29, 0.0625
    g.fsub g22, g22, g29           ; distance to tyre
    g.fli g29, 0.00390625
    g.flt g27, g22, g29
    g.bnz g27, rt_th
    g.fadd g23, g23, g22
    g.flt g27, g24, g23
    g.bnz g27, rt_cn
    g.li g27, 1
    g.sub g17, g17, g27
    g.bnz g17, rt_tl
    g.jmp rt_cn
rt_th:
    g.sltu g27, g23, g15
    g.bz g27, rt_cn
    g.mov g15, g23
    g.li g30, 12
    g.add g30, g30, g10
    g.ld g16, g30, 1
    g.jmp rt_cn
; ---------------------------------------------------------------- surface hit
rt_hit:
    g.vscale g18, g4, g15
    g.vadd g18, g18, g1            ; hit point g18-20
    g.bz g16, rt_ground
    g.li g21, 8
    g.sltu g21, g16, g21
    g.bnz g21, rt_wheel
    g.mov g30, g16
    g.ld g21, g30, 0
    g.add g30, g30, g31
    g.ld g22, g30, 0
    g.add g30, g30, g31
    g.ld g23, g30, 0
    g.add g30, g30, g31
    g.ld g24, g30, 0
    g.add g30, g30, g31
    g.ld g25, g30, 0
    g.add g30, g30, g31
    g.ld g26, g30, 0
    g.add g30, g30, g31
    g.ld g27, g30, 0               ; baba
    g.li g28, 36
    g.add g28, g28, g16
    g.ld g29, g28, 0               ; material
    g.vsub g21, g18, g21
    g.dot3 g28, g21, g24
    g.fdiv g28, g28, g27
    g.fmax g28, g28, g0
    g.fli g30, 1.0
    g.fmin g28, g28, g30
    g.vscale g24, g24, g28
    g.vsub g21, g21, g24
    g.norm3 g21, g21               ; surface normal g21-23
    g.li g30, 4
    g.shl g29, g29, g30
    g.li g30, mat_tab-IMG
    g.add g29, g29, g30
    g.jmp rt_mat
rt_wheel:
    g.shl g21, g16, g31
    g.li g30, OFF_PTS-16
    g.add g21, g21, g30
    g.ld g24, g21, 0
    g.add g21, g21, g31
    g.ld g25, g21, 0
    g.add g21, g21, g31
    g.ld g26, g21, 0
    g.vsub g21, g18, g24
    g.norm3 g21, g21               ; tyre normal (radial approximation)
    g.li g29, mat_tab-IMG+16
rt_mat:
    g.ld g24, g29, 1
    g.add g29, g29, g31
    g.ld g25, g29, 1
    g.add g29, g29, g31
    g.ld g26, g29, 1
    g.add g29, g29, g31
    g.ld g27, g29, 1               ; gloss
    g.jmp rt_lit
; ---- sand: ripples, grain, the bike's track, wet sand near the sea
rt_ground:
    g.fli g21, 9.0
    g.flt g21, g21, g20
    g.bnz g21, rt_water
    g.fli g21, 2.875
    g.fmul g21, g18, g21
    g.fli g22, 1.75
    g.fmul g22, g20, g22
    g.fadd g21, g21, g22
    g.fli g22, 0.15915494
    g.fmul g21, g21, g22
    g.fli g22, 1000.5
    g.fadd g21, g21, g22
    g.ftoi g22, g21
    g.itof g22, g22
    g.fsub g21, g21, g22
    g.fli g22, 0.5
    g.fsub g21, g21, g22
    g.fsub g22, g0, g21
    g.fmax g22, g22, g21
    g.fli g23, -16.0
    g.fmul g22, g22, g23
    g.fli g23, 8.0
    g.fadd g22, g22, g23
    g.fmul g21, g21, g22
    g.fli g23, 0.0625
    g.fmul g21, g21, g23
    g.fli g23, 0.9375
    g.fadd g21, g21, g23           ; brightness
    g.dot3 g22, g18, g18
    g.sqrt g22, g22
    g.fli g23, 4.25
    g.fsub g22, g22, g23
    g.fsub g23, g0, g22
    g.fmax g22, g22, g23
    g.fli g23, 8.0
    g.fmul g22, g22, g23
    g.fli g23, 1.0
    g.fsub g22, g23, g22
    g.fmax g22, g22, g0
    g.fli g23, -0.3125
    g.fmul g22, g22, g23
    g.fli g23, 1.0
    g.fadd g22, g22, g23
    g.fmul g21, g21, g22           ; wheel track
    g.fli g22, -7.25
    g.fadd g22, g20, g22
    g.fli g23, 0.5
    g.fmul g22, g22, g23
    g.fmax g22, g22, g0
    g.fli g23, 1.0
    g.fmin g22, g22, g23
    g.fli g23, -0.34375
    g.fmul g22, g22, g23
    g.fli g23, 1.0
    g.fadd g22, g22, g23
    g.fmul g21, g21, g22           ; wet sand
    g.fli g24, 0.875
    g.fmul g24, g24, g21
    g.fli g25, 0.75
    g.fmul g25, g25, g21
    g.fli g26, 0.5
    g.fmul g26, g26, g21
    g.mov g21, g0
    g.fli g22, 1.0
    g.mov g23, g0
    g.mov g27, g0
; ---------------------------------------------------------------- lighting
;  p g18-20  n g21-23  albedo g24-26  gloss g27  rd g4-6  t g15
rt_lit:
    g.fli g28, 0.6875
    g.fli g29, 0.3125
    g.fli g30, 0.65625
    g.dot3 g12, g21, g28
    g.fmax g12, g12, g0            ; n.l
    g.vsub g4, g28, g4
    g.norm3 g4, g4
    g.dot3 g13, g21, g4
    g.fmax g13, g13, g0
    g.fmul g13, g13, g13
    g.fmul g13, g13, g13
    g.fmul g13, g13, g13
    g.fmul g13, g13, g13
    g.fmul g13, g13, g13           ; (n.h)^32
    g.fmul g13, g13, g27           ; specular
    g.fli g14, 0.5
    g.fmul g4, g22, g14
    g.fadd g14, g4, g14            ; hemisphere blend
    g.fli g4, -0.03125
    g.fli g5, 0.125
    g.fli g6, 0.34375
    g.vscale g4, g4, g14
    g.fli g28, 0.34375
    g.fadd g4, g4, g28
    g.fli g28, 0.25
    g.fadd g5, g5, g28
    g.fli g28, 0.15625
    g.fadd g6, g6, g28             ; ambient light colour
    g.fmul g7, g4, g24
    g.fmul g8, g5, g25
    g.fmul g9, g6, g26
    g.vscale g4, g24, g12
    g.fadd g4, g4, g13
    g.fadd g5, g5, g13
    g.fadd g6, g6, g13
    g.mov g12, g4
    g.mov g13, g5
    g.mov g14, g6                  ; sun term, applied if unshadowed
    g.fli g28, 220.0
    g.fadd g28, g15, g28
    g.fdiv g28, g15, g28
    g.fli g29, 1.0
    g.fsub g29, g29, g28           ; 1 - haze
    g.vscale g7, g7, g29
    g.vscale g12, g12, g29
    g.fli g30, 1.0
    g.fmul g30, g30, g28
    g.fadd g7, g7, g30
    g.fli g30, 0.75
    g.fmul g30, g30, g28
    g.fadd g8, g8, g30
    g.fli g30, 0.5
    g.fmul g30, g30, g28
    g.fadd g9, g9, g30
    g.fli g28, 0.012
    g.vscale g21, g21, g28
    g.vadd g1, g18, g21
    g.fli g4, 0.6875
    g.fli g5, 0.3125
    g.fli g6, 0.65625
    g.li g18, 1
    g.or g11, g11, g18
    g.jmp rt_loop
; ---------------------------------------------------------------- sea
rt_water:
    g.uniform g21, 0
    g.itof g21, g21
    g.fli g22, 0.015625
    g.fmul g21, g21, g22           ; time
    g.fli g22, 1.875
    g.fmul g22, g18, g22
    g.fli g23, 0.8125
    g.fmul g23, g20, g23
    g.fadd g22, g22, g23
    g.fli g23, 1.75
    g.fmul g23, g21, g23
    g.fadd g22, g22, g23
    g.fli g23, 0.15915494
    g.fmul g22, g22, g23
    g.fli g23, 1000.5
    g.fadd g22, g22, g23
    g.ftoi g23, g22
    g.itof g23, g23
    g.fsub g22, g22, g23
    g.fli g23, 0.5
    g.fsub g22, g22, g23
    g.fsub g23, g0, g22
    g.fmax g23, g23, g22
    g.fli g24, -16.0
    g.fmul g23, g23, g24
    g.fli g24, 8.0
    g.fadd g23, g23, g24
    g.fmul g22, g22, g23
    g.fli g23, 2.125
    g.fmul g23, g20, g23
    g.fli g24, 0.625
    g.fmul g24, g18, g24
    g.fsub g23, g23, g24
    g.fli g24, 1.25
    g.fmul g24, g21, g24
    g.fadd g23, g23, g24
    g.fli g24, 0.15915494
    g.fmul g23, g23, g24
    g.fli g24, 1000.5
    g.fadd g23, g23, g24
    g.ftoi g24, g23
    g.itof g24, g24
    g.fsub g23, g23, g24
    g.fli g24, 0.5
    g.fsub g23, g23, g24
    g.fsub g24, g0, g23
    g.fmax g24, g24, g23
    g.fli g25, -16.0
    g.fmul g24, g24, g25
    g.fli g25, 8.0
    g.fadd g24, g24, g25
    g.fmul g23, g23, g24
    g.fli g24, 16.0
    g.fadd g24, g24, g15
    g.fli g26, 1.0
    g.fdiv g24, g26, g24           ; ripples fade with distance
    g.fsub g24, g0, g24
    g.fmul g25, g22, g24
    g.fmul g27, g23, g24
    g.norm3 g25, g25               ; ripple normal (y = 1 in g26)
    g.dot3 g28, g4, g25
    g.fsub g28, g0, g28
    g.fmax g28, g28, g0
    g.fsub g28, g26, g28
    g.fmul g29, g28, g28
    g.fmul g29, g29, g29
    g.fmul g29, g29, g28
    g.fli g28, 0.75
    g.fmul g29, g29, g28
    g.fli g28, 0.03125
    g.fadd g29, g29, g28           ; Fresnel
    g.fli g28, -9.0
    g.fadd g28, g20, g28           ; distance past the shoreline
    g.fli g30, -0.0625
    g.fmul g30, g28, g30
    g.fadd g30, g30, g26
    g.fmax g30, g30, g0            ; shallowness
    g.fli g24, -1.75
    g.fmul g24, g28, g24
    g.fadd g24, g24, g26
    g.fmax g24, g24, g0
    g.fadd g23, g22, g26
    g.fmul g24, g24, g23
    g.fadd g30, g30, g24           ; + shore foam
    g.fli g12, 0.03125
    g.fli g28, 0.125
    g.fmul g28, g28, g30
    g.fadd g12, g12, g28
    g.fli g13, 0.25
    g.fli g28, 0.4375
    g.fmul g28, g28, g30
    g.fadd g13, g13, g28
    g.fli g14, 0.34375
    g.fli g28, 0.3125
    g.fmul g28, g28, g30
    g.fadd g14, g14, g28
    g.fsub g24, g26, g29
    g.vscale g7, g12, g24
    g.mov g10, g29                 ; weight of the mirrored sky
    g.reflect3 g4, g4, g25
    g.fli g28, 0.03125
    g.fmax g5, g5, g28
    g.norm3 g4, g4
    g.jmp rt_sky
k_render_end:
; ============================================================================
;  K4  the score.  SPU kernel: one lane per output sample (256 per block).
;  Data driven: a table of voices (FM plucks / noise percussion), each with a
;  step pattern, plays over an 8-bar chord loop; a 3-tap ping-pong echo is
;  made by re-evaluating the whole band at earlier times.
;  b0 = audio out (rw), b1 = IMG tables (ro)
; ============================================================================
.equ SONGLEN, 2883584
k_gpu_end:
k_spu:
    g.li g31, 4
    g.li g30, 255
    g.li g29, 17
    g.li g28, 8
    g.fli g26, 1.0
    g.li g25, 1
    g.id g1, 2
    g.li g2, 3
    g.shl g3, g1, g2               ; output byte offset
    g.uniform g2, 14
    g.add g1, g1, g2               ; absolute sample index
    g.li g2, SONGLEN
    g.sltu g5, g1, g2
    g.bnz g5, sp_nw
    g.sub g1, g1, g2
sp_nw:
    g.mov g4, g0
    g.mov g5, g0
    g.li g6, tap_tab-IMG
sp_tap:
    g.ld g8, g6, 1                 ; delay
    g.add g23, g6, g31
    g.ld g9, g23, 1                ; gain
    g.add g23, g23, g31
    g.ld g24, g23, 1               ; channel swap
    g.add g23, g23, g31
    g.ld g7, g23, 1                ; first voice this tap plays
    g.sub g8, g1, g8               ; time seen by this tap
    g.slt g2, g8, g0
    g.bnz g2, sp_tn
sp_v:
    g.ld g10, g7, 1
    g.add g23, g7, g31
    g.ld g11, g23, 1               ; pattern
    g.and g12, g10, g30            ; step length (shift)
    g.shr g10, g10, g28            ; pattern mask
    g.shr g13, g8, g12             ; step number
    g.and g14, g13, g10
    g.add g14, g14, g11
    g.ldb g14, g14, 1              ; note (255 = rest)
    g.sub g15, g14, g30
    g.bz g15, sp_vn
    g.add g23, g23, g31
    g.ld g15, g23, 1               ; flags
    g.shr g16, g8, g29             ; bar
    g.shr g17, g15, g28
    g.and g17, g17, g30
    g.sltu g17, g16, g17
    g.bnz g17, sp_vn               ; voice has not entered yet
    g.li g17, 7
    g.and g16, g16, g17
    g.li g17, chord_tab-IMG
    g.add g16, g16, g17
    g.ldb g16, g16, 1              ; chord root degree
    g.and g17, g15, g25
    g.mul g16, g16, g17
    g.add g14, g14, g16
    g.li g17, scale_tab-IMG
    g.add g14, g14, g17
    g.ldb g14, g14, 1              ; semitones
    g.itof g14, g14
    g.fli g17, 0.08333333
    g.fmul g14, g14, g17
    g.fli g17, -9.9375
    g.fadd g14, g14, g17
    g.fli g17, 32.0
    g.fadd g14, g14, g17
    g.ftoi g17, g14
    g.itof g16, g17
    g.fsub g14, g14, g16
    g.li g16, 95
    g.add g17, g17, g16
    g.li g16, 23
    g.shl g17, g17, g16
    g.fli g16, 0.078125
    g.fmul g16, g16, g14
    g.fli g18, 0.2265625
    g.fadd g16, g16, g18
    g.fmul g16, g16, g14
    g.fli g18, 0.6953125
    g.fadd g16, g16, g18
    g.fmul g16, g16, g14
    g.fli g18, 1.0
    g.fadd g16, g16, g18
    g.fmul g14, g16, g17
    g.shl g13, g13, g12
    g.sub g13, g8, g13
    g.itof g13, g13                ; samples since the note began
    g.fmul g14, g14, g13
    g.add g23, g23, g31
    g.ld g16, g23, 1               ; decay
    g.fmul g16, g16, g13
    g.fadd g16, g16, g26
    g.fmul g16, g16, g16
    g.fdiv g16, g26, g16           ; envelope
    g.add g23, g23, g31
    g.ld g17, g23, 1               ; FM index
    g.li g18, 2
    g.and g18, g15, g18
    g.bnz g18, sp_noise
    g.fmul g17, g17, g16
    g.mov g21, g0
    g.li g20, 2
    g.fadd g19, g26, g26
sp_fm:
    g.fmul g22, g14, g19
    g.fmul g18, g17, g21
    g.fadd g22, g22, g18
    g.fli g18, 1000.5
    g.fadd g21, g22, g18
    g.ftoi g18, g21
    g.itof g18, g18
    g.fsub g21, g21, g18
    g.fli g18, 0.5
    g.fsub g21, g21, g18
    g.fsub g18, g0, g21
    g.fmax g18, g18, g21
    g.fli g13, -16.0
    g.fmul g18, g18, g13
    g.fli g13, 8.0
    g.fadd g18, g18, g13
    g.fmul g21, g21, g18
    g.fsub g18, g0, g21
    g.fmax g18, g18, g21
    g.fli g13, 0.225
    g.fmul g18, g18, g13
    g.fli g13, 0.775
    g.fadd g18, g18, g13
    g.fmul g21, g21, g18
    g.mov g19, g26
    g.sub g20, g20, g25
    g.bnz g20, sp_fm
    g.jmp sp_mix
sp_noise:
    g.li g22, 2654435761
    g.mul g21, g8, g22
    g.shl g22, g30, g28
    g.shr g22, g21, g28
    g.xor g21, g21, g22
    g.li g22, 2246822519
    g.mul g21, g21, g22
    g.shr g22, g21, g28
    g.xor g21, g21, g22
    g.itof g21, g21
    g.fli g22, 0.0000000004656613
    g.fmul g21, g21, g22
sp_mix:
    g.fmul g21, g21, g16
    g.add g23, g23, g31
    g.ld g22, g23, 1               ; amplitude
    g.fmul g21, g21, g22
    g.fmul g21, g21, g9
    g.add g23, g23, g31
    g.ld g22, g23, 1               ; pan
    g.bz g24, sp_nf
    g.fsub g22, g26, g22
sp_nf:
    g.fmul g15, g21, g22
    g.fadd g5, g5, g15
    g.fsub g22, g26, g22
    g.fmul g15, g21, g22
    g.fadd g4, g4, g15
sp_vn:
    g.li g2, 28
    g.add g7, g7, g2
    g.li g2, voice_end-IMG
    g.sltu g2, g7, g2
    g.bnz g2, sp_v
sp_tn:
    g.li g2, 16
    g.add g6, g6, g2
    g.li g2, tap_end-IMG
    g.sltu g2, g6, g2
    g.bnz g2, sp_tap
    g.fsub g10, g0, g4
    g.fmax g10, g10, g4
    g.fadd g10, g10, g26
    g.fdiv g4, g4, g10
    g.fsub g10, g0, g5
    g.fmax g10, g10, g5
    g.fadd g10, g10, g26
    g.fdiv g5, g5, g10
    g.itof g11, g1
    g.fli g12, 0.0000152587890625
    g.fmul g12, g12, g11
    g.fmin g12, g12, g26
    g.li g13, SONGLEN
    g.sub g13, g13, g1
    g.itof g13, g13
    g.fli g14, 0.0000101725
    g.fmul g13, g13, g14
    g.fmin g13, g13, g26
    g.fmul g12, g12, g13
    g.fli g14, 1.5
    g.fmul g12, g12, g14
    g.fmul g4, g4, g12
    g.fmul g5, g5, g12
    g.st g4, g3, 0
    g.add g3, g3, g31
    g.st g5, g3, 0
    g.end
k_spu_end:
; ---- generated scene tables ----
.equ N_PTS, 62
.equ N_CAPS, 46
cl_tab:
.word OFF_PTS+816
.float 1.3
.word OFF_CAPS+680, OFF_CAPS+1520
.word OFF_PTS+832
.float 0.95
.word OFF_CAPS+0, OFF_CAPS+680
.word OFF_PTS+880
.float 2.7
.word OFF_CAPS+1520, OFF_CAPS+1840
.word OFF_PTS+0
.float 0.5
.word 0, 1
.word OFF_PTS+16
.float 0.5
.word 0, 2
cl_end:
pt_tab:
.byte 228,20,0,0 ; RH
.byte 28,20,0,0 ; FH
.byte 0,18,0,0 ; BB
.byte 246,46,0,0 ; ST
.byte 247,43,0,0 ; TT
.byte 21,45,0,0 ; HT
.byte 23,40,0,0 ; HB
.byte 20,51,0,0 ; STEM
.byte 20,51,243,0 ; BARL
.byte 20,51,13,0 ; BARR
.byte 238,49,0,0 ; SAD1
.byte 251,50,0,0 ; SAD2
.byte 0,18,251,0 ; CRL
.byte 0,18,5,0 ; CRR
.byte 8,0,5,1 ; PR
.byte 8,0,10,1 ; PRo
.byte 8,0,8,1 ; PRc
.byte 248,0,251,1 ; PL
.byte 248,0,246,1 ; PLo
.byte 248,0,249,1 ; PLc
.byte 15,0,0,2 ; RS0
.byte 241,0,0,2 ; RS1
.byte 15,0,0,3 ; FS0
.byte 241,0,0,3 ; FS1
.byte 241,59,0,0 ; BODYA
.byte 5,63,0,0 ; BODYB
.byte 235,57,0,0 ; TAILA
.byte 216,53,0,0 ; TAILB
.byte 7,70,0,0 ; N0
.byte 15,82,0,0 ; N1
.byte 8,91,0,0 ; N2
.byte 11,99,0,0 ; N3
.byte 17,101,0,0 ; HEAD
.byte 21,101,0,0 ; BK0
.byte 61,94,0,0 ; BKT
.byte 22,97,0,0 ; PO0
.byte 55,85,0,0 ; POT
.byte 22,105,251,0 ; SHL
.byte 22,105,6,0 ; SHR
.byte 2,65,242,0 ; SHL
.byte 16,55,237,0 ; ELL
.byte 20,51,243,0 ; HDL
.byte 236,58,235,0 ; TIPL
.byte 251,52,248,0 ; HIPL
.byte 2,65,14,0 ; SHR
.byte 16,55,19,0 ; ELR
.byte 20,51,13,0 ; HDR
.byte 236,58,21,0 ; TIPR
.byte 251,52,9,0 ; HIPR
.byte 4,0,9,4 ; KNEER
.byte 252,0,248,4 ; KNEEL
.byte 8,73,0,0 ; PELC
.byte 0,33,0,0 ; BIKEC
.byte 3,181,0,5 ; T0
.byte 8,241,3,5 ; T1
.byte 23,45,3,5 ; T2
.byte 45,100,3,5 ; T3
.byte 120,75,3,5 ; FR0
.byte 68,75,74,5 ; FR1
.byte 241,75,47,5 ; FR2
.byte 241,75,215,5 ; FR3
.byte 68,75,187,5 ; FR4
cap_tab:
.byte 2,3,6,4 ; BB-ST
.byte 4,5,6,4 ; TT-HT
.byte 2,6,7,4 ; BB-HB
.byte 5,6,8,4 ; HT-HB
.byte 2,0,5,4 ; BB-RH
.byte 4,0,4,4 ; TT-RH
.byte 6,1,6,5 ; HB-FH
.byte 8,9,5,5 ; BARL-BARR
.byte 10,11,11,1 ; SAD1-SAD2
.byte 13,14,5,5 ; CRR-PR
.byte 12,17,5,5 ; CRL-PL
.byte 14,15,6,1 ; PR-PRo
.byte 17,18,6,1 ; PL-PLo
.byte 0,20,3,5 ; RH-RS0
.byte 0,21,3,5 ; RH-RS1
.byte 1,22,3,5 ; FH-FS0
.byte 1,23,3,5 ; FH-FS1
.byte 24,25,58,0 ; BODYA-BODYB
.byte 26,27,18,0 ; TAILA-TAILB
.byte 28,29,26,0 ; N0-N1
.byte 29,30,20,0 ; N1-N2
.byte 30,31,17,0 ; N2-N3
.byte 32,32,22,0 ; HEAD-HEAD
.byte 33,34,10,2 ; BK0-BKT
.byte 35,36,18,3 ; PO0-POT
.byte 39,44,9,1 ; SHL-SHR
.byte 39,40,20,0 ; SHL-ELL
.byte 40,41,16,0 ; ELL-HDL
.byte 40,42,14,1 ; ELL-TIPL
.byte 43,50,14,0 ; HIPL-KNEEL
.byte 50,19,8,2 ; KNEEL-PLc
.byte 19,19,10,2 ; PLc-PLc
.byte 44,45,20,0 ; SHR-ELR
.byte 45,46,16,0 ; ELR-HDR
.byte 45,47,14,1 ; ELR-TIPR
.byte 48,49,14,0 ; HIPR-KNEER
.byte 49,16,8,2 ; KNEER-PRc
.byte 16,16,10,2 ; PRc-PRc
.byte 53,54,32,6 ; T0-T1
.byte 54,55,26,6 ; T1-T2
.byte 55,56,22,6 ; T2-T3
.byte 56,57,14,7 ; T3-FR0
.byte 56,58,14,7 ; T3-FR1
.byte 56,59,14,7 ; T3-FR2
.byte 56,60,14,7 ; T3-FR3
.byte 56,61,14,7 ; T3-FR4
sin_tab:
.word 9
.word 16393
.word 37
.word 16421
.word 92
.word 16476
.word 4099
.word 102105088
.word 102121472
.word 12546
.word 151259136
.word 151275520
.word 31234
.word 0
.word 16384
piv_tab:
.float 0, 0
.word 52
.float 0
.float 0, 0.36
.word 8
.float 0
.float -0.56, 0.4
.word 16
.float 0
.float 0.56, 0.4
.word 16
.float 0
.float 0.11, 0.755
.word 8
.float 0
.float -2.5, 1.5
.word 52
.float 7
mat_tab:
.float 0.9375, 0.9375, 0.875, 0.125
.float 0.03125, 0.03125, 0.03125, 0.75
.float 1, 0.5, 0.0625, 0.375
.float 1, 0.71875, 0.375, 0.25
.float 0.8125, 0.0625, 0.0625, 0.5
.float 0.75, 0.75, 0.8125, 0.875
.float 0.4375, 0.28125, 0.125, 0.125
.float 0.125, 0.5, 0.125, 0.25
tap_tab:
.word 0
.float 1
.word 0, voice_tab-IMG
.word 24576
.float 0.4375
.word 1, voice_mel-IMG
tap_end:
voice_tab:
.word 1805, pat_kick-IMG, 1024
.float 0.000244140625, 0.5, 1, 0.5
.word 1805, pat_snare-IMG, 1026
.float 0.00048828125, 0, 0.5, 0.5
.word 1805, pat_hat-IMG, 514
.float 0.001953125, 0, 0.125, 0.625
.word 7949, pat_bass-IMG, 513
.float 0.0001220703125, 0.0625, 0.75, 0.5
voice_mel:
.word 1805, pat_stab-IMG, 1025
.float 0.00048828125, 0.25, 0.25, 0.375
.word 1805, pat_stab5-IMG, 1025
.float 0.00048828125, 0.25, 0.1875, 0.625
.word 3853, pat_arp-IMG, 1
.float 0.000244140625, 0.25, 0.125, 0.75
.word 7949, pat_lead-IMG, 2049
.float 0.000244140625, 0.375, 0.375, 0.5
voice_end:
pat_kick:
.byte 0,255,255,255,255,255,255,255
pat_snare:
.byte 255,255,255,255,0,255,255,255
pat_hat:
.byte 255,255,0,255,255,255,0,255
pat_bass:
.byte 7,255,255,7,255,255,11,255,7,255,255,14,255,255,11,255,7,255,255,7,255,255,11,255,7,255,11,255,12,255,11,255
pat_stab:
.byte 255,255,16,255,255,255,16,255
pat_stab5:
.byte 255,255,18,255,255,255,18,255
pat_arp:
.byte 21,23,25,28,25,23,21,23,25,28,30,28,25,23,25,23
pat_lead:
.byte 21,255,255,21,255,255,25,255,23,255,255,21,255,255,18,255,23,255,255,25,255,255,28,255,26,255,25,255,23,255,21,255
chord_tab:
.byte 0,4,5,3,0,4,3,4
scale_tab:
.byte 0,2,4,5,7,9,11,12,14,16,17,19,21,23,24,26,28,29,31,33,35,36,38,40,41,43,45,47,48,50,52,53,55,57,59,60,62,64,65,67

