//! Two-pass assembler for DB32 bootstrap-1 and gpu-1 cartridges.
use db_contracts::{op, CART_LIMIT, HEADER_SIZE};
use std::collections::{HashMap, HashSet};
use std::fmt;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Assembly {
    pub cartridge: Vec<u8>,
    pub payload_len: usize,
    pub listing: String,
}

/// An offline link image, not a loadable cartridge. Sparse `.org` gaps are zero.
/// The packer extracts its ROM and RAM spans before enforcing CART_LIMIT.
#[derive(Clone, Debug)]
pub struct Image {
    pub bytes: Vec<u8>,
    pub entry: u32,
    pub profile: u32,
    pub listing: String,
    pub symbols: HashMap<String, i64>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AsmError {
    pub line: usize,
    pub message: String,
}
impl fmt::Display for AsmError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.line == 0 {
            write!(f, "{}", self.message)
        } else {
            write!(f, "line {}: {}", self.line, self.message)
        }
    }
}
impl std::error::Error for AsmError {}

fn err(line: usize, message: impl Into<String>) -> AsmError {
    AsmError {
        line,
        message: message.into(),
    }
}

#[derive(Clone)]
struct Statement {
    line: usize,
    address: usize,
    source: String,
    head: String,
    args: Vec<String>,
}

#[derive(Clone, Copy)]
enum GpuForm {
    None,
    Literal,
    FloatLiteral,
    Unary,
    Builtin(u32),
    Binary,
    Sphere,
    Binding,
    Branch,
    Jump,
}

fn gpu_instruction(head: &str) -> Option<(u8, GpuForm)> {
    use GpuForm::*;
    Some(match head {
        "g.end" => (0, None),
        "g.li" => (1, Literal),
        "g.fli" => (1, FloatLiteral),
        "g.mov" => (2, Unary),
        "g.id" => (3, Builtin(5)),
        "g.uniform" => (4, Builtin(15)),
        "g.add" => (5, Binary),
        "g.sub" => (6, Binary),
        "g.mul" => (7, Binary),
        "g.and" => (8, Binary),
        "g.or" => (9, Binary),
        "g.xor" => (10, Binary),
        "g.shl" => (11, Binary),
        "g.shr" => (12, Binary),
        "g.sar" => (13, Binary),
        "g.slt" => (14, Binary),
        "g.sltu" => (15, Binary),
        "g.fadd" => (16, Binary),
        "g.fsub" => (17, Binary),
        "g.fmul" => (18, Binary),
        "g.fdiv" => (19, Binary),
        "g.fmin" => (20, Binary),
        "g.fmax" => (21, Binary),
        "g.sqrt" => (22, Unary),
        "g.rsqrt" => (23, Unary),
        "g.itof" => (24, Unary),
        "g.ftoi" => (25, Unary),
        "g.flt" => (26, Binary),
        "g.fle" => (27, Binary),
        "g.vadd" => (28, Binary),
        "g.vsub" => (29, Binary),
        "g.vscale" => (30, Binary),
        "g.dot3" => (31, Binary),
        "g.norm3" => (32, Unary),
        "g.reflect3" => (33, Binary),
        "g.sphere" => (34, Sphere),
        "g.ld" => (35, Binding),
        "g.st" => (36, Binding),
        "g.ldb" => (37, Binding),
        "g.stb" => (38, Binding),
        "g.rgb" => (39, Binding),
        "g.bz" => (40, Branch),
        "g.bnz" => (41, Branch),
        "g.jmp" => (42, Jump),
        _ => return Option::None,
    })
}

pub fn assemble(source: &str) -> Result<Assembly, AsmError> {
    let image = assemble_inner(source, false)?;
    let mut cartridge = vec![0u8; HEADER_SIZE];
    cartridge[..4].copy_from_slice(b"DB32");
    cartridge[4..8].copy_from_slice(&image.profile.to_le_bytes());
    cartridge[8..12].copy_from_slice(&(image.bytes.len() as u32).to_le_bytes());
    cartridge[12..16].copy_from_slice(&image.entry.to_le_bytes());
    cartridge.extend_from_slice(&image.bytes);
    Ok(Assembly {
        cartridge,
        payload_len: image.bytes.len(),
        listing: image.listing,
    })
}

/// Assemble CPU code/data at their final RAM addresses for guest self-extraction.
/// Only this offline API accepts forward `.org`; the cartridge API is unchanged.
pub fn assemble_image(source: &str) -> Result<Image, AsmError> {
    assemble_inner(source, true)
}

