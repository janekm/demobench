; =====================================================================
;  DB32 demo  --  CPU sequencer + GPU renderer + SPU synth in 4096 bytes
; =====================================================================
.profile spu-1
.entry start

.equ FB0,   0x10000
.equ FB1,   0x1E100
.equ AOUT,  0x2C200

; ---------------------------------------------------------------------
; CPU: apply MMIO config script, then render loop
; ---------------------------------------------------------------------
start:
    li r1, cfg
cfg_next:
    lw r2, 0(r1)            ; destination (0 terminates)
    beq r2, r0, cfg_done
    lw r3, 4(r1)            ; word count
    addi r1, r1, 8
    jal r15, copy
    j cfg_next
; copy r3 words from r1 to r2
copy:
    lw r4, 0(r1)
    sw r4, 0(r2)
    addi r1, r1, 4
    addi r2, r2, 4
    addi r3, r3, -1
    bne r3, r0, copy
    jalr r0, 0(r15)
cfg_done:
    lui r13, 0xf3
    lui r14, 0xf5
    li r10, FB0
    li r11, FB1
frame:
    ; demo time wraps every 3600 frames (32 bars), like the music
    lw r5, 24(r14)
    addi r2, r0, 3600
wrap:
    blt r5, r2, wrapped
    sub r5, r5, r2
    j wrap
wrapped:
    sw r5, 0x100(r13)       ; U0 global frame
    ; scene = frame / 450, local = frame mod 450
    addi r2, r0, 450
    li r1, scenes - 20
scn:
    addi r1, r1, 20
    sub r5, r5, r2
    blt r5, r0, scn_found
    j scn
scn_found:
    add r5, r5, r2
    li r6, scenes
    bne r1, r6, not_first
    addi r5, r5, 12         ; no flash at the very start
not_first:
    sw r5, 0x104(r13)       ; U1 local frame
    addi r2, r13, 0x108
    addi r3, r0, 5
    jal r15, copy           ; U2..U6 scene parameters
    sw r10, 0x40(r13)       ; render into the back buffer
    addi r1, r0, 1
    sw r1, 16(r13)
wgpu:
    wfi
    lw r1, 20(r13)
    addi r2, r0, 1
    beq r1, r2, wgpu
    sw r10, 0(r14)
    sw r2, 20(r14)
wvbl:
    wfi
    lw r1, 20(r14)
    bne r1, r0, wvbl
    xor r10, r10, r11
    xor r11, r10, r11
    xor r10, r10, r11
    j frame

; ---- include gpu.s ----
; ---------------------------------------------------------------------
; GPU kernel: one invocation per pixel.
; uniforms: 0 global frame  1 local frame  2 scene type (0 RT, 1 tunnel,
;   2 menger)  3 [yaw0|yaw rate]  4 [cam distance|height]
;   5 [fly speed|-]  6 daylight   (bf16 pairs: high half, low half)
; Pipeline: setup/camera -> (ray tracer | sphere tracer) -> sky -> post.
; The sky block adds THR*sky(RD) to COL, so fog and escaped rays share it.
; ---------------------------------------------------------------------

gpu_k:
    g.li g30, 1
    g.fli g29, 1.0
    ; ---- primary ray (x-80, horizon-y, 110) ----
    g.id g26, 0
    g.id g27, 4
    g.shr g27, g27, g30
    g.sub g26, g26, g27
    g.itof g21, g26
    g.id g26, 1
    g.li g27, 40
    g.sub g26, g27, g26
    g.itof g9, g26
    g.fli g23, 110.0
    g.uniform g26, 1
    g.itof g26, g26
    g.fli g27, 0.035555556
    g.fmul g1, g26, g27            ; beats since scene start
    g.li g24, 0xffff0000
    g.li g25, 16
    ; kick zoom: forward += pump * (1 - f)^2, f = beat fraction (kept in Z)
    g.ftoi g27, g1
    g.itof g27, g27
    g.fsub g28, g1, g27
    g.fsub g27, g29, g28
    g.fmul g27, g27, g27
    g.uniform g26, 5
    g.shl g26, g26, g25
    g.fmul g27, g27, g26
    g.fadd g23, g23, g27
    ; the tunnel looks along +y, so the yaw rotation below becomes a roll
    g.uniform g26, 2
    g.sub g26, g26, g30
    g.bnz g26, no_swap
    g.fli g26, 20.0
    g.fadd g26, g9, g26
    g.mov g9, g23
    g.mov g23, g26
