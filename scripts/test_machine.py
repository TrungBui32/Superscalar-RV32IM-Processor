#!/usr/bin/env python3
"""Architectural M-mode access-fault, precision and integration regressions."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parent.parent
os.chdir(ROOT)
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--build',type=Path,default=Path('sim/build/machine'))
p.add_argument('--suite',choices=['access','precision','csr','integration','supervisor','all'],default='all')
a=p.parse_args();a.build.mkdir(parents=True,exist_ok=True)
prefix=os.environ.get('RISCV_PREFIX','riscv64-unknown-elf-')
def command(args):
    r=subprocess.run(list(map(str,args)),text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    if r.returncode:raise RuntimeError(f'{args}\n{r.stdout}')
    return r.stdout
command(['iverilog','-g2012','-s','tb_machine_core','-o',a.build/'core',
         'tests/machine/tb_core.sv',*sorted(Path('rtl/core').glob('*.v')),'rtl/soc/machine_timer.v'])
source_files=[Path(__file__),*Path('rtl/core').glob('*.v'),*Path('rtl/soc').glob('*.v'),
              *Path('tests/machine').glob('*')]
source_hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files if p.is_file()}
results=[]
def run(name,source,args=()):
    src=a.build/(name+'.S');elf=a.build/(name+'.elf');binary=a.build/(name+'.bin');image=a.build/(name+'.hex')
    src.write_text(source)
    command([prefix+'gcc','-march=rv32ima','-mabi=ilp32','-nostdlib','-nostartfiles',
             '-Wl,--no-relax','-T','tests/machine/link.ld',src,'-o',elf])
    nm=command([prefix+'nm','-n',elf]);(a.build/(name+'.nm')).write_text(nm)
    symbols={r.split()[-1]:int(r.split()[0],16) for r in nm.splitlines() if len(r.split())==3}
    command([prefix+'objcopy','-O','binary',elf,binary]);data=binary.read_bytes();data+=b'\0'*(-len(data)%4)
    image.write_text('\n'.join(f'{int.from_bytes(data[i:i+4],"little"):08x}' for i in range(0,len(data),4))+'\n')
    if callable(args): args=args(symbols)
    for seed in [0,1,7,42]:
        out=command(['vvp',a.build/'core',f'+mem={image}',f'+tohost={symbols["tohost"]:x}',f'+seed={seed}',*args])
        (a.build/f'{name}.{seed}.log').write_text(out)
        assert 'PASS' in out,out
        if name=='context_switch': assert 'traps=12 returns=11' in out,out
        results.append(dict(test=name,seed=seed,output=out.strip().splitlines()[-1]))
        print(name,seed,results[-1]['output'],flush=True)

PRE='''.option norvc
.option norelax
.section .text.init
.globl _start
_start:
    la t0, handler
    csrw mtvec, t0
    li s1, 0
    li s6, 0
    li a3, 0x5eed
    li a0, 0x6000
    li a1, 0xaa
'''
POST='''
pass:
    la t0, tohost
    li t1, 1
    sw t1, 0(t0)
1:  j 1b
fail:
    la t0, tohost
    li t1, 3
    sw t1, 0(t0)
2:  j 2b
.section .tohost,"aw"
.balign 4
.globl tohost
tohost: .word 0
'''
if a.suite in ['access','all']:
    command(['iverilog','-g2012','-s','tb_access_map','-o',a.build/'map',
             'tests/machine/tb_access_map.sv','rtl/soc/soc_access_check.v'])
    print(command(['vvp',a.build/'map']).strip(),flush=True)
    cases=[('load','lw a3,0(a0)',5,0x6000,0x6000,0,''),
           ('store','sw a1,0(a0)',7,0x6000,0x6000,0,''),
           ('split_load','lw a3,1(a0)',5,0x6002,0x6002,0,''),
           ('split_store','sw a1,1(a0)',7,0x6002,0x6002,0,''),
           ('lr','lr.w a3,(a0)',5,0x6000,0x6000,1,''),
           ('sc','sc.w a3,a1,(a0)',7,0x6000,0x6000,2,'lr.w t1,(a0)'),
           ('amo_read','amoadd.w a3,a1,(a0)',7,0x6000,0x6000,1,''),
           ('amo_write','amoswap.w a3,a1,(a0)',7,0x6000,0x6000,2,''),
           ('fetch','',1,0x2000,None,0,'')]
    for name,op,cause,tval,bad,mode,setup in cases:
        for slot in [0,1]:
            source=PRE+f'''    {setup}
    li s2,{cause}
    li s3,{tval}
    la s4,fault
    la s5,after_fault
    .balign 8
'''
            source+=('    addi s1,zero,17\n' if slot else '')
            if name=='fetch':
                source+=f'    li s4,{0x2000+slot*4}\n    li t2,0x2000\n    jalr zero,t2,0\n'
            else:
                source+='fault:\n    '+op+'\n    addi s1,zero,99\n'
            source+='''after_fault:
    li t0,1
    bne s6,t0,fail
    li t0,0x5eed
    bne a3,t0,fail
'''
            source+=f'    li t0,{17 if slot else 0}\n    bne s1,t0,fail\n    j pass\n'
            source+='''handler:
    csrr t0,mcause
    bne t0,s2,fail
    csrr t0,mtval
    bne t0,s3,fail
    csrr t0,mepc
    bne t0,s4,fail
    addi s6,s6,1
    csrw mepc,s5
    mret
'''
            if name=='fetch': source=source.replace('la s4,fault',f'li s4,{0x2000+slot*4}').replace('li s3,8192',f'li s3,{0x2000+slot*4}')+'    .org 0x2000\n    nop\n    nop\n'
            run(f'{name}_p{slot}',source+POST,[f'+mode={mode}',f'+bad_addr={bad:x}'] if bad is not None else [f'+bad_pc={0x2000+slot*4:x}'])
if a.suite in ['precision','all']:
    command(['iverilog','-g2012','-s','tb_machine_soc_precision','-o',a.build/'soc',
             'tests/machine/tb_soc.sv','tests/machine/soc_models.sv',
             *sorted(Path('rtl/core').glob('*.v')),*sorted(Path('rtl/soc').glob('*.v'))])
    print(command(['vvp',a.build/'soc']).strip(),flush=True)
    # The pair is aligned and independent so both slots can reach MEM together.
    pairs=[
        ('older_alu','addi s1,zero,17','lw a3,0(a0)','li t0,17; bne s1,t0,fail'),
        ('older_store','sw a1,0(a4)','lw a3,0(a0)','lw t0,0(a4); bne t0,a1,fail'),
        ('older_load','lw s1,4(a4)','lw a3,0(a0)','li t0,0; bne s1,t0,fail'),
        ('older_mmio','sw a1,0(a4)','lw a3,0(a0)','lw t0,0(a4); li t1,1; bne t0,t1,fail; sw zero,0(a4)'),
        ('younger_store','lw a3,0(a0)','sw a1,0(a4)','lw t0,0(a4); bnez t0,fail'),
        ('younger_alu','lw a3,0(a0)','addi s1,zero,99','bnez s1,fail'),
        ('younger_csr','lw a3,0(a0)','csrw mscratch,a1','csrr t0,mscratch; bnez t0,fail'),
        ('two_faults','lw a3,0(a0)','sw a1,0(a0)','li t0,0x5eed; bne a3,t0,fail')]
    for name,older,younger,check in pairs:
        younger_fault=name.startswith('older_')
        source=PRE+('    li a1,1\n' if name=='older_mmio' else '')+f"    li a4,{0x02000000 if name=='older_mmio' else 0x5000}\n"
        source+='    li s2,5\n    li s3,0x6000\n    la s4,fault\n    la s5,resume\n    .balign 8\n'
        source+=(f'    {older}\nfault:\n    {younger}\n' if younger_fault else f'fault:\n    {older}\n    {younger}\n')
        source+="""resume:
    li t0,1
    bne s6,t0,fail
