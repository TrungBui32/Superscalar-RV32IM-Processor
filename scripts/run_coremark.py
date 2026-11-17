#!/usr/bin/env python3
"""Run unmodified pinned CoreMark kernels on the current RTL, with CRC validation."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--coremark', type=Path, default=Path.home()/'coremark')
ap.add_argument('--rev', default='HEAD')
ap.add_argument('--iterations', type=int, default=40)
ap.add_argument('--hz', type=int, default=1000000,
                help='Actual simulated CPU clock and timer frequency; not a hardware Fmax claim')
ap.add_argument('--opt', choices=['O1', 'O2', 'O3'], default='O2')
ap.add_argument('--build', type=Path, default=Path('sim/build/coremark'))
ap.add_argument('--jobs', type=int, default=4)
a = ap.parse_args()
if a.iterations < 1 or a.hz < 1 or a.jobs < 1:
    ap.error('iterations, hz, and jobs must be positive')
a.build = a.build.resolve()
a.coremark = a.coremark.resolve()
a.build.mkdir(parents=True, exist_ok=True)
port = ROOT/'tests/coremark'
src = a.build/'source'
src.mkdir(exist_ok=True)
kernels = ['core_main.c', 'core_list_join.c', 'core_matrix.c', 'core_state.c', 'core_util.c']

def command(args):
    p = subprocess.run(list(map(str, args)), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if p.returncode:
        raise SystemExit(p.stdout)
    return p.stdout

rev = command(['git', '-C', a.coremark, 'rev-parse', a.rev]).strip()
def original(name):
    return subprocess.check_output(['git', '-C', str(a.coremark), 'show', rev+':'+name])

for name in [*kernels, 'coremark.h', 'LICENSE.md', 'README.md']:
    (src/name).write_bytes(original(name))
# The output formatter belongs to the platform port; only its UART hook changes.
s = original('barebones/ee_printf.c').decode()
i, j = s.index('void\nuart_send_char(char c)'), s.index('\nint\nee_printf', s.index('void\nuart_send_char(char c)'))
s = s[:i]+'''void
uart_send_char(char c) {
    *(volatile unsigned int *)0xffff000c = (unsigned char)c;
}
'''+s[j:]
(src/'ee_printf.c').write_text(s)
rtl_hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in Path('rtl/core').glob('*.v')}
port_hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in port.iterdir() if p.is_file()}
model = a.build/'obj_dir'
cmd = ['verilator', '--cc', '--exe', '--build', '-j', a.jobs, '-O3', '-Wno-fatal',
       '--top-module', 'coremark_sim', '--Mdir', model, '-CFLAGS', '-O3 -march=native',
       port/'sim_top.v', *sorted(Path('rtl/core').glob('*.v')), port/'sim_main.cpp']
signature = dict(rtl=rtl_hashes, port=port_hashes, verilator=command(['verilator', '--version']).strip())
stamp = model/'inputs.json'
if not (stamp.is_file() and json.loads(stamp.read_text()) == signature and (model/'Vcoremark_sim').is_file()):
    (a.build/'verilator_build.log').write_text(command(cmd))
    stamp.write_text(json.dumps(signature, indent=2)+'\n')
# Independently verify crcfinal after every iteration using native execution.
native = a.build/'native'
native.mkdir(exist_ok=True)
for name in ['core_portme.c', 'core_portme.h', 'core_portme_posix_overrides.h']:
    (native/name).write_bytes(original('posix/'+name))
command(['gcc', '-O2', '-I'+str(native), '-I'+str(src), '-DSEED_METHOD=SEED_ARG',
         '-DCOMPILER_FLAGS="native CRC reference -O2"', *[src/n for n in kernels],
         native/'core_portme.c', '-o', native/'reference'])
flags = ['-'+a.opt, '-march=rv32ima', '-mabi=ilp32', '-mcmodel=medany', '-msmall-data-limit=0',
         '-ffreestanding', '-fno-builtin', '-fno-pic', '-fno-pie', '-ffunction-sections', '-fdata-sections']
prefix = os.environ.get('RISCV_PREFIX', 'riscv64-unknown-elf-')
results = []

def run(mode):
    b = a.build/f'{mode}_{a.opt}_{a.iterations}'
    b.mkdir(exist_ok=True)
    elf = b/'coremark.elf'
    compile_cmd = [prefix+'gcc', *flags, '-nostdlib', '-nostartfiles', '-static', '-Wl,--gc-sections,--no-relax',
                   '-T'+str(port/'link.ld'), '-I'+str(port), '-I'+str(src),
                   '-D'+mode.upper()+'_RUN=1', f'-DITERATIONS={a.iterations}', f'-DCPU_HZ={a.hz}',
                   '-DCOMPILER_FLAGS="'+' '.join(flags)+'"', port/'startup.S', port/'core_portme.c',
                   *[src/n for n in kernels], src/'ee_printf.c', '-lgcc', '-o', elf]
    (b/'build.log').write_text(command(compile_cmd))
    (b/'compile.json').write_text(json.dumps(list(map(str, compile_cmd)), indent=2)+'\n')
    (b/'size.txt').write_text(command([prefix+'size', elf]))
    (b/'symbols.txt').write_text(command([prefix+'nm', '-n', elf]))
    for name, sections, words in [('imem', ['.text'], 8192), ('dmem', ['.rodata', '.data'], 4096)]:
        binary = b/(name+'.bin')
        command([prefix+'objcopy', '-O', 'binary', *[x for sec in sections for x in ['-j', sec]], elf, binary])
        data = binary.read_bytes()
        if len(data) > words*4:
            raise SystemExit('Image exceeds actual SoC BRAM capacity')
        data += b'\0'*(words*4-len(data))
        (b/(name+'.hex')).write_text('\n'.join(f'{int.from_bytes(data[i:i+4], "little"):08x}'
                                              for i in range(0, len(data), 4))+'\n')
    limit = max(20000000, a.iterations*2000000)
    sim_cmd = [str(model/'Vcoremark_sim'), f'+imem={b/"imem.hex"}', f'+dmem={b/"dmem.hex"}',
               f'+limit={limit}', f'+hz={a.hz}']
    print('Running', mode, a.opt, 'iterations', a.iterations, 'clock Hz', a.hz, flush=True)
    with (b/'run.log').open('w') as out, (b/'progress.log').open('w') as err:
        p = subprocess.run(sim_cmd, stdout=out, stderr=err)
    output = (b/'run.log').read_text()
    def value(label, base=10):
        m = re.search(re.escape(label)+r'\s*:\s*(?:0x)?([0-9a-fA-F]+)', output)
        if not m:
            raise SystemExit('Missing '+label+' in '+str(b/'run.log'))
        return int(m[1], base)
    values = {x: value(x, 16) for x in ['seedcrc', 'crclist', 'crcmatrix', 'crcstate', 'crcfinal']}
    expected = [0xe9f5, 0xe714, 0x1fd7, 0x8e3a] if mode == 'performance' else [0x18f2, 0xe3c1, 0x0747, 0x8d84]
    crc_ok = list(values.values())[:4] == expected
    ticks = value('Total ticks')
    iterations = value('Iterations')
    seed = '0' if mode == 'performance' else '0x3415'
    native_output = command([native/'reference', seed, seed, '0x66', iterations])
    reference_log = b/'native_reference.log'
    reference_log.write_text(native_output)
    reference = {key: int(re.search(re.escape(key)+r'\s*:\s*0x([0-9a-fA-F]+)', native_output)[1],16)
                 for key in values}
    final_ok = reference == values
    finish = re.search(r'RTL_FINISH status=PASS cycles=(\d+).*simulated_seconds=([0-9.]+)', output)
    if not finish:
        raise SystemExit('Missing clock/time verification in '+str(b/'run.log'))
    model_cycles, model_seconds = int(finish[1]), float(finish[2])
    if model_cycles >= 2**32:
        raise SystemExit('32-bit timer range exceeded; use fewer iterations')
    if abs(model_seconds-(model_cycles+4)/a.hz) > 1e-7:
        raise SystemExit('Simulator timestamp disagrees with the CPU timer frequency')
    record = dict(mode=mode, optimization=a.opt, iterations=iterations, ticks=ticks,
                  cycles_per_iteration=ticks/iterations, simulated_clock_hz=a.hz,
                  simulated_seconds=ticks/a.hz, iterations_per_second=iterations*a.hz/ticks,
                  coremark_per_mhz=iterations*1e6/ticks, crc=values, crc_valid=crc_ok,
                  native_crc_all_match=final_ok, native_reference_log=str(reference_log),
                  minimum_duration_met=ticks >= 10*a.hz, rtl_exit_success=p.returncode == 0,
                  retired_snapshot=value('RTL retired'), model_cycles=model_cycles,
                  model_simulated_seconds=model_seconds, clock_time_verified=True, log=str(b/'run.log'))
    (b/'results.json').write_text(json.dumps(record, indent=2)+'\n')
    if not crc_ok or not final_ok or p.returncode or 'RTL TRAP' in output or 'ERROR! list' in output or 'ERROR! matrix' in output or 'ERROR! state' in output:
        raise SystemExit('CoreMark validation failed: '+str(b/'run.log'))
    if record['minimum_duration_met'] and 'Correct operation validated.' not in output:
        raise SystemExit('Benchmark did not validate: '+str(b/'run.log'))
    print(json.dumps(record), flush=True)
    return record

with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(run, ['performance', 'validation']))
summary = dict(rtl_commit=command(['git', 'rev-parse', 'HEAD']).strip(), rtl_sha256=rtl_hashes,
               port_sha256=port_hashes, source_commit=rev, kernel_sha256={n: hashlib.sha256((src/n).read_bytes()).hexdigest() for n in [*kernels, 'coremark.h']},
               compiler=command([prefix+'gcc', '--version']).splitlines()[0], compiler_flags=flags,
               memory='Single-hart core RTL; zero-wait 32 KiB IMEM, 16 KiB DMEM; no cache; always-ready UART',
               scope='RTL simulation estimate, not board measurement or timing closure', results=results)
assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest() == h for p,h in rtl_hashes.items())
(a.build/f'results_{a.opt}_{a.iterations}.json').write_text(json.dumps(summary, indent=2)+'\n')
print('PASS: standard performance/validation CRCs and independent crcfinal match.', flush=True)
print(f'CoreMark/MHz (RTL estimate): {results[0]["coremark_per_mhz"]:.6f}', flush=True)
if not all(r['minimum_duration_met'] for r in results):
    print('NOTE: simulated duration is below 10 seconds; this is a short-run estimate.', flush=True)
