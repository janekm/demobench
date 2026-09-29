// Shared reference/real-hardware regressions, not a showcase cartridge.
export function budgetFixture(processor, iterations) {
  const spu = processor === 'spu';
  const kernel = `kernel:
    g.li g1, ${iterations}
    g.li g2, 1
loop:
    g.sub g1, g1, g2
    g.bnz g1, loop
    g.st g2, g0, 0
    g.end
kernel_end:`;
  const code = spu ? 0x40 : 0;
  const binding = spu ? 0x100 : 0x40;
  return {
    kernel,
    // Setup 16 + wave 4 + two constants + 2 instructions/iteration + store 2 + END 1.
    referenceTicks: 2 * iterations + 25,
    invocationInstructions: 2 * iterations + 4,
    source: `.profile spu-1
.entry start
start:
    lui r10, ${spu ? '0xf6' : '0xf3'}
    li r1, kernel
    sw r1, ${code}(r10)
    li r1, kernel_end-kernel
    sw r1, ${code + 4}(r10)
    li r1, 1
    sw r1, ${code + 8}(r10)
    sw r1, ${code + 12}(r10)
    lui r1, 0x10
    sw r1, ${binding}(r10)
    ${spu ? 'sw r1, 80(r10)' : ''}
    li r1, 2048
    sw r1, ${binding + 4}(r10)
    li r1, 3
    sw r1, ${binding + 8}(r10)
    li r1, 1
    sw r1, ${spu ? 0 : 16}(r10)
idle:
    wfi
    j idle
${kernel}
`,
  };
}
