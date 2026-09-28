//! Shared contracts for the DB32 bootstrap-1, gpu-1 and spu-1 profiles.
pub const RAM_BASE: u32 = 0x0001_0000;
pub const RAM_SIZE: usize = 128 * 1024;
pub const CART_LIMIT: usize = 4096;
pub const HEADER_SIZE: usize = 32;
pub const SYS_BASE: u32 = 0x000f_0000;
pub const GPU_BASE: u32 = 0x000f_3000;
pub const VIDEO_BASE: u32 = 0x000f_5000;
pub const SPU_BASE: u32 = 0x000f_6000;
pub const AUDIO_RATE: u32 = 48_000;
pub const AUDIO_BLOCK_FRAMES: u32 = 256;
pub const AUDIO_BLOCK_TICKS: u64 = 65_536;
pub const WIDTH: usize = 160;
pub const HEIGHT: usize = 120;
pub const FRAME_BYTES: usize = WIDTH * HEIGHT * 4;
pub const LINE_TICKS: u64 = 1600;
pub const FRAME_TICKS: u64 = LINE_TICKS * 128;
pub const CLOCK_HZ: u32 = 12_288_000;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Fault {
    pub code: &'static str,
    pub address: u32,
    pub message: String,
}
impl Fault {
    pub fn new(code: &'static str, address: u32, message: impl Into<String>) -> Self {
        Self {
            code,
            address,
            message: message.into(),
        }
    }
}
impl std::fmt::Display for Fault {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{} at 0x{:08x}: {}",
            self.code, self.address, self.message
        )
    }
}
impl std::error::Error for Fault {}

pub trait Bus {
    fn read(&mut self, address: u32, width: u32) -> Result<u32, Fault>;
    fn write(&mut self, address: u32, width: u32, value: u32) -> Result<(), Fault>;
    fn fetch(&mut self, address: u32) -> Result<u32, Fault>;
}

pub mod op {
    pub const NOP: u8 = 0;
    pub const ADD: u8 = 1;
    pub const SUB: u8 = 2;
    pub const MUL: u8 = 3;
    pub const AND: u8 = 4;
    pub const OR: u8 = 5;
    pub const XOR: u8 = 6;
    pub const SHL: u8 = 7;
    pub const SHR: u8 = 8;
    pub const SAR: u8 = 9;
    pub const SLT: u8 = 10;
    pub const SLTU: u8 = 11;
    pub const ADDI: u8 = 12;
    pub const ANDI: u8 = 13;
    pub const ORI: u8 = 14;
    pub const XORI: u8 = 15;
    pub const LUI: u8 = 16;
    pub const LB: u8 = 17;
    pub const LBU: u8 = 18;
    pub const LH: u8 = 19;
    pub const LHU: u8 = 20;
    pub const LW: u8 = 21;
    pub const SB: u8 = 22;
    pub const SH: u8 = 23;
    pub const SW: u8 = 24;
    pub const BEQ: u8 = 25;
    pub const BNE: u8 = 26;
    pub const BLT: u8 = 27;
    pub const BLTU: u8 = 28;
    pub const JAL: u8 = 29;
    pub const JALR: u8 = 30;
    pub const WFI: u8 = 31;
    pub const HALT: u8 = 32;
}
