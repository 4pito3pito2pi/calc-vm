#!/usr/bin/env python3
"""
codegen.py — Bytecode-to-native translator for calc VM
Reads bytecode from stdin, emits C or x86-64 assembly to stdout.

Usage:
  m4 ... compiler.m4 | python3 codegen.py -t c    > gen.c
  m4 ... compiler.m4 | python3 codegen.py -t amd64 > gen.s

Build:
  gcc -O2 -o calc gen.c bignum.c        # C target
  gcc -O2 -o calc gen.s bignum.c        # amd64 target
"""
import sys
import re

def parse_bytecode(lines):
    """Parse bytecode lines into (op, args) tuples, preserving labels."""
    instrs = []
    for line in lines:
        line = line.strip()
        if not line or line[0] in ('#', ';'):
            continue
        parts = line.split()
        op = parts[0]
        args = parts[1:]
        instrs.append((op, args))
    return instrs

def reg_idx(s):
    """Extract register number from 'rN'."""
    return int(s[1:])

# ============================================================
# C TARGET
# ============================================================
def emit_c(instrs):
    out = []
    out.append('#include "bignum.h"')
    out.append('')
    out.append('static int cmp_flag = 0;')
    out.append('')
    out.append('int main(void) {')

    for op, args in instrs:
        if op == 'LABEL':
            out.append(f'  {args[0]}:;')
        elif op == 'SET':
            r = reg_idx(args[0])
            out.append(f'  bn_set_str(&reg[{r}], "{args[1]}");')
        elif op == 'ADD':
            out.append(f'  bn_add(&reg[{reg_idx(args[2])}], &reg[{reg_idx(args[0])}], &reg[{reg_idx(args[1])}]);')
        elif op == 'SUB':
            out.append(f'  bn_sub(&reg[{reg_idx(args[2])}], &reg[{reg_idx(args[0])}], &reg[{reg_idx(args[1])}]);')
        elif op == 'MUL':
            out.append(f'  bn_mul(&reg[{reg_idx(args[2])}], &reg[{reg_idx(args[0])}], &reg[{reg_idx(args[1])}]);')
        elif op == 'SMUL':
            out.append(f'  bn_smul(&reg[{reg_idx(args[2])}], &reg[{reg_idx(args[0])}], {args[1]});')
        elif op == 'DIV':
            out.append(f'  bn_div(&reg[{reg_idx(args[2])}], &reg[{reg_idx(args[3])}], &reg[{reg_idx(args[0])}], &reg[{reg_idx(args[1])}]);')
        elif op == 'SDIV':
            out.append(f'  bn_sdiv(&reg[{reg_idx(args[2])}], &reg[{reg_idx(args[0])}], {args[1]});')
        elif op == 'SHL':
            out.append(f'  bn_shl(&reg[{reg_idx(args[2])}], &reg[{reg_idx(args[0])}], {args[1]});')
        elif op == 'CMP':
            out.append(f'  cmp_flag = bn_cmp_abs(&reg[{reg_idx(args[0])}], &reg[{reg_idx(args[1])}]);')
        elif op == 'COPY':
            out.append(f'  bn_copy(&reg[{reg_idx(args[1])}], &reg[{reg_idx(args[0])}]);')
        elif op == 'NEG':
            d = reg_idx(args[1])
            out.append(f'  bn_copy(&reg[{d}], &reg[{reg_idx(args[0])}]);')
            out.append(f'  reg[{d}].neg ^= 1;')
            out.append(f'  if (reg[{d}].n == 1 && reg[{d}].limbs[0] == 0) reg[{d}].neg = 0;')
        elif op == 'ABS':
            d = reg_idx(args[1])
            out.append(f'  bn_copy(&reg[{d}], &reg[{reg_idx(args[0])}]);')
            out.append(f'  reg[{d}].neg = 0;')
        elif op == 'ISNEG':
            a, d = reg_idx(args[0]), reg_idx(args[1])
            out.append(f'  reg[{d}].n = 1; reg[{d}].neg = 0;')
            out.append(f'  reg[{d}].limbs[0] = (reg[{a}].neg && !(reg[{a}].n == 1 && reg[{a}].limbs[0] == 0)) ? 1 : 0;')
        elif op == 'POW':
            out.append(f'  bn_pow(&reg[{reg_idx(args[2])}], &reg[{reg_idx(args[0])}], reg[{reg_idx(args[1])}].n == 1 ? reg[{reg_idx(args[1])}].limbs[0] : 0);')
        elif op == 'FACT':
            out.append(f'  bn_fact(&reg[{reg_idx(args[1])}], reg[{reg_idx(args[0])}].n == 1 ? reg[{reg_idx(args[0])}].limbs[0] : 0);')
        elif op == 'JMP':
            out.append(f'  goto {args[0]};')
        elif op == 'BGT':
            out.append(f'  if (cmp_flag > 0) goto {args[0]};')
        elif op == 'BLT':
            out.append(f'  if (cmp_flag < 0) goto {args[0]};')
        elif op == 'BGE':
            out.append(f'  if (cmp_flag >= 0) goto {args[0]};')
        elif op == 'BLE':
            out.append(f'  if (cmp_flag <= 0) goto {args[0]};')
        elif op == 'BEQ':
            out.append(f'  if (cmp_flag == 0) goto {args[0]};')
        elif op == 'BNE':
            out.append(f'  if (cmp_flag != 0) goto {args[0]};')
        elif op == 'PRINT':
            r = reg_idx(args[0])
            out.append(f'  bn_print(&reg[{r}]); printf("\\n");')
        elif op == 'PRINTFP':
            out.append(f'  bn_printfp({reg_idx(args[0])}, {args[1]});')
        elif op == 'PRINTFPC':
            out.append(f'  bn_printfp_nonl({reg_idx(args[0])}, {args[1]});')
        elif op == 'PRINTFPP':
            out.append(f'  bn_printfp_plus({reg_idx(args[0])}, {args[1]});')
        elif op == 'PRINTS':
            out.append(f'  if (!bn_last_zero) printf("%s", "{args[0]}");')
            out.append(f'  bn_last_zero = 0;')
        elif op == 'HALT':
            out.append('  return 0;')
        else:
            out.append(f'  /* unknown: {op} */')

    out.append('  return 0;')
    out.append('}')
    return '\n'.join(out) + '\n'

