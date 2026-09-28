//! Deterministic DB32 gpu-1 lane interpreter and MMIO device.
//! The frontend and the host scheduler own memory and time; this device owns no scene logic.

use db_contracts::{Fault, RAM_BASE};

pub const GPU_BASE: u32 = 0x000f_3000;
const LANES: usize = 64;
const REGISTERS: usize = 32;
const MAX_TICKS: u64 = 1_048_576;

#[derive(Clone, Copy, Debug, Default)]
struct Binding {
    base: u32,
    len: u32,
    flags: u32,
    reserved: u32,
}

#[derive(Clone, Copy, Debug, Default)]
struct Config {
    code: u32,
    code_len: u32,
    width: u32,
    height: u32,
    bindings: [Binding; 4],
    uniforms: [u32; 16],
}

#[derive(Clone, Copy, Debug)]
struct Instruction {
    op: u8,
    rd: usize,
    ra: usize,
    rb: usize,
    rc: usize,
    literal: u32,
    bytes: u32,
}

#[derive(Clone, Copy, Debug, Default)]
struct Effect {
    next_pc: u32,
    end: bool,
    reg_start: u8,
    reg_count: u8,
    values: [u32; 3],
    address: u32,
    store_count: u8,
    store: [u8; 4],
}

impl Effect {
    #[inline(always)]
    fn scalar(&mut self, rd: usize, value: u32) {
        if rd != 0 {
            self.reg_start = rd as u8;
            self.reg_count = 1;
            self.values[0] = value;
        }
    }

    #[inline(always)]
    fn vector(&mut self, rd: usize, value: [u32; 3]) {
        self.reg_start = rd as u8;
        self.reg_count = 3;
        self.values = value;
    }
}

#[derive(Clone, Copy, Debug)]
enum PendingKind {
    DispatchSetup,
    WaveSetup,
    Cohort,
    BudgetFault,
}

#[derive(Clone, Copy, Debug)]
struct Pending {
    at: u64,
    kind: PendingKind,
}

/// One resident wave with deterministic PC-cohort execution.
pub struct Gpu {
    ram_code: bool,
    config: Config,
    active: Config,
    decoded: Vec<Option<Instruction>>,
    regs: [[u32; REGISTERS]; LANES],
    lane_pc: [u32; LANES],
    finished: [bool; LANES],
    effects: [Effect; LANES],
    scalar_values: [u32; LANES],
    cohort_mask: u64,
    cohort_instruction: Option<Instruction>,
    wave_base: u32,
    active_lanes: usize,
    current_pc: u32,
    status: u32,
    started_at: u64,
    elapsed: u32,
    last_ticks: u32,
    completed_dispatches: u32,
    completed_invocations: u32,
    pending: Option<Pending>,
}

impl Default for Gpu {
    fn default() -> Self {
        Self::new()
    }
}

impl Gpu {
    pub fn new() -> Self {
        Self::with_ram_code(false)
    }

    /// dynamic-1 snapshots validated ROM or RAM instructions at each START.
    pub fn new_dynamic() -> Self {
        Self::with_ram_code(true)
    }

    fn with_ram_code(ram_code: bool) -> Self {
        Self {
            ram_code,
            config: Config::default(),
            active: Config::default(),
            decoded: Vec::new(),
            regs: [[0; REGISTERS]; LANES],
            lane_pc: [0; LANES],
            finished: [true; LANES],
            effects: [Effect::default(); LANES],
            scalar_values: [0; LANES],
            cohort_mask: 0,
            cohort_instruction: None,
            wave_base: 0,
            active_lanes: 0,
            current_pc: 0,
            status: 0,
            started_at: 0,
            elapsed: 0,
            last_ticks: 0,
            completed_dispatches: 0,
            completed_invocations: 0,
            pending: None,
        }
    }

    pub fn status(&self) -> u32 {
        self.status
    }
    pub fn elapsed_ticks(&self) -> u32 {
        self.elapsed
    }
    pub fn completed_dispatches(&self) -> u32 {
        self.completed_dispatches
    }
    pub fn completed_invocations(&self) -> u32 {
        self.completed_invocations
    }
    pub fn pc(&self) -> u32 {
        self.current_pc
    }
    pub fn last_ticks(&self) -> u32 {
        self.last_ticks
    }
    pub fn busy(&self) -> bool {
        self.status == 1
    }
    pub fn next_event(&self) -> Option<u64> {
        self.pending.map(|p| p.at)
    }

