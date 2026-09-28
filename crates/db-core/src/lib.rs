//! DB32 bootstrap CPU. Devices, scheduling, and store deferral belong to the machine.

use db_contracts::{op, Bus, Fault, SYS_BASE};

#[derive(Clone, Debug)]
pub struct Cpu {
    pub regs: [u32; 16],
    pub pc: u32,
    pub waiting: bool,
    pub halted: bool,
}

impl Cpu {
    pub fn new(entry: u32) -> Self {
        let mut regs = [0; 16];
        regs[15] = 0x0003_0000;
        Self {
            regs,
            pc: entry,
            waiting: false,
            halted: false,
        }
    }

    /// Issue one complete instruction and return its latency in machine ticks.
    /// The machine schedules the returned state and deferred store at completion.
    /// A waiting or halted CPU has no instruction to issue and returns zero.
    pub fn step(&mut self, bus: &mut impl Bus) -> Result<u32, Fault> {
        if self.waiting || self.halted {
            return Ok(0);
        }
        let pc = self.pc;
        if pc & 3 != 0 {
            return Err(fault(
                "fetch_alignment",
                pc,
                pc,
                "instruction address is not four-byte aligned",
            ));
        }
        let word = bus.fetch(pc).map_err(|error| at_pc(error, pc))?;
        let opcode = (word & 0xff) as u8;
        let rd = ((word >> 8) & 15) as usize;
        let ra = ((word >> 12) & 15) as usize;
        let rb = ((word >> 16) & 15) as usize;
        let imm16 = ((word >> 16) as u16 as i16) as i32 as u32;
        let uimm16 = word >> 16;
        let imm20 = word >> 12;
        let next = pc.wrapping_add(4);
        let mut new_pc = next;
        let mut writeback = None;
        let mut waiting = false;
        let mut halted = false;
        let mut ticks = 1;

        match opcode {
            op::NOP | op::WFI | op::HALT => {
                if word >> 8 != 0 {
                    return Err(fault(
                        "encoding",
                        pc,
                        pc,
                        "system instruction has nonzero operand bits",
                    ));
                }
                waiting = opcode == op::WFI;
                halted = opcode == op::HALT;
            }
            op::ADD..=op::SLTU => {
                if word >> 20 != 0 {
                    return Err(fault(
                        "encoding",
                        pc,
                        pc,
                        "R instruction has nonzero reserved bits",
                    ));
                }
                let a = self.reg(ra);
                let b = self.reg(rb);
                let result = match opcode {
                    op::ADD => a.wrapping_add(b),
                    op::SUB => a.wrapping_sub(b),
                    op::MUL => {
                        ticks = 4;
                        a.wrapping_mul(b)
                    }
                    op::AND => a & b,
                    op::OR => a | b,
                    op::XOR => a ^ b,
                    op::SHL => a.wrapping_shl(b & 31),
                    op::SHR => a.wrapping_shr(b & 31),
                    op::SAR => ((a as i32) >> (b & 31)) as u32,
                    op::SLT => ((a as i32) < (b as i32)) as u32,
                    op::SLTU => (a < b) as u32,
                    _ => unreachable!(),
                };
                writeback = Some((rd, result));
            }
            op::ADDI..=op::XORI => {
                let a = self.reg(ra);
                let value = match opcode {
                    op::ADDI => a.wrapping_add(imm16),
                    op::ANDI => a & uimm16,
                    op::ORI => a | uimm16,
                    op::XORI => a ^ uimm16,
                    _ => unreachable!(),
                };
                writeback = Some((rd, value));
            }
            op::LUI => writeback = Some((rd, imm20 << 12)),
            op::LB..=op::LW => {
                let address = self.reg(ra).wrapping_add(imm16);
                let width = match opcode {
                    op::LB | op::LBU => 1,
                    op::LH | op::LHU => 2,
                    _ => 4,
                };
                check_alignment(address, width, pc)?;
                let raw = bus.read(address, width).map_err(|error| at_pc(error, pc))?;
                let value = match opcode {
                    op::LB => (raw as u8 as i8 as i32) as u32,
                    op::LBU => raw as u8 as u32,
                    op::LH => (raw as u16 as i16 as i32) as u32,
                    op::LHU => raw as u16 as u32,
                    _ => raw,
                };
                writeback = Some((rd, value));
                ticks = memory_ticks(address);
            }
            op::SB..=op::SW => {
                let address = self.reg(ra).wrapping_add(imm16);
                let width = match opcode {
                    op::SB => 1,
                    op::SH => 2,
                    _ => 4,
                };
                check_alignment(address, width, pc)?;
                bus.write(address, width, self.reg(rd))
                    .map_err(|error| at_pc(error, pc))?;
                ticks = memory_ticks(address);
            }
            op::BEQ..=op::BLTU => {
                let a = self.reg(rd);
                let b = self.reg(ra);
                let taken = match opcode {
                    op::BEQ => a == b,
                    op::BNE => a != b,
                    op::BLT => (a as i32) < (b as i32),
                    op::BLTU => a < b,
                    _ => unreachable!(),
                };
                if taken {
                    new_pc = next.wrapping_add(imm16.wrapping_mul(4));
                    validate_target(bus, new_pc, pc)?;
                }
            }
            op::JAL => {
                let displacement = ((imm20 << 12) as i32 >> 12).wrapping_mul(4) as u32;
                new_pc = next.wrapping_add(displacement);
                validate_target(bus, new_pc, pc)?;
                writeback = Some((rd, next));
            }
            op::JALR => {
                new_pc = self.reg(ra).wrapping_add(imm16);
                validate_target(bus, new_pc, pc)?;
                writeback = Some((rd, next));
            }
            _ => return Err(fault("opcode", pc, pc, format!("unknown opcode {opcode}"))),
        }

        if let Some((register, value)) = writeback {
            if register != 0 {
                self.regs[register] = value;
            }
        }
        self.regs[0] = 0;
        self.pc = new_pc;
        self.waiting = waiting;
        self.halted = halted;
        Ok(ticks)
    }

