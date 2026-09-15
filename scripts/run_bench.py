#!/usr/bin/env python3
"""
Run the IPC benchmark on riscyC1 and report cycles, instructions and IPC.

The benchmark program runs a 200-iteration loop mixing dependent ALU operations,
a store, a load-use hazard, and a taken branch, then emits its counter readings
as raw bytes framed by 0xAA / 0x55 markers:

    AA  <cycles:4 LE>  <instret:4 LE>  55

Usage:
    python run_bench.py COM5 programs/ipc_bench.hex [clock_hz]
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
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(1)
    port, hexfile = sys.argv[1], sys.argv[2]
    clock_hz = int(sys.argv[3]) if len(sys.argv) > 3 else 12_000_000

    try:
        import serial
    except ImportError:
        print("pyserial not installed.  Run:  pip install pyserial"); sys.exit(1)

    words = load_hex(hexfile)
    ser = serial.Serial(port, 115200, timeout=0.3)
    time.sleep(0.1)
    ser.reset_input_buffer()

    ser.write(struct.pack('<I', len(words)))
    for w in words:
        ser.write(struct.pack('<I', w))
    ser.flush()

    # collect until the end marker or timeout
    data = b""
    deadline = time.time() + 5.0
    while time.time() < deadline and 0x55 not in data:
        chunk = ser.read(32)
        if chunk:
            data += chunk
    ser.close()

    if 0xAA not in data:
        print(f"No start marker received.  Raw: {data.hex()}")
        sys.exit(1)

    i = data.index(0xAA)
    payload = data[i+1:i+9]
    if len(payload) < 8:
        print(f"Truncated response.  Raw: {data.hex()}")
        sys.exit(1)

    cycles  = struct.unpack('<I', payload[0:4])[0]
    instret = struct.unpack('<I', payload[4:8])[0]
    ipc     = instret / cycles if cycles else 0.0

    print()
    print("  riscyC1 IPC benchmark")
    print("  " + "-" * 34)
    print(f"  cycles            {cycles:>10,}")
    print(f"  instructions      {instret:>10,}")
    print(f"  IPC               {ipc:>10.3f}")
    print(f"  CPI               {1/ipc if ipc else 0:>10.3f}")
    print(f"  clock             {clock_hz/1e6:>10.1f} MHz")
    print(f"  MIPS              {instret/ (cycles/clock_hz) / 1e6:>10.1f}")
    print()

if __name__ == '__main__':
    main()
