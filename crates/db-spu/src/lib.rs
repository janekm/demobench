//! Audio-clocked, guest-programmed signal compute for the DB32 spu-1 profile.
//! No synthesis primitives live here: the shared GPU ISA produces raw stereo PCM.

use db_contracts::{Fault, RAM_BASE};
use db_gpu::Gpu;

pub const SPU_BASE: u32 = 0x000f_6000;
pub const AUDIO_RATE: u32 = 48_000;
pub const BLOCK_FRAMES: usize = 256;
pub const BLOCK_TICKS: u64 = 65_536;
pub const WORK_LIMIT: u64 = 65_536;
pub const QUEUE_FRAMES: usize = 8_192;
const OUTPUT_BYTES: u64 = (BLOCK_FRAMES * 2 * std::mem::size_of::<f32>()) as u64;

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
    output: u32,
    bindings: [Binding; 4],
    uniforms: [u32; 14],
}

pub struct Spu {
    ram_code: bool,
    config: Config,
    gpu: Gpu,
    control: bool,
    status: u32,
    external_pending: bool,
    audio: Vec<f32>,
    sample_count: u64,
    blocks: u32,
    overruns: u32,
    last_ticks: u32,
    peak: f32,
    current_start: u32,
}

impl Default for Spu {
    fn default() -> Self {
        Self::new()
    }
}

impl Spu {
    pub fn new() -> Self {
        Self::with_ram_code(false)
    }

    pub fn new_dynamic() -> Self {
        Self::with_ram_code(true)
    }

    fn with_ram_code(ram_code: bool) -> Self {
        Self {
            ram_code,
            config: Config::default(),
            gpu: Gpu::new(),
            control: false,
            status: 0,
            external_pending: false,
            audio: Vec::with_capacity(QUEUE_FRAMES * 2),
            sample_count: 0,
            blocks: 0,
            overruns: 0,
            last_ticks: 0,
            peak: 0.0,
            current_start: 0,
        }
    }

    pub fn status(&self) -> u32 {
        self.status
    }
    pub fn enabled(&self) -> bool {
        self.control
    }
    pub fn code_range(&self) -> (u32, u32) {
        (self.config.code, self.config.code_len)
    }
    pub fn external_pending(&self) -> bool {
        self.external_pending
    }
    pub fn audio(&self) -> &[f32] {
        &self.audio
    }
    pub fn clear_audio(&mut self) {
        self.audio.clear();
    }
    pub fn sample_count(&self) -> u64 {
        self.sample_count
    }
    pub fn blocks(&self) -> u32 {
        self.blocks
    }
    pub fn peak(&self) -> f32 {
        self.peak
    }
    pub fn overruns(&self) -> u32 {
        self.overruns
    }
    pub fn last_ticks(&self) -> u32 {
        self.last_ticks
    }

    /// Active/configured descriptors for conflict checks with the central GPU.
    /// Unused and disabled descriptors are returned as zero triples.
    pub fn bindings(&self) -> [(u32, u32, u32); 4] {
        let mut result = [(0, 0, 0); 4];
        if self.control {
            for (slot, binding) in result.iter_mut().zip(self.config.bindings) {
                if binding.flags != 0 {
                    *slot = (binding.base, binding.len, binding.flags);
                }
            }
        }
        result
    }

    pub fn read_reg(&self, offset: u32) -> Result<u32, Fault> {
        check_offset(offset)?;
        let value = match offset {
            0x00 => u32::from(self.control),
            0x04 => self.status,
            0x08 => AUDIO_RATE,
            0x0c => BLOCK_FRAMES as u32,
            0x10 => self.blocks,
            0x14 => self.sample_count as u32,
            0x18 => (self.sample_count >> 32) as u32,
            0x1c => (self.audio.len() / 2) as u32,
            0x20 => self.overruns,
            0x24 => self.last_ticks,
            0x28 => self.peak.to_bits(),
            0x2c => WORK_LIMIT as u32,
            0x40 => self.config.code,
            0x44 => self.config.code_len,
            0x48 => self.config.width,
            0x4c => self.config.height,
            0x50 => self.config.output,
            0x100..=0x13f => {
                let b = self.config.bindings[((offset - 0x100) / 16) as usize];
                match offset & 15 {
                    0 => b.base,
                    4 => b.len,
                    8 => b.flags,
                    12 => b.reserved,
                    _ => unreachable!(),
                }
            }
            0x200..=0x237 => self.config.uniforms[((offset - 0x200) / 4) as usize],
            0x238 => self.current_start,
            0x23c => AUDIO_RATE,
            _ => return Err(reg_fault(offset, "unknown SPU register")),
        };
        Ok(value)
    }

