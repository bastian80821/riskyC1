#!/usr/bin/env python3
"""Convert a raw binary to the hex format the riscyC1 bootloader expects:
one 32-bit word per line, written big-endian as text but representing a
little-endian value (which is how RISC-V stores instructions)."""
import sys, struct

def main():
    if len(sys.argv) != 3:
        print("usage: bin2hex.py <in.bin> <out.hex>")
        sys.exit(1)
    data = open(sys.argv[1], 'rb').read()
    # pad to a word boundary
    if len(data) % 4:
        data += b'\x00' * (4 - len(data) % 4)
    with open(sys.argv[2], 'w') as f:
        for i in range(0, len(data), 4):
            word = struct.unpack('<I', data[i:i+4])[0]
            f.write(f"{word:08X}\n")

if __name__ == '__main__':
    main()