fn assemble_inner(source: &str, image_mode: bool) -> Result<Image, AsmError> {
    let limit = if image_mode { 0x30000 } else { CART_LIMIT };
    let mut labels = HashMap::<String, i64>::new();
    let mut equs = HashMap::<String, (usize, String)>::new();
    let mut equ_order = Vec::<String>::new();
    let mut statements = Vec::<Statement>::new();
    let mut cpu_instructions = HashSet::<usize>::new();
    let mut gpu_instructions = HashSet::<usize>::new();
    let mut address = 0usize;
    let mut entry: Option<(usize, String)> = None;
    // The profile applies to the whole cartridge, regardless of directive position.
    let mut profile: Option<(usize, u32)> = None;
    let mut first_gpu_line = None;
    for (index, raw) in source.lines().enumerate() {
        let line = index + 1;
        let clean = raw
            .split(';')
            .next()
            .unwrap_or("")
            .split("//")
            .next()
            .unwrap_or("")
            .trim();
        if clean.is_empty() {
            continue;
        }
        let mut rest = clean;
        while let Some(colon) = rest.find(':') {
            let candidate = rest[..colon].trim();
            if candidate.is_empty() || candidate.chars().any(char::is_whitespace) {
                break;
            }
            if !identifier(candidate) {
                return Err(err(line, format!("invalid label `{candidate}`")));
            }
            let key = candidate.to_ascii_lowercase();
            if labels.contains_key(&key) || equs.contains_key(&key) {
                return Err(err(line, format!("duplicate symbol `{candidate}`")));
            }
            labels.insert(key, address as i64);
            rest = rest[colon + 1..].trim();
        }
        if rest.is_empty() {
            continue;
        }
        let split = rest.find(char::is_whitespace).unwrap_or(rest.len());
        let head = rest[..split].to_ascii_lowercase();
        let args = operands(rest[split..].trim(), line)?;
        if head == ".equ" {
            if args.len() != 2 || !identifier(&args[0]) {
                return Err(err(line, "expected `.equ NAME, expression`"));
            }
            let key = args[0].to_ascii_lowercase();
            if labels.contains_key(&key) || equs.contains_key(&key) {
                return Err(err(line, format!("duplicate symbol `{}`", args[0])));
            }
            equ_order.push(key.clone());
            equs.insert(key, (line, args[1].clone()));
            continue;
        }
        if head == ".entry" {
            if args.len() != 1 || entry.is_some() {
                return Err(err(line, "expected one `.entry label`"));
            }
            entry = Some((line, args[0].clone()));
            continue;
        }
        if head == ".profile" {
            if profile.is_some() {
                return Err(err(line, "duplicate `.profile` directive"));
            }
            let version =
                match args.as_slice() {
                    [name] if name.eq_ignore_ascii_case("bootstrap-1") => 1,
                    [name] if name.eq_ignore_ascii_case("gpu-1") => 2,
                    [name] if name.eq_ignore_ascii_case("spu-1") => 3,
                    [name] if name.eq_ignore_ascii_case("dynamic-1") => 4,
                    _ => return Err(err(
                        line,
                        "expected `.profile bootstrap-1`, `.profile gpu-1`, `.profile spu-1`, or `.profile dynamic-1`",
                    )),
                };
            profile = Some((line, version));
            continue;
        }
        if head == ".org" && image_mode {
            expect(&args, 1, line)?;
            let next = expression(&args[0], &labels, &equs, line)?;
            if next < address as i64 || next >= limit as i64 {
                return Err(err(line, "image origin must move forward below 0x30000"));
            }
            address = next as usize;
            continue;
        }
        let size = match head.as_str() {
            ".byte" => {
                if args.is_empty() {
                    return Err(err(line, "`.byte` needs values"));
                }
                args.len()
            }
            ".word" => {
                if args.is_empty() {
                    return Err(err(line, "`.word` needs values"));
                }
                args.len()
                    .checked_mul(4)
                    .ok_or_else(|| err(line, "size overflow"))?
            }
            ".float" => {
                if args.is_empty() {
                    return Err(err(line, "`.float` needs values"));
                }
                args.len()
                    .checked_mul(4)
                    .ok_or_else(|| err(line, "size overflow"))?
            }
            ".align" => {
                if args.len() != 1 {
                    return Err(err(line, "`.align` needs one byte alignment"));
                }
                let value = expression(&args[0], &labels, &equs, line)?;
                if value < 1 || value > 4096 || !(value as u64).is_power_of_two() {
                    return Err(err(line, "alignment must be a power of two from 1 to 4096"));
                }
                let alignment = value as usize;
                (alignment - address % alignment) % alignment
            }
            "li" => {
                if args.len() != 2 {
                    return Err(err(line, "`li` needs two operands"));
                }
                cpu_instructions.insert(address);
                8
            }
            "mov" | "j" | "nop" | "wfi" | "halt" | "add" | "sub" | "mul" | "and" | "or" | "xor"
            | "shl" | "shr" | "sar" | "slt" | "sltu" | "addi" | "andi" | "ori" | "xori" | "lui"
            | "lb" | "lbu" | "lh" | "lhu" | "lw" | "sb" | "sh" | "sw" | "beq" | "bne" | "blt"
            | "bltu" | "jal" | "jalr" => {
                cpu_instructions.insert(address);
                4
            }
            _ => {
                if let Some((_, form)) = gpu_instruction(&head) {
                    first_gpu_line.get_or_insert(line);
                    gpu_instructions.insert(address);
                    if matches!(
                        form,
                        GpuForm::Literal | GpuForm::FloatLiteral | GpuForm::Branch | GpuForm::Jump
                    ) {
                        8
                    } else {
                        4
                    }
                } else {
                    return Err(err(
                        line,
                        format!("unknown directive or instruction `{head}`"),
                    ));
                }
            }
        };
        if (cpu_instructions.contains(&address) || gpu_instructions.contains(&address))
            && address % 4 != 0
        {
            return Err(err(
                line,
                "instruction address is not four-byte aligned; use `.align 4`",
            ));
        }
        statements.push(Statement {
            line,
            address,
            source: rest.to_string(),
            head,
            args,
        });
        address = address
            .checked_add(size)
            .ok_or_else(|| err(line, "payload size overflow"))?;
        if address > limit {
            return Err(err(line, format!("payload exceeds {limit} bytes")));
        }
    }
    if profile.map_or(true, |(_, version)| version < 2) {
        if let Some(line) = first_gpu_line {
            return Err(err(
                line,
                "GPU instructions require `.profile gpu-1`, `.profile spu-1`, or `.profile dynamic-1`",
            ));
        }
    }
    // An unused definition must still be a valid expression. Walk in source
    // order so the first malformed definition gets a stable diagnostic.
    // Cache resolved values and share the work budget across this walk.
    let mut equ_cache = HashMap::new();
    let mut equ_work = MAX_EXPRESSION_WORK;
    for name in &equ_order {
        let (line, _) = &equs[name];
        resolve(
            name,
            &labels,
            &equs,
            *line,
            &mut Vec::new(),
            &mut equ_cache,
            &mut equ_work,
        )?;
    }
    if address == 0 {
        return Err(err(0, "payload is empty"));
    }
    // Small programs start at byte zero; `.entry` selects another instruction.
    let (entry_line, entry_expr) = entry.unwrap_or((0, "0".to_string()));
    let entry_value = expression(&entry_expr, &labels, &equs, entry_line)?;
    if entry_value < 0
        || entry_value >= address as i64
        || entry_value % 4 != 0
        || !cpu_instructions.contains(&(entry_value as usize))
    {
        return Err(err(
            entry_line,
            "entry must point to a complete aligned CPU instruction in the payload",
        ));
    }
    let mut payload = vec![0u8; address];
    let mut listing = String::new();
    for statement in &statements {
        let pc = statement.address;
        let line = statement.line;
        let args = &statement.args;
        let bytes: Vec<u8> = match statement.head.as_str() {
            ".byte" => args
                .iter()
                .map(|arg| checked_byte(expression(arg, &labels, &equs, line)?, line))
                .collect::<Result<Vec<_>, _>>()?,
            ".word" => args
                .iter()
                .map(|arg| {
                    checked_word(expression(arg, &labels, &equs, line)?, line).map(u32::to_le_bytes)
                })
                .collect::<Result<Vec<_>, _>>()?
                .concat(),
            ".float" => args
                .iter()
                .map(|arg| {
                    finite_float(arg, line)
                        .map(f32::to_bits)
                        .map(u32::to_le_bytes)
                })
                .collect::<Result<Vec<_>, _>>()?
                .concat(),
            ".align" => {
                let alignment = expression(&args[0], &labels, &equs, line)? as usize;
                vec![0; (alignment - pc % alignment) % alignment]
            }
            "li" => {
                expect(args, 2, line)?;
                let rd = register(&args[0], line)?;
                let value = checked_word(expression(&args[1], &labels, &equs, line)?, line)?;
                [
                    u(16, rd, value >> 12).to_le_bytes(),
                    i(14, rd, rd, (value & 0xfff) as u16).to_le_bytes(),
                ]
                .concat()
            }
            "mov" => {
                expect(args, 2, line)?;
                r(
                    op::ADD,
                    register(&args[0], line)?,
                    register(&args[1], line)?,
                    0,
                )
                .to_le_bytes()
                .to_vec()
            }
            "j" => {
                expect(args, 1, line)?;
                jump(0, &args[0], pc, &labels, &equs, line)?
                    .to_le_bytes()
                    .to_vec()
            }
            "nop" | "wfi" | "halt" => {
                expect(args, 0, line)?;
                (match statement.head.as_str() {
                    "nop" => op::NOP,
                    "wfi" => op::WFI,
                    _ => op::HALT,
                } as u32)
                    .to_le_bytes()
                    .to_vec()
            }
            "add" | "sub" | "mul" | "and" | "or" | "xor" | "shl" | "shr" | "sar" | "slt"
            | "sltu" => {
                expect(args, 3, line)?;
                let code = match statement.head.as_str() {
                    "add" => op::ADD,
                    "sub" => op::SUB,
                    "mul" => op::MUL,
                    "and" => op::AND,
                    "or" => op::OR,
                    "xor" => op::XOR,
                    "shl" => op::SHL,
                    "shr" => op::SHR,
                    "sar" => op::SAR,
                    "slt" => op::SLT,
                    _ => op::SLTU,
                };
                r(
                    code,
                    register(&args[0], line)?,
                    register(&args[1], line)?,
                    register(&args[2], line)?,
                )
                .to_le_bytes()
                .to_vec()
            }
            "addi" | "andi" | "ori" | "xori" => {
                expect(args, 3, line)?;
                let code = match statement.head.as_str() {
                    "addi" => op::ADDI,
                    "andi" => op::ANDI,
                    "ori" => op::ORI,
                    _ => op::XORI,
                };
                let value = expression(&args[2], &labels, &equs, line)?;
                let immediate = if code == op::ADDI {
                    signed(value, 16, line)? as u16
                } else {
                    unsigned(value, 16, line)? as u16
                };
                i(
                    code,
                    register(&args[0], line)?,
                    register(&args[1], line)?,
                    immediate,
                )
                .to_le_bytes()
                .to_vec()
            }
            "lui" => {
                expect(args, 2, line)?;
                let value = unsigned(expression(&args[1], &labels, &equs, line)?, 20, line)?;
                u(op::LUI, register(&args[0], line)?, value)
                    .to_le_bytes()
                    .to_vec()
            }
            "lb" | "lbu" | "lh" | "lhu" | "lw" | "sb" | "sh" | "sw" | "jalr" => {
                expect(args, 2, line)?;
                let code = match statement.head.as_str() {
                    "lb" => op::LB,
                    "lbu" => op::LBU,
                    "lh" => op::LH,
                    "lhu" => op::LHU,
                    "lw" => op::LW,
                    "sb" => op::SB,
                    "sh" => op::SH,
                    "sw" => op::SW,
                    _ => op::JALR,
                };
                let (offset, base) = memory(&args[1], line)?;
                let value = signed(expression(offset, &labels, &equs, line)?, 16, line)? as u16;
                i(
                    code,
                    register(&args[0], line)?,
                    register(base, line)?,
                    value,
                )
                .to_le_bytes()
                .to_vec()
            }
            "beq" | "bne" | "blt" | "bltu" => {
                expect(args, 3, line)?;
                let code = match statement.head.as_str() {
                    "beq" => op::BEQ,
                    "bne" => op::BNE,
                    "blt" => op::BLT,
                    _ => op::BLTU,
                };
                let offset = relative(&args[2], pc, 16, &labels, &equs, line)? as u16;
                i(
                    code,
                    register(&args[0], line)?,
                    register(&args[1], line)?,
                    offset,
                )
                .to_le_bytes()
                .to_vec()
            }
            "jal" => {
                expect(args, 2, line)?;
                jump(
                    register(&args[0], line)?,
                    &args[1],
                    pc,
                    &labels,
                    &equs,
                    line,
                )?
                .to_le_bytes()
                .to_vec()
            }
            _ => encode_gpu(statement, &labels, &equs, &gpu_instructions)?,
        };
        let end = pc + bytes.len();
        payload[pc..end].copy_from_slice(&bytes);
        let hex = bytes
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<Vec<_>>()
            .join(" ");
        listing.push_str(&format!(
            "{pc:04x}  {hex:<24}  {:>4}  {}\n",
            line, statement.source
        ));
    }
    Ok(Image {
        bytes: payload,
        entry: entry_value as u32,
        profile: profile.map_or(1, |(_, version)| version),
        listing,
        symbols: labels,
    })
}