    pub fn write_reg(
        &mut self,
        offset: u32,
        value: u32,
        rom: &[u8],
        ram: &[u8],
    ) -> Result<(), Fault> {
        check_offset(offset)?;
        if self.external_pending {
            return Err(reg_fault(
                offset,
                "SPU configuration frozen while external block is pending",
            ));
        }
        match offset {
            0x00 => match value {
                0 => {
                    self.control = false;
                    self.status = 0;
                }
                1 => {
                    self.validate_output(ram)?;
                    let _ = self.prepare_gpu(rom, ram, self.sample_count as u32)?;
                    self.control = true;
                    self.status = 1;
                }
                _ => return Err(reg_fault(offset, "CONTROL requires 0 or 1")),
            },
            0x40 => self.config.code = value,
            0x44 => self.config.code_len = value,
            0x48 => self.config.width = value,
            0x4c => self.config.height = value,
            0x50 => self.config.output = value,
            0x100..=0x13f => {
                let b = &mut self.config.bindings[((offset - 0x100) / 16) as usize];
                match offset & 15 {
                    0 => b.base = value,
                    4 => b.len = value,
                    8 => b.flags = value,
                    12 => b.reserved = value,
                    _ => unreachable!(),
                }
            }
            0x200..=0x237 => self.config.uniforms[((offset - 0x200) / 4) as usize] = value,
            _ => return Err(reg_fault(offset, "unknown or read-only SPU register")),
        }
        Ok(())
    }

    /// Handle one audio-clock event. Reference compute is atomic with respect
    /// to central machine time; only its separate work quota advances.
    pub fn block(&mut self, rom: &[u8], ram: &mut [u8], external: bool) -> Result<(), Fault> {
        if self.external_pending {
            return Err(fault(
                "SPU_PENDING",
                SPU_BASE,
                "previous external block is pending",
            ));
        }
        self.current_start = self.sample_count as u32;
        if !self.control {
            self.last_ticks = 0;
            self.publish(&[0.0; BLOCK_FRAMES * 2]);
            return Ok(());
        }
        let result = (|| {
            self.validate_output(ram)?;
            self.gpu = self.prepare_gpu(rom, ram, self.current_start)?;
            if external {
                self.external_pending = true;
                self.status = 2;
                self.last_ticks = 0;
                Ok(())
            } else {
                self.run_reference(rom, ram)
            }
        })();
        if result.is_err() {
            self.status = 3;
            self.external_pending = false;
        }
        result
    }

    /// Execute the exact suspended dispatch after a hardware decline. The
    /// caller must do this before copying any hardware output into guest RAM.
    pub fn run_pending(&mut self, rom: &[u8], ram: &mut [u8]) -> Result<(), Fault> {
        if !self.external_pending {
            return Err(fault("SPU_PENDING", SPU_BASE, "no external block pending"));
        }
        self.external_pending = false;
        let result = self.run_reference(rom, ram);
        if result.is_err() {
            self.status = 3;
        }
        result
    }

    /// Commit hardware output at the same central machine tick as the block
    /// boundary. Hardware wall duration does not become virtual compute work.
    pub fn complete_external(&mut self, ram: &[u8]) -> Result<(), Fault> {
        if !self.external_pending {
            return Err(fault("SPU_PENDING", SPU_BASE, "no external block pending"));
        }
        let samples = match self.read_output(ram) {
            Ok(samples) => samples,
            Err(error) => {
                let _ = self.gpu.external_fail(0);
                self.external_pending = false;
                self.status = 3;
                return Err(error);
            }
        };
        self.gpu.external_complete(0)?;
        self.external_pending = false;
        self.status = 1;
        self.last_ticks = 0;
        self.publish(&samples);
        Ok(())
    }

    pub fn read_dispatch_reg(&self, offset: u32) -> Result<u32, Fault> {
        if !self.external_pending {
            return Err(fault("SPU_PENDING", SPU_BASE, "no external block pending"));
        }
        self.gpu.read_active_reg(offset)
    }