no_swap:
    ; ---- camera: (c, s) = norm(1, u, 0), u = yaw0 + rate*t ----
    g.uniform g26, 3
    g.shl g27, g26, g25
    g.fmul g27, g27, g1
    g.and g26, g26, g24
    g.fadd g18, g26, g27
    g.mov g17, g29
    g.mov g19, g0
    g.norm3 g17, g17
    g.fmul g26, g21, g17
    g.fmul g27, g23, g18
    g.fadd g8, g26, g27
    g.fmul g26, g23, g17
    g.fmul g27, g21, g18
    g.fsub g10, g26, g27
    g.norm3 g8, g8
    ; ro = (0, h + speed*t, 0) - dist * (s, 0, c)
    g.uniform g26, 4
    g.and g27, g26, g24
    g.fsub g27, g0, g27
    g.fmul g5, g18, g27
    g.fmul g7, g17, g27
    g.shl g26, g26, g25
    g.uniform g27, 5
    g.and g27, g27, g24
    g.fmul g27, g27, g1
    g.fadd g6, g26, g27
    ; ---- sun: elevation from daylight ----
    g.uniform g3, 6
    g.fli g2, 0.5
    g.mov g4, g29
    g.norm3 g2, g2
    g.mov g14, g29
    g.mov g15, g29
    g.mov g16, g29
    g.uniform g26, 2
    g.bnz g26, sdf_scene

; =====================================================================
; Ray tracer: plane y=0 + ring of six bouncing mirror spheres.
; Diffuse hits continue toward the sun, so the sphere test doubles as
; the shadow test and the sky supplies the sun light.
; =====================================================================
    g.mov g17, g0
    g.fli g19, 2.6
    g.fli g20, 0.8
    g.fadd g26, g28, g28
    g.fsub g26, g26, g29
    g.fmul g26, g26, g26
    g.fsub g26, g29, g26
    g.fli g27, 1.4
    g.fmul g26, g26, g27
    g.fadd g18, g26, g20        ; bounce height, lands on each beat
    g.li g31, 3
bounce:
    g.fli g24, 1000.0
    g.mov g25, g0
    g.flt g26, g9, g0
    g.bz g26, no_plane
    g.fdiv g26, g6, g9
    g.fsub g24, g0, g26
    g.mov g25, g30
no_plane:
    g.li g28, 6
sph_loop:
    g.sphere g26, g5, g8, g17
    g.flt g27, g26, g24
    g.bz g27, sph_miss
    g.flt g27, g0, g26
    g.bz g27, sph_miss
    g.mov g24, g26
    g.vscale g21, g17, g29
    g.and g25, g28, g30
    g.add g25, g25, g30
    g.add g25, g25, g30         ; 2 chrome, 3 gold (alternating)
sph_miss:
    ; rotate centre 60 degrees about y
    g.fli g1, 0.8660254
    g.fmul g26, g19, g1
    g.fmul g1, g17, g1
    g.fli g27, 0.5
    g.fmul g17, g17, g27
    g.fmul g19, g19, g27
    g.fadd g17, g17, g26
    g.fsub g19, g19, g1
    g.sub g28, g28, g30
    g.bnz g28, sph_loop
    g.bz g25, sky
    ; hit point
    g.vscale g26, g8, g24
    g.vadd g5, g5, g26
    g.sub g26, g25, g30
    g.bz g26, hit_plane
    ; mirror sphere
    g.vsub g21, g5, g21
    g.norm3 g21, g21
    g.fli g26, 0.8
    g.vscale g14, g14, g26
    g.and g26, g25, g30
    g.bz g26, chrome
    g.fli g26, 0.35
    g.fmul g16, g16, g26
chrome:
    g.reflect3 g8, g8, g21
    g.jmp next_bounce
hit_plane:
    g.mov g21, g0
    g.mov g22, g29
    g.mov g23, g0
    ; checker albedo
    g.fli g27, 512.0
    g.fadd g26, g5, g27
    g.ftoi g26, g26
    g.fadd g28, g7, g27
    g.ftoi g28, g28
    g.xor g26, g26, g28
    g.and g26, g26, g30
    g.itof g26, g26
    g.fli g27, 0.5
    g.fsub g26, g26, g27
    g.fli g27, 4.0
    g.fdiv g27, g27, g24
    g.fmin g27, g27, g29
    g.fmul g26, g26, g27              ; checker contrast fades with distance
    g.fli g27, 0.52
    g.fadd g26, g26, g27
    g.vscale g14, g14, g26
    ; ambient, scaled by daylight
    g.uniform g27, 6
    g.fli g28, 0.3
    g.fmul g27, g27, g28
    g.vscale g26, g14, g27
    g.vadd g11, g11, g26
    ; continue toward the sun (shadow test + direct light)
    g.vscale g14, g14, g3
    g.vscale g8, g2, g29
next_bounce:
    g.fli g26, 0.002
    g.vscale g26, g21, g26
    g.vadd g5, g5, g26
    g.sub g31, g31, g30
    g.bnz g31, bounce
    g.jmp sky

; =====================================================================
; Sphere tracer for SDF worlds, flying along +y. No normals: shading is
; step-count occlusion + beat-pulsed glow + fog into the sky colour.
; =====================================================================
sdf_scene:
    g.uniform g1, 2
    g.sub g1, g1, g30         ; 0 tunnel, 1 sponge
    g.mov g24, g0
    g.li g31, 20
march:
    g.vscale g17, g8, g24
    g.vadd g17, g17, g5