# ============================================================
# AMD64 TARGET (System V ABI, AT&T syntax)
# ============================================================
def emit_amd64(instrs):
    """instrs is list of (op, [arg1, arg2, ...]) tuples. Returns string of x86-64 asm."""

    # Struct layout: uint32_t limbs[MAX_LIMBS] + int n + int neg
    MAX_LIMBS = 20000
    SIZEOF_BIGNUM = MAX_LIMBS * 4 + 4 + 4  # 80008
    OFF_N   = MAX_LIMBS * 4                 # offset of .n field
    OFF_NEG = MAX_LIMBS * 4 + 4             # offset of .neg field

    # Collect unique string constants for SET and PRINTS instructions
    str_constants = {}
    for op, args in instrs:
        if op == 'SET':
            val = args[1]
            if val not in str_constants:
                str_constants[val] = f'.Lstr_{len(str_constants)}'
        elif op == 'PRINTS':
            val = args[0]
            if val not in str_constants:
                str_constants[val] = f'.Lstr_{len(str_constants)}'

    def reg_offset(reg_num):
        return reg_num * SIZEOF_BIGNUM

    label_counter = [0]
    def new_label(prefix):
        label_counter[0] += 1
        return f'.L{prefix}_{label_counter[0]}'

    lines = []

    # .rodata section with string constants
    lines.append('.section .rodata')
    for val, label in str_constants.items():
        lines.append(f'{label}:')
        lines.append(f'  .asciz "{val}"')
    lines.append('.Lnewline:')
    lines.append('  .asciz "\\n"')
    lines.append('')

    # .bss section for cmp_flag
    lines.append('.section .bss')
    lines.append('.lcomm cmp_flag, 4')
    lines.append('')

    # .text section with main function
    lines.append('.section .text')
    lines.append('.globl main')
    lines.append('main:')
    lines.append('  pushq %r12')
    lines.append('  subq $8, %rsp')
    lines.append('  leaq reg(%rip), %r12')
    lines.append('')

    for op, args in instrs:
        lines.append(f'  # {op} {" ".join(map(str, args))}')

        if op == 'SET':
            rN = reg_idx(args[0])
            val = args[1]
            off = reg_offset(rN)
            label = str_constants[val]
            lines.append(f'  leaq {off}(%r12), %rdi')
            lines.append(f'  leaq {label}(%rip), %rsi')
            lines.append('  call bn_set_str')

        elif op == 'ADD':
            rA, rB, rD = reg_idx(args[0]), reg_idx(args[1]), reg_idx(args[2])
            lines.append(f'  leaq {reg_offset(rD)}(%r12), %rdi')
            lines.append(f'  leaq {reg_offset(rA)}(%r12), %rsi')
            lines.append(f'  leaq {reg_offset(rB)}(%r12), %rdx')
            lines.append('  call bn_add')

        elif op == 'SUB':
            rA, rB, rD = reg_idx(args[0]), reg_idx(args[1]), reg_idx(args[2])
            lines.append(f'  leaq {reg_offset(rD)}(%r12), %rdi')
            lines.append(f'  leaq {reg_offset(rA)}(%r12), %rsi')
            lines.append(f'  leaq {reg_offset(rB)}(%r12), %rdx')
            lines.append('  call bn_sub')

        elif op == 'MUL':
            rA, rB, rD = reg_idx(args[0]), reg_idx(args[1]), reg_idx(args[2])
            lines.append(f'  leaq {reg_offset(rD)}(%r12), %rdi')
            lines.append(f'  leaq {reg_offset(rA)}(%r12), %rsi')
            lines.append(f'  leaq {reg_offset(rB)}(%r12), %rdx')
            lines.append('  call bn_mul')

        elif op == 'SMUL':
            rA, imm, rD = reg_idx(args[0]), int(args[1]), reg_idx(args[2])
            lines.append(f'  leaq {reg_offset(rD)}(%r12), %rdi')
            lines.append(f'  leaq {reg_offset(rA)}(%r12), %rsi')
            lines.append(f'  movl ${imm}, %edx')
            lines.append('  call bn_smul')

        elif op == 'DIV':
            rA, rB = reg_idx(args[0]), reg_idx(args[1])
            rQ, rR = reg_idx(args[2]), reg_idx(args[3])
            lines.append(f'  leaq {reg_offset(rQ)}(%r12), %rdi')
            lines.append(f'  leaq {reg_offset(rR)}(%r12), %rsi')
            lines.append(f'  leaq {reg_offset(rA)}(%r12), %rdx')
            lines.append(f'  leaq {reg_offset(rB)}(%r12), %rcx')
            lines.append('  call bn_div')

        elif op == 'SDIV':
            rA, imm, rD = reg_idx(args[0]), int(args[1]), reg_idx(args[2])
            lines.append(f'  leaq {reg_offset(rD)}(%r12), %rdi')
            lines.append(f'  leaq {reg_offset(rA)}(%r12), %rsi')
            lines.append(f'  movl ${imm}, %edx')
            lines.append('  call bn_sdiv')

        elif op == 'SHL':
            rA, imm, rD = reg_idx(args[0]), int(args[1]), reg_idx(args[2])
            lines.append(f'  leaq {reg_offset(rD)}(%r12), %rdi')
            lines.append(f'  leaq {reg_offset(rA)}(%r12), %rsi')
            lines.append(f'  movl ${imm}, %edx')
            lines.append('  call bn_shl')

        elif op == 'CMP':
            rA, rB = reg_idx(args[0]), reg_idx(args[1])
            lines.append(f'  leaq {reg_offset(rA)}(%r12), %rdi')
            lines.append(f'  leaq {reg_offset(rB)}(%r12), %rsi')
            lines.append('  call bn_cmp_abs')
            lines.append('  movl %eax, cmp_flag(%rip)')

        elif op == 'COPY':
            rA, rD = reg_idx(args[0]), reg_idx(args[1])
            lines.append(f'  leaq {reg_offset(rD)}(%r12), %rdi')
            lines.append(f'  leaq {reg_offset(rA)}(%r12), %rsi')
            lines.append('  call bn_copy')

        elif op == 'NEG':
            rA, rD = reg_idx(args[0]), reg_idx(args[1])
            off_D = reg_offset(rD)
            lines.append(f'  leaq {off_D}(%r12), %rdi')
            lines.append(f'  leaq {reg_offset(rA)}(%r12), %rsi')
            lines.append('  call bn_copy')
            lines.append(f'  xorl $1, {off_D + OFF_NEG}(%r12)')
            skip = new_label('neg_skip')
            lines.append(f'  cmpl $1, {off_D + OFF_N}(%r12)')
            lines.append(f'  jne {skip}')
            lines.append(f'  cmpl $0, {off_D}(%r12)')
            lines.append(f'  jne {skip}')
            lines.append(f'  movl $0, {off_D + OFF_NEG}(%r12)')
            lines.append(f'{skip}:')

        elif op == 'ABS':
            rA, rD = reg_idx(args[0]), reg_idx(args[1])
            off_D = reg_offset(rD)
            lines.append(f'  leaq {off_D}(%r12), %rdi')
            lines.append(f'  leaq {reg_offset(rA)}(%r12), %rsi')
            lines.append('  call bn_copy')
            lines.append(f'  movl $0, {off_D + OFF_NEG}(%r12)')

        elif op == 'ISNEG':
            rA, rD = reg_idx(args[0]), reg_idx(args[1])
            off_A = reg_offset(rA)
            off_D = reg_offset(rD)
            not_zero = new_label('isneg_nz')
            is_neg = new_label('isneg_yes')
            done = new_label('isneg_done')
            # Check if zero: n==1 && limbs[0]==0
            lines.append(f'  cmpl $1, {off_A + OFF_N}(%r12)')
            lines.append(f'  jne {not_zero}')
            lines.append(f'  cmpl $0, {off_A}(%r12)')
            lines.append(f'  je {done}')  # zero → result=0, skip to done
            lines.append(f'{not_zero}:')
            # Not zero — check neg flag
            lines.append(f'  cmpl $0, {off_A + OFF_NEG}(%r12)')
            lines.append(f'  jne {is_neg}')
            # Not negative
            lines.append(f'  jmp {done}')
            lines.append(f'{is_neg}:')
            # Is negative and not zero: set D to 1
            lines.append(f'  movl $1, {off_D}(%r12)')
            lines.append(f'  movl $1, {off_D + OFF_N}(%r12)')
            lines.append(f'  movl $0, {off_D + OFF_NEG}(%r12)')
            lines.append(f'  jmp {done}_end')
            lines.append(f'{done}:')
            # Result = 0
            lines.append(f'  movl $0, {off_D}(%r12)')
            lines.append(f'  movl $1, {off_D + OFF_N}(%r12)')
            lines.append(f'  movl $0, {off_D + OFF_NEG}(%r12)')
            lines.append(f'{done}_end:')

        elif op == 'POW':
            rA, rB, rD = reg_idx(args[0]), reg_idx(args[1]), reg_idx(args[2])
            off_B = reg_offset(rB)
            lbl_zero = new_label('pow_zero')
            lbl_done = new_label('pow_done')
            lines.append(f'  cmpl $1, {off_B + OFF_N}(%r12)')
            lines.append(f'  jne {lbl_zero}')
            lines.append(f'  movl {off_B}(%r12), %edx')
            lines.append(f'  jmp {lbl_done}')
            lines.append(f'{lbl_zero}:')
            lines.append('  xorl %edx, %edx')
            lines.append(f'{lbl_done}:')
            lines.append(f'  leaq {reg_offset(rD)}(%r12), %rdi')
            lines.append(f'  leaq {reg_offset(rA)}(%r12), %rsi')
            lines.append('  call bn_pow')

        elif op == 'FACT':
            rA, rD = reg_idx(args[0]), reg_idx(args[1])
            off_A = reg_offset(rA)
            lbl_zero = new_label('fact_zero')
            lbl_done = new_label('fact_done')
            lines.append(f'  cmpl $1, {off_A + OFF_N}(%r12)')
            lines.append(f'  jne {lbl_zero}')
            lines.append(f'  movl {off_A}(%r12), %esi')
            lines.append(f'  jmp {lbl_done}')
            lines.append(f'{lbl_zero}:')
            lines.append('  xorl %esi, %esi')
            lines.append(f'{lbl_done}:')
            lines.append(f'  leaq {reg_offset(rD)}(%r12), %rdi')
            lines.append('  call bn_fact')

        elif op == 'JMP':
            lines.append(f'  jmp {args[0]}')

        elif op in ('BGT', 'BLT', 'BGE', 'BLE', 'BEQ', 'BNE'):
            label = args[0]
            lines.append('  cmpl $0, cmp_flag(%rip)')
            jcc = {'BGT': 'jg', 'BLT': 'jl', 'BGE': 'jge',
                   'BLE': 'jle', 'BEQ': 'je', 'BNE': 'jne'}
            lines.append(f'  {jcc[op]} {label}')

        elif op == 'PRINT':
            rN = reg_idx(args[0])
            lines.append(f'  leaq {reg_offset(rN)}(%r12), %rdi')
            lines.append('  call bn_print')
            lines.append('  leaq .Lnewline(%rip), %rdi')
            lines.append('  xorl %eax, %eax')
            lines.append('  call printf')

        elif op == 'PRINTFP':
            rN = reg_idx(args[0])
            dp = int(args[1])
            lines.append(f'  movl ${rN}, %edi')
            lines.append(f'  movl ${dp}, %esi')
            lines.append('  call bn_printfp')

        elif op == 'PRINTFPC':
            rN = reg_idx(args[0])
            dp = int(args[1])
            lines.append(f'  movl ${rN}, %edi')
            lines.append(f'  movl ${dp}, %esi')
            lines.append('  call bn_printfp_nonl')

        elif op == 'PRINTFPP':
            rN = reg_idx(args[0])
            dp = int(args[1])
            lines.append(f'  movl ${rN}, %edi')
            lines.append(f'  movl ${dp}, %esi')
            lines.append('  call bn_printfp_plus')

        elif op == 'PRINTS':
            label_skip = new_label('ps')
            str_label = str_constants[args[0]]
            lines.append(f'  cmpl $0, bn_last_zero(%rip)')
            lines.append(f'  jne {label_skip}')
            lines.append(f'  leaq {str_label}(%rip), %rdi')
            lines.append(f'  xorl %eax, %eax')
            lines.append(f'  call printf')
            lines.append(f'{label_skip}:')
            lines.append(f'  movl $0, bn_last_zero(%rip)')

        elif op == 'HALT':
            lines.append('  jmp .Lexit')

        elif op == 'LABEL':
            lines.append(f'{args[0]}:')

        lines.append('')

    lines.append('.Lexit:')
    lines.append('  xorl %eax, %eax')
    lines.append('  addq $8, %rsp')
    lines.append('  popq %r12')
    lines.append('  ret')
    lines.append('')
    lines.append('.section .note.GNU-stack,"",@progbits')

    return '\n'.join(lines) + '\n'

# ============================================================
# MAIN
# ============================================================
TARGETS = {
    'c': emit_c,
    'amd64': emit_amd64,
}

def main():
    import argparse
    p = argparse.ArgumentParser(description='Bytecode to native translator')
    p.add_argument('-t', '--target', choices=TARGETS.keys(), default='c',
                   help='Output target (default: c)')
    args = p.parse_args()

    lines = sys.stdin.readlines()
    instrs = parse_bytecode(lines)
    print(TARGETS[args.target](instrs), end='')

if __name__ == '__main__':
    main()
