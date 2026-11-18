#!/usr/bin/env python3
"""Architectural M-mode access-fault, precision and integration regressions."""
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parent.parent
os.chdir(ROOT)
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--build',type=Path,default=Path('sim/build/machine'))
p.add_argument('--suite',choices=['access','precision','integration','all'],default='all')
a=p.parse_args();a.build.mkdir(parents=True,exist_ok=True)
prefix=os.environ.get('RISCV_PREFIX','riscv64-unknown-elf-')
def command(args):
    r=subprocess.run(list(map(str,args)),text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    if r.returncode:raise RuntimeError(f'{args}\n{r.stdout}')
    return r.stdout
command(['iverilog','-g2012','-s','tb_machine_core','-o',a.build/'core',
         'tests/machine/tb_core.sv',*sorted(Path('rtl/core').glob('*.v')),'rtl/soc/machine_timer.v'])
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
    for seed in [0,1,7,42]:
        out=command(['vvp',a.build/'core',f'+mem={image}',f'+tohost={symbols["tohost"]:x}',f'+seed={seed}',*args])
        (a.build/f'{name}.{seed}.log').write_text(out)
        assert 'PASS' in out,out
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
# Additional suites are appended below.
(a.build/'results.json').write_text(json.dumps(results,indent=2)+'\n')