sdf_eval:
    g.bnz g1, sdf_menger
    ; ---- tunnel: square pipe of half-width 1 with ribs every unit ----
    g.fsub g26, g0, g17
    g.fmax g26, g26, g17
    g.fsub g27, g0, g19
    g.fmax g27, g27, g19
    g.fmax g26, g26, g27
    g.fsub g25, g29, g26         ; inside the pipe
    g.fli g28, 256.5
    g.fadd g27, g18, g28
    g.ftoi g28, g27
    g.itof g28, g28
    g.fsub g27, g27, g28
    g.fli g28, 0.5
    g.fsub g27, g27, g28
    g.fsub g28, g0, g27
    g.fmax g27, g27, g28              ; |fract(y) - .5|
    g.fli g28, 0.05
    g.fsub g21, g27, g28
    g.fli g28, 0.12
    g.fsub g26, g25, g28
    g.fmax g21, g21, g26        ; rib (kept in HC.x for emission)
    g.fmin g25, g25, g21
    g.jmp sdf_ret
sdf_menger:
    ; ---- Menger sponge, 2 folds ----
    g.fli g21, 3.0
    g.fli g22, 2.0
    g.li g23, 2
m_it:
    g.fsub g26, g0, g17
    g.fmax g17, g17, g26
    g.fsub g26, g0, g18
    g.fmax g18, g18, g26
    g.fsub g26, g0, g19
    g.fmax g19, g19, g26
    g.fmax g26, g17, g18
    g.fmin g18, g17, g18
    g.fmax g17, g26, g19
    g.fmin g19, g26, g19
    g.fmax g26, g18, g19
    g.fmin g19, g18, g19
    g.mov g18, g26
    g.vscale g17, g17, g21
    g.fsub g17, g17, g22
    g.fsub g18, g18, g22
    g.fsub g26, g22, g19
    g.fmin g19, g19, g26
    g.sub g23, g23, g30
    g.bnz g23, m_it
    g.fsub g26, g0, g17
    g.fmax g17, g17, g26
    g.fsub g26, g0, g18
    g.fmax g18, g18, g26
    g.fsub g26, g0, g19
    g.fmax g19, g19, g26
    g.fmax g26, g17, g18
    g.fmax g26, g26, g19
    g.fsub g26, g26, g29
    g.fli g27, 0.11111111         ; 1/9
    g.fmul g25, g26, g27
sdf_ret:
    g.bnz g20, sdf_lit
    g.fadd g24, g24, g25
    g.fli g26, 0.003
    g.flt g26, g25, g26
    g.bnz g26, sdf_hit
    g.fli g26, 7.0
    g.flt g26, g26, g24
    g.bnz g26, sky
    g.sub g31, g31, g30
    g.bnz g31, march
sdf_hit:
    ; one more SDF sample offset toward the light (sun for the sponge,
    ; headlight for the tunnel): d/h ~ N.L
    g.mov g14, g21           ; rib distance at the hit (tunnel)
    g.mov g20, g30
    g.vscale g17, g8, g24
    g.vadd g17, g17, g5
    g.fli g26, -0.08
    g.vscale g21, g8, g26
    g.bz g1, lit_dir
    g.fli g26, 0.08
    g.vscale g21, g2, g26
lit_dir:
    g.vadd g17, g17, g21
    g.jmp sdf_eval
sdf_lit:
    g.fli g26, 10.0
    g.fmul g26, g25, g26
    g.fmax g26, g26, g0
    g.fmin g26, g26, g29
    ; occlusion from remaining steps
    g.itof g27, g31
    g.fli g28, 0.03
    g.fmul g27, g27, g28
    g.fmul g26, g26, g27
    g.fli g11, 0.9
    g.fli g12, 0.7
    g.fli g13, 0.5
    g.vscale g11, g11, g26
    ; neon ribs, pulsed on the beat
    g.fli g26, 0.02
    g.flt g26, g14, g26
    g.bz g26, no_neon
    g.uniform g26, 1
    g.itof g26, g26
    g.fli g27, 0.035555556
    g.fmul g26, g26, g27
    g.fmul g27, g9, g24
    g.fadd g27, g27, g6
    g.fli g28, 0.25
    g.fmul g27, g27, g28
    g.fsub g26, g26, g27              ; pulse travels down the tunnel each beat
    g.ftoi g27, g26
    g.itof g27, g27
    g.fsub g26, g26, g27
    g.fsub g26, g29, g26
    g.fmul g27, g26, g26
    g.fmul g26, g27, g26
    g.fadd g26, g26, g26
    g.fli g27, 0.3
    g.fadd g26, g26, g27              ; 0.3 + 2(1-f)^3
    g.uniform g27, 6
    g.fadd g27, g27, g27
    g.fmul g27, g26, g27
    g.fadd g11, g11, g27
    g.fmul g27, g27, g27
    g.fadd g12, g12, g27
    g.fadd g13, g13, g26
