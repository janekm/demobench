use db_contracts::RAM_BASE;
use db_gpu::Gpu;

fn word(op: u8, d: u32, a: u32, b: u32, c: u32) -> u32 {
    op as u32 | d << 8 | a << 13 | b << 18 | c << 23
}

fn code(words: &[u32]) -> Vec<u8> {
    words.iter().flat_map(|word| word.to_le_bytes()).collect()
}

fn setup(gpu: &mut Gpu, rom: &[u8], ram: &[u8], width: u32, height: u32, binding_len: u32) {
    gpu.write_reg(0, 0, rom, ram, 0).unwrap();
    gpu.write_reg(4, rom.len() as u32, rom, ram, 0).unwrap();
    gpu.write_reg(8, width, rom, ram, 0).unwrap();
    gpu.write_reg(12, height, rom, ram, 0).unwrap();
    gpu.write_reg(0x40, RAM_BASE, rom, ram, 0).unwrap();
    gpu.write_reg(0x44, binding_len, rom, ram, 0).unwrap();
    gpu.write_reg(0x48, 3, rom, ram, 0).unwrap();
}

fn finish(gpu: &mut Gpu, rom: &[u8], ram: &mut [u8]) -> Result<(), db_contracts::Fault> {
    while let Some(tick) = gpu.next_event() {
        gpu.event(tick, rom, ram)?;
    }
    Ok(())
}

#[test]
fn pending_timing_and_high_lane_store_wins() {
    let rom = code(&[
        word(3, 1, 3, 0, 0),  // lane ID
        word(36, 1, 0, 0, 0), // both lanes store at offset zero
        word(0, 0, 0, 0, 0),
    ]);
    let mut ram = [0u8; 8];
    let mut gpu = Gpu::new();
    setup(&mut gpu, &rom, &ram, 2, 1, 4);
    gpu.write_reg(16, 1, &rom, &ram, 100).unwrap();
    assert_eq!(gpu.next_event(), Some(116));
    assert_eq!(
        gpu.check_cpu_access(RAM_BASE, 4, false).unwrap_err().code,
        "GPU_LEASE"
    );
    assert_eq!(
        gpu.check_cpu_access(RAM_BASE, 4, true).unwrap_err().code,
        "GPU_LEASE"
    );
    gpu.event(116, &rom, &mut ram).unwrap();
    assert_eq!(gpu.next_event(), Some(120));
    gpu.event(120, &rom, &mut ram).unwrap();
    assert_eq!(gpu.next_event(), Some(121));
    gpu.event(121, &rom, &mut ram).unwrap();
    assert_eq!(ram[..4], [0; 4]); // store issue has no early effect
    assert_eq!(gpu.next_event(), Some(123));
    gpu.event(123, &rom, &mut ram).unwrap();
    assert_eq!(ram[..4], 1u32.to_le_bytes());
    finish(&mut gpu, &rom, &mut ram).unwrap();
    assert_eq!(gpu.status(), 2);
    assert_eq!(gpu.completed_invocations(), 2);
    assert_eq!(gpu.last_ticks(), 24);
    assert_eq!(gpu.completed_dispatches(), 1);
    gpu.check_cpu_access(RAM_BASE, 4, true).unwrap();
}

#[test]
fn issue_fault_discards_all_cohort_writes() {
    let rom = code(&[
        word(3, 1, 3, 0, 0), // lane ID
        word(1, 2, 0, 0, 0),
        4,
        word(7, 1, 1, 2, 0),  // offsets 0 and 4
        word(36, 1, 1, 0, 0), // lane 1 falls beyond four-byte binding
        word(0, 0, 0, 0, 0),
    ]);
    let mut ram = [0x7bu8; 8];
    let mut gpu = Gpu::new();
    setup(&mut gpu, &rom, &ram, 2, 1, 4);
    gpu.write_reg(16, 1, &rom, &ram, 0).unwrap();
    let error = finish(&mut gpu, &rom, &mut ram).unwrap_err();
    assert_eq!(error.code, "GPU_MEMORY");
    assert!(error.message.contains("lane 1"));
    assert!(error.message.contains("PC"));
    assert_eq!(ram, [0x7b; 8]);
    assert_eq!(gpu.status(), 3);
    assert_eq!(gpu.next_event(), None);
    gpu.check_cpu_access(RAM_BASE, 4, true).unwrap();
}