    fn reg(&self, index: usize) -> u32 {
        if index == 0 {
            0
        } else {
            self.regs[index]
        }
    }
}

fn memory_ticks(address: u32) -> u32 {
    if address >= SYS_BASE {
        4
    } else {
        2
    }
}

fn check_alignment(address: u32, width: u32, pc: u32) -> Result<(), Fault> {
    if address & (width - 1) != 0 {
        Err(fault(
            "data_alignment",
            address,
            pc,
            format!("{width}-byte access is misaligned"),
        ))
    } else {
        Ok(())
    }
}

fn validate_target(bus: &mut impl Bus, address: u32, pc: u32) -> Result<(), Fault> {
    if address & 3 != 0 {
        return Err(fault(
            "branch_alignment",
            address,
            pc,
            "branch target is not four-byte aligned",
        ));
    }
    bus.fetch(address)
        .map(|_| ())
        .map_err(|error| at_pc(error, pc))
}

fn fault(code: &'static str, address: u32, pc: u32, message: impl AsRef<str>) -> Fault {
    Fault::new(
        code,
        address,
        format!("PC 0x{pc:08x}: {}", message.as_ref()),
    )
}

fn at_pc(mut error: Fault, pc: u32) -> Fault {
    error.message = format!("PC 0x{pc:08x}: {}", error.message);
    error
}

#[cfg(test)]
mod tests {
    use super::*;
    use db_contracts::{RAM_BASE, RAM_SIZE};

    struct TestBus {
        rom: Vec<u8>,
        ram: Vec<u8>,
        mmio_value: u32,
        writes: Vec<(u32, u32, u32)>,
    }