    fn run_reference(&mut self, rom: &[u8], ram: &mut [u8]) -> Result<(), Fault> {
        while let Some(tick) = self.gpu.next_event() {
            if tick > WORK_LIMIT {
                self.last_ticks = WORK_LIMIT as u32;
                return Err(fault(
                    "SPU_BUDGET",
                    SPU_BASE,
                    "block exceeded 65536 compute ticks",
                ));
            }
            if let Err(error) = self.gpu.event(tick, rom, ram) {
                self.last_ticks = self.gpu.elapsed_ticks();
                return Err(error);
            }
        }
        if self.gpu.status() != 2 {
            return Err(fault("SPU_GPU", SPU_BASE, "compute job did not complete"));
        }
        self.last_ticks = self.gpu.last_ticks();
        let samples = self.read_output(ram)?;
        self.status = 1;
        self.publish(&samples);
        Ok(())
    }

    fn prepare_gpu(&self, rom: &[u8], ram: &[u8], start: u32) -> Result<Gpu, Fault> {
        let mut gpu = if self.ram_code {
            Gpu::new_dynamic()
        } else {
            Gpu::new()
        };
        for (offset, value) in [
            (0, self.config.code),
            (4, self.config.code_len),
            (8, self.config.width),
            (12, self.config.height),
        ] {
            gpu.write_reg(offset, value, rom, ram, 0)?;
        }
        for (index, b) in self.config.bindings.iter().enumerate() {
            let offset = 0x40 + index as u32 * 16;
            for (delta, value) in [(0, b.base), (4, b.len), (8, b.flags), (12, b.reserved)] {
                gpu.write_reg(offset + delta, value, rom, ram, 0)?;
            }
        }
        for (index, value) in self.config.uniforms.iter().enumerate() {
            gpu.write_reg(0x100 + index as u32 * 4, *value, rom, ram, 0)?;
        }
        gpu.write_reg(0x138, start, rom, ram, 0)?;
        gpu.write_reg(0x13c, AUDIO_RATE, rom, ram, 0)?;
        gpu.write_reg(16, 1, rom, ram, 0)?;
        Ok(gpu)
    }

    fn validate_output(&self, ram: &[u8]) -> Result<usize, Fault> {
        let base = self.config.output;
        let end = base as u64 + OUTPUT_BYTES;
        if base & 3 != 0 || base < RAM_BASE || end > RAM_BASE as u64 + ram.len() as u64 {
            return Err(fault(
                "SPU_OUTPUT",
                base,
                "output must be aligned and wholly inside RAM",
            ));
        }
        if !self.config.bindings.iter().any(|b| {
            b.flags == 3 && base as u64 >= b.base as u64 && end <= b.base as u64 + b.len as u64
        }) {
            return Err(fault(
                "SPU_OUTPUT",
                base,
                "output must fit inside one writable binding",
            ));
        }
        Ok((base - RAM_BASE) as usize)
    }

    fn read_output(&self, ram: &[u8]) -> Result<[f32; BLOCK_FRAMES * 2], Fault> {
        let offset = self.validate_output(ram)?;
        let mut samples = [0.0f32; BLOCK_FRAMES * 2];
        for (index, sample) in samples.iter_mut().enumerate() {
            let at = offset + index * 4;
            let value = f32::from_le_bytes(ram[at..at + 4].try_into().unwrap());
            if !value.is_finite() {
                return Err(fault(
                    "SPU_SAMPLE",
                    self.config.output + (index as u32) * 4,
                    format!("non-finite PCM sample {index}"),
                ));
            }
            *sample = value.clamp(-1.0, 1.0);
        }
        Ok(samples)
    }

    fn publish(&mut self, samples: &[f32; BLOCK_FRAMES * 2]) {
        self.peak = samples
            .iter()
            .fold(0.0f32, |peak, &value| peak.max(value.abs()));
        let free_frames = QUEUE_FRAMES.saturating_sub(self.audio.len() / 2);
        let accepted_frames = BLOCK_FRAMES.min(free_frames);
        self.audio
            .extend_from_slice(&samples[..accepted_frames * 2]);
        self.overruns = self
            .overruns
            .saturating_add((BLOCK_FRAMES - accepted_frames) as u32);
        self.sample_count = self.sample_count.wrapping_add(BLOCK_FRAMES as u64);
        self.blocks = self.blocks.wrapping_add(1);
    }
}

fn fault(code: &'static str, address: u32, message: impl Into<String>) -> Fault {
    Fault::new(code, address, message)
}
fn reg_fault(offset: u32, message: &'static str) -> Fault {
    fault("SPU_REGISTER", SPU_BASE.wrapping_add(offset), message)
}
fn check_offset(offset: u32) -> Result<(), Fault> {
    if offset & 3 != 0 {
        Err(fault(
            "SPU_ALIGNMENT",
            SPU_BASE.wrapping_add(offset),
            "SPU requires aligned u32",
        ))
    } else {
        Ok(())
    }
}