    /// Read the configuration latched by START. The external executor may call
    /// this only while a validated dispatch is busy. Offsets mirror GPU MMIO.
    pub fn read_active_reg(&self, offset: u32) -> Result<u32, Fault> {
        register_offset(offset)?;
        if !self.busy() {
            return Err(reg_fault(offset, "no active GPU dispatch"));
        }
        let value = match offset {
            0 => self.active.code,
            4 => self.active.code_len,
            8 => self.active.width,
            12 => self.active.height,
            0x40..=0x7f => {
                let b = self.active.bindings[((offset - 0x40) / 16) as usize];
                match offset & 15 {
                    0 => b.base,
                    4 => b.len,
                    8 => b.flags,
                    12 => b.reserved,
                    _ => unreachable!(),
                }
            }
            0x100..=0x13f => self.active.uniforms[((offset - 0x100) / 4) as usize],
            _ => return Err(reg_fault(offset, "offset has no latched configuration")),
        };
        Ok(value)
    }

    /// Complete a host-executed dispatch at the START commit tick. Host wall
    /// time is external to virtual time; this deliberately records zero GPU
    /// virtual ticks and must not be presented as canonical interpreter timing.
    pub fn external_complete(&mut self, tick: u64) -> Result<(), Fault> {
        self.external_finish(tick, false)
    }

    /// Report a host execution failure as GPU STATUS=fault, allowing guest CPU
    /// code to inspect the device fault status after it wakes.
    pub fn external_fail(&mut self, tick: u64) -> Result<(), Fault> {
        self.external_finish(tick, true)
    }

    fn external_finish(&mut self, tick: u64, failed: bool) -> Result<(), Fault> {
        if !self.busy()
            || tick != self.started_at
            || !matches!(
                self.pending,
                Some(Pending {
                    kind: PendingKind::DispatchSetup,
                    ..
                })
            )
        {
            return Err(fault(
                "GPU_EXTERNAL",
                self.current_pc,
                "no suspended START dispatch at this tick",
            ));
        }
        self.pending = None;
        self.cohort_instruction = None;
        self.elapsed = 0;
        self.last_ticks = 0;
        if failed {
            self.status = 3;
        } else {
            self.status = 2;
            self.completed_invocations = self.active.width * self.active.height;
            self.completed_dispatches = self.completed_dispatches.wrapping_add(1);
        }
        Ok(())
    }

    pub fn read_reg(&self, offset: u32) -> Result<u32, Fault> {
        register_offset(offset)?;
        let value = match offset {
            0 => self.config.code,
            4 => self.config.code_len,
            8 => self.config.width,
            12 => self.config.height,
            20 => self.status,
            24 => self.elapsed,
            28 => self.completed_dispatches,
            32 => self.completed_invocations,
            36 => self.current_pc,
            40 => self.last_ticks,
            44 => {
                if self.ram_code {
                    0x0001_0002
                } else {
                    0x0001_0001
                }
            }
            0x40..=0x7f => {
                let b = self.config.bindings[((offset - 0x40) / 16) as usize];
                match offset & 15 {
                    0 => b.base,
                    4 => b.len,
                    8 => b.flags,
                    12 => b.reserved,
                    _ => unreachable!(),
                }
            }
            0x100..=0x13f => self.config.uniforms[((offset - 0x100) / 4) as usize],
            _ => return Err(reg_fault(offset, "unknown or write-only GPU register")),
        };
        Ok(value)
    }

    pub fn write_reg(
        &mut self,
        offset: u32,
        value: u32,
        rom: &[u8],
        ram: &[u8],
        tick: u64,
    ) -> Result<(), Fault> {
        register_offset(offset)?;
        if self.busy() {
            return Err(reg_fault(offset, "GPU configuration is busy"));
        }
        if offset == 16 {
            if value != 1 {
                return Err(reg_fault(offset, "START requires value 1"));
            }
            return self.start(rom, ram, tick);
        }
        match offset {
            0 => self.config.code = value,
            4 => self.config.code_len = value,
            8 => self.config.width = value,
            12 => self.config.height = value,
            0x40..=0x7f => {
                let binding = &mut self.config.bindings[((offset - 0x40) / 16) as usize];
                match offset & 15 {
                    0 => binding.base = value,
                    4 => binding.len = value,
                    8 => binding.flags = value,
                    12 => binding.reserved = value,
                    _ => unreachable!(),
                }
            }
            0x100..=0x13f => self.config.uniforms[((offset - 0x100) / 4) as usize] = value,
            _ => return Err(reg_fault(offset, "unknown or read-only GPU register")),
        }
        Ok(())
    }

