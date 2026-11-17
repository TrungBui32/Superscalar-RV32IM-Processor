#!/usr/bin/env python3
"""RV32A decode/unit, architectural and optional upstream ISA regressions."""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
a = argparse.ArgumentParser(description=__doc__)
a.add_argument('--riscv-tests', type=Path)
a.add_argument('--riscv-env', type=Path, help='Directory containing riscv_test.h and link.ld')
a.add_argument('--build', type=Path, default=Path('sim/build/atomic_tests'))
args = a.parse_args()
args.build.mkdir(parents=True, exist_ok=True)
sources = sorted(map(str, Path('rtl/core').glob('*.v')))

def command(cmd):
    result = subprocess.run(list(map(str, cmd)), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        raise SystemExit(result.stdout)
    return result.stdout

for top, tb, rtl in [('tb_atomic_decode', 'tb_decode.sv', ['rtl/core/decode_unit.v']),
                     ('tb_atomic_unit', 'tb_unit.sv', ['rtl/core/atomic_unit.v']),
                     ('tb_atomic_core', 'tb_core.sv', sources)]:
    command(['iverilog', '-g2012', '-s', top, '-o', args.build/top,
             Path('tests/atomic')/tb, *rtl])
    if top != 'tb_atomic_core':
        print(command(['vvp', args.build/top]).strip(), flush=True)

prefix = os.environ.get('RISCV_PREFIX', 'riscv64-unknown-elf-')
programs = [(p.stem, p, Path('tests/atomic/link.ld'), Path('tests/atomic'))
            for p in sorted(Path('tests/atomic').glob('*.S'))]
if args.riscv_tests:
    env = args.riscv_env or args.riscv_tests/'env/p'
    if not (env/'riscv_test.h').is_file():
        raise SystemExit('Missing upstream environment; initialize riscv-tests/env or pass --riscv-env')
    programs += [('rv32ua-'+p.stem, p, env/'link.ld', env)
                 for p in sorted((args.riscv_tests/'isa/rv32ua').glob('*.S'))]

runs = []
for name, source, linker, includes in programs:
    elf = args.build/(name+'.elf')
    flags = [prefix+'gcc', '-march=rv32ima', '-mabi=ilp32', '-static', '-mcmodel=medany',
             '-nostdlib', '-nostartfiles', '-Wl,--no-relax', '-I'+str(includes), '-T'+str(linker)]
    if args.riscv_tests:
        flags += ['-I'+str(args.riscv_tests/'isa/macros/scalar')]
    command([*flags, source, '-o', elf])
    binary = args.build/(name+'.bin')
    command([prefix+'objcopy', '-O', 'binary', elf, binary])
    nm = command([prefix+'nm', '-n', elf])
    (args.build/(name+'.nm')).write_text(nm)
    tohost = next(x.split()[0] for x in nm.splitlines() if x.endswith(' tohost'))
    data = binary.read_bytes()
    data += b'\0' * (-len(data) % 4)
    image = args.build/(name+'.hex')
    image.write_text('\n'.join(f'{int.from_bytes(data[i:i+4], "little"):08x}'
                               for i in range(0, len(data), 4))+'\n')
    for seed in [0, 1, 7, 42]:
        for inject in ([1, 2, 3] if name == 'interrupt' else [1, 3] if name == 'lrsc_interrupt' else [0]):
            runs.append((name, image, tohost, seed, inject))

def run(item):
    name, image, tohost, seed, inject = item
    r = subprocess.run(['vvp', str(args.build/'tb_atomic_core'), f'+mem={image}',
                        f'+tohost={tohost}', f'+seed={seed}', f'+inject={inject}'],
                       text=True, capture_output=True, timeout=150)
    log = r.stdout+r.stderr
    (args.build/f'{name}.{seed}.{inject}.log').write_text(log)
    line = next((x for x in log.splitlines() if x.startswith(('PASS', 'FATAL', 'FAIL'))), log[-500:])
    result = dict(name=name, seed=seed, inject=inject, passed=r.returncode == 0 and line.startswith('PASS'), detail=line)
    print(name, seed, inject, line, flush=True)
    return result

with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    results = list(pool.map(run, runs))
(args.build/'results.json').write_text(json.dumps(results, indent=2)+'\n')
if not all(r['passed'] for r in results):
    raise SystemExit('Atomic regression failed; see results.json and per-run logs')
print(f'PASS atomic architectural runs={len(results)}', flush=True)
