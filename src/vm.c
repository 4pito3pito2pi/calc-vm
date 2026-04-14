/*
 * vm.c — Bytecode interpreter for m4 calculator
 * Thin wrapper over bignum.c runtime
 * Build: gcc -O2 -o vm vm.c bignum.c
 */
#include "bignum.h"

/* ============ SELF-TEST ============ */
#ifdef SELF_TEST
int main(void) {
    Bignum a, b, c, r;

    bn_set_str(&a, "1000000000000000001");
    bn_set_str(&b, "999999999999999999");
    bn_add(&c, &a, &b);
    printf("add: "); bn_print(&c); printf("\n");
    bn_sub(&c, &a, &b);
    printf("sub: "); bn_print(&c); printf("\n");

    bn_smul(&c, &a, 3);
    printf("smul*3: "); bn_print(&c); printf("\n");

    bn_set_str(&a, "123456789012345678");
    bn_set_str(&b, "987654321098765432");
    bn_mul(&c, &a, &b);
    printf("mul: "); bn_print(&c); printf("\n");
    printf("exp: 121932631137021794322511812221002896\n");

    bn_set_str(&a, "1000000000000000000");
    uint32_t rem = bn_sdiv(&c, &a, 7);
    printf("sdiv: "); bn_print(&c); printf(" rem %u\n", rem);

    bn_set_str(&a, "123456789012345678901234567890");
    bn_set_str(&b, "9876543210");
    bn_div(&c, &r, &a, &b);
    printf("div q: "); bn_print(&c); printf("\n");
    printf("div r: "); bn_print(&r); printf("\n");
    printf("exp q: 12499999887343749990\n");
    printf("exp r: 1562499990\n");

    bn_set_str(&a, "1");
    for (int i = 2; i <= 100; i++) bn_smul(&a, &a, i);
    char buf[1024];
    bn_sprint(&a, buf);
    printf("100! digits: %d\n", (int)strlen(buf));

    return 0;
}
#endif

/* ============ BYTECODE VM ============ */
#ifndef SELF_TEST

static int cmp_flag = 0;

#define MAX_PROG 4096
#define MAX_LABELS 256

static char prog[MAX_PROG][1024];
static int  prog_n = 0;

typedef struct { char name[64]; int pc; } Label;
static Label labels[MAX_LABELS];
static int   nlabels = 0;

static int find_label(const char *name) {
    for (int i = 0; i < nlabels; i++)
        if (!strcmp(labels[i].name, name)) return labels[i].pc;
    fprintf(stderr, "VM: undefined label '%s'\n", name);
    return -1;
}

static void vm_load(void) {
    char line[1024];
    while (fgets(line, sizeof(line), stdin)) {
        char op[32];
        if (sscanf(line, "%31s", op) < 1 || op[0] == '#' || op[0] == ';')
            continue;
        if (!strcmp(op, "LABEL")) {
            char name[64];
            sscanf(line, "%*s %63s", name);
            labels[nlabels].pc = prog_n;
            strncpy(labels[nlabels].name, name, 63);
            labels[nlabels].name[63] = '\0';
            nlabels++;
            continue;
        }
        strncpy(prog[prog_n], line, 1023);
        prog[prog_n][1023] = '\0';
        prog_n++;
    }
}

