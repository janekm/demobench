//! Import-free offline image linker for the portable authoring kit.
//! Kept separate from the runtime so linking cannot relax cartridge limits.
use std::cell::RefCell;

const INPUT_CAPACITY: usize = 1_048_576;
struct Linker {
    input: Vec<u8>,
    bytes: Vec<u8>,
    metadata: String,
    listing: String,
    error: String,
}
thread_local! {
    static LINKER: RefCell<Linker> = RefCell::new(Linker {
        input: vec![0; INPUT_CAPACITY], bytes: Vec::new(), metadata: String::new(),
        listing: String::new(), error: String::new(),
    });
}

#[no_mangle]
pub extern "C" fn db_linker_abi_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn db_input_capacity() -> u32 {
    INPUT_CAPACITY as u32
}
#[no_mangle]
pub extern "C" fn db_input_ptr() -> u32 {
    LINKER.with(|l| l.borrow().input.as_ptr() as u32)
}
#[no_mangle]
pub extern "C" fn db_link(len: u32) -> i32 {
    LINKER.with(|l| {
        let mut l = l.borrow_mut();
        l.bytes.clear();
        l.metadata.clear();
        l.listing.clear();
        l.error.clear();
        let result = (|| {
            if len as usize > INPUT_CAPACITY {
                return Err("source exceeds linker input capacity".to_string());
            }
            let source = std::str::from_utf8(&l.input[..len as usize])
                .map_err(|_| "assembly source must be UTF-8".to_string())?;
            db_asm::assemble_image(source).map_err(|e| e.to_string())
        })();
        match result {
            Ok(image) => {
                let mut symbols: Vec<_> = image.symbols.iter().collect();
                symbols.sort_by_key(|(name, _)| *name);
                // Assembler identifiers contain only ASCII letters, digits and underscores.
                let symbols = symbols
                    .iter()
                    .map(|(name, value)| format!("\"{name}\":{value}"))
                    .collect::<Vec<_>>()
                    .join(",");
                l.metadata = format!(
                    "{{\"entry\":{},\"profile\":{},\"symbols\":{{{symbols}}}}}",
                    image.entry, image.profile
                );
                l.bytes = image.bytes;
                l.listing = image.listing;
                0
            }
            Err(error) => {
                l.error = error;
                -1
            }
        }
    })
}
macro_rules! output {
    ($ptr:ident, $len:ident, $field:ident) => {
        #[no_mangle]
        pub extern "C" fn $ptr() -> u32 {
            LINKER.with(|l| l.borrow().$field.as_ptr() as u32)
        }
        #[no_mangle]
        pub extern "C" fn $len() -> u32 {
            LINKER.with(|l| l.borrow().$field.len() as u32)
        }
    };
}
output!(db_image_ptr, db_image_len, bytes);
output!(db_metadata_ptr, db_metadata_len, metadata);
output!(db_listing_ptr, db_listing_len, listing);
output!(db_error_ptr, db_error_len, error);