    fn start(&mut self, rom: &[u8], ram: &[u8], tick: u64) -> Result<(), Fault> {
        let decoded = validate(&self.config, rom, ram, self.ram_code)?;
        let at = tick
            .checked_add(16)
            .ok_or_else(|| fault("GPU_CLOCK", 0, "tick overflow"))?;
        tick.checked_add(MAX_TICKS)
            .ok_or_else(|| fault("GPU_CLOCK", 0, "dispatch deadline overflow"))?;
        self.active = self.config;
        self.decoded = decoded;
        self.status = 1;
        self.started_at = tick;
        self.elapsed = 0;
        self.completed_invocations = 0;
        self.current_pc = self.active.code;
        self.wave_base = 0;
        self.active_lanes = 0;
        self.cohort_instruction = None;
        self.pending = Some(Pending {
            at,
            kind: PendingKind::DispatchSetup,
        });
        Ok(())
    }

    /// Commit one scheduled event at its exact virtual tick, then issue subsequent work.
    pub fn event(&mut self, tick: u64, rom: &[u8], ram: &mut [u8]) -> Result<(), Fault> {
        let pending = self
            .pending
            .ok_or_else(|| fault("GPU_EVENT", self.current_pc, "no pending GPU event"))?;
        if pending.at != tick {
            return Err(fault(
                "GPU_EVENT",
                self.current_pc,
                format!("event expected at {}, got {tick}", pending.at),
            ));
        }
        self.pending = None;
        self.elapsed = (tick - self.started_at) as u32;
        let result = match pending.kind {
            PendingKind::DispatchSetup => self.schedule_wave(tick),
            PendingKind::WaveSetup => {
                self.reset_wave();
                self.issue(tick, rom, ram)
            }
            PendingKind::Cohort => {
                self.commit(ram);
                if self.completed_invocations == self.active.width * self.active.height {
                    self.status = 2;
                    self.last_ticks = self.elapsed;
                    self.completed_dispatches = self.completed_dispatches.wrapping_add(1);
                    Ok(())
                } else if self.finished[..self.active_lanes].iter().all(|f| *f) {
                    self.wave_base += self.active_lanes as u32;
                    self.schedule_wave(tick)
                } else {
                    self.issue(tick, rom, ram)
                }
            }
            PendingKind::BudgetFault => Err(fault(
                "GPU_BUDGET",
                self.current_pc,
                "dispatch exceeded 1048576 ticks",
            )),
        };
        if result.is_err() {
            self.status = 3;
            self.last_ticks = self.elapsed;
            self.pending = None;
        }
        result
    }

    fn schedule(&mut self, now: u64, cost: u64, kind: PendingKind) -> Result<(), Fault> {
        let deadline = self.started_at + MAX_TICKS;
        if now >= deadline {
            return Err(fault(
                "GPU_BUDGET",
                self.current_pc,
                "dispatch exceeded 1048576 ticks",
            ));
        }
        let at = now
            .checked_add(cost)
            .ok_or_else(|| fault("GPU_CLOCK", self.current_pc, "tick overflow"))?;
        self.pending = Some(if at > deadline {
            Pending {
                at: deadline,
                kind: PendingKind::BudgetFault,
            }
        } else {
            Pending { at, kind }
        });
        Ok(())
    }

    fn schedule_wave(&mut self, tick: u64) -> Result<(), Fault> {
        self.schedule(tick, 4, PendingKind::WaveSetup)
    }

    fn reset_wave(&mut self) {
        self.active_lanes =
            (self.active.width * self.active.height - self.wave_base).min(LANES as u32) as usize;
        for lane in 0..LANES {
            self.regs[lane] = [0; REGISTERS];
            self.lane_pc[lane] = self.active.code;
            self.finished[lane] = lane >= self.active_lanes;
        }
        self.current_pc = self.active.code;
    }

    fn issue(&mut self, tick: u64, rom: &[u8], ram: &[u8]) -> Result<(), Fault> {
        let mut pc = u32::MAX;
        let mut mask = 0u64;
        for lane in 0..self.active_lanes {
            if self.finished[lane] {
                continue;
            }
            let lane_pc = self.lane_pc[lane];
            if lane_pc < pc {
                pc = lane_pc;
                mask = 1u64 << lane;
            } else if lane_pc == pc {
                mask |= 1u64 << lane;
            }
        }
        if mask == 0 {
            return Err(fault("GPU_PC", self.current_pc, "no active lane to issue"));
        }
        self.cohort_mask = mask;
        self.current_pc = pc;
        let index = ((pc - self.active.code) / 4) as usize;
        let instruction = self
            .decoded
            .get(index)
            .and_then(|i| *i)
            .ok_or_else(|| fault("GPU_PC", pc, "PC is outside code or targets a literal"))?;
        self.cohort_instruction = Some(instruction);
        if is_scalar_float(instruction.op) {
            while mask != 0 {
                let lane = mask.trailing_zeros() as usize;
                mask &= mask - 1;
                self.scalar_values[lane] = self.scalar_float(lane, instruction).map_err(|e| {
                    fault(
                        e.code,
                        e.address,
                        format!("PC 0x{pc:08x}, lane {lane}: {}", e.message),
                    )
                })?;
            }
        } else if !is_infallible(instruction.op) {
            while mask != 0 {
                let lane = mask.trailing_zeros() as usize;
                mask &= mask - 1;
                self.effects[lane] = self.execute(lane, instruction, rom, ram).map_err(|e| {
                    fault(
                        e.code,
                        e.address,
                        format!("PC 0x{pc:08x}, lane {lane}: {}", e.message),
                    )
                })?;
            }
        }
        self.schedule(tick, instruction_cost(instruction.op), PendingKind::Cohort)
    }

