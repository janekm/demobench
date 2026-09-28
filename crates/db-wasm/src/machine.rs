use db_contracts::*;
use db_core::Cpu;
use db_gpu::Gpu;
use db_spu::Spu;
use db_video::Video;

#[derive(Clone, Debug)]
struct Store {
    address: u32,
    width: u32,
    value: u32,
}
#[derive(Debug)]
struct Pending {
    cpu: Cpu,
    store: Option<Store>,
    clock_high: u32,
    at: u64,
    origin_pc: u32,
}

pub struct Machine {
    pub cpu: Cpu,
    pub video: Video,
    pub gpu: Gpu,
    pub spu: Spu,
    pub profile: u32,
    pub ram: Vec<u8>,
    pub rom: Vec<u8>,
    pub tick: u64,
    pub instructions: u64,
    pub error: String,
    external_gpu: bool,
    external_spu: bool,
    external_gpu_pending: bool,
    external_wake_pending: bool,
    loaded: bool,
    clock_high: u32,
    pending: Option<Pending>,
    next_line: u32,
    next_line_tick: u64,
    next_spu_tick: u64,
}

impl Default for Machine {
    fn default() -> Self {
        Self::new()
    }
}
impl Machine {
    pub fn new() -> Self {
        Self {
            cpu: Cpu::new(0),
            video: Video::new(),
            gpu: Gpu::new(),
            spu: Spu::new(),
            profile: 1,
            ram: vec![0; RAM_SIZE],
            rom: Vec::new(),
            tick: 0,
            instructions: 0,
            error: String::new(),
            external_gpu: false,
            external_spu: false,
            external_gpu_pending: false,
            external_wake_pending: false,
            loaded: false,
            clock_high: 0,
            pending: None,
            next_line: 0,
            next_line_tick: 0,
            next_spu_tick: AUDIO_BLOCK_TICKS,
        }
    }

    pub fn load(&mut self, cartridge: &[u8]) -> Result<(), String> {
        let entry = validate_cartridge(cartridge)?;
        *self = Self::new();
        self.profile = u32::from_le_bytes(cartridge[4..8].try_into().unwrap());
        if self.profile == 4 {
            self.gpu = Gpu::new_dynamic();
            self.spu = Spu::new_dynamic();
        }
        self.rom.extend_from_slice(&cartridge[HEADER_SIZE..]);
        self.cpu = Cpu::new(entry);
        self.loaded = true;
        self.video_event()?;
        Ok(())
    }

    pub fn status(&self) -> u32 {
        if !self.error.is_empty() {
            3
        } else if !self.loaded {
            0
        } else if self.cpu.halted {
            2
        } else if self.cpu.waiting {
            4
        } else {
            1
        }
    }

    pub fn gpu_external_pending(&self) -> bool {
        self.external_gpu_pending
    }

    pub fn spu_external_pending(&self) -> bool {
        self.spu.external_pending()
    }

    pub fn set_spu_external(&mut self, enabled: u32) -> Result<(), String> {
        if enabled > 1 {
            return Err("external SPU mode requires 0 or 1".into());
        }
        if self.spu.external_pending() {
            return Err("complete or fall back the pending SPU block first".into());
        }
        self.external_spu = enabled == 1;
        Ok(())
    }

    pub fn spu_external_complete(&mut self) -> Result<(), String> {
        self.spu
            .complete_external(&self.ram)
            .map_err(|e| self.fail(self.cpu.pc, e))?;
        self.finish_spu_event()
    }

    pub fn spu_external_fallback(&mut self) -> Result<(), String> {
        self.external_spu = false;
        self.spu
            .run_pending(&self.rom, &mut self.ram)
            .map_err(|e| self.fail(self.cpu.pc, e))?;
        self.finish_spu_event()
    }

    fn finish_spu_event(&mut self) -> Result<(), String> {
        // An external audio block suspends this tick before simultaneous scanout.
        if self.next_line_tick == self.tick {
            self.video_event()?;
        }
        Ok(())
    }

    pub fn set_gpu_external(&mut self, enabled: u32) -> Result<(), String> {
        if enabled > 1 {
            return Err("external GPU mode requires 0 or 1".into());
        }
        if enabled == 1 && self.gpu.busy() && !self.external_gpu_pending {
            return Err("cannot intercept an already-running GPU dispatch".into());
        }
        self.external_gpu = enabled == 1;
        if !self.external_gpu {
            // The original validated START remains scheduled at tick+16.
            // Call this before copying external output into RAM when falling back.
            self.external_gpu_pending = false;
        }
        Ok(())
    }