    impl TestBus {
        fn new(words: &[u32]) -> Self {
            Self {
                rom: words.iter().flat_map(|word| word.to_le_bytes()).collect(),
                ram: vec![0; RAM_SIZE],
                mmio_value: 0xffff_8081,
                writes: Vec::new(),
            }
        }

        fn bytes(&self, address: u32, width: u32) -> Result<&[u8], Fault> {
            let size = width as usize;
            let offset = address as usize;
            if let Some(end) = offset.checked_add(size) {
                if let Some(bytes) = self.rom.get(offset..end) {
                    return Ok(bytes);
                }
            }
            if address >= RAM_BASE {
                let offset = (address - RAM_BASE) as usize;
                if let Some(end) = offset.checked_add(size) {
                    if let Some(bytes) = self.ram.get(offset..end) {
                        return Ok(bytes);
                    }
                }
            }
            Err(Fault::new(
                "bus",
                address,
                "address outside executable memory",
            ))
        }
    }

    impl Bus for TestBus {
        fn read(&mut self, address: u32, width: u32) -> Result<u32, Fault> {
            if address == SYS_BASE {
                return Ok(self.mmio_value);
            }
            let bytes = self.bytes(address, width)?;
            Ok(bytes
                .iter()
                .enumerate()
                .fold(0, |acc, (i, byte)| acc | ((*byte as u32) << (i * 8))))
        }

        fn write(&mut self, address: u32, width: u32, value: u32) -> Result<(), Fault> {
            if address != SYS_BASE && self.bytes(address, width).is_err() {
                return Err(Fault::new("bus", address, "write address outside memory"));
            }
            self.writes.push((address, width, value));
            Ok(())
        }

        fn fetch(&mut self, address: u32) -> Result<u32, Fault> {
            let bytes: [u8; 4] = self.bytes(address, 4)?.try_into().unwrap();
            Ok(u32::from_le_bytes(bytes))
        }
    }

    fn r(opcode: u8, rd: u32, ra: u32, rb: u32) -> u32 {
        opcode as u32 | rd << 8 | ra << 12 | rb << 16
    }

    fn i(opcode: u8, rd: u32, ra: u32, imm: u16) -> u32 {
        opcode as u32 | rd << 8 | ra << 12 | (imm as u32) << 16
    }

    fn j(opcode: u8, rd: u32, imm: u32) -> u32 {
        opcode as u32 | rd << 8 | imm << 12
    }

    #[test]
    fn reset_and_zero_register_are_fixed() {
        let mut cpu = Cpu::new(4);
        assert_eq!(cpu.regs[15], 0x30000);
        assert_eq!(cpu.pc, 4);
        cpu.regs[0] = 123;
        let mut bus = TestBus::new(&[0, i(op::ADDI, 0, 0, 7)]);
        assert_eq!(cpu.step(&mut bus).unwrap(), 1);
        assert_eq!(cpu.regs[0], 0);
        assert_eq!(cpu.pc, 8);
    }

    #[test]
    fn zero_register_reads_as_zero_even_if_public_array_was_modified() {
        let mut bus = TestBus::new(&[r(op::ADD, 1, 0, 0), i(op::SW, 0, 2, 0)]);
        let mut cpu = Cpu::new(0);
        cpu.regs[0] = 99;
        cpu.regs[2] = RAM_BASE;
        cpu.step(&mut bus).unwrap();
        cpu.step(&mut bus).unwrap();
        assert_eq!(cpu.regs[0], 0);
        assert_eq!(cpu.regs[1], 0);
        assert_eq!(bus.writes, [(RAM_BASE, 4, 0)]);
    }