    fn commit(&mut self, ram: &mut [u8]) {
        let instruction = self.cohort_instruction.take().expect("pending GPU cohort");
        if is_infallible(instruction.op) {
            self.commit_infallible(instruction);
            return;
        }
        if is_scalar_float(instruction.op) {
            let mut mask = self.cohort_mask;
            let rd = instruction.rd;
            let next_pc = self.current_pc + instruction.bytes;
            while mask != 0 {
                let lane = mask.trailing_zeros() as usize;
                mask &= mask - 1;
                if rd != 0 {
                    self.regs[lane][rd] = self.scalar_values[lane];
                }
                self.lane_pc[lane] = next_pc;
            }
            return;
        }
        let mut mask = self.cohort_mask;
        while mask != 0 {
            let lane = mask.trailing_zeros() as usize;
            mask &= mask - 1;
            let effect = self.effects[lane];
            for n in 0..effect.reg_count as usize {
                self.regs[lane][effect.reg_start as usize + n] = effect.values[n];
            }
            if effect.store_count > 0 {
                let offset = (effect.address - RAM_BASE) as usize;
                let n = effect.store_count as usize;
                ram[offset..offset + n].copy_from_slice(&effect.store[..n]);
            }
            self.lane_pc[lane] = effect.next_pc;
            if effect.end {
                self.finished[lane] = true;
                self.completed_invocations += 1;
            }
        }
    }

    // Registers are lane-local, uniforms are latched, and START leases all bound
    // RAM. For these no-fault operations, their issue-time inputs cannot change
    // before completion. Computing them once at commit avoids a staging copy.
    fn commit_infallible(&mut self, inst: Instruction) {
        let d = inst.rd;
        let a = inst.ra;
        let b = inst.rb;
        let fallthrough = self.current_pc + inst.bytes;
        macro_rules! scalar {
            ($r:ident, $expr:expr) => {{
                let mut mask = self.cohort_mask;
                while mask != 0 {
                    let lane = mask.trailing_zeros() as usize;
                    mask &= mask - 1;
                    let value = {
                        #[allow(unused_variables)]
                        let $r = &self.regs[lane];
                        $expr
                    };
                    if d != 0 {
                        self.regs[lane][d] = value;
                    }
                    self.lane_pc[lane] = fallthrough;
                }
            }};
        }
        match inst.op {
            0 => {
                let mut mask = self.cohort_mask;
                while mask != 0 {
                    let lane = mask.trailing_zeros() as usize;
                    mask &= mask - 1;
                    self.finished[lane] = true;
                    self.completed_invocations += 1;
                }
            }
            1 => scalar!(r, inst.literal),
            2 => scalar!(r, r[a]),
            3 => {
                let mut mask = self.cohort_mask;
                while mask != 0 {
                    let lane = mask.trailing_zeros() as usize;
                    mask &= mask - 1;
                    let id = self.wave_base + lane as u32;
                    let value = match a {
                        0 => id % self.active.width,
                        1 => id / self.active.width,
                        2 => id,
                        3 => lane as u32,
                        4 => self.active.width,
                        5 => self.active.height,
                        _ => unreachable!(),
                    };
                    if d != 0 {
                        self.regs[lane][d] = value;
                    }
                    self.lane_pc[lane] = fallthrough;
                }
            }
            4 => scalar!(r, self.active.uniforms[a]),
            5 => scalar!(r, r[a].wrapping_add(r[b])),
            6 => scalar!(r, r[a].wrapping_sub(r[b])),
            7 => scalar!(r, r[a].wrapping_mul(r[b])),
            8 => scalar!(r, r[a] & r[b]),
            9 => scalar!(r, r[a] | r[b]),
            10 => scalar!(r, r[a] ^ r[b]),
            11 => scalar!(r, r[a] << (r[b] & 31)),
            12 => scalar!(r, r[a] >> (r[b] & 31)),
            13 => scalar!(r, ((r[a] as i32) >> (r[b] & 31)) as u32),
            14 => scalar!(r, u32::from((r[a] as i32) < (r[b] as i32))),
            15 => scalar!(r, u32::from(r[a] < r[b])),
            40 | 41 => {
                let mut mask = self.cohort_mask;
                while mask != 0 {
                    let lane = mask.trailing_zeros() as usize;
                    mask &= mask - 1;
                    let zero = self.regs[lane][d] == 0;
                    self.lane_pc[lane] = if (inst.op == 40 && zero) || (inst.op == 41 && !zero) {
                        inst.literal
                    } else {
                        fallthrough
                    };
                }
            }
            42 => {
                let mut mask = self.cohort_mask;
                while mask != 0 {
                    let lane = mask.trailing_zeros() as usize;
                    mask &= mask - 1;
                    self.lane_pc[lane] = inst.literal;
                }
            }
            _ => unreachable!(),
        }
    }