    pub fn gpu_external_complete(&mut self) -> Result<(), String> {
        if !self.external_gpu_pending {
            return Err("no external GPU dispatch is pending".into());
        }
        self.gpu
            .external_complete(self.tick)
            .map_err(|e| e.to_string())?;
        self.external_gpu_pending = false;
        self.cpu.waiting = false;
        self.external_wake_pending = true;
        Ok(())
    }

    pub fn gpu_external_fail(&mut self) -> Result<(), String> {
        if !self.external_gpu_pending {
            return Err("no external GPU dispatch is pending".into());
        }
        self.gpu
            .external_fail(self.tick)
            .map_err(|e| e.to_string())?;
        self.external_gpu_pending = false;
        self.cpu.waiting = false;
        self.external_wake_pending = true;
        Ok(())
    }

    fn fail(&mut self, pc: u32, fault: impl std::fmt::Display) -> String {
        self.error = format!("tick {} / PC 0x{pc:08x}: {fault}", self.tick);
        self.pending = None;
        self.error.clone()
    }

    fn video_event(&mut self) -> Result<(), String> {
        let published = self
            .video
            .line_event(self.next_line, &self.ram)
            .map_err(|e| self.fail(self.cpu.pc, e))?;
        if published {
            self.cpu.waiting = false;
        }
        self.next_line = (self.next_line + 1) % 128;
        self.next_line_tick += LINE_TICKS;
        Ok(())
    }

    pub fn run(&mut self, ticks: u32) -> Result<u32, String> {
        if ticks as u64 > FRAME_TICKS * 10 {
            return Err("run slice exceeds 10 frames".into());
        }
        if !self.loaded {
            return Err("load a cartridge before running".into());
        }
        if !self.error.is_empty() {
            return Err(self.error.clone());
        }
        if self.external_gpu_pending || self.spu.external_pending() {
            return Ok(self.status());
        }
        let end = self
            .tick
            .checked_add(ticks as u64)
            .ok_or("virtual clock overflow")?;
        while self.tick < end {
            if self.pending.is_none() && !self.cpu.halted && !self.cpu.waiting {
                let origin_pc = self.cpu.pc;
                let mut next_cpu = self.cpu.clone();
                let mut bus = StepBus {
                    rom: &self.rom,
                    ram: &self.ram,
                    video: &self.video,
                    gpu: &self.gpu,
                    spu: &self.spu,
                    profile: self.profile,
                    tick: self.tick,
                    clock_high: self.clock_high,
                    store: None,
                };
                let result = next_cpu.step(&mut bus);
                let store = bus.store.take();
                match result {
                    Ok(cost) if cost > 0 => {
                        self.pending = Some(Pending {
                            cpu: next_cpu,
                            store,
                            clock_high: bus.clock_high,
                            at: self.tick + cost as u64,
                            origin_pc,
                        })
                    }
                    Ok(_) => return Err(self.fail(origin_pc, "CPU returned zero instruction cost")),
                    Err(e) => return Err(self.fail(origin_pc, e)),
                }
            }
            let commit_tick = self.pending.as_ref().map(|p| p.at).unwrap_or(u64::MAX);
            let gpu_tick = self.gpu.next_event().unwrap_or(u64::MAX);
            let spu_tick = if self.profile >= 3 {
                self.next_spu_tick
            } else {
                u64::MAX
            };
            self.tick = end
                .min(self.next_line_tick)
                .min(commit_tick)
                .min(gpu_tick)
                .min(spu_tick);
            if commit_tick == self.tick {
                let pending = self.pending.take().expect("pending instruction");
                if let Some(store) = pending.store {
                    if let Err(e) = self.commit_store(store) {
                        return Err(self.fail(pending.origin_pc, e));
                    }
                }
                self.cpu = pending.cpu;
                self.clock_high = pending.clock_high;
                self.instructions += 1;
                // External completion occurs at the START tick, before the
                // guest's next instruction. A directly following WFI consumes
                // that completion wake instead of sleeping until vblank.
                if self.external_wake_pending {
                    self.cpu.waiting = false;
                    self.external_wake_pending = false;
                }
            }
            // CPU stores, GPU writes, SPU block, then video scanout.
            // GPU events issue their next instruction only after committing this one.
            if self.gpu.next_event() == Some(self.tick) {
                let was_busy = self.gpu.busy();
                if let Err(e) = self.gpu.event(self.tick, &self.rom, &mut self.ram) {
                    return Err(self.fail(self.cpu.pc, e));
                }
                if was_busy && !self.gpu.busy() {
                    self.cpu.waiting = false;
                }
            }
            if spu_tick == self.tick {
                if self.spu.enabled() {
                    if self.profile == 4 {
                        let (base, len) = self.spu.code_range();
                        if let Err(e) = self.gpu.check_cpu_access(base, len, false) {
                            return Err(self.fail(self.cpu.pc, e));
                        }
                    }
                    for (base, len, flags) in self.spu.bindings() {
                        if flags != 0 {
                            if let Err(e) = self.gpu.check_cpu_access(base, len, flags & 2 != 0) {
                                return Err(self.fail(self.cpu.pc, e));
                            }
                        }
                    }
                }
                if let Err(e) = self.spu.block(&self.rom, &mut self.ram, self.external_spu) {
                    return Err(self.fail(self.cpu.pc, e));
                }
                self.next_spu_tick += AUDIO_BLOCK_TICKS;
                if self.spu.external_pending() {
                    return Ok(self.status());
                }
            }
            if self.next_line_tick == self.tick {
                self.video_event()?;
            }
            if self.external_gpu_pending || self.spu.external_pending() {
                return Ok(self.status());
            }
        }
        Ok(self.status())
    }