fn operands(input: &str, line: usize) -> Result<Vec<String>, AsmError> {
    if input.is_empty() {
        return Ok(Vec::new());
    }
    let mut depth = 0i32;
    for c in input.chars() {
        match c {
            '(' => depth += 1,
            ')' => depth -= 1,
            _ => {}
        }
        if depth < 0 {
            return Err(err(line, "unmatched `)`"));
        }
    }
    if depth != 0 {
        return Err(err(line, "unmatched `(`"));
    }
    let mut result = Vec::new();
    let mut begin = 0;
    depth = 0;
    for (index, c) in input.char_indices() {
        match c {
            '(' => depth += 1,
            ')' => depth -= 1,
            ',' if depth == 0 => {
                let item = input[begin..index].trim();
                if item.is_empty() {
                    return Err(err(line, "empty operand"));
                }
                result.push(item.to_string());
                begin = index + 1;
            }
            _ => {}
        }
    }
    let item = input[begin..].trim();
    if item.is_empty() {
        return Err(err(line, "empty operand"));
    }
    result.push(item.to_string());
    Ok(result)
}
fn identifier(s: &str) -> bool {
    let mut chars = s.chars();
    matches!(chars.next(), Some(c) if c.is_ascii_alphabetic() || c == '_')
        && chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
}
const MAX_EXPRESSION_WORK: usize = 20_000;
fn expression(
    text: &str,
    labels: &HashMap<String, i64>,
    equs: &HashMap<String, (usize, String)>,
    line: usize,
) -> Result<i64, AsmError> {
    let mut cache = HashMap::new();
    let mut work = MAX_EXPRESSION_WORK;
    resolve(
        text,
        labels,
        equs,
        line,
        &mut Vec::new(),
        &mut cache,
        &mut work,
    )
}
fn resolve(
    text: &str,
    labels: &HashMap<String, i64>,
    equs: &HashMap<String, (usize, String)>,
    line: usize,
    stack: &mut Vec<String>,
    cache: &mut HashMap<String, i64>,
    work: &mut usize,
) -> Result<i64, AsmError> {
    let s = text.trim();
    if s.is_empty() {
        return Err(err(line, "empty expression"));
    }
    let mut total = 0i64;
    let mut pos = 0usize;
    let mut first = true;
    while pos < s.len() {
        while pos < s.len() && s.as_bytes()[pos].is_ascii_whitespace() {
            pos += 1;
        }
        if pos == s.len() {
            break;
        }
        *work = work
            .checked_sub(1)
            .ok_or_else(|| err(line, "expression work limit exceeded"))?;
        let sign = if s.as_bytes()[pos] == b'+' {
            pos += 1;
            1
        } else if s.as_bytes()[pos] == b'-' {
            pos += 1;
            -1
        } else if first {
            1
        } else {
            return Err(err(line, format!("expected `+` or `-` in `{text}`")));
        };
        while pos < s.len() && s.as_bytes()[pos].is_ascii_whitespace() {
            pos += 1;
        }
        let begin = pos;
        while pos < s.len()
            && s.as_bytes()[pos] != b'+'
            && s.as_bytes()[pos] != b'-'
            && !s.as_bytes()[pos].is_ascii_whitespace()
        {
            pos += 1;
        }
        if begin == pos {
            return Err(err(line, format!("missing expression term in `{text}`")));
        }
        let term = &s[begin..pos];
        let value = if let Some(hex) = term.strip_prefix("0x").or_else(|| term.strip_prefix("0X")) {
            i64::from_str_radix(hex, 16)
                .map_err(|_| err(line, format!("invalid hexadecimal literal `{term}`")))?
        } else if term.bytes().all(|b| b.is_ascii_digit()) {
            term.parse::<i64>()
                .map_err(|_| err(line, format!("invalid decimal literal `{term}`")))?
        } else if identifier(term) {
            let key = term.to_ascii_lowercase();
            if let Some(value) = labels.get(&key) {
                *value
            } else if let Some(value) = cache.get(&key) {
                *value
            } else if let Some((equ_line, formula)) = equs.get(&key) {
                if stack.contains(&key) {
                    return Err(err(*equ_line, format!("cyclic `.equ` involving `{term}`")));
                }
                if stack.len() >= 256 {
                    return Err(err(*equ_line, "`.equ` reference chain is too deep"));
                }
                stack.push(key);
                let value = resolve(formula, labels, equs, *equ_line, stack, cache, work)?;
                let name = stack.pop().expect("pushed symbol");
                cache.insert(name, value);
                value
            } else {
                return Err(err(line, format!("unknown symbol `{term}`")));
            }
        } else {
            return Err(err(line, format!("invalid expression term `{term}`")));
        };
        let signed_value = value
            .checked_mul(sign)
            .ok_or_else(|| err(line, "expression overflow"))?;
        total = total
            .checked_add(signed_value)
            .ok_or_else(|| err(line, "expression overflow"))?;
        first = false;
    }
    if first || s.ends_with('+') || s.ends_with('-') {
        return Err(err(line, format!("incomplete expression `{text}`")));
    }
    Ok(total)
}
fn register(s: &str, line: usize) -> Result<u8, AsmError> {
    let digits = s
        .trim()
        .strip_prefix('r')
        .or_else(|| s.trim().strip_prefix('R'));
    let value = digits.and_then(|s| s.parse::<u8>().ok());
    match value {
        Some(n @ 0..=15) => Ok(n),
        _ => Err(err(
            line,
            format!("invalid register `{s}`; expected r0..r15"),
        )),
    }
}
fn gpu_register(s: &str, line: usize) -> Result<u8, AsmError> {
    let digits = s
        .trim()
        .strip_prefix('g')
        .or_else(|| s.trim().strip_prefix('G'));
    match digits.and_then(|s| s.parse::<u8>().ok()) {
        Some(n @ 0..=31) => Ok(n),
        _ => Err(err(
            line,
            format!("invalid GPU register `{s}`; expected g0..g31"),
        )),
    }
}
fn vector_register(s: &str, line: usize, destination: bool, width: u8) -> Result<u8, AsmError> {
    let n = gpu_register(s, line)?;
    let minimum = if destination { 1 } else { 0 };
    let maximum = 32 - width;
    if n < minimum || n > maximum {
        return Err(err(
            line,
            format!("vector register `{s}` must start in g{minimum}..g{maximum}"),
        ));
    }
    Ok(n)
}
fn finite_float(s: &str, line: usize) -> Result<f32, AsmError> {
    let value = s
        .trim()
        .parse::<f32>()
        .map_err(|_| err(line, format!("invalid float literal `{s}`")))?;
    if !value.is_finite() {
        return Err(err(
            line,
            format!("float literal `{s}` is not finite binary32"),
        ));
    }
    Ok(value)
}
fn gpu_word(code: u8, rd: u8, ra: u8, rb: u8, rc: u8) -> u32 {
    code as u32 | (rd as u32) << 8 | (ra as u32) << 13 | (rb as u32) << 18 | (rc as u32) << 23
}
fn gpu_target(
    text: &str,
    labels: &HashMap<String, i64>,
    equs: &HashMap<String, (usize, String)>,
    gpu_instructions: &HashSet<usize>,
    line: usize,
) -> Result<u32, AsmError> {
    let value = expression(text, labels, equs, line)?;
    if value < 0 || value > u32::MAX as i64 || !gpu_instructions.contains(&(value as usize)) {
        return Err(err(
            line,
            format!("GPU branch target {value} must be an aligned GPU instruction start"),
        ));
    }
    Ok(value as u32)
}
fn encode_gpu(
    statement: &Statement,
    labels: &HashMap<String, i64>,
    equs: &HashMap<String, (usize, String)>,
    gpu_instructions: &HashSet<usize>,
) -> Result<Vec<u8>, AsmError> {
    use GpuForm::*;
    let line = statement.line;
    let args = &statement.args;
    let (code, form) = gpu_instruction(&statement.head).expect("known GPU instruction");
    let mut extra = Option::None;
    let (rd, ra, rb, rc) = match form {
        None => {
            expect(args, 0, line)?;
            (0, 0, 0, 0)
        }
        Literal | FloatLiteral => {
            expect(args, 2, line)?;
            extra = Some(if matches!(form, FloatLiteral) {
                finite_float(&args[1], line)?.to_bits()
            } else {
                checked_word(expression(&args[1], labels, equs, line)?, line)?
            });
            (gpu_register(&args[0], line)?, 0, 0, 0)
        }
        Unary => {
            expect(args, 2, line)?;
            if matches!(code, 32) {
                (
                    vector_register(&args[0], line, true, 3)?,
                    vector_register(&args[1], line, false, 3)?,
                    0,
                    0,
                )
            } else {
                (
                    gpu_register(&args[0], line)?,
                    gpu_register(&args[1], line)?,
                    0,
                    0,
                )
            }
        }
        Builtin(maximum) => {
            expect(args, 2, line)?;
            let index = unsigned(expression(&args[1], labels, equs, line)?, 5, line)?;
            if index > maximum {
                return Err(err(
                    line,
                    format!("GPU index {index} must be in 0..{maximum}"),
                ));
            }
            (gpu_register(&args[0], line)?, index as u8, 0, 0)
        }
        Binary => {
            expect(args, 3, line)?;
            let vector_destination = matches!(code, 28..=30 | 33);
            let vector_a = matches!(code, 28..=31 | 33);
            let vector_b = matches!(code, 28 | 29 | 31 | 33);
            let rd = if vector_destination {
                vector_register(&args[0], line, true, 3)?
            } else {
                gpu_register(&args[0], line)?
            };
            let ra = if vector_a {
                vector_register(&args[1], line, false, 3)?
            } else {
                gpu_register(&args[1], line)?
            };
            let rb = if vector_b {
                vector_register(&args[2], line, false, 3)?
            } else {
                gpu_register(&args[2], line)?
            };
            (rd, ra, rb, 0)
        }
        Sphere => {
            expect(args, 4, line)?;
            (
                gpu_register(&args[0], line)?,
                vector_register(&args[1], line, false, 3)?,
                vector_register(&args[2], line, false, 3)?,
                vector_register(&args[3], line, false, 4)?,
            )
        }
        Binding => {
            expect(args, 3, line)?;
            let rd = if code == 39 {
                vector_register(&args[0], line, false, 3)?
            } else {
                gpu_register(&args[0], line)?
            };
            let binding = unsigned(expression(&args[2], labels, equs, line)?, 2, line)?;
            (rd, gpu_register(&args[1], line)?, binding as u8, 0)
        }
        Branch => {
            expect(args, 2, line)?;
            extra = Some(gpu_target(&args[1], labels, equs, gpu_instructions, line)?);
            (gpu_register(&args[0], line)?, 0, 0, 0)
        }
        Jump => {
            expect(args, 1, line)?;
            extra = Some(gpu_target(&args[0], labels, equs, gpu_instructions, line)?);
            (0, 0, 0, 0)
        }
    };
    let mut bytes = gpu_word(code, rd, ra, rb, rc).to_le_bytes().to_vec();
    if let Some(value) = extra {
        bytes.extend_from_slice(&value.to_le_bytes());
    }
    Ok(bytes)
}
fn expect(args: &[String], count: usize, line: usize) -> Result<(), AsmError> {
    if args.len() == count {
        Ok(())
    } else {
        Err(err(
            line,
            format!("expected {count} operand(s), got {}", args.len()),
        ))
    }
}
fn memory(s: &str, line: usize) -> Result<(&str, &str), AsmError> {
    let open = s
        .rfind('(')
        .ok_or_else(|| err(line, format!("expected offset(register), got `{s}`")))?;
    if !s.ends_with(')') {
        return Err(err(line, format!("expected offset(register), got `{s}`")));
    }
    let offset = s[..open].trim();
    Ok((
        if offset.is_empty() { "0" } else { offset },
        s[open + 1..s.len() - 1].trim(),
    ))
}
fn signed(value: i64, bits: u32, line: usize) -> Result<i64, AsmError> {
    if value < -(1i64 << (bits - 1)) || value >= (1i64 << (bits - 1)) {
        Err(err(
            line,
            format!("{value} is outside signed {bits}-bit range"),
        ))
    } else {
        Ok(value)
    }
}
fn unsigned(value: i64, bits: u32, line: usize) -> Result<u32, AsmError> {
    if value < 0 || value >= 1i64 << bits {
        Err(err(
            line,
            format!("{value} is outside unsigned {bits}-bit range"),
        ))
    } else {
        Ok(value as u32)
    }
}
fn checked_byte(value: i64, line: usize) -> Result<u8, AsmError> {
    if !(-128..=255).contains(&value) {
        Err(err(
            line,
            format!("{value} is outside byte range -128..255"),
        ))
    } else {
        Ok(value as u8)
    }
}
fn checked_word(value: i64, line: usize) -> Result<u32, AsmError> {
    if !(-2147483648..=4294967295).contains(&value) {
        Err(err(line, format!("{value} is outside 32-bit word range")))
    } else {
        Ok(value as u32)
    }
}
fn relative(
    target: &str,
    pc: usize,
    bits: u32,
    labels: &HashMap<String, i64>,
    equs: &HashMap<String, (usize, String)>,
    line: usize,
) -> Result<i64, AsmError> {
    let target = expression(target, labels, equs, line)?;
    let displacement = target
        .checked_sub(pc as i64 + 4)
        .ok_or_else(|| err(line, "branch displacement overflow"))?;
    if displacement % 4 != 0 {
        return Err(err(
            line,
            format!("branch target {target} is not four-byte aligned"),
        ));
    }
    signed(displacement / 4, bits, line)
}
fn jump(
    rd: u8,
    target: &str,
    pc: usize,
    labels: &HashMap<String, i64>,
    equs: &HashMap<String, (usize, String)>,
    line: usize,
) -> Result<u32, AsmError> {
    let offset = relative(target, pc, 20, labels, equs, line)? as u32 & 0xfffff;
    Ok(u(op::JAL, rd, offset))
}
fn r(code: u8, rd: u8, ra: u8, rb: u8) -> u32 {
    code as u32 | (rd as u32) << 8 | (ra as u32) << 12 | (rb as u32) << 16
}
fn i(code: u8, rd: u8, ra: u8, imm: u16) -> u32 {
    code as u32 | (rd as u32) << 8 | (ra as u32) << 12 | (imm as u32) << 16
}
fn u(code: u8, rd: u8, imm: u32) -> u32 {
    code as u32 | (rd as u32) << 8 | (imm & 0xfffff) << 12
}

