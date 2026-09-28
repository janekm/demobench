//! Bootstrap video controller: validated page configuration and line scanout.

use db_contracts::{Fault, FRAME_BYTES, HEIGHT, RAM_BASE, RAM_SIZE, VIDEO_BASE, WIDTH};

const RAM_END: u64 = RAM_BASE as u64 + RAM_SIZE as u64;
const VISIBLE_LINES: u32 = HEIGHT as u32;
const TOTAL_LINES: u32 = 128;

#[derive(Clone, Copy, Debug)]
struct Config {
    base: u32,
    stride: u32,
    format: u32,
    palette: u32,
    enable: u32,
    border: u32,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            base: RAM_BASE,
            stride: WIDTH as u32,
            format: 3, // I8
            palette: RAM_BASE + 0x18000,
            enable: 0,
            border: 0,
        }
    }
}

impl Config {
    fn row_bytes(self) -> Option<usize> {
        match self.format {
            0 => Some(WIDTH / 8),
            1 => Some(WIDTH / 4),
            2 => Some(WIDTH / 2),
            3 => Some(WIDTH),
            4 => Some(WIDTH * 3),
            _ => None,
        }
    }

    fn palette_entries(self) -> usize {
        match self.format {
            0 => 2,
            1 => 4,
            2 => 16,
            3 => 256,
            _ => 0,
        }
    }

    fn validate(self) -> Result<(), Fault> {
        let row_bytes = self
            .row_bytes()
            .ok_or_else(|| Fault::new("VIDEO_CONFIG", self.format, "unknown pixel format"))?;
        if self.enable > 1 {
            return Err(Fault::new(
                "VIDEO_CONFIG",
                self.enable,
                "enable must be 0 or 1",
            ));
        }
        if u64::from(self.stride) < row_bytes as u64 {
            return Err(Fault::new(
                "VIDEO_CONFIG",
                self.stride,
                "stride is shorter than a pixel row",
            ));
        }
        // Include padding after the final row, as required by the memory contract.
        check_ram_span(self.base, u64::from(self.stride) * HEIGHT as u64)?;
        if self.palette_entries() != 0 {
            check_ram_span(self.palette, (self.palette_entries() * 3) as u64)?;
        }
        Ok(())
    }
}

fn check_ram_span(address: u32, len: u64) -> Result<(), Fault> {
    let start = u64::from(address);
    if start < u64::from(RAM_BASE) || start.checked_add(len).map_or(true, |end| end > RAM_END) {
        return Err(Fault::new("VIDEO_RAM", address, "buffer is outside RAM"));
    }
    Ok(())
}

fn opaque_black() -> Vec<u8> {
    let mut pixels = vec![0; FRAME_BYTES];
    for alpha in pixels[3..].iter_mut().step_by(4) {
        *alpha = 255;
    }
    pixels
}

#[derive(Clone, Debug)]
pub struct Video {
    pending: Config,
    queued: Option<Config>,
    active: Config,
    scanline: u32,
    frames: u32,
    working: Vec<u8>,
    completed: Vec<u8>,
}

impl Default for Video {
    fn default() -> Self {
        Self::new()
    }
}

impl Video {
    pub fn new() -> Self {
        Self {
            pending: Config::default(),
            queued: None,
            active: Config::default(),
            scanline: 0,
            frames: 0,
            working: opaque_black(),
            completed: opaque_black(),
        }
    }

    pub fn read_reg(&self, offset: u32) -> Result<u32, Fault> {
        let value = match offset {
            0 => self.pending.base,
            4 => self.pending.stride,
            8 => self.pending.format,
            12 => self.pending.palette,
            16 => self.pending.enable,
            20 => u32::from(self.queued.is_some()),
            24 => self.frames,
            28 => self.scanline,
            32 => self.active.format,
            36 => self.active.enable | (u32::from(self.queued.is_some()) << 1),
            40 => self.pending.border,
            _ => return Err(bad_register(offset)),
        };
        Ok(value)
    }