"""+f'    {check}\n    j pass\n'
        source+="""handler:
    csrr t0,mcause
    bne t0,s2,fail
    csrr t0,mtval
    bne t0,s3,fail
    csrr t0,mepc
    bne t0,s4,fail
    addi s6,s6,1
    csrw mepc,s5
    mret
"""
        run('precision_'+name,source+POST,['+bad_addr=6000']+(['+timer'] if name=='older_mmio' else []))
    source=PRE+"""    .balign 8
    beq zero,zero,resume
wrong:
    lw a3,0(a0)
    sw a1,0(a0)
resume:
    bnez s6,fail
    li t0,0x5eed
    bne a3,t0,fail
    j pass
handler:
    j fail
"""
    run('precision_wrong_path',source+POST,lambda symbols: ['+bad_addr=6000',f'+bad_pc={symbols["wrong"]:x}'])

if a.suite in ['csr','all']:
    for top,tb,rtl in [
        ('tb_machine_csr','tests/machine/tb_csr.sv',['rtl/core/csr.v']),
        ('tb_machine_timer','tests/machine/tb_timer.sv',['rtl/soc/machine_timer.v'])]:
        command(['iverilog','-g2012','-s',top,'-o',a.build/top,tb,*rtl])
        out=command(['vvp',a.build/top]);print(out.strip(),flush=True)
        (a.build/(top+'.log')).write_text(out)

if a.suite in ['csr','all']:
    command(['iverilog','-g2012','-s','tb_machine_mode','-o',a.build/'privileged',
             'tests/machine/tb_privileged.sv',*sorted(Path('rtl/core').glob('*.v'))])
    cases='ecall ebreak illegal zero system unsupported load_align store_align jump_align fence fence_pipe1 mret mret_pipe1 counters timer software external priority vectored retrigger irq_masked irq_global_masked sync_irq trap_stall'.split()
    for case in cases:
        for slot in ([0,1] if case in 'ecall ebreak illegal zero system unsupported load_align store_align jump_align trap_stall'.split() else [0]):
            out=command(['vvp',a.build/'privileged',f'+case={case}',f'+slot={slot}'])
            (a.build/f'privileged_{case}.{slot}.log').write_text(out)
            print(out.strip(),flush=True)

if a.suite in ['supervisor','all']:
    command(['iverilog','-g2012','-s','tb_supervisor_csr','-o',a.build/'supervisor_csr',
             'tests/machine/tb_supervisor_csr.sv','rtl/core/csr.v'])
    print(command(['vvp',a.build/'supervisor_csr']).strip(),flush=True)
    # name, mode, operation, cause, tval expression, setup, delegated, result
    cases=[
        ('ecall_u_m',0,'ecall',8,'0','',False,'marker'),
        ('ecall_s_m',1,'ecall',9,'0','',False,'marker'),
        ('ecall_u_s',0,'ecall',8,'0','li t0,256; csrw medeleg,t0',True,'marker'),
        ('ecall_s_s',1,'ecall',9,'0','li t0,512; csrw medeleg,t0',True,'marker'),
        ('csr_u',0,'csrr a3,sstatus',2,'instruction','',False,'marker'),
        ('csr_s',1,'csrr a3,mstatus',2,'instruction','',False,'marker'),
        ('mret_s',1,'mret',2,'instruction','',False,'marker'),
        ('sret_u',0,'sret',2,'instruction','',False,'marker'),
        ('tsr_s',1,'sret',2,'instruction','li t0,0x400000; csrs mstatus,t0',False,'marker'),
        ('bare_tvm_satp_s',1,'csrr a3,satp; ebreak',3,'last','li t0,0x100000; csrs mstatus,t0',False,'zero'),
        ('sfence_s_bare',1,'sfence.vma',2,'instruction','li t0,0x100000; csrs mstatus,t0',False,'marker'),
        ('sfence_u',0,'sfence.vma',2,'instruction','',False,'marker'),
        ('sfence_m_bare',3,'sfence.vma',2,'instruction','',False,'marker'),
        ('wfi_u',0,'wfi',2,'instruction','',False,'marker'),
        ('tw_wfi_s',1,'wfi',2,'instruction','li t0,0x200000; csrs mstatus,t0',False,'marker'),
        ('counter_s_denied',1,'csrr a3,cycle',2,'instruction','',False,'marker'),
        ('counter_u_denied',0,'csrr a3,cycle',2,'instruction','li t0,7; csrw mcounteren,t0',False,'marker'),
        ('counter_s_ok',1,'csrr a3,time; ebreak',3,'last','li t0,7; csrw mcounteren,t0',False,'positive'),
        ('counter_u_ok',0,'csrr a3,time; ebreak',3,'last','li t0,7; csrw mcounteren,t0; csrw scounteren,t0',False,'positive'),
        ('pmp_s_load',1,'lw a3,0(a0)',5,'0x6000','li t0,0x1c; csrw pmpcfg0,t0',False,'marker'),
        ('pmp_u_store',0,'sw a1,0(a0)',7,'0x6000','li t0,0x1d; csrw pmpcfg0,t0',False,'marker'),
        ('pmp_s_fetch',1,'nop',1,'pc','csrw pmpcfg0,zero',False,'marker'),
        ('mprv_u_load',3,'lw a3,0(a0)',5,'0x6000','li t0,0x1c; csrw pmpcfg0,t0; li t0,0x20000; csrw mstatus,t0',False,'marker'),
        ('bare_s',1,'csrr a3,satp; bnez a3,fail; li t0,-1; csrw satp,t0; csrr a3,satp; bnez a3,fail; ebreak',3,'last','',False,'zero')]
    supervisor_prelude=PRE.replace('la t0, handler','la t0, m_handler')+"""    la t0,s_handler
    csrw stvec,t0
    li t0,-1
    csrw pmpaddr0,t0
    li t0,0x1f
    csrw pmpcfg0,t0
    li s7,0
