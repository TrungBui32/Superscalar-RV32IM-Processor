.option norvc
.option norelax
.section .text.init
.globl _start
_start:
    la t0,m_handler
    csrw mtvec,t0
    la t0,s_handler
    csrw stvec,t0
    li t0,-1
    csrw pmpaddr0,t0
    li t0,0x1f
    csrw pmpcfg0,t0
    li t0,256
    csrw medeleg,t0
    li s1,0
    li s2,0x12345678
    la t0,s_start
    csrw mepc,t0
    li t0,0x880
    csrw mstatus,t0
    mret
    j fail
s_start:
    # Supervisor CSR RAW/RMW and aliases preserve machine-only fields.
    li t0,0x123
    csrw sscratch,t0
    csrrs t1,sscratch,zero
    bne t0,t1,fail
    csrrwi t1,sscratch,7
    li t0,0x123
    bne t0,t1,fail
    csrr t1,sscratch
    li t0,7
    bne t0,t1,fail
    la t0,u_start
    csrw sepc,t0
    li t0,0x20
    csrw sstatus,t0
    sret
    j fail
u_start:
    ecall
u_resume:
    li t0,1
    bne s1,t0,fail
    li t0,0x12345678
    bne s2,t0,fail
u_exit:
    ebreak
    j fail
s_handler:
    addi s1,s1,1
    csrr t0,scause
    li t1,8
    bne t0,t1,fail
    csrr t0,sepc
    la t1,u_start
    bne t0,t1,fail
    csrr t0,stval
    bnez t0,fail
    csrr t0,sstatus
    andi t0,t0,0x122
    li t1,0x20
    bne t0,t1,fail
    la t0,u_resume
    csrw sepc,t0
    sret
    j fail
m_handler:
    csrr t0,mcause
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
    li t1,8
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