    pub fn write_reg(&mut self, offset: u32, value: u32) -> Result<(), Fault> {
        match offset {
            0 => self.pending.base = value,
            4 => self.pending.stride = value,
            8 => self.pending.format = value,
            12 => self.pending.palette = value,
            16 => self.pending.enable = value,
            20 => {
                if value != 1 {
                    return Err(Fault::new("VIDEO_CONFIG", value, "COMMIT requires 1"));
                }
                self.pending.validate()?;
                self.queued = Some(self.pending);
            }
            40 => self.pending.border = value,
            _ => return Err(bad_register(offset)),
        }
        Ok(())
    }

    /// Capture one complete line from the RAM state at this event. Returns true at vblank.
    pub fn line_event(&mut self, line: u32, ram: &[u8]) -> Result<bool, Fault> {
        if line >= TOTAL_LINES {
            return Err(Fault::new(
                "VIDEO_LINE",
                line,
                "scanline is outside the frame",
            ));
        }
        if line < VISIBLE_LINES {
            self.capture_line(line as usize, ram)?;
        } else if line == VISIBLE_LINES {
            std::mem::swap(&mut self.working, &mut self.completed);
            if let Some(config) = self.queued.take() {
                self.active = config;
            }
            self.frames = self.frames.wrapping_add(1);
            self.scanline = line;
            return Ok(true);
        }
        self.scanline = line;
        Ok(false)
    }

    pub fn frame(&self) -> &[u8] {
        &self.completed
    }

    pub fn frame_count(&self) -> u32 {
        self.frames
    }

    pub fn active_format(&self) -> u32 {
        self.active.format
    }

    fn capture_line(&mut self, line: usize, ram: &[u8]) -> Result<(), Fault> {
        let output = &mut self.working[line * WIDTH * 4..(line + 1) * WIDTH * 4];
        if self.active.enable == 0 {
            let rgb = self.active.border.to_be_bytes();
            for pixel in output.chunks_exact_mut(4) {
                pixel.copy_from_slice(&[rgb[1], rgb[2], rgb[3], 255]);
            }
            return Ok(());
        }

        // COMMIT checked full guest RAM spans. Check the supplied slice as well,
        // since callers may pass an incomplete RAM view.
        let row_start = (self.active.base - RAM_BASE) as usize + line * self.active.stride as usize;
        let row_len = self
            .active
            .row_bytes()
            .expect("active format was validated");
        let row = ram.get(row_start..row_start + row_len).ok_or_else(|| {
            Fault::new(
                "VIDEO_RAM",
                self.active.base,
                "framebuffer is absent from RAM view",
            )
        })?;
        if self.active.format == 4 {
            for (src, dst) in row.chunks_exact(3).zip(output.chunks_exact_mut(4)) {
                dst.copy_from_slice(&[src[0], src[1], src[2], 255]);
            }
            return Ok(());
        }

        let palette_start = (self.active.palette - RAM_BASE) as usize;
        let palette_len = self.active.palette_entries() * 3;
        let palette = ram
            .get(palette_start..palette_start + palette_len)
            .ok_or_else(|| {
                Fault::new(
                    "VIDEO_RAM",
                    self.active.palette,
                    "palette is absent from RAM view",
                )
            })?;
        let bits = 1usize << self.active.format;
        let mask = (1usize << bits) - 1;
        for (x, pixel) in output.chunks_exact_mut(4).enumerate() {
            let bit_position = x * bits;
            let shift = 8 - bits - (bit_position % 8);
            let index = ((row[bit_position / 8] as usize) >> shift) & mask;
            let colour = &palette[index * 3..index * 3 + 3];
            pixel.copy_from_slice(&[colour[0], colour[1], colour[2], 255]);
        }
        Ok(())
    }
}