"""
    for name,mode,op,cause,tval,setup,delegated,result in cases:
        pre=supervisor_prelude+'    '+setup+'\n'
        if mode!=3:
            pre+=f'    li t0,0x1800\n    csrc mstatus,t0\n    li t0,{mode<<11}\n    csrs mstatus,t0\n    la t0,entry\n    csrw mepc,t0\n    mret\n'
        # No branch or context switch between entry and the faulting opcode.
        ops=op.split('; ')
        body='entry:\n'
        for index,line in enumerate(ops):
            if index==len(ops)-1:body+='fault:\n'
            body+='    '+line+'\n'
        body+='    j fail\n'
        expected="""m_handler:
    csrr t0,mcause
    li t1,EXPECTED_CAUSE
    bne t0,t1,fail
    csrr t0,mepc
    la t1,EXPECTED_PC
    bne t0,t1,fail
    csrr t0,mtval
    TVAL_CHECK
    csrr t0,mstatus
    srli t0,t0,11
    andi t0,t0,3
    li t1,EXPECTED_PRIV
    bne t0,t1,fail
    li t0,EXPECTED_S_TRAPS
    bne s7,t0,fail
    RESULT_CHECK
    j pass
s_handler:
    addi s7,s7,1
    csrr t0,scause
    li t1,ORIGINAL_CAUSE
    bne t0,t1,fail
    csrr t0,sepc
    la t1,fault
    bne t0,t1,fail
    csrr t0,sstatus
    andi t0,t0,0x102
    li t1,EXPECTED_SPP
    bne t0,t1,fail