no_neon:
    ; fog: f = 1/(1 + 0.05 t^2)
    g.fmul g26, g24, g24
    g.fli g27, 0.05
    g.fmul g26, g26, g27
    g.fadd g26, g26, g29
    g.fdiv g26, g29, g26
    g.vscale g11, g11, g26
    g.fsub g26, g29, g26
    g.mov g14, g26
    g.mov g15, g26
    g.mov g16, g26

; =====================================================================
; Sky: COL += THR * sky(RD); colours follow the daylight parameter d:
;   zenith = cool(.2+.6d), horizon = warm(.3+.6d)*(.2+d), sun glow
; =====================================================================
sky:
    g.uniform g28, 6
    g.fli g27, 0.6
    g.fmul g27, g28, g27
    g.fli g26, 0.2
    g.fadd g23, g27, g26
    g.fmul g22, g23, g23
    g.fmul g21, g22, g22     ; zenith (s^4, s^2, s)
    g.fli g26, 0.3
    g.fadd g17, g27, g26
    g.fmul g18, g17, g17
    g.fmul g19, g18, g18     ; horizon (s, s^2, s^4)
    g.fli g26, 0.2
    g.fadd g28, g28, g26
    g.vscale g17, g17, g28
    g.fmax g24, g9, g0
    g.fsub g24, g29, g24
    g.fmul g24, g24, g24
    g.fmul g24, g24, g24           ; horizon weight
    g.vsub g26, g17, g21
    g.vscale g26, g26, g24
    g.vadd g21, g21, g26            ; gradient
    ; sun glow
    g.dot3 g26, g8, g2
    g.fmax g26, g26, g0
    g.fmul g26, g26, g26
    g.fmul g26, g26, g26
    g.fmul g26, g26, g26
    g.fmul g26, g26, g26
    g.fmul g26, g26, g26
    g.fli g27, 2.0
    g.fmul g26, g26, g27
    g.vscale g17, g17, g26
    g.vadd g21, g21, g17
    g.fmul g21, g21, g14
    g.fmul g22, g22, g15
    g.fmul g23, g23, g16
    g.vadd g11, g11, g21
post:
    ; ---- white flash on every scene change ----
    g.uniform g26, 1
    g.itof g26, g26
    g.fli g27, 0.1
    g.fmul g26, g26, g27
    g.fsub g26, g29, g26
    g.fmax g26, g26, g0
    g.fadd g11, g11, g26
    g.fadd g12, g12, g26
    g.fadd g13, g13, g26
    
    g.sqrt g11, g11
    g.sqrt g12, g12
    g.sqrt g13, g13
    ; ---- text banner: 32x5 bits scaled 5x, rows 48..72 ----
    g.uniform g26, 0
    g.li g27, 3240
    g.sltu g28, g26, g27
    g.li g27, t_end - t_title
    g.bz g28, text_on
    g.li g27, 420
    g.sltu g28, g26, g27
    g.bz g28, no_text
    g.mov g27, g0
text_on:
    g.fli g24, 0.2
    g.id g28, 1
    g.li g26, 12
    g.sub g28, g28, g26
    g.li g26, 25
    g.sltu g26, g28, g26
    g.bz g26, no_text
    g.itof g28, g28
    g.fmul g28, g28, g24
    g.ftoi g28, g28
    g.add g28, g28, g28
    g.add g28, g28, g28
    g.add g28, g28, g27
    g.ld g28, g28, 1                ; banner row
    g.id g26, 0
    g.itof g26, g26
    g.fmul g26, g26, g24
    g.ftoi g26, g26
    g.shr g28, g28, g26
    g.and g28, g28, g30
    g.bz g28, no_text
    g.mov g11, g29
    g.mov g12, g29
    g.mov g13, g29
no_text:
    g.id g26, 2
    g.rgb g11, g26, 0
    g.end
gpu_k_end:

; ---- include spu.s ----
; ---------------------------------------------------------------------
; SPU kernel: one invocation per stereo sample frame (grid 64x4)
;   for tap in taps: for voice in voices: for j < poly: FM/noise voice
; Sines are computed as -sin scaled to +-2^29 (F*(|F|*2^-31 - 1), F = phase);
; noise is +-2^31, voice gains are pre-scaled by 2^-29.
; ---------------------------------------------------------------------
.equ U_7,  0
.equ U_23, 1
.equ U_3,  2

spu_k:
    g.id g1, 2
    g.uniform g19, 14
    g.add g1, g1, g19
    g.id g27, 5                  ; grid height = 4
    g.sltu g25, g0, g27
    g.mul g28, g27, g27
    g.li g29, 0xffff0000
    g.li g30, 5625
    g.fli g26, 1.0
    g.fli g31, 4.656613e-10      ; 2^-31
    g.li g4, d_taps_end - d_taps
