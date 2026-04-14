/*
 * bignum.c — Bignum arithmetic runtime for calc VM
 * Base 10^9 limbs, uint32_t limbs, uint64_t intermediate
 */
#include "bignum.h"

Bignum reg[NREG];

void bn_set_str(Bignum *r, const char *s) {
    memset(r, 0, sizeof(*r));
    if (*s == '-') { r->neg = 1; s++; }
    while (*s == '0' && *(s+1)) s++;
    int len = strlen(s);
    int nlimbs = (len + 8) / 9;
    r->n = nlimbs;
    for (int i = 0; i < nlimbs; i++) {
        int end = len - (nlimbs - 1 - i) * 9;
        int start = end - 9;
        if (start < 0) start = 0;
        uint32_t v = 0;
        for (int j = start; j < end; j++)
            v = v * 10 + (s[j] - '0');
        r->limbs[i] = v;
    }
}

void bn_print(const Bignum *r) {
    if (r->neg && !(r->n == 1 && r->limbs[0] == 0)) printf("-");
    printf("%u", r->limbs[0]);
    for (int i = 1; i < r->n; i++)
        printf("%09u", r->limbs[i]);
}

int bn_sprint(const Bignum *r, char *buf) {
    int pos = 0;
    if (r->neg && !(r->n == 1 && r->limbs[0] == 0))
        pos += sprintf(buf + pos, "-");
    pos += sprintf(buf + pos, "%u", r->limbs[0]);
    for (int i = 1; i < r->n; i++)
        pos += sprintf(buf + pos, "%09u", r->limbs[i]);
    return pos;
}

void bn_norm(Bignum *r) {
    while (r->n > 1 && r->limbs[0] == 0) {
        memmove(r->limbs, r->limbs + 1, (r->n - 1) * sizeof(uint32_t));
        r->n--;
    }
}

int bn_cmp_abs(const Bignum *a, const Bignum *b) {
    if (a->n != b->n) return a->n > b->n ? 1 : -1;
    for (int i = 0; i < a->n; i++) {
        if (a->limbs[i] != b->limbs[i])
            return a->limbs[i] > b->limbs[i] ? 1 : -1;
    }
    return 0;
}

void bn_add_abs(Bignum *dst, const Bignum *a, const Bignum *b) {
    int na = a->n, nb = b->n;
    int nd = na > nb ? na : nb;
    uint64_t carry = 0;
    for (int i = 0; i < nd; i++) {
        int ia = na - 1 - i, ib = nb - 1 - i;
        uint64_t va = ia >= 0 ? a->limbs[ia] : 0;
        uint64_t vb = ib >= 0 ? b->limbs[ib] : 0;
        uint64_t s = va + vb + carry;
        carry = s / BASE;
        dst->limbs[nd - i] = (uint32_t)(s % BASE);
    }
    if (carry) {
        dst->limbs[0] = (uint32_t)carry;
        dst->n = nd + 1;
    } else {
        memmove(dst->limbs, dst->limbs + 1, nd * sizeof(uint32_t));
        dst->n = nd;
    }
}

void bn_sub_abs(Bignum *dst, const Bignum *a, const Bignum *b) {
    int na = a->n, nb = b->n;
    int64_t borrow = 0;
    for (int i = 0; i < na; i++) {
        int ia = na - 1 - i, ib = nb - 1 - i;
        int64_t va = a->limbs[ia];
        int64_t vb = ib >= 0 ? b->limbs[ib] : 0;
        int64_t s = va - vb - borrow;
        if (s < 0) { borrow = 1; s += BASE; } else { borrow = 0; }
        dst->limbs[ia] = (uint32_t)s;
    }
    dst->n = na;
    bn_norm(dst);
}

void bn_add(Bignum *dst, const Bignum *a, const Bignum *b) {
    if (a->neg == b->neg) {
        bn_add_abs(dst, a, b);
        dst->neg = a->neg;
    } else {
        int c = bn_cmp_abs(a, b);
        if (c >= 0) { bn_sub_abs(dst, a, b); dst->neg = a->neg; }
        else         { bn_sub_abs(dst, b, a); dst->neg = b->neg; }
    }
    if (dst->n == 1 && dst->limbs[0] == 0) dst->neg = 0;
}

void bn_sub(Bignum *dst, const Bignum *a, const Bignum *b) {
    Bignum tmp = *b;
    tmp.neg = !tmp.neg;
    bn_add(dst, a, &tmp);
}

void bn_smul(Bignum *dst, const Bignum *a, uint32_t imm) {
    uint64_t carry = 0;
    int na = a->n;
    for (int i = na - 1; i >= 0; i--) {
        uint64_t p = (uint64_t)a->limbs[i] * imm + carry;
        dst->limbs[i + 1] = (uint32_t)(p % BASE);
        carry = p / BASE;
    }
    if (carry) {
        dst->limbs[0] = (uint32_t)carry;
        dst->n = na + 1;
    } else {
        memmove(dst->limbs, dst->limbs + 1, na * sizeof(uint32_t));
        dst->n = na;
    }
    dst->neg = a->neg;
}