    #[test]
    fn arithmetic_signs_wraps_and_masks_shift_counts() {
        let words = [
            r(op::ADD, 3, 1, 2),
            r(op::SUB, 4, 1, 2),
            r(op::MUL, 5, 1, 2),
            r(op::SAR, 6, 1, 7),
            r(op::SHR, 8, 1, 7),
            r(op::SLT, 9, 1, 2),
            r(op::SLTU, 10, 1, 2),
            i(op::ADDI, 11, 2, 0xffff),
            i(op::ANDI, 12, 1, 0x8000),
            i(op::ORI, 13, 0, 0x8000),
            i(op::XORI, 14, 13, 0x8000),
            j(op::LUI, 2, 0xabcde),
        ];
        let mut bus = TestBus::new(&words);
        let mut cpu = Cpu::new(0);
        cpu.regs[1] = 0xffff_fffe;
        cpu.regs[2] = 3;
        cpu.regs[7] = 33;
        let costs: Vec<_> = (0..words.len())
            .map(|_| cpu.step(&mut bus).unwrap())
            .collect();
        assert_eq!(costs[2], 4);
        assert!(costs
            .iter()
            .enumerate()
            .all(|(i, cost)| i == 2 || *cost == 1));
        assert_eq!(cpu.regs[3], 1);
        assert_eq!(cpu.regs[4], 0xffff_fffb);
        assert_eq!(cpu.regs[5], 0xffff_fffa);
        assert_eq!(cpu.regs[6], 0xffff_ffff);
        assert_eq!(cpu.regs[8], 0x7fff_ffff);
        assert_eq!(cpu.regs[9], 1);
        assert_eq!(cpu.regs[10], 0);
        assert_eq!(cpu.regs[11], 2);
        assert_eq!(cpu.regs[12], 0x8000);
        assert_eq!(cpu.regs[13], 0x8000);
        assert_eq!(cpu.regs[14], 0);
        assert_eq!(cpu.regs[2], 0xabcde000);
    }

    #[test]
    fn memory_width_sign_extension_store_source_and_mmio_cost() {
        let words = [
            i(op::LB, 3, 1, 0),
            i(op::LBU, 4, 1, 0),
            i(op::LH, 5, 1, 2),
            i(op::LHU, 6, 1, 2),
            i(op::LW, 7, 1, 0),
            i(op::SH, 2, 1, 4),
            i(op::LW, 8, 9, 0),
            i(op::SW, 2, 9, 0),
        ];
        let mut bus = TestBus::new(&words);
        bus.ram[0..4].copy_from_slice(&[0x81, 0x02, 0xfe, 0xff]);
        let mut cpu = Cpu::new(0);
        cpu.regs[1] = RAM_BASE;
        cpu.regs[2] = 0x1234_5678;
        cpu.regs[9] = SYS_BASE;
        let costs: Vec<_> = (0..words.len())
            .map(|_| cpu.step(&mut bus).unwrap())
            .collect();
        assert_eq!(costs, [2, 2, 2, 2, 2, 2, 4, 4]);
        assert_eq!(cpu.regs[3], 0xffff_ff81);
        assert_eq!(cpu.regs[4], 0x81);
        assert_eq!(cpu.regs[5], 0xffff_fffe);
        assert_eq!(cpu.regs[6], 0xfffe);
        assert_eq!(cpu.regs[7], 0xfffe_0281);
        assert_eq!(cpu.regs[8], bus.mmio_value);
        assert_eq!(
            bus.writes,
            [(RAM_BASE + 4, 2, 0x1234_5678), (SYS_BASE, 4, 0x1234_5678)]
        );
    }

