# DB32 bootstrap-1 implementation contract

This profile delivers CPU-written images in a WASM machine. It is distinct from the complete proposed DB32-v1: GPU, synthesizer, DMA, timer interrupts, vector interrupt handlers, snapshots, and benchmark scoring are not implemented in this first milestone. `WFI` wakes on vblank. `HALT` stops the CPU while video continues. Do not silently substitute bootstrap results for full-profile results.

## Cartridge and machine

32-byte header: bytes 0..4 ASCII `DB32`; u32 little-endian version=1 at 4; payload byte length at 8; entry byte offset at 12; bytes 16..32 zero. Payload immediately follows; 1..4096 bytes; exact file length; entry four-byte aligned with a full instruction in payload. RAM is 128 KiB at 0x10000..0x2ffff; ROM is the exact payload at address zero. All accesses validate alignment, full range and permissions. Executable RAM is supported. Reset zeros RAM/registers, r15=0x30000, PC=entry. r0 always zero. ISA fetch is four-byte aligned.

160×120 screen; 128 scanlines, 1600 ticks each, 204800 ticks/frame. Line 0 is captured at tick 0. Lines 0..119 capture pixels; line 120 publishes the completed image, latches pending video configuration, increments the frame counter, and wakes WFI. Lines 120..127 are blanking. CPU instructions read at issue and commit at completion; at the same tick CPU commits precede video events. Host calls may stop midway through an instruction; its pending effects must remain uncommitted until its completion. All run slices end at precisely the requested tick.

## Instruction encoding

All words little-endian, 32 bits. Opcode bits 0..7; rd bits 8..11; ra bits 12..15; rb bits 16..19. R format leaves bits 20..31 zero. I format replaces bits 16..31 with an immediate. U/J format uses bits 12..31 for imm20. Invalid reserved bits fault.

Opcodes, in numerical order (0..32): NOP, ADD, SUB, MUL, AND, OR, XOR, SHL, SHR, SAR, SLT, SLTU, ADDI, ANDI, ORI, XORI, LUI, LB, LBU, LH, LHU, LW, SB, SH, SW, BEQ, BNE, BLT, BLTU, JAL, JALR, WFI, HALT.

- R: `add rd, ra, rb` and analogous operations. Wrap32, signed SLT/SAR, unsigned SLTU/SHR; shifts mask count to five bits; low-word MUL.
- I arithmetic: `addi rd, ra, imm16` sign-extends; ANDI/ORI/XORI zero-extend imm16.
- `lui rd, imm20` writes imm20 << 12.
- Loads: `lw rd, offset(ra)` and analogous byte/halfword signed/unsigned forms. Sign-extended imm16 offset. Stores: `sw rs, offset(ra)` with the stored source in the rd field. Address sum wraps32, then bus checks full access.
- Branches: `beq ra, rb, label` encodes first compared register in rd field, second in ra field. Target = PC+4 + sign_extend(imm16)*4. BLT is signed; BLTU unsigned.
- `jal rd, label`: target PC+4 + sign_extend(imm20)*4; rd=PC+4. `jalr rd, offset(ra)`: exact wrapping register+signed offset target, no bit clearing; target must be four-byte aligned. Jumps write link only if valid.
- NOP/WFI/HALT require all operand bits zero. WFI advances PC and waits for next vblank. HALT advances PC and stops CPU execution.
- Cost: ALU/control/system=1 tick; MUL=4; RAM/ROM load/store=2; MMIO load/store=4. Fetch cost included. A fault is terminal with PC/tick/address context.

Assembler API: `db_asm::assemble(&str) -> Result<Assembly, AsmError>`; `Assembly { cartridge: Vec<u8>, payload_len: usize, listing: String }`; error implements Display. Support labels, `.equ NAME, expression`, `.byte`, `.word`, `.align`, `.entry label`, simple +/- expressions, register r0..r15, decimal/hex literals, `;` and `//` comments. Entry defaults to byte zero if `.entry` is omitted. Pseudos: `li rd, value` always LUI+ORI (8 bytes, stable two-pass size), `mov rd, rs` -> ADD rd,rs,r0, `j label` -> JAL r0,label. `li` upper=value>>12 and lower=value&0xfff. No external dependencies.