    pub fn check_cpu_access(&self, address: u32, width: u32, write: bool) -> Result<(), Fault> {
        if !self.busy() {
            return Ok(());
        }
        let end = (address as u64)
            .checked_add(width as u64)
            .ok_or_else(|| fault("GPU_LEASE", address, "CPU access wraps"))?;
        for binding in self.active.bindings {
            if binding.flags == 0 {
                continue;
            }
            let b_end = binding.base as u64 + binding.len as u64;
            if (address as u64) < b_end
                && end > binding.base as u64
                && (write && binding.base >= RAM_BASE || !write && binding.flags == 3)
            {
                return Err(fault(
                    "GPU_LEASE",
                    address,
                    "CPU access conflicts with active GPU binding",
                ));
            }
        }
        Ok(())
    }

    fn memory_address(
        &self,
        binding: usize,
        offset: u64,
        bytes: u32,
        write: bool,
        rom: &[u8],
        ram: &[u8],
    ) -> Result<(u32, usize, bool), Fault> {
        let b = self.active.bindings[binding];
        let address = b.base as u64 + offset;
        if b.flags == 0
            || write && b.flags != 3
            || offset
                .checked_add(bytes as u64)
                .map_or(true, |end| end > b.len as u64)
            || address + bytes as u64 > u32::MAX as u64 + 1
        {
            return Err(fault(
                "GPU_MEMORY",
                address.min(u32::MAX as u64) as u32,
                "binding access is out of bounds or prohibited",
            ));
        }
        let address = address as u32;
        if bytes == 4 && address & 3 != 0 {
            return Err(fault(
                "GPU_ALIGNMENT",
                address,
                "word access requires four-byte alignment",
            ));
        }
        if address >= RAM_BASE {
            let index = (address - RAM_BASE) as usize;
            if index + bytes as usize > ram.len() {
                return Err(fault("GPU_MEMORY", address, "RAM address out of bounds"));
            }
            Ok((address, index, true))
        } else {
            if write || address as usize + bytes as usize > rom.len() {
                return Err(fault(
                    "GPU_MEMORY",
                    address,
                    "ROM address out of bounds or read-only",
                ));
            }
            Ok((address, address as usize, false))
        }
    }

