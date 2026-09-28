//! Offline packer linker. Does not alter cartridge validation or the WASM ABI.
use std::{env, fs, process};

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        process::exit(1);
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = env::args().skip(1).collect();
    if args.len() != 2 {
        return Err("usage: image SOURCE OUTPUT_PREFIX".into());
    }
    let image = db_asm::assemble_image(&fs::read_to_string(&args[0])?)?;
    fs::write(format!("{}.bin", args[1]), &image.bytes)?;
    fs::write(format!("{}.listing", args[1]), &image.listing)?;
    let mut symbols: Vec<_> = image.symbols.iter().collect();
    symbols.sort_by_key(|(name, _)| *name);
    let symbols = symbols
        .iter()
        .map(|(name, value)| format!("\"{name}\":{value}"))
        .collect::<Vec<_>>()
        .join(",");
    fs::write(
        format!("{}.json", args[1]),
        format!(
            "{{\"entry\":{},\"profile\":{},\"symbols\":{{{symbols}}}}}\n",
            image.entry, image.profile
        ),
    )?;
    Ok(())
}
