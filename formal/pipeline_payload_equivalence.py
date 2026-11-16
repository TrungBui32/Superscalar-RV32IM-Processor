#!/usr/bin/env python3
"""Prove pipeline controls and valid payloads match a pre-optimization revision."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile

PAYLOADS = {
    'if_id_reg': ['pc_id', 'pcplus4_id', 'branch_pred_target_id'],
    'id_ex_reg': ['pc_ex', 'pcplus4_ex', 'rs1_val_ex', 'rs2_val_ex', 'imm_ex',
                  'csr_rdata_ex', 'csr_addr_ex', 'branch_pred_target_ex'],
    'ex_mem_reg': ['pc_mem', 'pcplus4_mem', 'alu_out_mem', 'store_data_mem',
                  'MCycle_Result_mem', 'PC_branch_mem', 'ALUFlags_mem',
                  'branch_pred_target_mem', 'csr_rdata_mem', 'csr_addr_mem', 'csr_wdata_mem'],
    'mem_wb_reg': ['pcplus4_wb', 'mem_rdata_wb', 'alu_out_wb', 'MCycle_Result_wb', 'csr_rdata_wb'],
}
VALID = dict(zip(PAYLOADS, ['valid_id', 'valid_ex', 'valid_mem', 'valid_wb']))


def quoted(path):
    return '"' + str(path).replace('\\', '\\\\').replace('"', '\\"') + '"'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', default='426e4e0', help='Baseline Git revision')
    parser.add_argument('--output', type=Path, help='Directory for proof sources and logs')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    out = (args.output or Path(tempfile.mkdtemp(prefix='pipeline-equivalence-'))).resolve()
    out.mkdir(parents=True, exist_ok=True)
    results = []
    for module, payloads in PAYLOADS.items():
        relative = f'rtl/core/{module}.v'
        current = repo / relative
        baseline = subprocess.check_output(
            ['git', 'show', f'{args.reference}:{relative}'], cwd=repo, text=True)
        gold = out / f'{module}_gold.v'
        gold.write_text(re.sub(r'\bmodule\s+' + module + r'\b',
                               'module ' + module + '_gold', baseline, count=1))
        inputs, outputs = [], []
        for line in current.read_text().split(');', 1)[0].splitlines():
            match = re.match(r'\s*(input|output)\s+(?:(?:wire|reg)\s+)?(\[[^]]+\])?\s*(\w+)', line)
            if match:
                (inputs if match[1] == 'input' else outputs).append((match[3], match[2] or ''))
        required = set(payloads + [VALID[module]])
        if not required.issubset({name for name, _ in outputs}):
            raise SystemExit(f'Missing validity/payload outputs in {module}')
        controls = [name for name, _ in outputs if name not in payloads]
        top = module + '_equivalence'
        text = f'module {top}(\n' + ',\n'.join(
            f'input {width} {name}' for name, width in inputs) + ',\noutput equivalent\n);\n'
        for prefix in ['gold', 'gate']:
            text += ''.join(f'wire {width} {prefix}_{name};\n' for name, width in outputs)
            implementation = module + '_gold' if prefix == 'gold' else module
            bindings = [f'.{name}({name})' for name, _ in inputs]
            bindings += [f'.{name}({prefix}_{name})' for name, _ in outputs]
            text += f'{implementation} {prefix}(' + ','.join(bindings) + ');\n'
        def equal(names):
            return ('{' + ','.join('gold_' + n for n in names) + '} == {' +
                    ','.join('gate_' + n for n in names) + '}')
        text += ('assign equivalent=(' + equal(controls) + ') && (!gold_' + VALID[module] +
                 ' || (' + equal(payloads) + '));\nendmodule\n')
        wrapper = out / (top + '.v')
        wrapper.write_text(text)
        script = out / (top + '.ys')
        script.write_text(
            f'read_verilog {quoted(gold)} {quoted(current)} {quoted(wrapper)}\n'
            f'prep -top {top} -flatten\nopt -full\n'
            'sat -verify -prove equivalent 1 -seq 2 -tempinduct -maxsteps 8 -set-init-zero -timeout 60\n')
        result = subprocess.run(['yosys', '-Q', '-s', str(script)], cwd=repo,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        log = out / (top + '.log')
        log.write_text(result.stdout)
        if result.returncode or 'Induction step proven: SUCCESS' not in result.stdout:
            raise SystemExit(f'FAIL: {module}; see {log}')
        print(f'PASS: {module}: controls always equal; payload equal whenever valid', flush=True)
        results.append({'module': module, 'reference': args.reference, 'status': 'PASS'})
    (out / 'results.json').write_text(json.dumps(results, indent=2))
    print(f'Proof artifacts: {out}')


if __name__ == '__main__':
    main()