    fn commit_store(&mut self, store: Store) -> Result<(), Fault> {
        self.gpu
            .check_cpu_access(store.address, store.width, true)?;
        if let Some(offset) = ram_offset(store.address, store.width)? {
            self.ram[offset..offset + store.width as usize]
                .copy_from_slice(&store.value.to_le_bytes()[..store.width as usize]);
            Ok(())
        } else if (VIDEO_BASE..VIDEO_BASE + 0x1000).contains(&store.address) {
            self.video
                .write_reg(store.address - VIDEO_BASE, store.value)
        } else if self.profile >= 2 && (GPU_BASE..GPU_BASE + 0x1000).contains(&store.address) {
            self.gpu.write_reg(
                store.address - GPU_BASE,
                store.value,
                &self.rom,
                &self.ram,
                self.tick,
            )?;
            if self.external_gpu && store.address == GPU_BASE + 16 && self.gpu.busy() {
                self.external_gpu_pending = true;
            }
            Ok(())
        } else if self.profile >= 3 && (SPU_BASE..SPU_BASE + 0x1000).contains(&store.address) {
            if self.profile == 4 && store.address == SPU_BASE && store.value == 1 {
                let (base, len) = self.spu.code_range();
                self.gpu.check_cpu_access(base, len, false)?;
            }
            self.spu
                .write_reg(store.address - SPU_BASE, store.value, &self.rom, &self.ram)
        } else {
            Err(Fault::new(
                "write",
                store.address,
                "unmapped or read-only address",
            ))
        }
    }
}

fn aligned(address: u32, width: u32) -> Result<(), Fault> {
    if !matches!(width, 1 | 2 | 4) || address % width != 0 {
        return Err(Fault::new(
            "alignment",
            address,
            format!("invalid {width}-byte access"),
        ));
    }
    Ok(())
}
fn ram_offset(address: u32, width: u32) -> Result<Option<usize>, Fault> {
    aligned(address, width)?;
    if address >= RAM_BASE && address < RAM_BASE + RAM_SIZE as u32 {
        let offset = (address - RAM_BASE) as usize;
        if offset + width as usize > RAM_SIZE {
            return Err(Fault::new("bounds", address, "access crosses RAM boundary"));
        }
        return Ok(Some(offset));
    }
    Ok(None)
}
fn read_bytes(bytes: &[u8], offset: usize, width: u32) -> u32 {
    let mut word = [0u8; 4];
    word[..width as usize].copy_from_slice(&bytes[offset..offset + width as usize]);
    u32::from_le_bytes(word)
}

