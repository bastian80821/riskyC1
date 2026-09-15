// Custom riscv-tests environment for riscyC1.
//
// The official env/p/riscv_test.h signals pass/fail by writing a `tohost`
// location, and uses CSR / ECALL / FENCE instructions. riscyC1 implements none
// of those, so this environment reports through the memory-mapped UART instead:
//
//     PASS  ->  transmit 'P', newline, then halt
//     FAIL  ->  transmit 'F', two hex digits of TESTNUM, newline, then halt
//
// "Halt" is an infinite self-jump; the host script reads the serial output and
// resets the board before the next test.
//
// TESTNUM is gp (x3) and holds the index of the sub-test currently running, so
// on failure it identifies exactly which case broke.

#ifndef _ENV_RISCYC1_TEST_H
#define _ENV_RISCYC1_TEST_H

#define TESTNUM gp

#define UART_BASE   0x1000
#define UART_DATA   0x0        /* write: transmit the low byte  */
#define UART_STATUS 0x4        /* read:  bit 0 = transmitter busy */

//-----------------------------------------------------------------------
// TVM macros - riscyC1 is a bare RV32I machine, so these are no-ops
//-----------------------------------------------------------------------

#define RVTEST_RV32U
#define RVTEST_RV32M
#define RVTEST_RV32S
#define RVTEST_RV64U
#define RVTEST_RV64M
#define RVTEST_RV64S

//-----------------------------------------------------------------------
// Code section
//-----------------------------------------------------------------------

#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .align 6;                                                       \
        .globl _start;                                                  \
_start:

#define RVTEST_CODE_END

//-----------------------------------------------------------------------
// Pass
//
//   t0 = UART base, t1 = character, t2 = busy flag.
//   Registers are free at this point: the test has finished.
//-----------------------------------------------------------------------

#define RVTEST_PASS                                                     \
        li   t0, UART_BASE;                                             \
        li   t1, 'P';                                                   \
1:      lw   t2, UART_STATUS(t0);                                       \
        bnez t2, 1b;                                                    \
        sw   t1, UART_DATA(t0);                                         \
        li   t1, 10;                                                    \
2:      lw   t2, UART_STATUS(t0);                                       \
        bnez t2, 2b;                                                    \
        sw   t1, UART_DATA(t0);                                         \
3:      j    3b;

//-----------------------------------------------------------------------
// Fail
//
//   Prints 'F' then the low byte of TESTNUM as two hex digits.
//   t3 holds a copy of TESTNUM so gp itself is never disturbed.
//-----------------------------------------------------------------------

#define RVTEST_FAIL                                                     \
        li   t0, UART_BASE;                                             \
        mv   t3, TESTNUM;                                               \
        li   t1, 'F';                                                   \
4:      lw   t2, UART_STATUS(t0);                                       \
        bnez t2, 4b;                                                    \
        sw   t1, UART_DATA(t0);                                         \
        srli t1, t3, 4;                                                 \
        andi t1, t1, 0xF;                                               \
        li   t4, 10;                                                    \
        blt  t1, t4, 5f;                                                \
        addi t1, t1, 55;                                                \
        j    6f;                                                        \
5:      addi t1, t1, 48;                                                \
6:      lw   t2, UART_STATUS(t0);                                       \
        bnez t2, 6b;                                                    \
        sw   t1, UART_DATA(t0);                                         \
        andi t1, t3, 0xF;                                               \
        li   t4, 10;                                                    \
        blt  t1, t4, 7f;                                                \
        addi t1, t1, 55;                                                \
        j    8f;                                                        \
7:      addi t1, t1, 48;                                                \
8:      lw   t2, UART_STATUS(t0);                                       \
        bnez t2, 8b;                                                    \
        sw   t1, UART_DATA(t0);                                         \
        li   t1, 10;                                                    \
9:      lw   t2, UART_STATUS(t0);                                       \
        bnez t2, 9b;                                                    \
        sw   t1, UART_DATA(t0);                                         \
0:      j    0b;

//-----------------------------------------------------------------------
// Data section
//
// No tohost/fromhost: nothing watches memory in this environment.
//-----------------------------------------------------------------------

#define EXTRA_DATA

#define RVTEST_DATA_BEGIN                                               \
        EXTRA_DATA                                                      \
        .align 4;                                                       \
        .global begin_signature; begin_signature:

#define RVTEST_DATA_END                                                 \
        .align 4;                                                       \
        .global end_signature; end_signature:

#endif
