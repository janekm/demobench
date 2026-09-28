use db_contracts::RAM_BASE;
use db_spu::{Spu, AUDIO_RATE, BLOCK_FRAMES, QUEUE_FRAMES, WORK_LIMIT};

fn word(op: u8, d: u32, a: u32, b: u32, c: u32) -> u32 {
    op as u32 | d << 8 | a << 13 | b << 18 | c << 23
}
fn rom(words: &[u32]) -> Vec<u8> {
    words.iter().flat_map(|word| word.to_le_bytes()).collect()
}
fn configure(spu: &mut Spu, rom: &[u8], ram: &[u8]) {
    for (offset, value) in [
        (0x40, 0),
        (0x44, rom.len() as u32),
        (0x48, 1),
        (0x4c, 1),
        (0x50, RAM_BASE),
        (0x100, RAM_BASE),
        (0x104, 2048),
        (0x108, 3),
    ] {
        spu.write_reg(offset, value, rom, ram).unwrap();
    }
}
fn constant_kernel(value: f32) -> Vec<u8> {
    rom(&[
        word(1, 1, 0, 0, 0),
        value.to_bits(),
        word(36, 1, 0, 0, 0),
        word(0, 0, 0, 0, 0),
    ])
}

#[test]
fn disabled_silence_queue_is_bounded_and_timeline_advances() {
    let mut spu = Spu::new();
    let mut ram = vec![0u8; 4096];
    for _ in 0..33 {
        spu.block(&[], &mut ram, false).unwrap();
    }
    assert_eq!(spu.blocks(), 33);
    assert_eq!(spu.sample_count(), 33 * BLOCK_FRAMES as u64);
    assert_eq!(spu.audio().len(), QUEUE_FRAMES * 2);
    assert!(spu.audio().iter().all(|value| *value == 0.0));
    assert_eq!(spu.overruns(), BLOCK_FRAMES as u32);
    assert_eq!(spu.peak(), 0.0);
    assert_eq!(spu.read_reg(0x1c).unwrap(), QUEUE_FRAMES as u32);
    assert_eq!(spu.read_reg(0x14).unwrap(), 33 * BLOCK_FRAMES as u32);
    assert_eq!(spu.read_reg(0x08).unwrap(), AUDIO_RATE);
    spu.clear_audio();
    assert!(spu.audio().is_empty());
    assert_eq!(spu.sample_count(), 33 * BLOCK_FRAMES as u64);
}

#[test]
fn reference_kernel_publishes_only_finite_clamped_pcm() {
    let rom = constant_kernel(0.5);
    let mut ram = vec![0u8; 4096];
    let mut spu = Spu::new();
    configure(&mut spu, &rom, &ram);
    spu.write_reg(0, 1, &rom, &ram).unwrap();
    spu.block(&rom, &mut ram, false).unwrap();
    assert_eq!(spu.status(), 1);
    assert_eq!(spu.blocks(), 1);
    assert_eq!(spu.sample_count(), BLOCK_FRAMES as u64);
    assert_eq!(spu.last_ticks(), 24);
    assert_eq!(spu.audio().len(), BLOCK_FRAMES * 2);
    assert_eq!(spu.audio()[0], 0.5);
    assert!(spu.audio()[1..].iter().all(|x| *x == 0.0));
    assert_eq!(spu.peak(), 0.5);
    assert_eq!(spu.read_reg(0x28).unwrap(), 0.5f32.to_bits());

    let rom = constant_kernel(f32::INFINITY);
    let mut spu = Spu::new();
    configure(&mut spu, &rom, &ram);
    spu.write_reg(0, 1, &rom, &ram).unwrap();
    assert_eq!(
        spu.block(&rom, &mut ram, false).unwrap_err().code,
        "SPU_SAMPLE"
    );
    assert_eq!(spu.status(), 3);
    assert!(spu.audio().is_empty());
    assert_eq!(spu.blocks(), 0);
}

#[test]
fn control_and_block_revalidate_code_bindings_and_output() {
    let rom = constant_kernel(0.0);
    let mut ram = vec![0u8; 4096];
    let mut spu = Spu::new();
    configure(&mut spu, &rom, &ram);
    spu.write_reg(0x104, 2047, &rom, &ram).unwrap();
    assert_eq!(
        spu.write_reg(0, 1, &rom, &ram).unwrap_err().code,
        "SPU_OUTPUT"
    );
    spu.write_reg(0x104, 2048, &rom, &ram).unwrap();
    spu.write_reg(0x44, 3, &rom, &ram).unwrap();
    assert_eq!(
        spu.write_reg(0, 1, &rom, &ram).unwrap_err().code,
        "GPU_CODE"
    );
    spu.write_reg(0x44, rom.len() as u32, &rom, &ram).unwrap();
    spu.write_reg(0x10c, 1, &rom, &ram).unwrap();
    assert_eq!(
        spu.write_reg(0, 1, &rom, &ram).unwrap_err().code,
        "GPU_BINDING"
    );
    spu.write_reg(0x10c, 0, &rom, &ram).unwrap();
    spu.write_reg(0, 1, &rom, &ram).unwrap();
    assert_eq!(spu.bindings()[0], (RAM_BASE, 2048, 3));
    spu.write_reg(0x50, RAM_BASE + 2, &rom, &ram).unwrap();
    assert_eq!(
        spu.block(&rom, &mut ram, false).unwrap_err().code,
        "SPU_OUTPUT"
    );
    assert_eq!(spu.status(), 3);
    assert_eq!(spu.blocks(), 0);
}

