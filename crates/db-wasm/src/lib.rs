//! Import-free WASM composition of CPU, GPU, signal compute, video and assembler.
pub mod machine;
use machine::Machine;
use std::cell::RefCell;

const INPUT_CAPACITY: usize = 65_536;
struct Host {
    machine: Machine,
    input: Vec<u8>,
    assembled: Vec<u8>,
    listing: String,
    error: String,
}
impl Host {
    fn new() -> Self {
        Self {
            machine: Machine::new(),
            input: vec![0; INPUT_CAPACITY],
            assembled: Vec::new(),
            listing: String::new(),
            error: String::new(),
        }
    }
}
thread_local! { static HOST: RefCell<Host> = RefCell::new(Host::new()); }
fn read<T>(f: impl FnOnce(&Host) -> T) -> T {
    HOST.with(|h| f(&h.borrow()))
}
fn write<T>(f: impl FnOnce(&mut Host) -> T) -> T {
    HOST.with(|h| f(&mut h.borrow_mut()))
}

#[no_mangle]
pub extern "C" fn db_abi_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn db_profile() -> u32 {
    read(|h| h.machine.profile)
}
#[no_mangle]
pub extern "C" fn db_gpu_status() -> u32 {
    read(|h| h.machine.gpu.status())
}
#[no_mangle]
pub extern "C" fn db_gpu_ticks() -> u32 {
    read(|h| h.machine.gpu.elapsed_ticks())
}
#[no_mangle]
pub extern "C" fn db_gpu_dispatches() -> u32 {
    read(|h| h.machine.gpu.completed_dispatches())
}
#[no_mangle]
pub extern "C" fn db_gpu_invocations() -> u32 {
    read(|h| h.machine.gpu.completed_invocations())
}
#[no_mangle]
pub extern "C" fn db_gpu_pc() -> u32 {
    read(|h| h.machine.gpu.pc())
}
#[no_mangle]
pub extern "C" fn db_gpu_last_ticks() -> u32 {
    read(|h| h.machine.gpu.last_ticks())
}