#[cfg(test)]
mod tests {
    use super::*;
    fn words(source: &str) -> Vec<u32> {
        let assembled = assemble(source).unwrap();
        assembled.cartridge[HEADER_SIZE..]
            .chunks_exact(4)
            .map(|b| u32::from_le_bytes(b.try_into().unwrap()))
            .collect()
    }
    #[test]
    fn hand_checked_encodings_and_header() {
        let src = ".entry start\nstart: add r1, r2, r3\naddi r4, r1, -2\nli r5, 0x12345678\nbeq r1, r2, start\njal r15, start\nhalt\n";
        assert_eq!(
            words(src),
            vec![
                0x0003_2101,
                0xfffe_140c,
                0x12345_510,
                0x0678_550e,
                0xfffb_2119,
                0xffffa_f1d,
                0x20
            ]
        );
        let assembled = assemble(src).unwrap();
        assert_eq!(&assembled.cartridge[..4], b"DB32");
        assert_eq!(
            u32::from_le_bytes(assembled.cartridge[4..8].try_into().unwrap()),
            1
        );
        assert_eq!(assembled.payload_len, 28);
        assert_eq!(assembled.cartridge.len(), HEADER_SIZE + 28);
    }
    #[test]
    fn labels_equ_data_alignment_and_pseudos() {
        let src = ".equ BASE, 0x20\n.entry run\n.byte 1, -1\n.align 4\nrun: mov r2, r3 // copy\nj run\n.word BASE+4, run-2\n";
        let assembled = assemble(src).unwrap();
        assert_eq!(
            u32::from_le_bytes(assembled.cartridge[12..16].try_into().unwrap()),
            4
        );
        assert_eq!(assembled.payload_len, 20);
        assert_eq!(&assembled.cartridge[32..36], &[1, 255, 0, 0]);
        assert_eq!(words(src)[1], 0x0000_3201);
        assert_eq!(words(src)[2], 0xffffe_01d);
    }
    #[test]
    fn rejects_bad_inputs_with_lines() {
        for (src, line) in [
            (".entry start\nstart: addi r1,r0,32768", 2),
            (".entry start\nstart: ori r1,r0,-1", 2),
            (".entry start\nstart: lui r1,0x100000", 2),
            (".entry start\nstart: beq r1,r0,start+2", 2),
            (".entry start\nstart: foo r1", 2),
            (".entry start\nstart: add r16,r0,r0", 2),
            (".entry data\ndata: .word 0\nhalt", 1),
        ] {
            assert_eq!(assemble(src).unwrap_err().line, line, "{src}");
        }
        assert!(assemble(".equ A,B\n.equ B,A\n.entry start\nstart: li r1,A")
            .unwrap_err()
            .message
            .contains("cyclic"));
        let giant = format!(
            ".entry start\nstart: halt\n.byte {}",
            "0,".repeat(4096) + "0"
        );
        assert!(assemble(&giant).unwrap_err().message.contains("exceeds"));
    }
    #[test]
    fn bundled_demos_fit_cartridge_and_have_valid_entries() {
        for (name, source) in [
            ("aurora", include_str!("../../../examples/aurora.asm")),
            ("rgb-study", include_str!("../../../examples/rgb-study.asm")),
        ] {
            let assembly = assemble(source).unwrap_or_else(|e| panic!("{name}: {e}"));
            assert!(assembly.payload_len <= CART_LIMIT, "{name}");
            assert_eq!(assembly.cartridge.len(), HEADER_SIZE + assembly.payload_len);
        }
    }
    #[test]
    fn entry_defaults_to_first_instruction() {
        let assembly = assemble("addi r1,r0,7\nhalt").unwrap();
        assert_eq!(&assembly.cartridge[12..16], &[0, 0, 0, 0]);
        assert!(assemble(".byte 1\n.align 4\nhalt")
            .unwrap_err()
            .message
            .contains("entry"));
    }
    #[test]
    fn extreme_arithmetic_returns_errors_without_panicking() {
        let prefix = ".equ MIN, -9223372036854775807-1\n.entry start\nstart: halt\n";
        let word = assemble(&(prefix.to_owned() + ".word -MIN")).unwrap_err();
        assert_eq!(word.line, 4);
        assert!(word.message.contains("overflow"));

        let branch = assemble(&(prefix.to_owned() + "beq r0,r0,MIN")).unwrap_err();
        assert_eq!(branch.line, 4);
        assert!(branch.message.contains("overflow"));

        let add = assemble(".equ MAX, 9223372036854775807\nhalt\n.word MAX+1").unwrap_err();
        assert_eq!(add.line, 3);
        assert!(add.message.contains("overflow"));
    }
    #[test]
    fn every_equ_is_validated_even_when_unused() {
        let missing = assemble(".equ UNUSED, MISSING\nhalt").unwrap_err();
        assert_eq!(missing.line, 1);
        assert!(missing.message.contains("unknown symbol"));

        let cycle = assemble(".equ A, B\n.equ B, A\nhalt").unwrap_err();
        assert!(cycle.message.contains("cyclic"));

        let entry = assemble(".entry 0x100000000\nhalt").unwrap_err();
        assert_eq!(entry.line, 1);
        assert!(entry.message.contains("entry"));
    }
    #[test]
    fn equ_resolution_caches_dag_and_bounds_work_and_depth() {
        let mut dag = String::from(".equ a0, 0\n");
        for i in 1..=40 {
            dag.push_str(&format!(".equ a{i}, a{}+a{}\n", i - 1, i - 1));
        }
        dag.push_str("halt\n.word a40");
        assert_eq!(words(&dag)[1], 0);

        let work = format!(".equ BIG, {}0\nhalt", "0+".repeat(MAX_EXPRESSION_WORK));
        let error = assemble(&work).unwrap_err();
        assert_eq!(error.line, 1);
        assert!(error.message.contains("work limit"));

        let mut depth = String::new();
        for i in 0..260 {
            depth.push_str(&format!(".equ a{i}, a{}\n", i + 1));
        }
        depth.push_str(".equ a260, 0\nhalt");
        assert!(assemble(&depth).unwrap_err().message.contains("too deep"));
    }
    #[test]
    fn gpu_profile_header_and_golden_words() {
        // The profile directive deliberately applies to the whole source, even below code.
        let src = ".entry boot\nboot: li r1,kernel\nhalt\nkernel: g.id g1,2\ng.fli g3,1.5\ng.bz g1,kernel\ng.end\n.float -2.5\n.profile gpu-1";
        let assembled = assemble(src).unwrap();
        assert_eq!(&assembled.cartridge[4..8], &2u32.to_le_bytes());
        assert_eq!(
            words(src),
            vec![
                0x0000_0110,
                0x000c_110e,
                0x0000_0020,
                0x0000_4103,
                0x0000_0301,
                0x3fc0_0000,
                0x0000_0128,
                12,
                0,
                0xc020_0000,
            ]
        );
        assert_eq!(assembled.payload_len, 40);
    }
    #[test]
    fn gpu_encodes_all_operand_shapes_without_reserved_bits() {
        let src = ".profile gpu-1\nhalt\nk: g.uniform g31,15\ng.vscale g29,g29,g31\ng.dot3 g0,g29,g29\ng.norm3 g1,g0\ng.reflect3 g1,g0,g29\ng.sphere g0,g29,g29,g28\ng.rgb g29,g1,3\ng.ld g31,g0,2\ng.stb g0,g31,1\ng.jmp k";
        let w = words(src);
        assert_eq!(w[1], 4 | (31 << 8) | (15 << 13));
        assert_eq!(w[2], 30 | (29 << 8) | (29 << 13) | (31 << 18));
        assert_eq!(w[3], 31 | (29 << 13) | (29 << 18));
        assert_eq!(w[4], 32 | (1 << 8));
        assert_eq!(w[5], 33 | (1 << 8) | (29 << 18));
        assert_eq!(w[6], 34 | (29 << 13) | (29 << 18) | (28 << 23));
        assert_eq!(w[7], 39 | (29 << 8) | (1 << 13) | (3 << 18));
        assert_eq!(w[8], 35 | (31 << 8) | (2 << 18));
        assert_eq!(w[9], 38 | (31 << 13) | (1 << 18));
        assert_eq!(w[10], 42);
        assert_eq!(w[11], 4);
    }
    #[test]
    fn gpu_scalar_destinations_and_rgb_source_accept_g0() {
        let w = words(".profile gpu-1\nhalt\ng.dot3 g0,g0,g0\ng.dot3 g30,g0,g0\ng.dot3 g31,g0,g0\ng.rgb g0,g0,0\ng.end");
        assert_eq!(w[1], 31);
        assert_eq!(w[2], 31 | (30 << 8));
        assert_eq!(w[3], 31 | (31 << 8));
        assert_eq!(w[4], 39);
    }
    #[test]
    fn spu_profile_uses_gpu_isa_and_cpu_entry() {
        let source =
            ".entry boot\nboot: halt\nkernel: g.li g1, 7\ng.st g1,g0,0\ng.end\n.profile spu-1";
        let assembly = assemble(source).unwrap();
        assert_eq!(&assembly.cartridge[4..8], &3u32.to_le_bytes());
        assert_eq!(&assembly.cartridge[12..16], &0u32.to_le_bytes());
        assert_eq!(words(source), vec![0x20, 0x101, 7, 0x124, 0]);
        let bad_entry = assemble(".profile spu-1\n.entry kernel\nhalt\nkernel: g.end").unwrap_err();
        assert!(bad_entry.message.contains("CPU instruction"));
        let bad_opcode = assemble(".profile spu-1\nhalt\ns.osc s1, 440").unwrap_err();
        assert!(bad_opcode.message.contains("unknown"));
    }
    #[test]
    fn gpu_rejects_invalid_operands_ranges_and_targets() {
        for (body, fragment) in [
            ("g.add g32,g0,g0", "register"),
            ("g.add r1,g0,g0", "register"),
            ("g.add g1,g0", "operand"),
            ("g.id g1,6", "index"),
            ("g.uniform g1,16", "index"),
            ("g.ld g1,g2,4", "unsigned 2-bit"),
            ("g.vadd g0,g1,g1", "vector register"),
            ("g.vsub g30,g1,g1", "vector register"),
            ("g.dot3 g1,g30,g1", "vector register"),
            ("g.sphere g1,g1,g1,g29", "vector register"),
            ("g.rgb g30,g1,0", "vector register"),
            ("g.li g1,0x100000000", "32-bit word"),
            ("g.fli g1,1e100", "finite"),
            ("g.jmp 0", "GPU instruction start"),
            ("g.bnz g1,3", "GPU instruction start"),
        ] {
            let src = format!(".profile gpu-1\nhalt\n{body}");
            let error = assemble(&src).unwrap_err();
            assert_eq!(error.line, 3, "{body}: {error}");
            assert!(error.message.contains(fragment), "{body}: {error}");
        }
        for src in [
            "halt\ng.end",
            ".profile bootstrap-1\nhalt\ng.end",
            "g.end\n.profile gpu-1",
            ".profile gpu-1\n.entry k\nhalt\nk: g.end",
            ".entry second\nli r1,0\nsecond: .word 0\nhalt",
            ".entry 4\nli r1,0\nhalt",
            ".profile gpu-1\nhalt\nk: g.li g1,0\ng.jmp k+4",
        ] {
            assert!(assemble(src).is_err(), "{src}");
        }
        assert_eq!(
            &assemble("halt\n.profile bootstrap-1").unwrap().cartridge[4..8],
            &1u32.to_le_bytes()
        );
        assert!(assemble(".profile gpu-1\nhalt\n.float NaN").is_err());
        assert!(assemble(".profile gpu-1\nhalt\n.float 1e100").is_err());
        let oversized = format!(".profile gpu-1\nhalt\n.float {}", "1,".repeat(1023) + "1");
        assert!(assemble(&oversized)
            .unwrap_err()
            .message
            .contains("exceeds"));
    }
}
