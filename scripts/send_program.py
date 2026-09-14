#!/usr/bin/env python3
"""
Send a .hex program to the riscyC1 bootloader over a serial port.

Protocol (little-endian):
    4 bytes : word count N
    N*4 bytes : the program, one 32-bit instruction per 4 bytes

Then prints whatever the core transmits back.

Usage:
    python send_program.py COM4 programs/hello_test.hex
    python send_program.py /dev/ttyUSB0 programs/hello_test.hex

Requires: pip install pyserial
"""
import sys, struct, time

def load_hex(path):
    words = []
    with open(path) as f:
        for line in f:
            line = line.split('//')[0].strip()
            if line:
                words.append(int(line, 16))
    return words

def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    port, hexfile = sys.argv[1], sys.argv[2]

    try:
        import serial
    except ImportError:
        print("pyserial not installed.  Run:  pip install pyserial")
        sys.exit(1)

    words = load_hex(hexfile)
    print(f"Loaded {len(words)} instruction words from {hexfile}")

    ser = serial.Serial(port, 115200, timeout=1)
    time.sleep(0.1)

    ser.write(struct.pack('<I', len(words)))          # word count
    for w in words:
        ser.write(struct.pack('<I', w))               # program
    ser.flush()
    print("Program sent.  Core released.  Output follows:\n")
    print("-" * 40)

    try:
        while True:
            data = ser.read(64)
            if data:
                sys.stdout.write(data.decode('ascii', errors='replace'))
                sys.stdout.flush()
    except KeyboardInterrupt:
        print("\n" + "-" * 40)
        ser.close()

if __name__ == '__main__':
    main()
