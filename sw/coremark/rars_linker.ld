/* ============================================================
   RISC-V Linker Script for RARS
   ============================================================ */

ENTRY(_start)  

/* ============================================================
   Memory Layout
   ============================================================ */
__TEXT_ORIGIN = 0x00400000;   /* Instruction memory base address */
__DATA_ORIGIN = 0x10010000;   /* Data memory base address */
__MMIO_ORIGIN = 0xFFFF0000;   /* Memory-mapped I/O base */

__TEXT_LENGTH = 0x8000;       /* 32KB for code (8192 lines × 4 bytes) */
__DATA_LENGTH = 0x4000;       /* 16KB for data (4096 lines × 4 bytes) */
__MMIO_LENGTH = 0x1000;       /* 4KB for MMIO */

__STACK_SIZE = 0x800;         /* 2KB for stack */

MEMORY
{
  text (rx)  : ORIGIN = __TEXT_ORIGIN, LENGTH = __TEXT_LENGTH
  data (rw)  : ORIGIN = __DATA_ORIGIN, LENGTH = __DATA_LENGTH
  mmio (rw)  : ORIGIN = __MMIO_ORIGIN, LENGTH = __MMIO_LENGTH
}

SECTIONS
{
  /* Code section */
  .text __TEXT_ORIGIN : {
    *(.text.startup)    /* _start first */
    *(.text.main)       /* main second */
    *(.text*)           /* Rest of code */
    . = ALIGN(4);
  } > text

  /* Read-only data - force 4-byte alignment */
  .rodata : ALIGN(4) {
    . = ALIGN(4);
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
    . = ALIGN(4);
  } > data

  /* Initialized data */
  .data : ALIGN(4) {
    . = ALIGN(4);
    *(.data*)
    *(.sdata*)
    . = ALIGN(4);
  } > data

  /* Uninitialized data (BSS) */
  .bss : ALIGN(4) {
    . = ALIGN(4);
    *(.bss*)
    *(.sbss*)
    . = ALIGN(4);
  } > data

  /* Stack section - grows downward */
  .stack (NOLOAD) : ALIGN(16) {
    . = ALIGN(16);
    __stack_bottom = .;
    . = . + __STACK_SIZE;       /* 2KB stack */
    __stack_top = .;
  } > data


  /* MMIO region */
  .mmio __MMIO_ORIGIN (NOLOAD) : {
    . = __MMIO_LENGTH;
  } > mmio
  __mmio_end = __MMIO_ORIGIN + __MMIO_LENGTH;
}