struct StepBus<'a> {
    rom: &'a [u8],
    ram: &'a [u8],
    video: &'a Video,
    gpu: &'a Gpu,
    spu: &'a Spu,
    profile: u32,
    tick: u64,
    clock_high: u32,
    store: Option<Store>,
}
impl Bus for StepBus<'_> {
    fn read(&mut self, address: u32, width: u32) -> Result<u32, Fault> {
        aligned(address, width)?;
        self.gpu.check_cpu_access(address, width, false)?;
        if let Some(offset) = ram_offset(address, width)? {
            return Ok(read_bytes(self.ram, offset, width));
        }
        if (address as u64) + width as u64 <= self.rom.len() as u64 {
            return Ok(read_bytes(self.rom, address as usize, width));
        }
        if (SYS_BASE..SYS_BASE + 0x1000).contains(&address) {
            if width != 4 {
                return Err(Fault::new(
                    "mmio-width",
                    address,
                    "MMIO requires a 32-bit access",
                ));
            }
            return match address - SYS_BASE {
                0 => Ok(0xdb32_0000 | self.profile),
                4 => Ok(self.profile),
                8 => {
                    self.clock_high = (self.tick >> 32) as u32;
                    Ok(self.tick as u32)
                }
                12 => Ok(self.clock_high),
                16 => Ok(self.video.frame_count()),
                20 => Ok(1),
                _ => Err(Fault::new("register", address, "unknown system register")),
            };
        }
        if (VIDEO_BASE..VIDEO_BASE + 0x1000).contains(&address) {
            if width != 4 {
                return Err(Fault::new(
                    "mmio-width",
                    address,
                    "MMIO requires a 32-bit access",
                ));
            }
            return self.video.read_reg(address - VIDEO_BASE);
        }
        if self.profile >= 2 && (GPU_BASE..GPU_BASE + 0x1000).contains(&address) {
            if width != 4 {
                return Err(Fault::new(
                    "mmio-width",
                    address,
                    "MMIO requires a 32-bit access",
                ));
            }
            return self.gpu.read_reg(address - GPU_BASE);
        }
        if self.profile >= 3 && (SPU_BASE..SPU_BASE + 0x1000).contains(&address) {
            if width != 4 {
                return Err(Fault::new(
                    "mmio-width",
                    address,
                    "MMIO requires a 32-bit access",
                ));
            }
            return self.spu.read_reg(address - SPU_BASE);
        }
        Err(Fault::new("read", address, "unmapped address"))
    }
    fn write(&mut self, address: u32, width: u32, value: u32) -> Result<(), Fault> {
        aligned(address, width)?;
        self.gpu.check_cpu_access(address, width, true)?;
        if ram_offset(address, width)?.is_none() {
            let gpu_address = self.profile >= 2 && (GPU_BASE..GPU_BASE + 0x1000).contains(&address);
            let video_address = (VIDEO_BASE..VIDEO_BASE + 0x1000).contains(&address);
            let spu_address = self.profile >= 3 && (SPU_BASE..SPU_BASE + 0x1000).contains(&address);
            if !video_address && !gpu_address && !spu_address {
                return Err(Fault::new(
                    "write",
                    address,
                    "unmapped or read-only address",
                ));
            }
            if width != 4 {
                return Err(Fault::new(
                    "mmio-width",
                    address,
                    "MMIO requires a 32-bit access",
                ));
            }
            if video_address && !matches!(address - VIDEO_BASE, 0 | 4 | 8 | 12 | 16 | 20 | 40) {
                return Err(Fault::new(
                    "register",
                    address,
                    "unknown or read-only video register",
                ));
            }
        }
        if self.store.is_some() {
            return Err(Fault::new(
                "internal",
                address,
                "more than one store per instruction",
            ));
        }
        self.store = Some(Store {
            address,
            width,
            value,
        });
        Ok(())
    }
    fn fetch(&mut self, address: u32) -> Result<u32, Fault> {
        aligned(address, 4)?;
        self.gpu.check_cpu_access(address, 4, false)?;
        if let Some(offset) = ram_offset(address, 4)? {
            return Ok(read_bytes(self.ram, offset, 4));
        }
        if address as u64 + 4 <= self.rom.len() as u64 {
            return Ok(read_bytes(self.rom, address as usize, 4));
        }
        Err(Fault::new(
            "fetch",
            address,
            "instruction outside executable ROM/RAM",
        ))
    }
}