static void vm_run(void) {
    vm_load();
    int pc = 0;
    while (pc < prog_n) {
        char *line = prog[pc];
        char op[32], arg1[256], arg2[256], arg3[256];
        sscanf(line, "%31s %255s %255s %255s", op, arg1, arg2, arg3);

        if (!strcmp(op, "SET")) {
            bn_set_str(&reg[atoi(arg1 + 1)], arg2);
        }
        else if (!strcmp(op, "ADD")) {
            bn_add(&reg[atoi(arg3+1)], &reg[atoi(arg1+1)], &reg[atoi(arg2+1)]);
        }
        else if (!strcmp(op, "SUB")) {
            bn_sub(&reg[atoi(arg3+1)], &reg[atoi(arg1+1)], &reg[atoi(arg2+1)]);
        }
        else if (!strcmp(op, "MUL")) {
            bn_mul(&reg[atoi(arg3+1)], &reg[atoi(arg1+1)], &reg[atoi(arg2+1)]);
        }
        else if (!strcmp(op, "SMUL")) {
            bn_smul(&reg[atoi(arg3+1)], &reg[atoi(arg1+1)], (uint32_t)atoi(arg2));
        }
        else if (!strcmp(op, "DIV")) {
            char arg4[256];
            sscanf(line, "%*s %*s %*s %255s %255s", arg3, arg4);
            bn_div(&reg[atoi(arg3+1)], &reg[atoi(arg4+1)], &reg[atoi(arg1+1)], &reg[atoi(arg2+1)]);
        }
        else if (!strcmp(op, "SDIV")) {
            bn_sdiv(&reg[atoi(arg3+1)], &reg[atoi(arg1+1)], (uint32_t)atoi(arg2));
        }
        else if (!strcmp(op, "SHL")) {
            bn_shl(&reg[atoi(arg3+1)], &reg[atoi(arg1+1)], atoi(arg2));
        }
        else if (!strcmp(op, "CMP")) {
            cmp_flag = bn_cmp_abs(&reg[atoi(arg1+1)], &reg[atoi(arg2+1)]);
        }
        else if (!strcmp(op, "CMPS")) {
            Bignum *a = &reg[atoi(arg1+1)], *b = &reg[atoi(arg2+1)];
            int az = (a->n == 1 && a->limbs[0] == 0);
            int bz = (b->n == 1 && b->limbs[0] == 0);
            int an = a->neg && !az, bn_ = b->neg && !bz;
            if (an && !bn_) cmp_flag = -1;
            else if (!an && bn_) cmp_flag = 1;
            else if (an && bn_) cmp_flag = -bn_cmp_abs(a, b);
            else cmp_flag = bn_cmp_abs(a, b);
        }
        else if (!strcmp(op, "COPY")) {
            bn_copy(&reg[atoi(arg2+1)], &reg[atoi(arg1+1)]);
        }
        else if (!strcmp(op, "NEG")) {
            bn_copy(&reg[atoi(arg2+1)], &reg[atoi(arg1+1)]);
            reg[atoi(arg2+1)].neg ^= 1;
            if (reg[atoi(arg2+1)].n == 1 && reg[atoi(arg2+1)].limbs[0] == 0)
                reg[atoi(arg2+1)].neg = 0;
        }
        else if (!strcmp(op, "ABS")) {
            bn_copy(&reg[atoi(arg2+1)], &reg[atoi(arg1+1)]);
            reg[atoi(arg2+1)].neg = 0;
        }
        else if (!strcmp(op, "ISNEG")) {
            int d = atoi(arg2+1);
            reg[d].n = 1;
            reg[d].limbs[0] = (reg[atoi(arg1+1)].neg &&
                !(reg[atoi(arg1+1)].n == 1 && reg[atoi(arg1+1)].limbs[0] == 0)) ? 1 : 0;
            reg[d].neg = 0;
        }
        else if (!strcmp(op, "POW")) {
            uint32_t exp = reg[atoi(arg2+1)].n == 1 ? reg[atoi(arg2+1)].limbs[0] : 0;
            bn_pow(&reg[atoi(arg3+1)], &reg[atoi(arg1+1)], exp);
        }
        else if (!strcmp(op, "FACT")) {
            uint32_t n = reg[atoi(arg1+1)].n == 1 ? reg[atoi(arg1+1)].limbs[0] : 0;
            bn_fact(&reg[atoi(arg2+1)], n);
        }
        /* ---- branch instructions ---- */
        else if (!strcmp(op, "JMP")) {
            pc = find_label(arg1); continue;
        }
        else if (!strcmp(op, "BGT")) {
            if (cmp_flag > 0) { pc = find_label(arg1); continue; }
        }
        else if (!strcmp(op, "BLT")) {
            if (cmp_flag < 0) { pc = find_label(arg1); continue; }
        }
        else if (!strcmp(op, "BGE")) {
            if (cmp_flag >= 0) { pc = find_label(arg1); continue; }
        }
        else if (!strcmp(op, "BLE")) {
            if (cmp_flag <= 0) { pc = find_label(arg1); continue; }
        }
        else if (!strcmp(op, "BEQ")) {
            if (cmp_flag == 0) { pc = find_label(arg1); continue; }
        }
        else if (!strcmp(op, "BNE")) {
            if (cmp_flag != 0) { pc = find_label(arg1); continue; }
        }
        else if (!strcmp(op, "PRINT")) {
            bn_print(&reg[atoi(arg1+1)]);
            printf("\n");
        }
        else if (!strcmp(op, "PRINTFP")) {
            bn_printfp(atoi(arg1+1), atoi(arg2));
        }
        else if (!strcmp(op, "PRINTFPC")) {
            /* Print fp value, no newline (for complex components) */
            bn_printfp_nonl(atoi(arg1+1), atoi(arg2));
        }
        else if (!strcmp(op, "PRINTFPP")) {
            /* Print fp value with + prefix for positive, no newline */
            bn_printfp_plus(atoi(arg1+1), atoi(arg2));
        }
        else if (!strcmp(op, "PRINTS")) {
            /* Print literal string; suppress after zero PRINTFPP */
            if (!bn_last_zero)
                printf("%s", arg1);
            bn_last_zero = 0;
        }
        else if (!strcmp(op, "HALT")) {
            return;
        }
        else {
            fprintf(stderr, "VM: unknown op '%s'\n", op);
        }
        pc++;
    }
}

int main(void) {
    vm_run();
    return 0;
}
#endif