tap_loop:
    g.li g23, d_taps - 8 - d_base
    g.add g23, g23, g4
    g.ld g19, g23, 1                ; tap delay in samples
    g.sub g6, g1, g19
    g.slt g19, g6, g0
    g.bnz g19, next_tap
    ; musical position of TT: 16th step, bar, samples into step
    g.itof g19, g6
    g.itof g20, g30
    g.fdiv g19, g19, g20
    g.ftoi g20, g19
    g.mul g19, g20, g30
    g.sub g7, g6, g19
    g.shr g9, g20, g27
    g.shl g19, g9, g27
    g.sub g8, g20, g19             ; step in bar
    g.li g19, 31
    g.and g9, g9, g19           ; song loops every 32 bars
    g.ldb g10, g9, 1           ; bar flags live at data offset 0
    g.uniform g19, U_3
    g.and g11, g9, g19
    g.shl g11, g11, g27              ; (bar & 3) * 16
    g.li g5, d_voices - d_base
voice_loop:
    g.ldb g13, g5, 1             ; taps*8 | poly
    g.sltu g19, g13, g4
    g.bnz g19, next_voice
    g.add g23, g5, g25
    g.ldb g19, g23, 1
    g.and g19, g19, g10             ; voice enabled in this bar?
    g.bz g19, next_voice
    g.add g23, g23, g25
    g.ldb g12, g23, 1
    g.add g23, g23, g25
    g.ldb g24, g23, 1               ; trigger mask offset
    g.add g23, g23, g25
    g.ldb g22, g23, 1               ; note array offset
    g.and g19, g12, g28          ; four-bar pattern?
    g.bz g19, one_bar
    g.add g24, g24, g11
    g.add g22, g22, g11
one_bar:
    g.ld g21, g24, 1                ; trigger mask
    g.add g19, g8, g25
    g.shl g19, g25, g19
    g.sub g19, g19, g25
    g.and g20, g21, g19               ; triggers at or before POS
    g.bz g20, next_voice
    g.sub g21, g21, g20               ; triggers after POS
    g.shl g19, g25, g28
    g.or g21, g21, g19
    g.sub g19, g0, g21
    g.and g21, g21, g19               ; lowest later trigger
    g.itof g20, g20
    g.itof g21, g21
    g.uniform g19, U_23
    g.shr g20, g20, g19               ; 127 + j0 (float exponent of highest bit)
    g.shr g21, g21, g19               ; 127 + j1
    g.sub g21, g21, g20
    g.mul g16, g21, g30        ; note length in samples
    g.li g19, 127
    g.sub g20, g20, g19               ; j0
    g.sub g19, g8, g20
    g.mul g19, g19, g30
    g.add g14, g19, g7            ; samples since note on
    g.itof g15, g14
    g.add g22, g22, g20
    g.ldb g22, g22, 1               ; note byte
    g.and g19, g12, g25
    g.bnz g19, chord_rel
    g.bz g22, next_voice          ; absolute-note rest
chord_rel:
    g.uniform g19, U_7
    g.and g13, g13, g19             ; poly count
    g.mov g17, g0
poly_loop:
    ; ---- note number ----
    g.mov g19, g22
    g.and g20, g12, g25
    g.bz g20, abs_note
    g.add g19, g22, g17
    g.uniform g20, U_7
    g.and g19, g19, g20
    g.shr g20, g11, g25
    g.add g19, g19, g20
    g.li g20, d_chords - d_base
    g.add g19, g19, g20
    g.ldb g19, g19, 1
abs_note:
    g.add g20, g23, g25
    g.ldb g20, g20, 1               ; base note (+36 bias, folded into pitch constant)
    g.add g19, g19, g20
    ; ---- phase increment = 2^((16n + j)/192 + c) ----
    g.shl g19, g19, g27
    g.add g19, g19, g17
    g.itof g19, g19
    g.fli g20, 0.0052083333       ; 1/192
    g.fmul g19, g19, g20
    g.ftoi g21, g19
    g.itof g20, g21
    g.fsub g19, g19, g20
    g.fli g20, 0.07738064
    g.fmul g20, g20, g19
    g.fli g24, 0.22694011
    g.fadd g20, g20, g24
    g.fmul g20, g20, g19
    g.fli g24, 0.69543002
    g.fadd g20, g20, g24
    g.fmul g20, g20, g19
    g.fadd g20, g20, g26
    g.uniform g19, U_23
    g.shl g21, g21, g19
    g.add g20, g20, g21
    g.ftoi g18, g20
    g.mul g18, g18, g14          ; carrier phase
    ; ---- modulator: sin(ratio * phase + 90deg) ----
    g.li g19, 5
    g.shr g19, g12, g19
    g.mul g20, g18, g19
    g.bnz g19, fm_ratio
    g.li g20, 0x40000000          ; ratio 0: constant modulator -> pitch sweep