pub fn validate_cartridge(bytes: &[u8]) -> Result<u32, String> {
    if bytes.len() < HEADER_SIZE {
        return Err("cartridge header is truncated".into());
    }
    if &bytes[..4] != b"DB32" {
        return Err("cartridge magic must be DB32".into());
    }
    let word = |at| u32::from_le_bytes(bytes[at..at + 4].try_into().unwrap());
    if !matches!(word(4), 1 | 2 | 3 | 4) {
        return Err("unsupported cartridge profile version".into());
    }
    let length = word(8) as usize;
    let entry = word(12);
    if length == 0 || length > CART_LIMIT {
        return Err("payload must contain 1..4096 bytes".into());
    }
    if bytes.len() != HEADER_SIZE + length {
        return Err("cartridge length does not match header".into());
    }
    if bytes[16..HEADER_SIZE].iter().any(|&b| b != 0) {
        return Err("reserved cartridge header bytes must be zero".into());
    }
    if entry % 4 != 0 || entry as u64 + 4 > length as u64 {
        return Err("entry must address a complete aligned instruction".into());
    }
    Ok(entry)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn load(source: &str) -> Machine {
        let assembly = db_asm::assemble(source).unwrap();
        let mut machine = Machine::new();
        machine.load(&assembly.cartridge).unwrap();
        machine
    }
    #[test]
    fn pending_store_is_committed_at_completion() {
        let mut m = load("li r1, 0x10000\naddi r2, r0, 42\nsw r2, 0(r1)\nhalt");
        m.run(4).unwrap(); // three 1-tick instructions, then first store tick
        assert_eq!(m.ram[0], 0);
        assert_eq!(m.cpu.pc, 12);
        m.run(1).unwrap();
        assert_eq!(m.ram[0], 42);
        assert_eq!(m.cpu.pc, 16);
    }
    #[test]
    fn chunking_does_not_change_guest_state_or_frame() {
        let src = "li r1, 0x10000\naddi r2, r0, 7\nloop: sw r2, 0(r1)\naddi r2, r2, 1\nj loop";
        let mut a = load(src);
        let mut b = load(src);
        a.run(204800).unwrap();
        for _ in 0..2048 {
            b.run(100).unwrap();
        }
        assert_eq!(a.ram, b.ram);
        assert_eq!(a.cpu.regs, b.cpu.regs);
        assert_eq!(a.cpu.pc, b.cpu.pc);
        assert_eq!(a.video.frame(), b.video.frame());
    }
    #[test]
    fn halt_keeps_scanout_running_and_wfi_wakes_at_vblank() {
        let mut m = load("wfi\naddi r1, r0, 9\nhalt");
        m.run(191999).unwrap();
        assert_eq!(m.cpu.regs[1], 0);
        assert_eq!(m.status(), 4);
        m.run(1).unwrap();
        assert_eq!(m.video.frame_count(), 1);
        assert_eq!(m.status(), 1);
        m.run(2).unwrap();
        assert_eq!(m.cpu.regs[1], 9);
        assert_eq!(m.status(), 2);
        m.run(FRAME_TICKS as u32).unwrap();
        assert_eq!(m.video.frame_count(), 2);
    }
    #[test]
    fn guest_cannot_write_rom_or_access_missing_gpu() {
        for source in ["sw r0, 0(r0)", "li r1, 0xf3000\nlw r2, 0(r1)"] {
            let mut m = load(source);
            assert!(m.run(30).is_err());
            assert_eq!(m.status(), 3);
        }
    }
    #[test]
    fn cartridge_rejects_reserved_header_and_trailing_data() {
        let a = db_asm::assemble("halt").unwrap();
        let mut bad = a.cartridge.clone();
        bad[16] = 1;
        assert!(validate_cartridge(&bad).is_err());
        let mut bad = a.cartridge.clone();
        bad.push(0);
        assert!(validate_cartridge(&bad).is_err());
    }
    #[test]
    fn clock_read_latch_waits_for_instruction_commit() {
        let mut m = load("lw r2, 8(r1)\nhalt");
        m.cpu.regs[1] = SYS_BASE;
        m.tick = 0x1_0000_0000;
        m.next_line_tick = m.tick + LINE_TICKS;
        m.run(3).unwrap();
        assert_eq!(m.clock_high, 0);
        assert_eq!(m.cpu.pc, 0);
        m.run(1).unwrap();
        assert_eq!(m.clock_high, 1);
        assert_eq!(m.cpu.pc, 4);
    }

    fn gpu_machine(cpu: &str, kernel: &str, length: u32, flags: u32) -> Machine {
        let source = format!(".profile gpu-1\n{cpu}\nkernel:\n{kernel}");
        let mut m = load(&source);
        let code = db_asm::assemble(cpu).unwrap().payload_len as u32;
        for (offset, value) in [
            (0, code),
            (4, length),
            (8, 1),
            (12, 1),
            (0x40, RAM_BASE),
            (0x44, 4),
            (0x48, flags),
            (16, 1),
        ] {
            m.gpu.write_reg(offset, value, &m.rom, &m.ram, 0).unwrap();
        }
        m
    }

    #[test]
    fn gpu_pending_store_and_completion_wake_have_exact_ticks() {
        let mut m = gpu_machine("wfi\nhalt", "g.li g1, 42\ng.stb g1, g0, 0\ng.end", 16, 3);
        m.run(22).unwrap(); // setup20, li1, first half of 2-tick store
        assert_eq!(m.ram[0], 0);
        assert!(m.cpu.waiting);
        m.run(1).unwrap();
        assert_eq!(m.ram[0], 42);
        assert!(m.gpu.busy());
        m.run(1).unwrap(); // END, before the next CPU instruction
        assert!(!m.cpu.waiting);
        assert!(!m.cpu.halted);
        assert_eq!(m.gpu.completed_dispatches(), 1);
        assert_eq!(m.gpu.last_ticks(), 24);
        m.run(1).unwrap();
        assert!(m.cpu.halted);
    }

    #[test]
    fn gpu_host_slices_preserve_state_pixels_and_completion() {
        let make = || gpu_machine("wfi\nhalt", "g.li g1, 93\ng.stb g1, g0, 0\ng.end", 16, 3);
        let mut a = make();
        let mut b = make();
        a.run(2000).unwrap();
        for _ in 0..2000 {
            b.run(1).unwrap();
        }
        assert_eq!(a.ram, b.ram);
        assert_eq!(a.cpu.regs, b.cpu.regs);
        assert_eq!(a.cpu.pc, b.cpu.pc);
        assert_eq!(a.gpu.last_ticks(), b.gpu.last_ticks());
        assert_eq!(a.video.frame(), b.video.frame());
    }

    #[test]
    fn gpu_bindings_protect_cpu_reads_writes_and_instruction_fetches() {
        for (cpu, flags) in [
            ("li r1, 0x10000\nlw r2, 0(r1)\nhalt", 3),
            ("li r1, 0x10000\nsw r0, 0(r1)\nhalt", 3),
            ("li r1, 0x10000\nsw r0, 0(r1)\nhalt", 1),
            ("li r1, 0x10000\njalr r0, 0(r1)", 3),
        ] {
            let mut m = gpu_machine(cpu, "g.end", 4, flags);
            assert!(m.run(100).unwrap_err().contains("GPU_LEASE"));
        }
        let mut m = gpu_machine("li r1, 0x10000\nlw r2, 0(r1)\nhalt", "g.end", 4, 1);
        m.run(100).unwrap();
        assert_eq!(m.cpu.regs[2], 0);
        assert_eq!(m.gpu.completed_dispatches(), 1); // HALT did not stop the GPU
    }

    #[test]
    fn gpu_budget_fault_commits_at_deadline_without_stalling_scheduler() {
        let mut m = gpu_machine("wfi\nhalt", "loop: g.jmp loop", 8, 3);
        m.run(1_048_575).unwrap();
        assert!(m.gpu.busy());
        assert!(m.run(1).unwrap_err().contains("GPU_BUDGET"));
        assert_eq!(m.tick, 1_048_576);
        assert_eq!(m.status(), 3);
    }

    #[test]
    fn gpu_profile_identity_and_legacy_cartridges_are_distinct() {
        for (profile, directive) in [
            (1, ""),
            (2, ".profile gpu-1\n"),
            (3, ".profile spu-1\n"),
            (4, ".profile dynamic-1\n"),
        ] {
            let mut m = load(&format!(
                "{directive}li r1, 0xf0000\nlw r2, 0(r1)\nlw r3, 4(r1)\nhalt"
            ));
            m.run(30).unwrap();
            assert_eq!(m.profile, profile);
            assert_eq!(m.cpu.regs[2], 0xdb32_0000 | profile);
            assert_eq!(m.cpu.regs[3], profile);
        }
    }

    fn spu_machine() -> Machine {
        let mut m = load(".profile spu-1\nhalt\ng.id g1,2\ng.li g2,8\ng.mul g1,g1,g2\ng.fli g3,0.25\ng.st g3,g1,0\ng.li g2,4\ng.add g1,g1,g2\ng.fli g3,-0.25\ng.st g3,g1,0\ng.end");
        for (offset, value) in [
            (0x40, 4),
            (0x44, m.rom.len() as u32 - 4),
            (0x48, 128),
            (0x4c, 2),
            (0x50, RAM_BASE),
            (0x100, RAM_BASE),
            (0x104, 2048),
            (0x108, 3),
            (0, 1),
        ] {
            m.spu.write_reg(offset, value, &m.rom, &m.ram).unwrap();
        }
        m
    }

    #[test]
    fn spu_clock_and_host_slices_preserve_pcm_after_cpu_halt() {
        let mut a = spu_machine();
        a.run((AUDIO_BLOCK_TICKS - 1) as u32).unwrap();
        assert!(a.spu.audio().is_empty());
        a.run(1).unwrap();
        assert!(a.cpu.halted);
        assert_eq!(a.spu.sample_count(), 256);
        assert_eq!(a.spu.audio().len(), 512);
        assert_eq!(&a.spu.audio()[..4], &[0.25, -0.25, 0.25, -0.25]);
        a.run(AUDIO_BLOCK_TICKS as u32).unwrap();
        let mut b = spu_machine();
        for _ in 0..1024 {
            b.run(128).unwrap();
        }
        assert_eq!(a.tick, b.tick);
        assert_eq!(a.spu.audio(), b.spu.audio());
        assert_eq!(a.ram, b.ram);
    }

    #[test]
    fn spu_external_block_yields_exactly_then_fallback_resumes() {
        let mut m = spu_machine();
        m.set_spu_external(1).unwrap();
        m.run(FRAME_TICKS as u32).unwrap();
        assert_eq!(m.tick, AUDIO_BLOCK_TICKS);
        assert!(m.spu_external_pending());
        assert!(m.spu.audio().is_empty());
        m.run(100).unwrap();
        assert_eq!(m.tick, AUDIO_BLOCK_TICKS);
        m.spu_external_fallback().unwrap();
        assert_eq!(&m.spu.audio()[..2], &[0.25, -0.25]);
        m.run((FRAME_TICKS - m.tick) as u32).unwrap();
        assert_eq!(m.tick, FRAME_TICKS);
        assert_eq!(m.spu.sample_count(), 768);
        assert!(!m.spu_external_pending());
    }

    #[test]
    fn spu_mmio_is_profile_gated_and_conflicting_gpu_leases_fault() {
        for directive in ["", ".profile gpu-1\n"] {
            let mut m = load(&format!("{directive}li r1,0xf6000\nlw r2,8(r1)\nhalt"));
            assert!(m.run(20).is_err());
        }
        let mut m = spu_machine();
        m.run((AUDIO_BLOCK_TICKS - 1) as u32).unwrap();
        for (offset, value) in [
            (0, 4),
            (4, m.rom.len() as u32 - 4),
            (8, 128),
            (12, 2),
            (0x40, RAM_BASE),
            (0x44, 2048),
            (0x48, 3),
            (16, 1),
        ] {
            m.gpu
                .write_reg(offset, value, &m.rom, &m.ram, m.tick)
                .unwrap();
        }
        assert!(m.run(1).unwrap_err().contains("GPU_LEASE"));
        assert!(m.spu.audio().is_empty());
    }

    #[test]
    fn external_spu_completes_before_simultaneous_video_event() {
        // Every 25th audio block coincides with the first scanline after eight frames.
        for fallback in [false, true] {
            let mut m = spu_machine();
            let boundary = AUDIO_BLOCK_TICKS * 25;
            m.run((boundary - 1) as u32).unwrap();
            assert_eq!(m.next_line_tick, boundary);
            assert_eq!(m.next_line, 0);
            m.set_spu_external(1).unwrap();
            m.run(1).unwrap();
            assert!(m.spu.external_pending());
            assert_eq!(m.next_line, 0, "scanout waits for the pending block");
            if fallback {
                m.spu_external_fallback().unwrap();
            } else {
                // Previous block already left valid PCM in the same output range.
                m.spu_external_complete().unwrap();
            }
            assert_eq!(m.tick, boundary);
            assert_eq!(m.next_line, 1);
            assert_eq!(m.next_line_tick, boundary + LINE_TICKS);
            assert_eq!(m.spu.blocks(), 25);
            m.run(1).unwrap();
            assert_eq!(m.next_line, 1, "completion must not replay scanout");
        }
    }

    fn external_source() -> &'static str {
        ".profile gpu-1
.entry start
start:
    li r1, 0xf3000
    li r2, kernel
    sw r2, 0(r1)
    li r2, kernel_end-kernel
    sw r2, 4(r1)
    li r2, 1
    sw r2, 8(r1)
    sw r2, 12(r1)
    li r2, 0x10000
    sw r2, 0x40(r1)
    li r2, 4
    sw r2, 0x44(r1)
    li r2, 3
    sw r2, 0x48(r1)
    li r2, 1
    sw r2, 16(r1)
    wfi
    lw r3, 20(r1)
    halt
kernel:
    g.li g1, 42
    g.stb g1, g0, 0
    g.end
kernel_end:"
    }

    #[test]
    fn external_start_yields_before_gpu_work_and_complete_wakes_wfi() {
        let mut m = load(external_source());
        m.set_gpu_external(1).unwrap();
        m.run(1000).unwrap();
        assert!(m.gpu_external_pending());
        assert!(m.gpu.busy());
        assert_eq!(m.ram[0], 0);
        assert_eq!(m.gpu.completed_invocations(), 0);
        assert_eq!(m.gpu.next_event(), Some(m.tick + 16));
        let code = m.gpu.read_active_reg(0).unwrap();
        assert_eq!(m.gpu.read_active_reg(4).unwrap(), 16);
        assert_eq!(m.gpu.read_active_reg(8).unwrap(), 1);
        assert_eq!(m.gpu.read_active_reg(0x40).unwrap(), RAM_BASE);
        assert_eq!(m.gpu.read_active_reg(0x48).unwrap(), 3);
        assert!(code < m.rom.len() as u32);
        let frozen_tick = m.tick;
        let frozen_instructions = m.instructions;
        m.run(1000).unwrap();
        assert_eq!(m.tick, frozen_tick);
        assert_eq!(m.instructions, frozen_instructions);
        m.ram[0] = 99; // external host upload through db_ram_ptr
        m.gpu_external_complete().unwrap();
        assert!(!m.gpu_external_pending());
        assert_eq!(m.gpu.status(), 2);
        assert_eq!(m.gpu.completed_dispatches(), 1);
        assert_eq!(m.gpu.completed_invocations(), 1);
        assert_eq!(m.gpu.last_ticks(), 0);
        assert_eq!(m.gpu.next_event(), None);
        m.run(1000).unwrap();
        assert!(m.cpu.halted);
        assert_eq!(m.cpu.regs[3], 2);
        assert_eq!(m.ram[0], 99);
    }

    #[test]
    fn external_fallback_resumes_same_validated_dispatch() {
        let mut m = load(external_source());
        m.set_gpu_external(1).unwrap();
        m.run(1000).unwrap();
        let start_tick = m.tick;
        assert!(m.set_gpu_external(2).is_err());
        assert_eq!(m.tick, start_tick);
        m.set_gpu_external(0).unwrap();
        assert!(!m.gpu_external_pending());
        m.run(1000).unwrap();
        assert_eq!(m.ram[0], 42);
        assert_eq!(m.gpu.status(), 2);
        assert_eq!(m.gpu.completed_dispatches(), 1);
        assert_eq!(m.gpu.last_ticks(), 24);
        assert_eq!(m.cpu.regs[3], 2);
    }

    #[test]
    fn dynamic_spu_code_reads_obey_gpu_write_leases() {
        for enable_first in [false, true] {
            let mut m = load(".profile dynamic-1\nhalt\nloop: g.jmp loop");
            for (offset, value) in [
                (0x40, 0x12000),
                (0x44, 4),
                (0x48, 1),
                (0x4c, 1),
                (0x50, 0x13000),
                (0x100, 0x13000),
                (0x104, 2048),
                (0x108, 3),
            ] {
                m.spu.write_reg(offset, value, &m.rom, &m.ram).unwrap();
            }
            let control = Store {
                address: SPU_BASE,
                width: 4,
                value: 1,
            };
            if enable_first {
                m.commit_store(control.clone()).unwrap();
            }
            for (offset, value) in [
                (0, 4),
                (4, 8),
                (8, 1),
                (12, 1),
                (64, 0x12000),
                (68, 4),
                (72, 3),
                (16, 1),
            ] {
                m.gpu.write_reg(offset, value, &m.rom, &m.ram, 0).unwrap();
            }
            if enable_first {
                assert!(m
                    .run(AUDIO_BLOCK_TICKS as u32)
                    .unwrap_err()
                    .contains("GPU_LEASE"));
            } else {
                assert_eq!(m.commit_store(control).unwrap_err().code, "GPU_LEASE");
            }
        }
    }

    #[test]
    fn external_failure_reset_and_same_tick_video_order() {
        let mut probe = load(external_source());
        probe.set_gpu_external(1).unwrap();
        probe.run(1000).unwrap();
        let start_tick = probe.tick;

        let mut m = load(external_source());
        m.next_line_tick = start_tick;
        m.set_gpu_external(1).unwrap();
        m.run(1000).unwrap();
        assert_eq!(m.tick, start_tick);
        assert_eq!(m.next_line, 2); // same-tick video event was processed before yield
        assert!(m.gpu_external_pending());
        m.gpu_external_fail().unwrap();
        assert_eq!(m.gpu.status(), 3);
        assert_eq!(m.gpu.completed_dispatches(), 0);
        m.run(1000).unwrap();
        assert!(m.cpu.halted);
        assert_eq!(m.cpu.regs[3], 3);

        let cartridge = db_asm::assemble(external_source()).unwrap().cartridge;
        m.load(&cartridge).unwrap(); // load resets external mode
        m.run(1000).unwrap();
        assert!(!m.gpu_external_pending());
        assert_eq!(m.ram[0], 42);
        assert_eq!(m.gpu.status(), 2);
    }
}
