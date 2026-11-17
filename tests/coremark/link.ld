OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY {
  IMEM(rx) : ORIGIN = 0x00400000, LENGTH = 32K
  DMEM(rw) : ORIGIN = 0x10010000, LENGTH = 16K
}
SECTIONS {
  .text : { *(.text.startup) *(.text*) } > IMEM
  .rodata : ALIGN(4) { *(.rodata*) *(.srodata*) } > DMEM
  .data : ALIGN(4) { *(.data*) *(.sdata*) } > DMEM
  .bss (NOLOAD) : ALIGN(4) {
    __bss_start = .; *(.bss*) *(.sbss*) *(COMMON) . = ALIGN(4); __bss_end = .;
  } > DMEM
  __stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
  ASSERT(__bss_end <= __stack_top - 4096, "Need at least 4 KiB stack")
}
