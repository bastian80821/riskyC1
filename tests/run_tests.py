#!/usr/bin/env python3
"""
Run the riscv-tests suite on riscyC1 hardware.

For each .hex in tests/, sends it to the board over serial, waits for the core
to report a result, and tallies. The test environment prints:

    P      -> pass
    Fxx    -> fail, xx = the failing sub-test number in hex

No board reset is needed between tests: the bootloader keeps listening after a
program has been loaded, and four further bytes are taken as a new word count,
which resets the core and starts a fresh load.

Usage:
    python run_tests.py COM5 tests/
"""
import sys, os, glob, struct, time

def load_hex(path):
    words = []
    with open(path) as f:
        for line in f:
            line = line.split('//')[0].strip()
            if line:
                words.append(int(line, 16))
    return words

def run_one(ser, path, timeout=3.0):
    words = load_hex(path)
    ser.reset_input_buffer()
    ser.write(struct.pack('<I', len(words)))
    for w in words:
        ser.write(struct.pack('<I', w))
    ser.flush()

    out = b""
    deadline = time.time() + timeout
    while time.time() < deadline:
        chunk = ser.read(16)
        if chunk:
            out += chunk
            if b'\n' in out:
                break
    return out.decode('ascii', errors='replace').strip()

def main():
    if len(sys.argv) != 3:
        print(__doc__); sys.exit(1)
    port, testdir = sys.argv[1], sys.argv[2]

    try:
        import serial
    except ImportError:
        print("pyserial not installed.  Run:  pip install pyserial"); sys.exit(1)

    tests = sorted(glob.glob(os.path.join(testdir, "*.hex")))
    if not tests:
        print(f"No .hex files in {testdir}"); sys.exit(1)

    ser = serial.Serial(port, 115200, timeout=0.2)
    passed, failed, noresp = [], [], []

    print(f"\nRunning {len(tests)} tests on {port}\n" + "=" * 46)
    for path in tests:
        name = os.path.basename(path).replace('.hex', '')
        # No board reset needed: the bootloader accepts a new word count at any
        # time, which drops core_run and starts a fresh load.
        result = run_one(ser, path)
        if result.startswith('P'):
            print(f"  PASS  {name}")
            passed.append(name)
        elif result.startswith('F'):
            print(f"  FAIL  {name}   (sub-test 0x{result[1:3]})")
            failed.append((name, result[1:3]))
        else:
            print(f"  ----  {name}   (no response: {result!r})")
            noresp.append(name)

    ser.close()
    print("=" * 46)
    print(f"  {len(passed)} passed, {len(failed)} failed, {len(noresp)} no response")
    if failed:
        print("\n  Failing tests:")
        for n, sub in failed:
            print(f"    {n}  at sub-test 0x{sub}")
    print()

if __name__ == '__main__':
    main()