#[no_mangle]
pub extern "C" fn db_audio_ptr() -> u32 {
    read(|h| h.machine.spu.audio().as_ptr() as u32)
}
#[no_mangle]
pub extern "C" fn db_audio_len() -> u32 {
    read(|h| h.machine.spu.audio().len() as u32)
}
#[no_mangle]
pub extern "C" fn db_audio_clear() {
    write(|h| h.machine.spu.clear_audio());
}
#[no_mangle]
pub extern "C" fn db_audio_rate() -> u32 {
    db_contracts::AUDIO_RATE
}
#[no_mangle]
pub extern "C" fn db_spu_status() -> u32 {
    read(|h| h.machine.spu.status())
}
#[no_mangle]
pub extern "C" fn db_spu_blocks() -> u32 {
    read(|h| h.machine.spu.blocks())
}
#[no_mangle]
pub extern "C" fn db_spu_samples_lo() -> u32 {
    read(|h| h.machine.spu.sample_count() as u32)
}
#[no_mangle]
pub extern "C" fn db_spu_samples_hi() -> u32 {
    read(|h| (h.machine.spu.sample_count() >> 32) as u32)
}
#[no_mangle]
pub extern "C" fn db_spu_peak() -> f32 {
    read(|h| h.machine.spu.peak())
}
#[no_mangle]
pub extern "C" fn db_spu_output_base() -> u32 {
    read(|h| h.machine.spu.read_reg(0x50).unwrap_or(0))
}
#[no_mangle]
pub extern "C" fn db_audio_overruns() -> u32 {
    read(|h| h.machine.spu.overruns())
}
#[no_mangle]
pub extern "C" fn db_spu_last_ticks() -> u32 {
    read(|h| h.machine.spu.last_ticks())
}
#[no_mangle]
pub extern "C" fn db_spu_set_external(enabled: u32) -> i32 {
    write(|h| match h.machine.set_spu_external(enabled) {
        Ok(()) => {
            h.error.clear();
            0
        }
        Err(e) => {
            h.error = e;
            -1
        }
    })
}
#[no_mangle]
pub extern "C" fn db_spu_external_pending() -> u32 {
    read(|h| u32::from(h.machine.spu_external_pending()))
}
#[no_mangle]
pub extern "C" fn db_spu_read_reg(offset: u32) -> u32 {
    read(|h| h.machine.spu.read_dispatch_reg(offset).unwrap_or(0))
}
#[no_mangle]
pub extern "C" fn db_spu_external_complete() -> i32 {
    write(|h| match h.machine.spu_external_complete() {
        Ok(()) => {
            h.error.clear();
            0
        }
        Err(e) => {
            h.error = e;
            -1
        }
    })
}
#[no_mangle]
pub extern "C" fn db_spu_external_fallback() -> i32 {
    write(|h| match h.machine.spu_external_fallback() {
        Ok(()) => {
            h.error.clear();
            0
        }
        Err(e) => {
            h.error = e;
            -1
        }
    })
}
#[no_mangle]
pub extern "C" fn db_gpu_set_external(enabled: u32) -> i32 {
    write(|h| match h.machine.set_gpu_external(enabled) {
        Ok(()) => {
            h.error.clear();
            0
        }
        Err(e) => {
            h.error = e;
            -1
        }
    })
}
#[no_mangle]
pub extern "C" fn db_gpu_external_pending() -> u32 {
    read(|h| u32::from(h.machine.gpu_external_pending()))
}
#[no_mangle]
pub extern "C" fn db_gpu_external_complete() -> i32 {
    write(|h| match h.machine.gpu_external_complete() {
        Ok(()) => {
            h.error.clear();
            0
        }
        Err(e) => {
            h.error = e;
            -1
        }
    })
}
#[no_mangle]
pub extern "C" fn db_gpu_external_fail() -> i32 {
    write(|h| match h.machine.gpu_external_fail() {
        Ok(()) => {
            h.error.clear();
            0
        }
        Err(e) => {
            h.error = e;
            -1
        }
    })
}
#[no_mangle]
pub extern "C" fn db_gpu_read_reg(offset: u32) -> u32 {
    read(|h| {
        if h.machine.gpu_external_pending() {
            h.machine.gpu.read_active_reg(offset).unwrap_or(0)
        } else {
            0
        }
    })
}
#[no_mangle]
pub extern "C" fn db_ram_ptr() -> u32 {
    read(|h| h.machine.ram.as_ptr() as u32)
}
#[no_mangle]
pub extern "C" fn db_ram_len() -> u32 {
    read(|h| h.machine.ram.len() as u32)
}
#[no_mangle]
pub extern "C" fn db_rom_ptr() -> u32 {
    read(|h| h.machine.rom.as_ptr() as u32)
}
#[no_mangle]
pub extern "C" fn db_rom_len() -> u32 {
    read(|h| h.machine.rom.len() as u32)
}
#[no_mangle]
pub extern "C" fn db_reset() {
    write(|h| {
        h.machine = Machine::new();
        h.error.clear();
    });
}
#[no_mangle]
pub extern "C" fn db_input_ptr() -> u32 {
    read(|h| h.input.as_ptr() as u32)
}
#[no_mangle]
pub extern "C" fn db_input_capacity() -> u32 {
    INPUT_CAPACITY as u32
}
#[no_mangle]
pub extern "C" fn db_load(len: u32) -> i32 {
    write(|h| {
        if len as usize > h.input.len() {
            h.error = "upload exceeds input capacity".into();
            return -1;
        }
        match h.machine.load(&h.input[..len as usize]) {
            Ok(()) => {
                h.error.clear();
                0
            }
            Err(e) => {
                h.error = e;
                -1
            }
        }
    })
}
#[no_mangle]
pub extern "C" fn db_assemble(len: u32) -> i32 {
    write(|h| {
        // A failed build never leaves an old cartridge available for accidental submission.
        h.assembled.clear();
        h.listing.clear();
        if len as usize > h.input.len() {
            h.error = "source exceeds input capacity".into();
            return -1;
        }
        let source = match std::str::from_utf8(&h.input[..len as usize]) {
            Ok(s) => s,
            Err(_) => {
                h.error = "assembly source must be UTF-8".into();
                return -1;
            }
        };
        match db_asm::assemble(source) {
            Ok(a) => {
                h.assembled = a.cartridge;
                h.listing = a.listing;
                h.error.clear();
                0
            }
            Err(e) => {
                h.error = e.to_string();
                -1
            }
        }
    })
}
#[no_mangle]
pub extern "C" fn db_load_assembled() -> i32 {
    write(|h| match h.machine.load(&h.assembled) {
        Ok(()) => {
            h.error.clear();
            0
        }
        Err(e) => {
            h.error = e;
            -1
        }
    })
}
#[no_mangle]
pub extern "C" fn db_run(ticks: u32) -> i32 {
    write(|h| match h.machine.run(ticks) {
        Ok(status) => {
            h.error.clear();
            status as i32
        }
        Err(e) => {
            h.error = e;
            3
        }
    })
}
#[no_mangle]
pub extern "C" fn db_assembled_ptr() -> u32 {
    read(|h| h.assembled.as_ptr() as u32)
}
#[no_mangle]
pub extern "C" fn db_assembled_len() -> u32 {
    read(|h| h.assembled.len() as u32)
}
#[no_mangle]
pub extern "C" fn db_listing_ptr() -> u32 {
    read(|h| h.listing.as_ptr() as u32)
}
#[no_mangle]
pub extern "C" fn db_listing_len() -> u32 {
    read(|h| h.listing.len() as u32)
}
#[no_mangle]
pub extern "C" fn db_frame_ptr() -> u32 {
    read(|h| h.machine.video.frame().as_ptr() as u32)
}
#[no_mangle]
pub extern "C" fn db_frame_len() -> u32 {
    read(|h| h.machine.video.frame().len() as u32)
}
#[no_mangle]
pub extern "C" fn db_frame_count() -> u32 {
    read(|h| h.machine.video.frame_count())
}
#[no_mangle]
pub extern "C" fn db_ticks_lo() -> u32 {
    read(|h| h.machine.tick as u32)
}
#[no_mangle]
pub extern "C" fn db_ticks_hi() -> u32 {
    read(|h| (h.machine.tick >> 32) as u32)
}
#[no_mangle]
pub extern "C" fn db_pc() -> u32 {
    read(|h| h.machine.cpu.pc)
}
#[no_mangle]
pub extern "C" fn db_register(index: u32) -> u32 {
    read(|h| h.machine.cpu.regs.get(index as usize).copied().unwrap_or(0))
}
#[no_mangle]
pub extern "C" fn db_status() -> u32 {
    read(|h| h.machine.status())
}
#[no_mangle]
pub extern "C" fn db_payload_size() -> u32 {
    read(|h| h.machine.rom.len() as u32)
}
#[no_mangle]
pub extern "C" fn db_format() -> u32 {
    read(|h| h.machine.video.active_format())
}
#[no_mangle]
pub extern "C" fn db_error_ptr() -> u32 {
    read(|h| h.error.as_ptr() as u32)
}
#[no_mangle]
pub extern "C" fn db_error_len() -> u32 {
    read(|h| h.error.len() as u32)
}
#[no_mangle]
pub extern "C" fn db_instruction_count_lo() -> u32 {
    read(|h| h.machine.instructions as u32)
}