void bn_mul(Bignum *dst, const Bignum *a, const Bignum *b) {
    int na = a->n, nb = b->n, nd = na + nb;
    static uint64_t tmp[MAX_LIMBS * 2];
    memset(tmp, 0, nd * sizeof(uint64_t));
    for (int i = na - 1; i >= 0; i--)
        for (int j = nb - 1; j >= 0; j--) {
            uint64_t p = (uint64_t)a->limbs[i] * b->limbs[j];
            int pos = (na - 1 - i) + (nb - 1 - j);
            tmp[pos] += p;
        }
    for (int i = 0; i < nd; i++) {
        tmp[i + 1] += tmp[i] / BASE;
        tmp[i] %= BASE;
    }
    while (nd > 1 && tmp[nd - 1] == 0) nd--;
    dst->n = nd;
    for (int i = 0; i < nd; i++)
        dst->limbs[i] = (uint32_t)tmp[nd - 1 - i];
    dst->neg = a->neg ^ b->neg;
    if (dst->n == 1 && dst->limbs[0] == 0) dst->neg = 0;
}

uint32_t bn_sdiv(Bignum *dst, const Bignum *a, uint32_t imm) {
    uint64_t rem = 0;
    dst->n = a->n;
    dst->neg = a->neg;
    for (int i = 0; i < a->n; i++) {
        rem = rem * BASE + a->limbs[i];
        dst->limbs[i] = (uint32_t)(rem / imm);
        rem %= imm;
    }
    bn_norm(dst);
    return (uint32_t)rem;
}

void bn_shl(Bignum *dst, const Bignum *a, int k) {
    dst->n = a->n + k;
    memmove(dst->limbs, a->limbs, a->n * sizeof(uint32_t));
    memset(dst->limbs + a->n, 0, k * sizeof(uint32_t));
    dst->neg = a->neg;
}

void bn_div(Bignum *q, Bignum *r, const Bignum *a, const Bignum *b) {
    int a_neg = a->neg, b_neg = b->neg;
    if (b->n == 1) {
        uint32_t rem = bn_sdiv(q, a, b->limbs[0]);
        q->neg = a_neg ^ b_neg;
        if (q->n == 1 && q->limbs[0] == 0) q->neg = 0;
        bn_set_str(r, "0");
        r->limbs[0] = rem;
        return;
    }
    *r = *a; r->neg = 0;
    int qlen = a->n - b->n + 1;
    if (qlen <= 0) {
        bn_set_str(q, "0");
        *r = *a;
        return;
    }
    Bignum babs = *b; babs.neg = 0;
    Bignum shifted, prod;
    for (int pos = 0; pos < qlen; pos++) {
        int shift = qlen - 1 - pos;
        bn_shl(&shifted, &babs, shift);
        if (bn_cmp_abs(r, &shifted) < 0) {
            q->limbs[pos] = 0;
            continue;
        }
        uint32_t lo = 1, hi = BASE - 1;
        while (lo < hi) {
            uint32_t mid = lo + (hi - lo + 1) / 2;
            bn_smul(&prod, &babs, mid);
            bn_shl(&shifted, &prod, shift);
            if (bn_cmp_abs(&shifted, r) <= 0)
                lo = mid;
            else
                hi = mid - 1;
        }
        q->limbs[pos] = lo;
        bn_smul(&prod, &babs, lo);
        bn_shl(&shifted, &prod, shift);
        bn_sub_abs(r, r, &shifted);
    }
    q->n = qlen;
    q->neg = a_neg ^ b_neg;
    bn_norm(q);
    if (q->n == 1 && q->limbs[0] == 0) q->neg = 0;
}

void bn_copy(Bignum *dst, const Bignum *src) { *dst = *src; }

void bn_pow(Bignum *dst, const Bignum *base, uint32_t exp) {
    Bignum tmp, b;
    bn_set_str(dst, "1");
    b = *base;
    while (exp > 0) {
        if (exp & 1) { bn_mul(&tmp, dst, &b); *dst = tmp; }
        exp >>= 1;
        if (exp > 0) { bn_mul(&tmp, &b, &b); b = tmp; }
    }
}

void bn_fact(Bignum *dst, uint32_t n) {
    bn_set_str(dst, "1");
    for (uint32_t i = 2; i <= n; i++)
        bn_smul(dst, dst, i);
}

/* Print fixed-point value without newline */
void bn_printfp_nonl(int r, int dp) {
    /* Check for zero */
    if (reg[r].n == 1 && reg[r].limbs[0] == 0) { printf("0"); return; }
    static char buf[MAX_LIMBS * 10 + 2];
    bn_sprint(&reg[r], buf);
    int neg = 0, start = 0;
    if (buf[0] == '-') { neg = 1; start = 1; }
    int len = strlen(buf + start);
    if (neg) printf("-");
    if (len <= dp) {
        printf("0.");
        for (int i = 0; i < dp - len; i++) printf("0");
        int end = start + len - 1;
        while (end > start && buf[end] == '0') end--;
        buf[end + 1] = '\0';
        printf("%s", buf + start);
    } else {
        int ipart = len - dp;
        char saved = buf[start + ipart];
        buf[start + ipart] = '\0';
        printf("%s", buf + start);
        buf[start + ipart] = saved;
        int end = start + len - 1;
        while (end >= start + ipart && buf[end] == '0') end--;
        if (end >= start + ipart) {
            buf[end + 1] = '\0';
            printf(".%s", buf + start + ipart);
        }
    }
}

void bn_printfp(int r, int dp) {
    bn_printfp_nonl(r, dp);
    printf("\n");
}

/* Print fixed-point with + prefix for positive (for complex formatting).
   Suppresses output entirely when value is zero; sets bn_last_zero flag. */
int bn_last_zero = 0;

void bn_printfp_plus(int r, int dp) {
    if (reg[r].n == 1 && reg[r].limbs[0] == 0) {
        bn_last_zero = 1;
        return;
    }
    bn_last_zero = 0;
    if (!reg[r].neg) printf("+");
    bn_printfp_nonl(r, dp);
}