#[test]
fn divergent_pc_cohort_and_tail_lane() {
    let rom = code(&[
        word(3, 1, 3, 0, 0), // lane ID
        word(40, 1, 0, 0, 0),
        20, // lane zero jumps to store
        word(1, 2, 0, 0, 0),
        255, // lane one executes this first
        word(38, 2, 1, 0, 0),
        word(0, 0, 0, 0, 0),
    ]);
    let mut ram = [0u8; 2];
    let mut gpu = Gpu::new();
    setup(&mut gpu, &rom, &ram, 2, 1, 2);
    gpu.write_reg(16, 1, &rom, &ram, 0).unwrap();
    finish(&mut gpu, &rom, &mut ram).unwrap();
    assert_eq!(ram, [0, 255]);

    let rom = code(&[
        word(3, 1, 2, 0, 0),
        word(38, 1, 1, 0, 0),
        word(0, 0, 0, 0, 0),
    ]);
    let mut ram = [0u8; 65];
    let mut gpu = Gpu::new();
    setup(&mut gpu, &rom, &ram, 65, 1, 65);
    gpu.write_reg(16, 1, &rom, &ram, 0).unwrap();
    finish(&mut gpu, &rom, &mut ram).unwrap();
    assert_eq!(ram[63], 63);
    assert_eq!(ram[64], 64);
    assert_eq!(gpu.completed_invocations(), 65);
    assert_eq!(gpu.last_ticks(), 32); // 16 setup + 2 waves*(4 wave + 1 id + 2 stb + 1 end)
}

#[test]
fn validation_rejects_literal_targets_and_unexecuted_bad_fields() {
    let rom = code(&[word(42, 0, 0, 0, 0), 4, word(0, 0, 0, 0, 0)]);
    let ram = [0u8; 4];
    let mut gpu = Gpu::new();
    setup(&mut gpu, &rom, &ram, 1, 1, 4);
    assert_eq!(
        gpu.write_reg(16, 1, &rom, &ram, 0).unwrap_err().code,
        "GPU_BRANCH"
    );
    assert!(!gpu.busy());
    let rom = code(&[word(0, 0, 0, 0, 0), word(5, 1, 1, 1, 1)]);
    setup(&mut gpu, &rom, &ram, 1, 1, 4);
    assert_eq!(
        gpu.write_reg(16, 1, &rom, &ram, 0).unwrap_err().code,
        "GPU_OPERAND"
    );
}

#[test]
fn nonfinite_input_fault_and_sphere_hit() {
    let rom = code(&[
        word(1, 1, 0, 0, 0),
        f32::INFINITY.to_bits(),
        word(1, 2, 0, 0, 0),
        1f32.to_bits(),
        word(16, 3, 1, 2, 0),
        word(0, 0, 0, 0, 0),
    ]);
    let mut ram = [0u8; 4];
    let mut gpu = Gpu::new();
    setup(&mut gpu, &rom, &ram, 1, 1, 4);
    gpu.write_reg(16, 1, &rom, &ram, 0).unwrap();
    assert_eq!(
        finish(&mut gpu, &rom, &mut ram).unwrap_err().code,
        "GPU_FLOAT"
    );

    let mut words = Vec::new();
    for (register, value) in [
        (3, 0.0f32),
        (4, 0.0),
        (5, 1.0),
        (6, 0.0),
        (7, 0.0),
        (8, 5.0),
        (9, 1.0),
    ] {
        words.extend([word(1, register, 0, 0, 0), value.to_bits()]);
    }
    words.extend([
        word(34, 10, 0, 3, 6),
        word(36, 10, 0, 0, 0),
        word(0, 0, 0, 0, 0),
    ]);
    let rom = code(&words);
    let mut gpu = Gpu::new();
    setup(&mut gpu, &rom, &ram, 1, 1, 4);
    gpu.write_reg(16, 1, &rom, &ram, 0).unwrap();
    finish(&mut gpu, &rom, &mut ram).unwrap();
    assert_eq!(f32::from_le_bytes(ram), 4.0);
}