    #[test]
    fn branch_fields_signedness_and_link_are_exact() {
        let words = [
            i(op::BLT, 1, 2, 1),
            i(op::BLTU, 1, 2, 1),
            i(op::BEQ, 2, 2, 1),
            i(op::ADDI, 3, 0, 99),
            j(op::JAL, 4, 1),
            i(op::ADDI, 3, 0, 88),
            i(op::JALR, 5, 6, 0),
            op::HALT as u32,
        ];
        let mut bus = TestBus::new(&words);
        let mut cpu = Cpu::new(0);
        cpu.regs[1] = u32::MAX;
        cpu.regs[2] = 1;
        cpu.regs[6] = 28;
        cpu.step(&mut bus).unwrap(); // signed -1 < 1, skip BLTU
        assert_eq!(cpu.pc, 8);
        cpu.step(&mut bus).unwrap(); // 1 == 1, skip ADDI
        assert_eq!(cpu.pc, 16);
        cpu.step(&mut bus).unwrap(); // JAL skips ADDI
        assert_eq!(cpu.pc, 24);
        assert_eq!(cpu.regs[4], 20);
        cpu.step(&mut bus).unwrap();
        assert_eq!(cpu.regs[5], 28);
        assert_eq!(cpu.pc, 28);
        cpu.step(&mut bus).unwrap();
        assert!(cpu.halted);
        assert_eq!(cpu.pc, 32);
        assert_eq!(cpu.regs[3], 0);
        assert_eq!(cpu.step(&mut bus).unwrap(), 0);
    }

    #[test]
    fn backward_branch_uses_signed_word_displacement() {
        let mut bus = TestBus::new(&[i(op::BNE, 1, 2, 0xffff), op::HALT as u32]);
        let mut cpu = Cpu::new(0);
        cpu.regs[1] = 1;
        assert_eq!(cpu.step(&mut bus).unwrap(), 1);
        assert_eq!(cpu.pc, 0);
    }

    #[test]
    fn jal_uses_signed_twenty_bit_word_displacement() {
        let mut bus = TestBus::new(&[j(op::JAL, 1, 0xfffff)]);
        let mut cpu = Cpu::new(0);
        cpu.step(&mut bus).unwrap();
        assert_eq!(cpu.pc, 0);
        assert_eq!(cpu.regs[1], 4);
    }

    #[test]
    fn invalid_encoding_alignment_and_targets_do_not_commit_cpu_state() {
        for word in [r(op::ADD, 1, 2, 3) | 1 << 20, op::WFI as u32 | 1 << 8, 255] {
            let mut bus = TestBus::new(&[word]);
            let mut cpu = Cpu::new(0);
            cpu.regs[1] = 42;
            let before = format!("{cpu:?}");
            assert!(cpu.step(&mut bus).is_err());
            assert_eq!(format!("{cpu:?}"), before);
        }
        let mut bus = TestBus::new(&[i(op::LW, 1, 2, 1)]);
        let mut cpu = Cpu::new(0);
        cpu.regs[2] = RAM_BASE;
        let error = cpu.step(&mut bus).unwrap_err();
        assert_eq!(error.address, RAM_BASE + 1);
        assert!(error.message.contains("PC 0x00000000"));
        assert_eq!(cpu.pc, 0);

        let mut bus = TestBus::new(&[i(op::JALR, 1, 2, 0)]);
        let mut cpu = Cpu::new(0);
        cpu.regs[2] = 3;
        assert_eq!(cpu.step(&mut bus).unwrap_err().code, "branch_alignment");
        assert_eq!(cpu.regs[1], 0);
        assert_eq!(cpu.pc, 0);

        cpu.regs[2] = 0x40000;
        let error = cpu.step(&mut bus).unwrap_err();
        assert_eq!(error.address, 0x40000);
        assert_eq!(cpu.regs[1], 0);
        assert_eq!(cpu.pc, 0);
    }

    #[test]
    fn wfi_advances_then_waits_without_issuing_more_instructions() {
        let mut bus = TestBus::new(&[op::WFI as u32, op::HALT as u32]);
        let mut cpu = Cpu::new(0);
        assert_eq!(cpu.step(&mut bus).unwrap(), 1);
        assert!(cpu.waiting);
        assert_eq!(cpu.pc, 4);
        assert_eq!(cpu.step(&mut bus).unwrap(), 0);
        assert_eq!(cpu.pc, 4);
        cpu.waiting = false; // Machine vblank wakeup.
        assert_eq!(cpu.step(&mut bus).unwrap(), 1);
        assert!(cpu.halted);
    }
}