    fn execute(
        &self,
        lane: usize,
        inst: Instruction,
        rom: &[u8],
        ram: &[u8],
    ) -> Result<Effect, Fault> {
        let r = &self.regs[lane];
        let mut effect = Effect {
            next_pc: self.current_pc + inst.bytes,
            ..Effect::default()
        };
        let d = inst.rd;
        let a = inst.ra;
        let b = inst.rb;
        let here = self.current_pc;
        match inst.op {
            0 => effect.end = true,
            1 => effect.scalar(d, inst.literal),
            2 => effect.scalar(d, r[a]),
            3 => {
                let id = self.wave_base + lane as u32;
                let value = match a {
                    0 => id % self.active.width,
                    1 => id / self.active.width,
                    2 => id,
                    3 => lane as u32,
                    4 => self.active.width,
                    5 => self.active.height,
                    _ => unreachable!(),
                };
                effect.scalar(d, value);
            }
            4 => effect.scalar(d, self.active.uniforms[a]),
            5 => effect.scalar(d, r[a].wrapping_add(r[b])),
            6 => effect.scalar(d, r[a].wrapping_sub(r[b])),
            7 => effect.scalar(d, r[a].wrapping_mul(r[b])),
            8 => effect.scalar(d, r[a] & r[b]),
            9 => effect.scalar(d, r[a] | r[b]),
            10 => effect.scalar(d, r[a] ^ r[b]),
            11 => effect.scalar(d, r[a] << (r[b] & 31)),
            12 => effect.scalar(d, r[a] >> (r[b] & 31)),
            13 => effect.scalar(d, ((r[a] as i32) >> (r[b] & 31)) as u32),
            14 => effect.scalar(d, u32::from((r[a] as i32) < (r[b] as i32))),
            15 => effect.scalar(d, u32::from(r[a] < r[b])),
            16..=27 | 31 | 34 => effect.scalar(d, self.scalar_float(lane, inst)?),
            28..=29 => {
                let x = vector(r, a, here)?;
                let y = vector(r, b, here)?;
                let mut result = [0; 3];
                for n in 0..3 {
                    result[n] = checked(
                        if inst.op == 28 {
                            x[n] + y[n]
                        } else {
                            x[n] - y[n]
                        },
                        here,
                    )?
                    .to_bits();
                }
                effect.vector(d, result);
            }
            30 => {
                let x = vector(r, a, here)?;
                let scale = float(r[b], here)?;
                let mut result = [0; 3];
                for n in 0..3 {
                    result[n] = checked(x[n] * scale, here)?.to_bits();
                }
                effect.vector(d, result);
            }
            32 => {
                let x = vector(r, a, here)?;
                let len2 = dot(x, x, here)?;
                let mut result = [0; 3];
                if x != [0.0; 3] {
                    let len = checked(len2.sqrt(), here)?;
                    for n in 0..3 {
                        result[n] = checked(x[n] / len, here)?.to_bits();
                    }
                }
                effect.vector(d, result);
            }
            33 => {
                let x = vector(r, a, here)?;
                let normal = vector(r, b, here)?;
                let factor = checked(checked(2.0 * dot(x, normal, here)?, here)?, here)?;
                let mut result = [0; 3];
                for n in 0..3 {
                    let scaled = checked(factor * normal[n], here)?;
                    result[n] = checked(x[n] - scaled, here)?.to_bits();
                }
                effect.vector(d, result);
            }
            35..=38 => {
                let bytes = if matches!(inst.op, 35 | 36) { 4 } else { 1 };
                let writing = matches!(inst.op, 36 | 38);
                let (address, offset, in_ram) =
                    self.memory_address(b, r[a] as u64, bytes, writing, rom, ram)?;
                if writing {
                    effect.address = address;
                    effect.store_count = bytes as u8;
                    effect.store = r[d].to_le_bytes();
                } else {
                    let source = if in_ram { ram } else { rom };
                    let mut word = [0u8; 4];
                    word[..bytes as usize]
                        .copy_from_slice(&source[offset..offset + bytes as usize]);
                    effect.scalar(d, u32::from_le_bytes(word));
                }
            }
            39 => {
                let pixel_offset = (r[a] as u64) * 3;
                let (address, _, _) = self.memory_address(b, pixel_offset, 3, true, rom, ram)?;
                let colour = vector(r, d, here)?;
                effect.address = address;
                effect.store_count = 3;
                for n in 0..3 {
                    effect.store[n] =
                        (checked(colour[n].clamp(0.0, 1.0) * 255.0, here)? as u32) as u8;
                }
            }
            40 => {
                if r[d] == 0 {
                    effect.next_pc = inst.literal;
                }
            }
            41 => {
                if r[d] != 0 {
                    effect.next_pc = inst.literal;
                }
            }
            42 => effect.next_pc = inst.literal,
            _ => unreachable!(),
        }
        Ok(effect)
    }

    fn scalar_float(&self, lane: usize, inst: Instruction) -> Result<u32, Fault> {
        let r = &self.regs[lane];
        let a = inst.ra;
        let b = inst.rb;
        let c = inst.rc;
        let here = self.current_pc;
        match inst.op {
            16..=21 | 26..=27 => {
                let x = float(r[a], here)?;
                let y = float(r[b], here)?;
                Ok(match inst.op {
                    16 => checked(x + y, here)?.to_bits(),
                    17 => checked(x - y, here)?.to_bits(),
                    18 => checked(x * y, here)?.to_bits(),
                    19 => checked(x / y, here)?.to_bits(),
                    20 => finite_min(x, y).to_bits(),
                    21 => finite_max(x, y).to_bits(),
                    26 => u32::from(x < y),
                    27 => u32::from(x <= y),
                    _ => unreachable!(),
                })
            }
            22 => Ok(checked(float(r[a], here)?.sqrt(), here)?.to_bits()),
            23 => Ok(checked(1.0 / checked(float(r[a], here)?.sqrt(), here)?, here)?.to_bits()),
            24 => Ok(checked(r[a] as i32 as f32, here)?.to_bits()),
            25 => Ok(float(r[a], here)?.trunc() as i32 as u32),
            31 => Ok(dot(vector(r, a, here)?, vector(r, b, here)?, here)?.to_bits()),
            34 => {
                let origin = vector(r, a, here)?;
                let direction = vector(r, b, here)?;
                let center = vector(r, c, here)?;
                let radius = float(r[c + 3], here)?;
                if direction == [0.0; 3] || radius < 0.0 {
                    return Err(fault(
                        "GPU_FLOAT",
                        here,
                        "sphere has zero direction or negative radius",
                    ));
                }
                let mut displacement = [0.0; 3];
                for n in 0..3 {
                    displacement[n] = checked(origin[n] - center[n], here)?;
                }
                let qa = dot(direction, direction, here)?;
                let qb = dot(displacement, direction, here)?;
                let qc = checked(
                    dot(displacement, displacement, here)? - checked(radius * radius, here)?,
                    here,
                )?;
                let disc = checked(checked(qb * qb, here)? - checked(qa * qc, here)?, here)?;
                let hit = if disc < 0.0 {
                    -1.0
                } else {
                    let root = checked(disc.sqrt(), here)?;
                    let near = checked(checked(-qb - root, here)? / qa, here)?;
                    if near >= 1.0 / 1024.0 {
                        near
                    } else {
                        let far = checked(checked(-qb + root, here)? / qa, here)?;
                        if far >= 1.0 / 1024.0 {
                            far
                        } else {
                            -1.0
                        }
                    }
                };
                Ok(hit.to_bits())
            }
            _ => unreachable!(),
        }
    }
}