#[test]
fn reference_work_quota_faults_infinite_kernel() {
    let rom = rom(&[word(42, 0, 0, 0, 0), 0]);
    let mut ram = vec![0u8; 4096];
    let mut spu = Spu::new();
    configure(&mut spu, &rom, &ram);
    spu.write_reg(0, 1, &rom, &ram).unwrap();
    assert_eq!(
        spu.block(&rom, &mut ram, false).unwrap_err().code,
        "SPU_BUDGET"
    );
    assert_eq!(spu.last_ticks(), WORK_LIMIT as u32);
    assert_eq!(spu.status(), 3);
    assert!(spu.audio().is_empty());
    assert_eq!(spu.blocks(), 0);
}

#[test]
fn guest_ram_state_feedback_persists_between_blocks() {
    let rom = rom(&[
        word(35, 1, 0, 1, 0), // load u32 state
        word(1, 2, 0, 0, 0),
        1,
        word(5, 1, 1, 2, 0),  // increment
        word(36, 1, 0, 1, 0), // write state
        word(24, 3, 1, 0, 0), // convert to f32
        word(36, 3, 0, 0, 0), // write first PCM sample
        word(0, 0, 0, 0, 0),
    ]);
    let mut ram = vec![0u8; 4096];
    let mut spu = Spu::new();
    configure(&mut spu, &rom, &ram);
    for (offset, value) in [(0x110, RAM_BASE + 2048), (0x114, 4), (0x118, 3)] {
        spu.write_reg(offset, value, &rom, &ram).unwrap();
    }
    spu.write_reg(0, 1, &rom, &ram).unwrap();
    spu.block(&rom, &mut ram, false).unwrap();
    assert_eq!(spu.audio()[0], 1.0);
    spu.clear_audio();
    spu.block(&rom, &mut ram, false).unwrap();
    assert_eq!(spu.audio()[0], 1.0); // raw 2.0 is clamped at final output
    assert_eq!(u32::from_le_bytes(ram[2048..2052].try_into().unwrap()), 2);
    assert_eq!(spu.read_reg(0x238).unwrap(), BLOCK_FRAMES as u32);
    assert_eq!(spu.sample_count(), (BLOCK_FRAMES * 2) as u64);
}

#[test]
fn external_completion_and_reference_fallback_use_same_pending_job() {
    let rom = constant_kernel(0.5);
    let mut ram = vec![0u8; 4096];
    let mut spu = Spu::new();
    configure(&mut spu, &rom, &ram);
    spu.write_reg(0x200, 0x12345678, &rom, &ram).unwrap();
    spu.write_reg(0, 1, &rom, &ram).unwrap();
    spu.block(&rom, &mut ram, true).unwrap();
    assert!(spu.external_pending());
    assert_eq!(spu.status(), 2);
    assert_eq!(spu.read_dispatch_reg(0x100).unwrap(), 0x12345678);
    assert_eq!(spu.read_dispatch_reg(0x138).unwrap(), 0);
    assert_eq!(spu.read_dispatch_reg(0x13c).unwrap(), AUDIO_RATE);
    assert_eq!(spu.read_dispatch_reg(0x40).unwrap(), RAM_BASE);
    assert_eq!(
        spu.write_reg(0x200, 9, &rom, &ram).unwrap_err().code,
        "SPU_REGISTER"
    );
    ram[..4].copy_from_slice(&2.0f32.to_le_bytes());
    spu.complete_external(&ram).unwrap();
    assert!(!spu.external_pending());
    assert_eq!(spu.audio()[0], 1.0);
    assert_eq!(spu.peak(), 1.0);
    assert_eq!(spu.last_ticks(), 0);
    assert_eq!(spu.blocks(), 1);

    spu.clear_audio();
    ram[..4].fill(0);
    spu.block(&rom, &mut ram, true).unwrap();
    assert_eq!(spu.read_dispatch_reg(0x138).unwrap(), BLOCK_FRAMES as u32);
    spu.run_pending(&rom, &mut ram).unwrap();
    assert_eq!(spu.audio()[0], 0.5);
    assert_eq!(spu.last_ticks(), 24);
    assert_eq!(spu.blocks(), 2);
}

#[test]
fn external_nonfinite_output_faults_without_audio_publication() {
    let rom = rom(&[word(0, 0, 0, 0, 0)]);
    let mut ram = vec![0u8; 4096];
    let mut spu = Spu::new();
    configure(&mut spu, &rom, &ram);
    spu.write_reg(0, 1, &rom, &ram).unwrap();
    spu.block(&rom, &mut ram, true).unwrap();
    ram[4..8].copy_from_slice(&f32::NAN.to_le_bytes());
    assert_eq!(spu.complete_external(&ram).unwrap_err().code, "SPU_SAMPLE");
    assert_eq!(spu.status(), 3);
    assert!(!spu.external_pending());
    assert!(spu.audio().is_empty());
    assert_eq!(spu.blocks(), 0);
}