fn bad_register(offset: u32) -> Fault {
    Fault::new(
        "VIDEO_REGISTER",
        VIDEO_BASE.wrapping_add(offset),
        "unknown or read-only video register",
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ram() -> Vec<u8> {
        vec![0; RAM_SIZE]
    }

    fn palette(ram: &mut [u8], format: u32) {
        let base = 0x18000;
        let entries = [2, 4, 16, 256][format as usize];
        for index in 0..entries {
            ram[base + index * 3..base + index * 3 + 3].copy_from_slice(&[
                index as u8,
                (index * 2) as u8,
                (index * 3) as u8,
            ]);
        }
    }

    fn configure(video: &mut Video, format: u32, stride: u32) {
        video.write_reg(8, format).unwrap();
        video.write_reg(4, stride).unwrap();
        video.write_reg(16, 1).unwrap();
        video.write_reg(20, 1).unwrap();
        assert_eq!(video.read_reg(20).unwrap(), 1);
        video.line_event(120, &[]).unwrap();
        assert_eq!(video.active_format(), format);
        assert_eq!(video.read_reg(20).unwrap(), 0);
    }

    #[test]
    fn all_indexed_formats_are_msb_first_with_stride_padding() {
        for (format, first_byte, expected) in [
            (0, 0b1010_0000, vec![1, 0, 1, 0]),
            (1, 0b00_01_10_11, vec![0, 1, 2, 3]),
            (2, 0x1e, vec![1, 14]),
            (3, 0xab, vec![171]),
        ] {
            let row_bytes = WIDTH >> (3 - format);
            let stride = row_bytes + 5;
            let mut video = Video::new();
            configure(&mut video, format, stride as u32);
            let mut memory = ram();
            palette(&mut memory, format);
            memory[0] = first_byte;
            memory[stride] = 1 << (8 - (1 << format));
            video.line_event(0, &memory).unwrap();
            video.line_event(1, &memory).unwrap();
            video.line_event(120, &memory).unwrap();
            for (x, index) in expected.iter().enumerate() {
                assert_eq!(
                    &video.frame()[x * 4..x * 4 + 4],
                    &[*index as u8, (*index * 2) as u8, (*index * 3) as u8, 255],
                    "format {format}, pixel {x}"
                );
            }
            let line_one = WIDTH * 4;
            assert_eq!(&video.frame()[line_one..line_one + 4], &[1, 2, 3, 255]);
        }
    }

    #[test]
    fn rgb888_reads_three_bytes_per_pixel_and_row_stride() {
        let mut video = Video::new();
        configure(&mut video, 4, 483);
        let mut memory = ram();
        memory[0..6].copy_from_slice(&[17, 34, 51, 68, 85, 102]);
        memory[480..483].copy_from_slice(&[201, 202, 203]); // padding
        memory[483..486].copy_from_slice(&[7, 8, 9]);
        video.line_event(0, &memory).unwrap();
        video.line_event(1, &memory).unwrap();
        video.line_event(120, &memory).unwrap();
        assert_eq!(&video.frame()[..8], &[17, 34, 51, 255, 68, 85, 102, 255]);
        assert_eq!(&video.frame()[WIDTH * 4..WIDTH * 4 + 4], &[7, 8, 9, 255]);
    }

    #[test]
    fn palette_changes_apply_only_to_later_lines() {
        let mut video = Video::new();
        configure(&mut video, 3, WIDTH as u32);
        let mut memory = ram();
        memory[0] = 1;
        memory[WIDTH] = 1;
        let colour = 0x18000 + 3;
        memory[colour..colour + 3].copy_from_slice(&[10, 20, 30]);
        video.line_event(0, &memory).unwrap();
        memory[colour..colour + 3].copy_from_slice(&[40, 50, 60]);
        video.line_event(1, &memory).unwrap();
        video.line_event(120, &memory).unwrap();
        assert_eq!(&video.frame()[..4], &[10, 20, 30, 255]);
        assert_eq!(&video.frame()[WIDTH * 4..WIDTH * 4 + 4], &[40, 50, 60, 255]);
    }

    #[test]
    fn commit_snapshots_pending_settings_and_latches_after_publication() {
        let mut video = Video::new();
        let memory = ram();
        assert_eq!(&video.frame()[..4], &[0, 0, 0, 255]);
        video.write_reg(40, 0x112233).unwrap();
        video.write_reg(20, 1).unwrap();
        assert_eq!(video.read_reg(36).unwrap(), 2);
        video.write_reg(40, 0xaabbcc).unwrap();
        video.write_reg(8, 4).unwrap(); // invalid current stride, but queued config stays valid
        video.line_event(0, &memory).unwrap();
        video.line_event(120, &memory).unwrap();
        assert_eq!(video.frame_count(), 1);
        assert_eq!(video.active_format(), 3);
        assert_eq!(&video.frame()[..4], &[0, 0, 0, 255]);
        video.line_event(0, &memory).unwrap();
        video.line_event(120, &memory).unwrap();
        assert_eq!(&video.frame()[..4], &[0x11, 0x22, 0x33, 255]);
        assert_eq!(video.read_reg(40).unwrap(), 0xaabbcc);
        assert_eq!(video.read_reg(36).unwrap(), 0);
        assert_eq!(video.read_reg(24).unwrap(), 2);
        assert_eq!(video.read_reg(28).unwrap(), 120);
    }

    #[test]
    fn commit_rejects_bad_config_without_replacing_queue() {
        let mut video = Video::new();
        video.write_reg(20, 1).unwrap();
        for (reg, value) in [
            (8, 5),
            (16, 2),
            (4, 19),
            (0, RAM_BASE - 1),
            (0, RAM_BASE + RAM_SIZE as u32 - 100),
            (12, RAM_BASE + RAM_SIZE as u32 - 767),
        ] {
            let mut invalid = video.clone();
            invalid.write_reg(reg, value).unwrap();
            assert!(invalid.write_reg(20, 1).is_err(), "register {reg}");
            assert_eq!(invalid.read_reg(20).unwrap(), 1); // prior queue survives
        }
        assert!(video.write_reg(20, 0).is_err());
        assert_eq!(video.read_reg(20).unwrap(), 1);
        assert_eq!(video.write_reg(24, 0).unwrap_err().address, VIDEO_BASE + 24);
        assert_eq!(video.write_reg(3, 0).unwrap_err().address, VIDEO_BASE + 3);
        assert_eq!(video.read_reg(44).unwrap_err().address, VIDEO_BASE + 44);
        assert!(video.line_event(128, &[]).is_err());
    }

    #[test]
    fn incomplete_ram_view_faults_without_publishing_a_partial_frame() {
        let mut video = Video::new();
        video.write_reg(0, RAM_BASE + 0x10000).unwrap();
        video.write_reg(12, RAM_BASE + 0x8000).unwrap();
        configure(&mut video, 3, WIDTH as u32);
        let memory = vec![0; 0x10000 + WIDTH];
        video.line_event(0, &memory).unwrap();
        assert!(video.line_event(1, &memory).is_err());
        assert_eq!(video.frame_count(), 1); // configuration latch in helper
        assert_eq!(&video.frame()[..4], &[0, 0, 0, 255]);
    }

    #[test]
    fn final_row_padding_must_also_fit_in_ram() {
        let mut video = Video::new();
        let stride = 481;
        let last_visible_end = (HEIGHT as u32 - 1) * stride + (WIDTH as u32 * 3);
        video
            .write_reg(0, RAM_BASE + RAM_SIZE as u32 - last_visible_end)
            .unwrap();
        video.write_reg(4, stride).unwrap();
        video.write_reg(8, 4).unwrap();
        video.write_reg(16, 1).unwrap();
        assert!(video.write_reg(20, 1).is_err());
        video
            .write_reg(0, RAM_BASE + RAM_SIZE as u32 - stride * HEIGHT as u32)
            .unwrap();
        video.write_reg(20, 1).unwrap();
    }

    #[test]
    fn completed_frame_remains_stable_until_line_120() {
        let mut video = Video::new();
        configure(&mut video, 4, 480);
        let mut memory = ram();
        memory[..3].copy_from_slice(&[1, 2, 3]);
        video.line_event(0, &memory).unwrap();
        assert_eq!(&video.frame()[..4], &[0, 0, 0, 255]);
        video.line_event(119, &memory).unwrap();
        video.line_event(120, &memory).unwrap();
        assert_eq!(&video.frame()[..4], &[1, 2, 3, 255]);
        assert_eq!(video.frame_count(), 2);
        memory[..3].copy_from_slice(&[4, 5, 6]);
        video.line_event(0, &memory).unwrap();
        assert_eq!(&video.frame()[..4], &[1, 2, 3, 255]);
        video.line_event(120, &memory).unwrap();
        assert_eq!(&video.frame()[..4], &[4, 5, 6, 255]);
    }
}