fm_ratio:
    g.itof g20, g20
    g.fsub g21, g0, g20
    g.fmax g21, g21, g20
    g.fmul g21, g21, g31
    g.fsub g21, g21, g26
    g.fmul g20, g20, g21
    g.add g24, g23, g27
    g.ld g22, g24, 1                ; [index*2^-3 | index decay]
    g.shl g19, g22, g28
    g.fmul g19, g19, g15
    g.fadd g19, g19, g26
    g.fmul g19, g19, g19
    g.fmul g19, g19, g19              ; (1 + k t)^4
    g.and g21, g22, g29
    g.fmul g21, g21, g20
    g.fdiv g21, g21, g19
    g.ftoi g21, g21
    g.shl g21, g21, g27
    g.add g18, g18, g21
    ; ---- carrier ----
    g.itof g20, g18
    g.fsub g21, g0, g20
    g.fmax g21, g21, g20
    g.fmul g21, g21, g31
    g.fsub g21, g21, g26
    g.fmul g20, g20, g21
    ; ---- noise mix ----
    g.add g24, g24, g27
    g.add g24, g24, g27
    g.ld g22, g24, 1                ; [gain*2^-31 | noise]
    g.shl g21, g22, g28
    g.bz g21, no_noise
    g.li g19, 0x9E3779B1
    g.mul g19, g6, g19
    g.mul g19, g19, g19
    g.itof g19, g19
    g.fsub g19, g19, g20
    g.fmul g19, g19, g21
    g.fadd g20, g20, g19
no_noise:
    g.and g22, g22, g29
    g.fmul g20, g20, g22
    ; ---- envelope: min(1, attack ramp, release ramp) / (1 + k t)^4 ----
    g.sub g24, g24, g27
    g.ld g22, g24, 1                ; [amp decay | attack rate]
    g.shl g19, g22, g28
    g.fmul g19, g19, g15
    g.sub g21, g16, g14
    g.itof g21, g21
    g.fli g24, 0.004
    g.fmul g21, g21, g24
    g.fmin g19, g19, g21
    g.fmin g19, g19, g26
    g.fmul g20, g20, g19
    g.and g19, g22, g29
    g.fmul g19, g19, g15
    g.fadd g19, g19, g26
    g.fmul g19, g19, g19
    g.fmul g19, g19, g19
    g.fdiv g20, g20, g19
    ; ---- sidechain duck (voice mode bit 2 and kick flag bit 2) ----
    g.and g19, g12, g10
    g.and g19, g19, g27
    g.bz g19, no_duck
    g.uniform g19, U_3
    g.and g19, g8, g19
    g.mul g19, g19, g30
    g.add g19, g19, g7
    g.itof g19, g19
    g.fli g21, 0.00012
    g.fmul g19, g19, g21
    g.fli g21, 0.25
    g.fadd g19, g19, g21
    g.fmin g19, g19, g26
    g.fmul g20, g20, g19
no_duck:
    ; ---- tap gain / pan, accumulate mid & side ----
    g.li g24, d_taps - 4 - d_base
    g.add g24, g24, g4
    g.ld g22, g24, 1                ; [gain | pan]
    g.and g19, g22, g29
    g.fmul g20, g20, g19
    g.fadd g2, g2, g20
    g.shl g22, g22, g28
    g.fmul g19, g22, g20
    g.fadd g3, g3, g19
    g.add g17, g17, g25
    g.sub g19, g17, g13
    g.bnz g19, poly_loop
next_voice:
    g.li g19, 20
    g.add g5, g5, g19
    g.li g19, d_voices_end - d_base
    g.sub g19, g5, g19
    g.bnz g19, voice_loop
next_tap:
    g.sub g4, g4, g27
    g.sub g4, g4, g27
    g.bnz g4, tap_loop
    ; ---- output ----
    g.fadd g19, g2, g3
    g.fsub g20, g2, g3
    ; soft limiter x / sqrt(1 + x^2)
    g.fmul g21, g19, g19
    g.fadd g21, g21, g26
    g.rsqrt g21, g21
    g.fmul g19, g19, g21
    g.fmul g21, g20, g20
    g.fadd g21, g21, g26
    g.rsqrt g21, g21
    g.fmul g20, g20, g21
    g.id g23, 2
    g.mul g23, g23, g27
    g.add g23, g23, g23
    g.st g19, g23, 0
    g.add g23, g23, g27
    g.st g20, g23, 0
    g.end
spu_k_end:


; ---- include music.s ----
; ---------------------------------------------------------------------
; Music data (SPU binding 1 = d_base .. d_end)
; 128 BPM, 16th = 5625 samples, bar = 16 steps, 32 bars loop (60 s).
; voice: [taps*8|poly, barflags mask, mode, mask offset, notes offset, base+36, 0, 0]
;        .bf index*2^-3, index decay/4/48000 ; .bf amp decay/4/48000, attack/48000
;        .bf gain*2^-31, noise
; mode: 1 chord-relative, 4 duck, 16 four-bar pattern, ratio<<5
; bar flags: 1 bass, 2 snare+hats, 4 kick, 8 arp, 16 lead, 32 pad, 64 roll, 128 crash
; ---------------------------------------------------------------------
.align 4
d_base:
; bar flags (32 bars)
d_flags:
    .byte 0x28,0x28,0x28,0x28
    .byte 0xAD,0x2D,0x2D,0x2D
    .byte 0xBF,0x3F,0x3F,0x3F
    .byte 0xBF,0x3F,0x3F,0x3F
    .byte 0xB8,0x38,0x38,0x78
    .byte 0xBF,0x3F,0x3F,0x3F
    .byte 0xBF,0x3F,0x3F,0x3F
    .byte 0xAD,0x2D,0x28,0x28
