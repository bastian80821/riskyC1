#!/bin/bash
# Build the official riscv-tests rv32ui ISA suite for riscyC1.
#
# Each test is assembled against our custom environment (riscv_test.h), linked
# flat at address 0, stripped to a raw binary, and converted to the hex format
# the bootloader expects.
#
# Usage:   ./build_tests.sh [path-to-riscv-tests]
# Output:  tests/*.hex

set -u

RVTESTS=${1:-$HOME/riscv-tests}
OUT=tests

# Pick a toolchain
PREFIX=riscv32-unknown-elf
if ! command -v $PREFIX-gcc >/dev/null 2>&1; then
    PREFIX=riscv64-unknown-elf
    if ! command -v $PREFIX-gcc >/dev/null 2>&1; then
        echo "ERROR: no RISC-V toolchain on PATH (tried riscv32- and riscv64-unknown-elf)."
        exit 1
    fi
fi
echo "Toolchain : $PREFIX-gcc"
echo "Tests     : $RVTESTS"

ISA_DIR=$RVTESTS/isa/rv32ui
MACROS=$RVTESTS/isa/macros/scalar

if [ ! -d "$ISA_DIR" ]; then
    echo "ERROR: $ISA_DIR not found. Pass the riscv-tests path as an argument."
    exit 1
fi

mkdir -p $OUT
rm -f $OUT/*.hex $OUT/*.elf $OUT/*.bin

# Only instructions riscyC1 implements.
# Excluded: fence_i (no instruction cache), lb/lbu/lh/lhu/sb/sh (no byte or
# halfword access), and anything requiring CSRs or ECALL.
TESTS="add addi and andi auipc beq bge bgeu blt bltu bne jal jalr lui \
       lw or ori sll slli slt slti sltiu sltu sra srai srl srli sub sw xor xori"

# -mno-relax is essential: linker relaxation rewrites `la` into gp-relative
# addressing, but gp is TESTNUM in this test framework, so relaxation would
# silently corrupt every test.
CFLAGS="-march=rv32i -mabi=ilp32 -mno-relax -nostdlib -nostartfiles -fno-pic"

OK=0; BAD=0
for t in $TESTS; do
    SRC=$ISA_DIR/$t.S
    if [ ! -f "$SRC" ]; then
        echo "  skip   $t   (source not found)"
        continue
    fi

    ERR=$( $PREFIX-gcc $CFLAGS -I. -I$MACROS -I$ISA_DIR \
             -T link.ld -o $OUT/$t.elf $SRC 2>&1 )
    if [ $? -eq 0 ]; then
        $PREFIX-objcopy -O binary $OUT/$t.elf $OUT/$t.bin
        python3 bin2hex.py $OUT/$t.bin $OUT/$t.hex
        WORDS=$(wc -l < $OUT/$t.hex)
        if [ "$WORDS" -gt 1024 ]; then
            echo "  WARN   $t   ($WORDS words - exceeds 1024-word memory!)"
        else
            echo "  built  $t   ($WORDS words)"
        fi
        OK=$((OK+1))
    else
        echo "  FAIL   $t"
        echo "$ERR" | head -5 | sed 's/^/           /'
        BAD=$((BAD+1))
    fi
done

rm -f $OUT/*.elf $OUT/*.bin
echo
echo "Built $OK tests, $BAD failed.  Hex files in $OUT/"
