.option norvc
.option norelax
.section .text.init
.globl _start
_start:
    la t0,m_handler
    csrw mtvec,t0
    la t0,s_vectors
    ori t0,t0,1
    csrw stvec,t0
    li t0,-1
    csrw pmpaddr0,t0
    li t0,0x1f
    csrw pmpcfg0,t0
    li t0,0x222
    csrw mideleg,t0
    csrw mie,t0
    li t0,IRQ_PENDING
    csrw mip,t0
    li s1,0
    li s2,0
    li a3,0x5eed
    la t0,u_entry
    csrw mepc,t0
    li t0,0x80
    csrw mstatus,t0
    mret
    j fail
u_entry:
    li t0,1
    bne s1,t0,fail
    bne s2,t0,fail
    li t0,0x5eed
    bne a3,t0,fail
u_exit:
    ebreak
    j fail
.balign 256
s_vectors:
    .rept 16
        j s_handler
    .endr
s_handler:
    addi s1,s1,1
    csrr t0,scause
    li t1,IRQ_CAUSE
    bne t0,t1,fail
    csrr t0,sepc
    la t1,u_entry
    bne t0,t1,fail
    csrr t0,sstatus
    andi t0,t0,0x102
    bnez t0,fail
    # STIP/SEIP are M-writable; request clearing through the M-mode handler.
s_call:
    ecall
    sret
    j fail
m_handler:
    csrr t0,mcause
    li t1,9
    bne t0,t1,final_check
    addi s2,s2,1
    csrr t0,mepc
    la t1,s_call
    bne t0,t1,fail
    addi t0,t0,4
    csrw mepc,t0
    csrw mip,zero
    mret
final_check:
    li t1,3
    bne t0,t1,fail
    csrr t0,mepc
    la t1,u_exit
    bne t0,t1,fail
    csrr t0,mstatus
    srli t0,t0,11
    andi t0,t0,3
    bnez t0,fail
    csrr t0,scause
    li t1,IRQ_CAUSE
    bne t0,t1,fail
    la t0,tohost
    li t1,1
    sw t1,0(t0)
1:  j 1b
fail:
    la t0,tohost
    li t1,3
    sw t1,0(t0)
2:  j 2b
.section .tohost,"aw"
.balign 4
.globl tohost
tohost: .word 0
