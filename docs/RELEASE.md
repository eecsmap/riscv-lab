# v0.1.0-xv6-boot

Private snapshot of the self-learning RISC-V FPGA project: custom CPU booting xv6 on PYNQ-Z1.

The binary archive contains the **original accepted artifacts**, not binaries rebuilt during repository
packaging: bitstream (Vivado .bit and raw .bit.bin), ARM fesvr, 128 MiB xv6 kernel, pristine disk image,
four boot probes and four extension probes. Two tiny auxiliary probe .bin files are also preserved;
they are not additional board acceptance tests. Performance-probe results are not part of this release's
accepted milestone.

Verify the download with `sha256sum -c SHA256SUMS`; after extraction, verify its contents with
`sha256sum -c MANIFEST.sha256` inside the extracted directory. Use a writable COPY of the disk image.

Read BOARD.md before hardware use: cold-start only, ARM low-256-MiB memory isolation required,
no safe PL hot reload. This is not a complete PS Linux/SD image. Do not substitute .bit for .bit.bin.

Acceptance is limited to the recorded cold-board session, eight smoke probes, xv6 shell and
echo/ls/cat/pipe. No full usertests, full ISA compliance, long-run reliability or Rocket performance
comparison is claimed. Historical scripts may require the original environment; see repository
docs/REPRODUCING.md for the portable entry points and remaining gaps.
