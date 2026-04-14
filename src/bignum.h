/*
 * bignum.h — Bignum arithmetic runtime for calc VM
 * Base 10^9 limbs, uint32_t limbs, uint64_t intermediate
 */
#ifndef BIGNUM_H
#define BIGNUM_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define BASE      1000000000ULL
#define MAX_LIMBS 20000  /* enough for ~180000 digits */
#define NREG      512

typedef struct {
    uint32_t limbs[MAX_LIMBS]; /* big-endian: limbs[0] = most significant */
    int n;                     /* number of limbs */
    int neg;                   /* sign: 0=positive, 1=negative */
} Bignum;

extern Bignum reg[NREG];

void     bn_set_str(Bignum *r, const char *s);
void     bn_print(const Bignum *r);
int      bn_sprint(const Bignum *r, char *buf);
void     bn_norm(Bignum *r);
int      bn_cmp_abs(const Bignum *a, const Bignum *b);
void     bn_add_abs(Bignum *dst, const Bignum *a, const Bignum *b);
void     bn_sub_abs(Bignum *dst, const Bignum *a, const Bignum *b);
void     bn_add(Bignum *dst, const Bignum *a, const Bignum *b);
void     bn_sub(Bignum *dst, const Bignum *a, const Bignum *b);
void     bn_smul(Bignum *dst, const Bignum *a, uint32_t imm);
void     bn_mul(Bignum *dst, const Bignum *a, const Bignum *b);
uint32_t bn_sdiv(Bignum *dst, const Bignum *a, uint32_t imm);
void     bn_shl(Bignum *dst, const Bignum *a, int k);
void     bn_div(Bignum *q, Bignum *r, const Bignum *a, const Bignum *b);
void     bn_copy(Bignum *dst, const Bignum *src);
void     bn_pow(Bignum *dst, const Bignum *base, uint32_t exp);
void     bn_fact(Bignum *dst, uint32_t n);

/* Helpers used by codegen targets */
void     bn_printfp(int r, int dp);
void     bn_printfp_nonl(int r, int dp);
void     bn_printfp_plus(int r, int dp);

/* Zero-suppression flag: set by bn_printfp_plus when value is zero */
extern int bn_last_zero;

#endif