#[inline(always)]
fn checked(value: f32, address: u32) -> Result<f32, Fault> {
    if value.is_finite() {
        Ok(value)
    } else {
        Err(fault(
            "GPU_FLOAT",
            address,
            "non-finite float input or result",
        ))
    }
}

#[inline(always)]
fn float(bits: u32, address: u32) -> Result<f32, Fault> {
    checked(f32::from_bits(bits), address)
}

#[inline(always)]
fn vector(registers: &[u32; REGISTERS], index: usize, address: u32) -> Result<[f32; 3], Fault> {
    Ok([
        float(registers[index], address)?,
        float(registers[index + 1], address)?,
        float(registers[index + 2], address)?,
    ])
}

#[inline(always)]
fn dot(a: [f32; 3], b: [f32; 3], address: u32) -> Result<f32, Fault> {
    let x = checked(a[0] * b[0], address)?;
    let y = checked(a[1] * b[1], address)?;
    let z = checked(a[2] * b[2], address)?;
    checked(checked(x + y, address)? + z, address)
}

fn finite_min(a: f32, b: f32) -> f32 {
    if a == 0.0 && b == 0.0 {
        if a.is_sign_negative() || b.is_sign_negative() {
            -0.0
        } else {
            0.0
        }
    } else if a < b {
        a
    } else {
        b
    }
}

fn finite_max(a: f32, b: f32) -> f32 {
    if a == 0.0 && b == 0.0 {
        if a.is_sign_positive() || b.is_sign_positive() {
            0.0
        } else {
            -0.0
        }
    } else if a > b {
        a
    } else {
        b
    }
}

#[cold]
#[inline(never)]
fn fault(code: &'static str, address: u32, message: impl Into<String>) -> Fault {
    Fault::new(code, address, message)
}
fn reg_fault(offset: u32, message: &'static str) -> Fault {
    fault("GPU_REGISTER", GPU_BASE.wrapping_add(offset), message)
}
fn register_offset(offset: u32) -> Result<(), Fault> {
    if offset & 3 != 0 {
        Err(fault(
            "GPU_ALIGNMENT",
            GPU_BASE.wrapping_add(offset),
            "GPU registers require aligned u32",
        ))
    } else {
        Ok(())
    }
}

