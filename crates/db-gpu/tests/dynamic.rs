use db_contracts::RAM_BASE;
use db_gpu::Gpu;

fn code(value: u32) -> Vec<u8> {
    [1u32 | 1 << 8, value, 36 | 1 << 8, 0]
        .iter()
        .flat_map(|v| v.to_le_bytes())
        .collect()
}
fn configure(gpu: &mut Gpu, ram: &[u8], base: u32, length: u32) {
    for (offset, value) in [
        (0, base),
        (4, length),
        (8, 1),
        (12, 1),
        (64, RAM_BASE + 8192),
        (68, 4),
        (72, 3),
    ] {
        gpu.write_reg(offset, value, &[], ram, 0).unwrap();
    }
}
fn finish(gpu: &mut Gpu, ram: &mut [u8]) {
    while let Some(tick) = gpu.next_event() {
        gpu.event(tick, &[], ram).unwrap();
    }
}

#[test]
fn ram_code_is_opt_in_and_snapshotted_each_dispatch() {
    let mut ram = vec![0; 131072];
    ram[..16].copy_from_slice(&code(17));
    let mut old = Gpu::new();
    configure(&mut old, &ram, RAM_BASE, 16);
    assert_eq!(
        old.write_reg(16, 1, &[], &ram, 0).unwrap_err().code,
        "GPU_CODE"
    );
    let mut gpu = Gpu::new_dynamic();
    configure(&mut gpu, &ram, RAM_BASE, 16);
    gpu.write_reg(16, 1, &[], &ram, 0).unwrap();
    // No code lease is held: CPU edits affect the next submission only.
    gpu.check_cpu_access(RAM_BASE + 4, 4, true).unwrap();
    ram[..16].copy_from_slice(&code(29));
    finish(&mut gpu, &mut ram);
    assert_eq!(ram[8192], 17);
    gpu.write_reg(16, 1, &[], &ram, 100).unwrap();
    finish(&mut gpu, &mut ram);
    assert_eq!(ram[8192], 29);
    ram[..4].copy_from_slice(&u32::MAX.to_le_bytes());
    assert_eq!(
        gpu.write_reg(16, 1, &[], &ram, 200).unwrap_err().code,
        "GPU_OPCODE"
    );
}

#[test]
fn dynamic_code_ranges_and_branch_boundaries_are_checked() {
    let mut ram = vec![0; 131072];
    for (base, length) in [
        (RAM_BASE - 4, 8),
        (RAM_BASE + 1, 4),
        (0x2fffc, 8),
        (RAM_BASE, 65540),
        (RAM_BASE, 0),
        (u32::MAX - 3, 16),
    ] {
        let mut gpu = Gpu::new_dynamic();
        configure(&mut gpu, &ram, base, length);
        assert_eq!(
            gpu.write_reg(16, 1, &[], &ram, 0).unwrap_err().code,
            "GPU_CODE"
        );
    }
    // 64 KiB is permitted; the existing compute work budget remains independent.
    let mut gpu = Gpu::new_dynamic();
    configure(&mut gpu, &ram, RAM_BASE, 65536);
    gpu.write_reg(16, 1, &[], &ram, 0).unwrap();
    finish(&mut gpu, &mut ram);
    // A branch to its literal word is never an instruction boundary.
    ram[..4].copy_from_slice(&42u32.to_le_bytes());
    ram[4..8].copy_from_slice(&(RAM_BASE + 4).to_le_bytes());
    let mut gpu = Gpu::new_dynamic();
    configure(&mut gpu, &ram, RAM_BASE, 8);
    assert!(gpu.write_reg(16, 1, &[], &ram, 0).is_err());
}