CPU API: `Cpu` Clone + Debug with public `regs:[u32;16]`, `pc:u32`, `waiting:bool`, `halted:bool`; `Cpu::new(entry:u32)`; `step(&mut self, bus:&mut impl Bus) -> Result<u32,Fault>` returns cost and advances CPU state. Composition executes step against a cloned CPU and deferred-store bus, then commits the resulting CPU/store at the returned tick. At most one store per instruction. Bus interface comes from db-contracts. Core does not know concrete devices.

## MMIO

All registers aligned u32 only. Unimplemented pages and unknown offsets fault; no GPU/sound placeholders that return success.

System page 0xf0000 read-only: +0 machine ID 0xdb320001; +4 ABI/profile version=1; +8 tick low (latches high); +12 latched tick high; +16 completed frames; +20 seed=1. Other offsets fault.

Video page 0xf5000: +0 pending framebuffer base; +4 pending stride bytes; +8 pending format; +12 pending palette base; +16 pending enable (0/1); +20 COMMIT (write 1 validates/queues pending configuration, read queued=0/1); +24 completed frames (RO); +28 scanline (RO); +32 active format (RO); +36 status (RO: bit0 active enabled, bit1 queued); +40 pending border RGB (0xRRGGBB). Other offsets fault.

Formats: 0=I1, 1=I2, 2=I4, 3=I8, 4=RGB888. Packed pixels use most-significant bits first; row stride may include padding and must be >= packed row size. RGB and palette bytes are R,G,B. Indexed formats require only their palette entry count, in RAM. Full framebuffer span including stride padding must fit RAM. Pending settings start base=RAM_BASE, stride=160, format=I8, palette=RAM_BASE+0x18000, enable=0, border=0. COMMIT snapshots settings; later setting writes must not alter the already queued configuration. Configuration latches only at line120. Reset displays black, alpha255.

Video API: `Video::new()`, `read_reg(offset:u32)->Result<u32,Fault>`, `write_reg(offset:u32,value:u32)->Result<(),Fault>` validates configured RAM address ranges using constants; `line_event(line:u32, ram:&[u8])->Result<bool,Fault>` true when frame published at line120; `frame(&self)->&[u8]` returns completed RGBA8 image; `frame_count(&self)->u32`; `active_format(&self)->u32`. Working and completed images are bounded observer buffers, never guest RAM.

## WASM ABI (composition owner)

No imports. `db_abi_version()->u32=1`; `db_reset()`; `db_input_ptr()/db_input_capacity()` (64 KiB upload workspace); `db_load(len:u32)->i32`; `db_assemble(source_len:u32)->i32`; `db_load_assembled()->i32`; `db_assembled_ptr()/db_assembled_len()`; `db_listing_ptr()/db_listing_len()`; `db_run(ticks:u32)->i32`; `db_frame_ptr()/db_frame_len()`; `db_frame_count()`; `db_ticks_lo()/db_ticks_hi()`; `db_pc()`; `db_register(index)`; `db_status()`; `db_payload_size()`; `db_format()`; `db_error_ptr()/db_error_len()`.

Status: 0=empty, 1=running, 2=halted, 3=fault, 4=waiting. Load/assemble return 0 success, -1 error; read UTF-8 error via error pointer/length. run returns current status, with a hard max slice of 2048000 ticks. WASM output memory may move between calls; hosts reacquire views after calls. Input and output pointers are module/host ABI, not guest addresses. Reset preserves last assembly for convenient load_assembled but clears machine/error state.

Browser worker owns the instance. Load `.asm` examples, assemble inside WASM, load assembled cart, and execute in bounded slices; return copied frame and telemetry to main UI. CPU and video must have no JavaScript implementation. Default example path `examples/aurora.asm`; alternate `examples/rgb-study.asm`. Build outputs `web/machine.wasm` and copies public examples into `web/examples/`.

The bootstrap headless host uses Node's WebAssembly API to keep the developer setup dependency-free. The same module is portable to Wasmtime through this ABI; that embedding remains a later implementation task. Browser/Node raw-frame parity is tested for this milestone.
