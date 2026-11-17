.option norvc
.option norelax
.section .text.startup,"ax",@progbits
.globl _start
_start:
    la sp, __stack_top
    la t0, trap_handler
    csrw mtvec, t0
    la t0, __bss_start
    la t1, __bss_end
1:  bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b
2:  call main
    li t0, 0xffff00f0
    li t1, 1
    sw t1, 0(t0)
3:  j 3b
trap_handler:
    li t0, 0xffff00e0
    csrr t1, mcause
    sw t1, 0(t0)
    csrr t1, mepc
    sw t1, 4(t0)
    csrr t1, mtval
    sw t1, 8(t0)
    li t0, 0xffff00f0
    li t1, 2
    sw t1, 0(t0)
4:  j 4b