; trigger masks, 16-byte stride so the lead's per-bar masks share Q
p_lead:  .word 0x4949
p_kick:  .word 0x1111
p_snare: .word 0x1010
p_hat:   .word 0xBBBB
         .word 0x4949
p_ohat:  .word 0x4444
p_crash: .word 0x0001
p_roll:  .word 0xFFFF
         .word 0x4949
p_pad:   .word 0x0001
p_bass:  .word 0xEEEE
p_arp:   .word 0xFFFF
         .word 0x5449
         .word 0, 0, 0
; lead notes: 4 bars x 16 steps (MIDI, 0 = rest)
n_lead:
    .byte 76,0,0,76, 0,0,81,0, 79,0,0,76, 0,0,74,0
    .byte 72,0,0,72, 0,0,77,0, 76,0,0,72, 0,0,69,0
    .byte 67,0,0,72, 0,0,76,0, 79,0,0,76, 0,0,72,0
    .byte 71,0,0,74, 0,0,79,0, 0,0,77,0, 76,0,74,0
; chord-relative notes: degree 0..7 (two octaves of 4 chord tones)
n_bass:  .byte 0,0,4,0, 0,0,4,0, 0,0,4,0, 0,0,4,0
n_arp:   .byte 0,1,2,3, 4,5,6,7, 6,5,4,3, 2,1,2,3
n_zero:  .byte 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0
; chords, 8 tones each: Am F C G
d_chords:
    .byte 57,60,64,69, 69,72,76,81
    .byte 53,57,60,65, 65,69,72,77
    .byte 60,64,67,72, 72,76,79,84
    .byte 55,59,62,67, 67,71,74,79
.align 4
d_voices:
v_kick:
    .byte 9, 0x04, 0x01, p_kick-d_base, n_zero-d_base, 36-24+198, 0, 0
    .word 0x40203924 ; bf 2.5, 0.00015625
    .word 0x38193c89 ; bf 0.000036458333333333336, 0.016666666666666666
    .word 0x30e60000 ; bf 1.67638059e-9, 0
v_snare:
    .byte 25, 0x02, 0x01, p_snare-d_base, n_zero-d_base, 36-7+198, 0, 0
    .word 0x3f403924 ; bf 0.75, 0.00015625
    .word 0x38af3c9a ; bf 0.00008333333333333333, 0.01875
    .word 0x300f3e9a ; bf 5.215406280000001e-10, 0.3
v_hat:
    .byte 25, 0x02, 0x01, p_hat-d_base, n_zero-d_base, 36+198, 0, 0
    .word 0x00000000 ; bf 0, 0
    .word 0x39f63d2b ; bf 0.00046875, 0.041666666666666664
    .word 0x2ea43f80 ; bf 7.4505804e-11, 1
v_ohat:
    .byte 25, 0x02, 0x01, p_ohat-d_base, n_zero-d_base, 36+198, 0, 0
    .word 0x00000000 ; bf 0, 0
    .word 0x38f03d2b ; bf 0.00011458333333333333, 0.041666666666666664
    .word 0x2e763f80 ; bf 5.5879353e-11, 1
v_crash:
    .byte 9, 0x80, 0x01, p_crash-d_base, n_zero-d_base, 36+198, 0, 0
    .word 0x00000000 ; bf 0, 0
    .word 0x375a3d2b ; bf 0.000013020833333333334, 0.041666666666666664
    .word 0x2ee13f80 ; bf 1.024454805e-10, 1
v_roll:
    .byte 25, 0x40, 0x01, p_roll-d_base, n_zero-d_base, 36-7+198, 0, 0
    .word 0x3f003924 ; bf 0.5, 0.00015625
    .word 0x38f03c9a ; bf 0.00011458333333333333, 0.01875
    .word 0x301a3eb3 ; bf 5.5879353e-10, 0.35
v_bass:
    .byte 9, 0x01, 0x25, p_bass-d_base, n_bass-d_base, 36-24+198, 0, 0
    .word 0x3e743845 ; bf 0.23873241, 0.000046875
    .word 0x37da3c09 ; bf 0.00002604166666666667, 0.008333333333333333
    .word 0x302e0000 ; bf 6.332993340000001e-10, 0
v_arp:
    .byte 73, 0x08, 0x65, p_arp-d_base, n_arp-d_base, 36+198, 0, 0
    .word 0x3e233899 ; bf 0.15915494, 0.00007291666666666667
    .word 0x38453c4d ; bf 0.000046875, 0.0125
    .word 0x2f4d0000 ; bf 1.8626451000000002e-10, 0
v_lead:
    .byte 42, 0x10, 0x30, p_lead-d_base, n_lead-d_base, 36+198, 0, 0
    .word 0x3e1336d2 ; bf 0.143239446, 0.0000062499999999999995
    .word 0x36af3a5a ; bf 0.000005208333333333333, 0.0008333333333333334
    .word 0x2f2e0000 ; bf 1.5832483350000002e-10, 0
