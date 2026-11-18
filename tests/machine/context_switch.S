# Two M-mode tasks, timer preemption, full integer context, ECALL and bus fault.
# This is a bounded single-hart regression, not a general-purpose RTOS.
.option norvc
.option norelax
.section .text.init
.globl _start
_start:
    la sp, stack_a_end
    la t0, handler
    csrw mtvec,t0
    la t0,stack_b_end
    addi t0,t0,-128
    la t1,task_b
    sw t1,0(t0)
    la t1,saved_b
    sw t0,0(t1)
    # Timer stays beyond startup; high half is zero for this bounded test.
    li t0,0x02004000
    li t1,-1
    sw t1,0(t0)
    sw zero,4(t0)
    csrr t1,time
    addi t1,t1,2000
    sw t1,0(t0)
    li t0,0x80
    csrw mie,t0
    csrsi mstatus,8
    j task_a

.macro TASK name,tag,progress
\name:
    # x2 is the task stack; x5 is scratch; x9 is a changing loop counter.
    .irp r,1,3,4,6,7,8,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
        li x\r,\tag+\r
    .endr
    li s1,0
    ecall
    li t0,0x6000
    lw t1,0(t0)               # Must fault without replacing t1's task value.
.Lloop\@:
    .irp r,1,3,4,6,7,8,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
        li t0,\tag+\r
        bne x\r,t0,fail
    .endr
    addi s1,s1,1
    la t0,\progress
    lw t0,0(t0)
    addi t0,t0,1
    bne t0,s1,fail            # Detect lost/duplicated task counter state.
    la t0,\progress
    sw s1,0(t0)
    mul t0,s1,s1
    div t0,t0,s1
    bne t0,s1,fail            # Context must also preserve a live temporary.
    j .Lloop\@
.endm
TASK task_a,0xa000,progress_a
TASK task_b,0xb000,progress_b

.balign 4
handler:
    addi sp,sp,-128
    .irp r,1,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
        sw x\r,4*\r(sp)
    .endr
    csrr t0,mepc
    sw t0,0(sp)
    csrr t0,mstatus
    andi t0,t0,8
    bnez t0,fail              # Trap entry must clear global MIE.
    csrr t0,mcause
    li t1,0x80000007
    beq t0,t1,timer_handler
    li t1,11
    beq t0,t1,syscall_handler
    li t1,5
    bne t0,t1,fail
    csrr t0,mtval
    li t1,0x6000
    bne t0,t1,fail
    la t0,faults
    j count_exception
syscall_handler:
    la t0,ecalls
count_exception:
    lw t1,0(t0)
    addi t1,t1,1
    sw t1,0(t0)
    lw t0,0(sp)
    addi t0,t0,4
    sw t0,0(sp)
    j restore

timer_handler:
    li t0,0x02004000
    li t1,-1
    sw t1,0(t0)
    sw zero,4(t0)
    csrr t1,time
    addi t1,t1,600
    sw t1,0(t0)
    la t0,switches
    lw t1,0(t0)
    addi t1,t1,1
    sw t1,0(t0)
    li t2,8
    bgeu t1,t2,check_done
    la t0,current
    lw t1,0(t0)
    bnez t1,switch_to_a
    li t1,1
    sw t1,0(t0)
    la t0,saved_a
    sw sp,0(t0)
    la t0,saved_b
    lw sp,0(t0)
    j restore
switch_to_a:
    sw zero,0(t0)
    la t0,saved_b
    sw sp,0(t0)
    la t0,saved_a
    lw sp,0(t0)
restore:
    lw t0,0(sp)
    csrw mepc,t0
    .irp r,1,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
        lw x\r,4*\r(sp)
    .endr
    addi sp,sp,128
    mret

check_done:
    la t0,ecalls
    lw t1,0(t0)
    li t2,2
    bne t1,t2,fail
    la t0,faults
    lw t1,0(t0)
    bne t1,t2,fail
    la t0,progress_a
    lw t1,0(t0)
    beqz t1,fail
    la t0,progress_b
    lw t1,0(t0)
    beqz t1,fail
    la t0,tohost
    li t1,1
    sw t1,0(t0)
1:  j 1b
fail:
    la t0,tohost
    li t1,3
    sw t1,0(t0)
2:  j 2b

.section .data
.balign 4
current: .word 0
saved_a: .word 0
saved_b: .word 0
switches: .word 0
ecalls: .word 0
faults: .word 0
progress_a: .word 0
progress_b: .word 0
.section .bss
.balign 16
stack_a: .space 1024
stack_a_end:
stack_b: .space 1024
stack_b_end:
.section .tohost,"aw"
.balign 4
.globl tohost
tohost: .word 0