s_exit:
    ebreak
"""
        original_tval='lw t1,0(t1)' if tval=='instruction' else ('la t1,fault' if tval in ['pc','last'] else f'li t1,{tval}')
        if tval=='instruction':tvalcheck='la t1,fault; lw t1,0(t1); bne t0,t1,fail'
        else:tvalcheck=original_tval+'; bne t0,t1,fail'
        expected=expected.replace('EXPECTED_CAUSE',str(3 if delegated else cause)).replace('EXPECTED_PC','s_exit' if delegated else 'fault')
        expected=expected.replace('TVAL_CHECK','la t1,s_exit; bne t0,t1,fail' if delegated else tvalcheck)
        expected=expected.replace('EXPECTED_PRIV',str(1 if delegated else mode)).replace('EXPECTED_S_TRAPS',str(int(delegated)))
        expected=expected.replace('ORIGINAL_CAUSE',str(cause)).replace('EXPECTED_SPP',str(0x100 if mode==1 else 0))
        check='li t0,0x5eed; bne a3,t0,fail' if result=='marker' else 'blez a3,fail' if result=='positive' else 'bnez a3,fail'
        expected=expected.replace('RESULT_CHECK',check)
        run('supervisor_'+name,pre+body+expected+POST)

if a.suite in ['supervisor','all']:
    run('supervisor_roundtrip',Path('tests/machine/supervisor_roundtrip.S').read_text())
    for pending,cause in [(2,1),(32,5),(512,9),(0x222,9)]:
        source=Path('tests/machine/supervisor_interrupt.S').read_text()
        source=source.replace('IRQ_PENDING',str(pending)).replace('IRQ_CAUSE',str(0x80000000|cause))
        run(f'supervisor_interrupt_{pending:x}',source)

if a.suite in ['integration','all']:
    run('context_switch',Path('tests/machine/context_switch.S').read_text(),['+timer','+bad_addr=6000'])

assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in source_hashes.items()), 'Sources changed while testing'
(a.build/'inputs.json').write_text(json.dumps(dict(source_sha256=source_hashes,
    compiler=command([prefix+'gcc','--version']).splitlines()[0],
    rtl_commit=command(['git','rev-parse','HEAD']).strip()),indent=2)+'\n')
(a.build/'results.json').write_text(json.dumps(results,indent=2)+'\n')
