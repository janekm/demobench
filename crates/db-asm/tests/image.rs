use db_asm::{assemble, assemble_image};

#[test]
fn offline_image_links_absolute_ram_addresses_and_relative_calls() {
    let source = ".profile dynamic-1\n.entry boot\nrom: .word boot\n.org 0x2c000\nboot: li r1, data\njal r14, routine\nhalt\nroutine: jalr r0,0(r14)\ndata: .word rom, boot\n";
    assert!(assemble(source).is_err());
    let image = assemble_image(source).unwrap();
    assert_eq!(image.entry, 0x2c000);
    assert_eq!(image.profile, 4);
    assert_eq!(&image.bytes[..4], &0x2c000u32.to_le_bytes());
    assert_eq!(image.symbols["data"], 0x2c014);
    assert_eq!(&image.bytes[0x2c018..], &0x2c000u32.to_le_bytes());
    let large = format!(
        ".entry boot\n.org 0x10000\nboot: halt\n{}",
        ".word 0\n".repeat(2000)
    );
    assert!(assemble_image(&large).unwrap().bytes.len() > 0x11000);
    assert!(assemble(&"nop\n".repeat(1025)).is_err());
}

#[test]
fn image_origins_are_bounded_and_entries_must_be_cpu_instructions() {
    for source in [
        ".org 0x30000\nhalt",
        "halt\n.org 0",
        ".org -1\nhalt",
        ".org 0x2fffc\nli r1, 1",
        ".profile dynamic-1\n.entry k\n.org 0x20000\nk: g.end",
    ] {
        assert!(assemble_image(source).is_err(), "{source}");
    }
}