v_pad:
    .byte 27, 0x20, 0x25, p_pad-d_base, n_zero-d_base, 36+198, 0, 0
    .word 0x3dc435d2 ; bf 0.095492964, 0.0000015624999999999999
    .word 0x35af385a ; bf 0.0000013020833333333333, 0.00005208333333333334
    .word 0x2f0f0000 ; bf 1.3038515700000002e-10, 0
d_voices_end:
; taps: [delay samples] [.bf gain, pan]. Voices use a prefix of this list:
; 3 = dry + 2 early reflections (pads, drums), 5 = + two ping-pong echoes (lead),
; 9 = everything (arp). Keeps the worst sample under the WebGPU compiler's
; 8192-instruction-per-invocation limit (checked with tools/spusteps.mjs).
d_taps:
    .word 0
    .word 0x3f800000 ; bf 1, 0
    .word 1733
    .word 0x3ea43f33 ; bf 0.32, 0.7
    .word 2851
    .word 0x3e8fbf33 ; bf 0.28, -0.7
    .word 16875
    .word 0x3ecdbf4d ; bf 0.4, -0.8
    .word 33750
    .word 0x3e853f4d ; bf 0.26, 0.8
    .word 4079
    .word 0x3e763f1a ; bf 0.24, 0.6
    .word 5557
    .word 0x3e4dbf1a ; bf 0.2, -0.6
    .word 7919
    .word 0x3e243f00 ; bf 0.16, 0.5
    .word 50625
    .word 0x3e24bf4d ; bf 0.16, -0.8
d_taps_end:
d_end:


; ---------------------------------------------------------------------
; Scenes, 450 frames (4 bars) each:
;   [type] [.bf yaw0, yaw rate] [.bf distance, height] [.bf speed, kick zoom] [daylight]
; ---------------------------------------------------------------------
scenes:
    ; spheres at night, title
    .word 0
    .word 0xbf663d76 ; bf -0.9, 0.06
    .word 0x40e03fcd ; bf 7, 1.6
    .word 0x00000000 ; bf 0, 0
    .float 0.15
    ; night tunnel, kick enters
    .word 1
    .word 0x00003ca4 ; bf 0, 0.02
    .word 0x00000000 ; bf 0, 0
    .word 0x3e9a4170 ; bf 0.3, 15
    .float 0.0
    ; Menger sponge, pre-dawn
    .word 2
    .word 0xbf803df6 ; bf -1, 0.12
    .word 0x405a3f4d ; bf 3.4, 0.8
    .word 0x000041a0 ; bf 0, 20
    .float 0.3
    ; fast tunnel
    .word 1
    .word 0x0000bd4d ; bf 0, -0.05
    .word 0x00000000 ; bf 0, 0
    .word 0x3f804170 ; bf 1, 15
    .float 0.1
    ; sunrise spheres (breakdown)
    .word 0
    .word 0x3f00bd24 ; bf 0.5, -0.04
    .word 0x41003f9a ; bf 8, 1.2
    .word 0x00000000 ; bf 0, 0
    .float 0.45
    ; Menger, morning (drop)
    .word 2
    .word 0x3f9abe1a ; bf 1.2, -0.15
    .word 0x404dbe9a ; bf 3.2, -0.3
    .word 0x000041c8 ; bf 0, 25
    .float 0.6
    ; fastest tunnel
    .word 1
    .word 0x00003df6 ; bf 0, 0.12
    .word 0x00000000 ; bf 0, 0
    .word 0x400041a0 ; bf 2, 20
    .float 0.35
    ; daylight spheres, end text
    .word 0
    .word 0xbe9a3cf6 ; bf -0.3, 0.03
    .word 0x41104020 ; bf 9, 2.5
    .word 0x00004120 ; bf 0, 10
    .float 0.75

; text banners (GPU binding 1), see tools/banner.py
t_title:   ; "DAYBREAK"
    .word 0x52733523, 0x55155555, 0x37333275, 0x55155255, 0x55753253
t_end:     ; "BY OPUS"
    .word 0x194c814c, 0x05554154, 0x094d408c, 0x11454094, 0x0dc4808c

; ---------------------------------------------------------------------
; MMIO configuration script: [dest, count, words...], 0 terminates
; ---------------------------------------------------------------------
cfg:
    .word 0xf6040, 5, spu_k, spu_k_end - spu_k, 64, 4, AOUT
    .word 0xf6100, 7, AOUT, 2048, 3, 0, d_base, d_end - d_base, 1
    .word 0xf6200, 3, 7, 23, 3
    .word 0xf6000, 1, 1
    .word 0xf3000, 4, gpu_k, gpu_k_end - gpu_k, 160, 120
    .word 0xf3044, 6, 57600, 3, 0, t_title, t_end + 20 - t_title, 1
    .word 0xf5004, 4, 480, 4, 0, 1
    .word 0

