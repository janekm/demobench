use db_contracts::RAM_BASE;
use db_spu::Spu;

fn configure(spu: &mut Spu, ram: &[u8]) {
    for (offset, value) in [
        (0x40, RAM_BASE),
        (0x44, 16),
        (0x48, 1),
        (0x4c, 1),
        (0x50, RAM_BASE + 4096),
        (0x100, RAM_BASE + 4096),
        (0x104, 2048),
        (0x108, 3),
    ] {
        spu.write_reg(offset, value, &[], ram).unwrap();
    }
}

#[test]
fn audio_snapshots_each_block_and_fallback_uses_original_snapshot() {
    let mut ram = vec![0; 131072];
    let code: Vec<u8> = [1u32 | 1 << 8, 0.25f32.to_bits(), 36 | 1 << 8, 0]
        .iter()
        .flat_map(|v| v.to_le_bytes())
        .collect();
    ram[..16].copy_from_slice(&code);
    let mut old = Spu::new();
    configure(&mut old, &ram);
    assert!(old.write_reg(0, 1, &[], &ram).is_err());
    let mut spu = Spu::new_dynamic();
    configure(&mut spu, &ram);
    spu.write_reg(0, 1, &[], &ram).unwrap();
    spu.block(&[], &mut ram, true).unwrap();
    ram[4..8].copy_from_slice(&0.5f32.to_bits().to_le_bytes());
    spu.run_pending(&[], &mut ram).unwrap();
    assert_eq!(spu.audio()[0], 0.25);
    spu.clear_audio();
    spu.block(&[], &mut ram, false).unwrap();
    assert_eq!(spu.audio()[0], 0.5);
    ram[..4].copy_from_slice(&u32::MAX.to_le_bytes());
    assert!(spu.block(&[], &mut ram, false).is_err());
    assert_eq!(spu.status(), 3);
}