fn validate(
    config: &Config,
    rom: &[u8],
    ram: &[u8],
    ram_code: bool,
) -> Result<Vec<Option<Instruction>>, Fault> {
    let limit = if ram_code { 65536 } else { 4096 };
    if config.code & 3 != 0
        || config.code_len == 0
        || config.code_len & 3 != 0
        || config.code_len > limit
    {
        return Err(fault(
            "GPU_CODE",
            config.code,
            format!("code range must be aligned, nonempty and at most {limit} bytes"),
        ));
    }
    let end = (config.code as u64)
        .checked_add(config.code_len as u64)
        .ok_or_else(|| fault("GPU_CODE", config.code, "code range overflow"))?;
    let code = if end <= rom.len() as u64 {
        &rom[config.code as usize..end as usize]
    } else if ram_code && config.code >= RAM_BASE && end <= RAM_BASE as u64 + ram.len() as u64 {
        &ram[(config.code - RAM_BASE) as usize..(end - RAM_BASE as u64) as usize]
    } else {
        return Err(fault(
            "GPU_CODE",
            config.code,
            if ram_code {
                "code range is outside ROM/RAM"
            } else {
                "code range is outside ROM"
            },
        ));
    };
    if !(1..=160).contains(&config.width) || !(1..=120).contains(&config.height) {
        return Err(fault(
            "GPU_GRID",
            config.width,
            "grid exceeds 160 by 120 or has a zero dimension",
        ));
    }
    for (i, b) in config.bindings.iter().enumerate() {
        match b.flags {
            0 if b.base == 0 && b.len == 0 && b.reserved == 0 => continue,
            1 | 3 if b.len > 0 && b.reserved == 0 => {}
            _ => {
                return Err(fault(
                    "GPU_BINDING",
                    b.base,
                    format!("invalid descriptor {i}"),
                ))
            }
        }
        let span_end = b.base as u64 + b.len as u64;
        let in_rom = span_end <= rom.len() as u64;
        let in_ram = b.base >= RAM_BASE && span_end <= RAM_BASE as u64 + ram.len() as u64;
        if !(in_ram || b.flags == 1 && in_rom) {
            return Err(fault(
                "GPU_BINDING",
                b.base,
                format!("descriptor {i} is outside permitted memory"),
            ));
        }
        for other in &config.bindings[..i] {
            if other.flags != 0
                && (b.base as u64) < other.base as u64 + other.len as u64
                && (other.base as u64) < span_end
            {
                return Err(fault(
                    "GPU_BINDING",
                    b.base,
                    format!("descriptor {i} overlaps another binding"),
                ));
            }
        }
    }
    let words = (config.code_len / 4) as usize;
    let mut decoded = vec![None; words];
    let mut i = 0;
    while i < words {
        let at = config.code + (i as u32) * 4;
        let raw = u32::from_le_bytes(code[i * 4..i * 4 + 4].try_into().unwrap());
        let op = raw as u8;
        let rd = ((raw >> 8) & 31) as usize;
        let ra = ((raw >> 13) & 31) as usize;
        let rb = ((raw >> 18) & 31) as usize;
        let rc = ((raw >> 23) & 31) as usize;
        if raw >> 28 != 0 || op > 42 {
            return Err(fault("GPU_OPCODE", at, "invalid opcode or reserved bits"));
        }
        let fields_ok = match op {
            0 | 42 => rd == 0 && ra == 0 && rb == 0 && rc == 0,
            1 => ra == 0 && rb == 0 && rc == 0,
            2 | 22..=25 => rb == 0 && rc == 0,
            3 => ra <= 5 && rb == 0 && rc == 0,
            4 => ra <= 15 && rb == 0 && rc == 0,
            5..=21 | 26..=27 => rc == 0,
            28..=29 => (1..=29).contains(&rd) && ra <= 29 && rb <= 29 && rc == 0,
            30 => (1..=29).contains(&rd) && ra <= 29 && rc == 0,
            31 => ra <= 29 && rb <= 29 && rc == 0,
            32 => (1..=29).contains(&rd) && ra <= 29 && rb == 0 && rc == 0,
            33 => (1..=29).contains(&rd) && ra <= 29 && rb <= 29 && rc == 0,
            34 => ra <= 29 && rb <= 29 && rc <= 28,
            35..=38 => rb <= 3 && rc == 0,
            39 => rd <= 29 && rb <= 3 && rc == 0,
            40..=41 => ra == 0 && rb == 0 && rc == 0,
            _ => false,
        };
        if !fields_ok {
            return Err(fault(
                "GPU_OPERAND",
                at,
                "invalid or unused instruction field",
            ));
        }
        let two_words = matches!(op, 1 | 40..=42);
        if two_words && i + 1 >= words {
            return Err(fault("GPU_CODE", at, "truncated two-word instruction"));
        }
        let literal = if two_words {
            u32::from_le_bytes(code[i * 4 + 4..i * 4 + 8].try_into().unwrap())
        } else {
            0
        };
        decoded[i] = Some(Instruction {
            op,
            rd,
            ra,
            rb,
            rc,
            literal,
            bytes: if two_words { 8 } else { 4 },
        });
        i += if two_words { 2 } else { 1 };
    }
    for (i, instruction) in decoded.iter().enumerate() {
        if let Some(inst) = instruction {
            if matches!(inst.op, 40..=42) {
                let target = inst.literal;
                if target < config.code
                    || target as u64 >= end
                    || target & 3 != 0
                    || decoded[((target - config.code) / 4) as usize].is_none()
                {
                    return Err(fault(
                        "GPU_BRANCH",
                        config.code + (i as u32) * 4,
                        "branch target is not an instruction boundary",
                    ));
                }
            }
        }
    }
    Ok(decoded)
}

fn instruction_cost(op: u8) -> u64 {
    match op {
        19 | 22 | 23 | 32 => 4,
        31 | 33 | 35..=39 => 2,
        34 => 8,
        _ => 1,
    }
}

#[inline]
fn is_infallible(op: u8) -> bool {
    op <= 15 || matches!(op, 40..=42)
}

#[inline]
fn is_scalar_float(op: u8) -> bool {
    matches!(op, 16..=27 | 31 | 34)
}
