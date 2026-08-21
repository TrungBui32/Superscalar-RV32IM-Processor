#!/usr/bin/env python3
"""
hex_to_coe.py
-------------
Convert DMEM_full.hex and IMEM.hex (od -An -tx4 format) to Xilinx .coe format.

Usage:
    python3 hex_to_coe.py
"""

import sys
import os

CONVERSIONS = [
    ("build/DMEM_full.hex", "DMEM.coe"),
    ("build/IMEM.hex",      "IMEM.coe"),
]


def hex_to_coe(input_path: str, output_path: str):
    """
    Convert an od-format .hex file to .coe format.

    od output lines look like: ' deadbeef' (leading space, one 4-byte word).
    """
    try:
        with open(input_path, 'r') as fin:
            hex_values = []
            for line in fin:
                value = line.strip()
                if value and not value.startswith('#'):
                    # Remove optional 0x prefix
                    value = value.replace('0x', '').replace('0X', '')
                    hex_values.append(value)

        if not hex_values:
            print(f"Error: No data found in '{input_path}'")
            return False

        with open(output_path, 'w') as fout:
            fout.write("; Coefficient file generated from .hex file\n")
            fout.write(f"; Source: {input_path}\n")
            fout.write(f"; Total entries: {len(hex_values)}\n")
            fout.write(";\n")
            fout.write("memory_initialization_radix=16;\n")
            fout.write("memory_initialization_vector=\n")

            for i, value in enumerate(hex_values):
                if i == len(hex_values) - 1:
                    fout.write(f"{value};\n")
                else:
                    fout.write(f"{value},\n")

        print(f"Converted '{input_path}' -> '{output_path}' ({len(hex_values)} entries)")
        return True

    except FileNotFoundError:
        print(f"Error: File '{input_path}' not found")
        return False
    except Exception as e:
        print(f"Error processing '{input_path}': {e}")
        return False


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    success = True
    for input_name, output_name in CONVERSIONS:
        input_path  = os.path.join(script_dir, input_name)
        output_path = os.path.join(script_dir, output_name)
        if not hex_to_coe(input_path, output_path):
            success = False
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