#[test]
fn infinite_loop_faults_at_exact_dispatch_budget() {
    let rom = code(&[word(42, 0, 0, 0, 0), 0]);
    let mut ram = [0u8; 4];
    let mut gpu = Gpu::new();
    setup(&mut gpu, &rom, &ram, 1, 1, 4);
    gpu.write_reg(16, 1, &rom, &ram, 0).unwrap();
    let mut last_tick = 0;
    let error = loop {
        let tick = gpu
            .next_event()
            .expect("loop remains busy until budget fault");
        assert!(
            tick > last_tick,
            "every pending event advances virtual time"
        );
        last_tick = tick;
        if let Err(error) = gpu.event(tick, &rom, &mut ram) {
            break error;
        }
    };
    assert_eq!(error.code, "GPU_BUDGET");
    assert_eq!(gpu.last_ticks(), 1_048_576);
    assert_eq!(gpu.status(), 3);
}

#[test]
fn rgb_clamps_and_ro_binding_allows_cpu_read() {
    let rom = code(&[
        word(1, 1, 0, 0, 0),
        (-0.5f32).to_bits(),
        word(1, 2, 0, 0, 0),
        (0.5f32).to_bits(),
        word(1, 3, 0, 0, 0),
        (2.0f32).to_bits(),
        word(39, 1, 0, 0, 0),
        word(0, 0, 0, 0, 0),
    ]);
    let mut ram = [0u8; 4];
    let mut gpu = Gpu::new();
    setup(&mut gpu, &rom, &ram, 1, 1, 3);
    gpu.write_reg(16, 1, &rom, &ram, 0).unwrap();
    finish(&mut gpu, &rom, &mut ram).unwrap();
    assert_eq!(ram[..3], [0, 127, 255]);

    let rom = code(&[word(0, 0, 0, 0, 0)]);
    let mut gpu = Gpu::new();
    gpu.write_reg(0, 0, &rom, &ram, 0).unwrap();
    gpu.write_reg(4, 4, &rom, &ram, 0).unwrap();
    gpu.write_reg(8, 1, &rom, &ram, 0).unwrap();
    gpu.write_reg(12, 1, &rom, &ram, 0).unwrap();
    gpu.write_reg(0x40, RAM_BASE, &rom, &ram, 0).unwrap();
    gpu.write_reg(0x44, 4, &rom, &ram, 0).unwrap();
    gpu.write_reg(0x48, 1, &rom, &ram, 0).unwrap();
    gpu.write_reg(16, 1, &rom, &ram, 0).unwrap();
    gpu.check_cpu_access(RAM_BASE, 4, false).unwrap();
    assert_eq!(
        gpu.check_cpu_access(RAM_BASE, 4, true).unwrap_err().code,
        "GPU_LEASE"
    );
}

#[test]
fn float_min_max_zero_ties_are_deterministic() {
    let rom = code(&[
        word(1, 1, 0, 0, 0),
        (-0.0f32).to_bits(),
        word(1, 2, 0, 0, 0),
        0.0f32.to_bits(),
        word(20, 3, 1, 2, 0),
        word(21, 4, 1, 2, 0),
        word(36, 3, 0, 0, 0),
        word(1, 5, 0, 0, 0),
        4,
        word(36, 4, 5, 0, 0),
        word(0, 0, 0, 0, 0),
    ]);
    let mut ram = [0u8; 8];
    let mut gpu = Gpu::new();
    setup(&mut gpu, &rom, &ram, 1, 1, 8);
    gpu.write_reg(16, 1, &rom, &ram, 0).unwrap();
    finish(&mut gpu, &rom, &mut ram).unwrap();
    assert_eq!(
        u32::from_le_bytes(ram[..4].try_into().unwrap()),
        (-0.0f32).to_bits()
    );
    assert_eq!(
        u32::from_le_bytes(ram[4..8].try_into().unwrap()),
        0.0f32.to_bits()
    );
}
