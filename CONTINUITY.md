# CALC VM PROJECT — Continuity State

## Rules

- **ALWAYS use `timeout 5` (or similar) on every m4 and VM invocation.** m4 can hang
  on bad input. LLM has no sense of time. No exceptions.
- Build incrementally. Max 2-3 tool calls per response. Save after every small piece.

## Critical Rules

- **ALWAYS use `timeout 5` (or similar) on m4 and ./vm commands.** m4 hangs on parse errors with no output. Without timeout, the response never completes. No exceptions.
- Max 2-3 tool calls per response. Break all code work into incremental steps.
- Save to disk after every small piece. Confirm plan before executing.

## Critical Rules

- **ALWAYS use `timeout` for m4 and VM commands.** `timeout 5` minimum. m4 can infinite-loop on bad input. LLM has no sense of time. No exceptions.
- **Atomic steps.** Max 2-3 tool calls per response. Save to disk after every small piece. Confirm plan before executing.
- **Never build large files in one turn.** Break all code work into incremental steps.

## Architecture

```
User expression → m4 compiler → bytecode → C VM (register machine)
                  (compiler.m4)  (text)     (vm.c, ~507 lines)
```

m4 = compiler (expression parsing, macro expansion, bytecode generation)
  - Recursive-descent parser + register allocator
  - m4-side Taylor/Newton unrolling for all transcendentals
  - Range reduction via CMP+branch loops
C VM = executor (pure bignum ALU — no transcendental knowledge)
  - Base 10^9 limbs, 64 registers, stored-program with labels+branches
  - ~25KB binary, fits in L1 cache

## Files

- **vm.c** (~507 lines) — Pure bignum ALU register VM
  - Build: `gcc -O2 -o vm vm.c` (VM mode)
  - Build: `gcc -O2 -DSELF_TEST -o vm_test vm.c` (test mode)
  - Base 10^9 limbs, uint32_t limbs, uint64_t intermediate
  - 128 registers (Bignum structs), signed arithmetic
  - Stored-program execution with instruction pointer
  - Labels + branch instructions (JMP, BGT, BLE, BLT, BGE, BEQ, BNE)
  - ABS, ISNEG instructions for sign handling
  - No transcendental knowledge — all math emitted by m4 compiler
  - Skips `#` and `;` comment lines

- **compiler.m4** (~925 lines) — Full recursive-descent parser → register bytecode
  - Precedence: expr(+,-) > term(*,/,%) > power(^) > unary(-) > postfix(!) > atom
  - Fixed-point tracking: compiler marks fp registers, scales int<->fp automatically
  - FP_DIGITS=18, FP_SCALE=10^18
  - Constants: pi (18 digits), e (18 digits)
  - Functions: sin, cos, tan, exp, ln, sqrt, atan, asin, acos, log10, log2, sinh, cosh, tanh, atanh, gamma, erf, phi, beta(a,b), Ei, Li, W, zeta, eta
  - Two-arg functions: beta(a,b) — comma transliterated to `@` to avoid m4 arg splitting
  - Uppercase function names: Ei, Li, W (scanner now handles A-Z)
  - All transcendentals implemented m4-side via Taylor/Newton unrolling
  - Parens via translit `()` → `<>`, commas via `,` → `@` (avoids m4 quoting conflict)
  - Invoke: `m4 -L 10000 -DTARGET='sin(0.5)' compiler.m4 | ./vm`

- **compile_test.m4** (17 lines) — Proof of concept m4 compiler
  - Demonstrates: register allocator, instruction accumulator, bytecode emission
  - `m4 compile_test.m4 | ./vm` prints 10 (= 2*3+4)

- **shell_cpu.sh** (391 lines) — Shell reference implementation
  - Same operations, used as test oracle
  - `bash shell_cpu.sh --test` runs all tests

- **calc5.sh** (518 lines) — Original pure m4 calculator (pre-VM)
  - Has the recursive-descent parser that was ported to compiler.m4
  - Supports: + - * / % ** ! sqrt sin cos exp ln, hex (0x), binary (0b), phi

## VM Instruction Set (22 instructions)

```
SET    rN value       — load decimal string into register
ADD    rA rB rD       — rD = rA + rB
SUB    rA rB rD       — rD = rA - rB
MUL    rA rB rD       — rD = rA * rB
SMUL   rA imm rD      — rD = rA * immediate (imm < 10^9)
DIV    rA rB rQ rR    — rQ = rA / rB, rR = rA % rB
SDIV   rA imm rD      — rD = rA / imm (remainder discarded)
SHL    rA imm rD      — rD = rA * BASE^imm
CMP    rA rB          — sets cmp_flag (-1/0/1) by |rA| vs |rB|
COPY   rA rD          — rD = rA
NEG    rA rD          — rD = -rA
ABS    rA rD          — rD = |rA|
ISNEG  rA rD          — rD = 1 if rA < 0, else 0
POW    rA rB rD       — rD = rA ^ rB (rB must fit uint32)
FACT   rA rD          — rD = rA!
LABEL  name           — branch target (not stored as instruction)
JMP    label          — unconditional jump
BGT    label          — branch if cmp_flag > 0
BLT    label          — branch if cmp_flag < 0
BGE    label          — branch if cmp_flag >= 0
BLE    label          — branch if cmp_flag <= 0
BEQ    label          — branch if cmp_flag == 0
BNE    label          — branch if cmp_flag != 0
PRINT  rN             — output register as decimal
PRINTFP rN digits     — output register as fixed-point with N decimal places
HALT                  — stop execution
```

## m4 Compiler Infrastructure (proven working)

```m4
_alloc          — returns next free register number, increments counter
_ins({text})    — appends instruction to _CODE buffer
_emit_set(val)  — emits SET (or SET+fp mark for decimals), returns register number
_emit_op(OP,rA,rB) — emits OP with fp-aware scaling, returns rD
_emit_div(rA,rB)   — scales numerator by 10^18, emits DIV, marks result fp
_emit_fn(name,rA)  — dispatches to m4-side implementations (exp/sin/cos/ln/sqrt)
_emit_exp(rA)      — range reduction (CMP+branch loop) + 20-term Taylor
_emit_sin(rA)      — mod-2π reduction + 10-term Taylor unrolling
_emit_cos(rA)      — sin(x + π/2)
_emit_ln(rA)       — divide-by-e reduction + 15-term atanh series
_emit_sqrt(rA)     — 60-iteration Newton loop (y = (y + x/y) / 2)
_emit_tan(rA)      — sin(x) / cos(x)
_emit_atan(rA)     — half-angle reduction + 20-term Taylor
_emit_asin(rA)     — atan(x / sqrt(1 - x²)), special-case |x|≥1
_emit_acos(rA)     — π/2 - asin(x)
_emit_log10(rA)    — ln(x) / ln(10)
_emit_log2(rA)     — ln(x) / ln(2)
_emit_sinh(rA)     — (exp(x) - exp(-x)) / 2
_emit_cosh(rA)     — (exp(x) + exp(-x)) / 2
_emit_tanh(rA)     — (e^2x - S) / (e^2x + S), single exp call
_emit_atanh(rA)    — ln((S+x)/(S-x)) / 2
_emit_gamma(rA)    — Stirling with shift-up + 4-term correction
_emit_erf(rA)      — 40-term Taylor + clamp for |x|>3.5
_emit_phi(rA)      — 0.5*(1 + erf(x/√2))
_emit_beta(rA,rB)  — Γ(a)·Γ(b)/Γ(a+b)
_emit_ei(rA)       — γ + ln|x| + 40-term power series
_emit_li(rA)       — Ei(ln(x))
_emit_lambertw(rA) — 20-iter Newton loop
_emit_zeta(rA)     — direct sum N=200 + Euler-Maclaurin
_emit_eta(rA)      — (1-2^{1-s})·ζ(s)
_gensym            — unique label generator (L1, L2, ...)
_CODE           — expands to all accumulated instructions
```

## Verified Results

### Integer (exact)
- 2*3+4 = 10 ✓
- 2^64 = 18446744073709551616 ✓
- 100! = 158 digits ✓
- add: 10^18+1 + (10^18-1) = 2×10^18 ✓
- mul: 123456789012345678 × 987654321098765432 ✓
- div: 123456789012345678901234567890 / 9876543210 ✓

### Transcendental (15-digit agreement with float64)
- exp(1)  = 2.718281828459045... ✓
- sin(0.5)= 0.479425538604203   ✓
- sin(1)  = 0.841470984807896... ✓
- cos(1)  = 0.540302305868139... ✓
- ln(2)   = 0.693147180559945... ✓
- sqrt(2) = 1.414213562373095... ✓

### Inverse trig + log (15-digit agreement)
- atan(1)   = 0.785398163397448... ✓ (π/4)
- atan(0.5) = 0.463647609000806... ✓
- atan(2)   = 1.107148717794090... ✓
- asin(0.5) = 0.523598775598298... ✓ (π/6)
- asin(1)   = 1.570796326794896... ✓ (π/2, special case)
- acos(0.5) = 1.047197551196597... ✓ (π/3)
- log10(10) = 0.999999999999999... ✓
- log10(0.1)= -0.999999999999999.. ✓
- log2(8)   = 2.999999999999999... ✓
- log2(0.5) = -0.999999999999999.. ✓

## What's Next

0. ~~**TEST hex/binary in compiler**~~ — DONE.

1. ~~**m4-side Taylor unrolling**~~ — DONE. All transcendentals moved from C to m4:
   - exp: range reduce (halve loop via CMP+BLE) + 20-term Taylor + square-back loop
   - sin: mod-2π + reflect-to-[0,π/2] + 10-term alternating Taylor (x²-based)
   - cos: sin(x + π/2)
   - ln: divide-by-e / multiply-by-e loops + atanh series (15 terms)
   - sqrt: 60-iteration Newton loop via CMP+BLE
   - tan: sin(x)/cos(x) (was already m4-side)
   VM is now pure bignum ALU — no transcendental knowledge. ~200 lines of C removed.
   Added: LABEL, JMP, BGT/BLE/BLT/BGE/BEQ/BNE, ABS, ISNEG, stored-program execution.
   SDIV no longer clobbers r15.
   All 37 test cases pass, verified by DeepSeek.

2. ~~TAN instruction~~ — DONE. Compiler emits SIN/COS/DIV sequence.

3. ~~**Hex/binary in compiler**~~ — DONE (see item 0).

4. ~~**AMD64 native codegen**~~ — DONE

### Architecture

```
m4 compiler → bytecode → codegen.py --target={c,amd64} → source → gcc → native binary
                              ↓
                         bignum.c (runtime library, linked in)
```

- `bignum.c` — extracted from vm.c, exposes bn_* functions + register file
- `codegen.py` — reads bytecode from stdin, emits C or x86-64 asm
- C target: bytecode → `bn_add(&reg[2], &reg[0], &reg[1]);` — portable, zero-overhead dispatch
- amd64 target: bytecode → native asm with `call bn_add` via System V ABI
- Labels → native labels, branches → native jmp/jcc
- Same bignum runtime links with all targets

### Build pipeline

```bash
# Interpret (current)
m4 -L 10000 -DTARGET='expr' compiler.m4 | ./vm

# Native C
m4 -L 10000 -DTARGET='expr' compiler.m4 | python3 codegen.py -t c > gen.c
gcc -O2 -o calc gen.c bignum.c && ./calc

# Native amd64
m4 -L 10000 -DTARGET='expr' compiler.m4 | python3 codegen.py -t amd64 > gen.s
gcc -O2 -o calc gen.s bignum.c && ./calc
```

### Files (new)
- `bignum.c` — bignum runtime (bn_add, bn_mul, etc.) + register file + print
- `bignum.h` — public API
- `codegen.py` — bytecode → {C, amd64 asm} translator
- `vm.c` — now thin: just bytecode interpreter #including bignum

### Agent manual
- DeepSeek agents generate repetitive codegen patterns (one per opcode)
- Each agent MUST self-verify: emit test code, describe expected output
- Claude reviews architecture, integration, correctness
- All m4/vm commands MUST use `timeout 5` or `timeout 10`

### amd64 target — verified results
All outputs match VM interpreter exactly:
- `2*3+4` → 10 ✓
- `100*200+300` → 20300 ✓
- `exp(1)` → 2.718281828459045209 ✓ (exercises labels, branches, loops)
- `sin(1)` → 0.841470984807896507 ✓
- `sqrt(2)` → 1.414213562373095048 ✓

### Implementation notes
- `emit_amd64()` in codegen.py: ~240 lines, handles all 22 opcodes
- System V AMD64 ABI: r12 = reg array base (callee-saved), args in rdi/rsi/rdx/rcx
- Each Bignum = 1032 bytes (256×4 limbs + n + neg), reg[N] at offset N*1032
- NEG/ABS/ISNEG inline field manipulation (no extra C helpers needed)
- POW/FACT extract limbs[0] from exponent register inline
- `.note.GNU-stack` section suppresses executable-stack warning
- DeepSeek agent generated initial draft; Claude fixed: string→int offset arithmetic,
  reg_idx extraction, removed nonexistent bn_set_int, unique labels for ISNEG

5. ~~**ARM64 codegen**~~ — DEFERRED. C VM fast enough, asm codegen adds no measurable speedup
   (benchmarks show identical times — all time is in bignum multiply, not dispatch).

6. ~~**New math functions**~~ — DONE
   - atan: half-angle reduction atan(x)=2*atan(x/(1+sqrt(1+x²))) + 20-term Taylor
   - asin: atan(x/sqrt(1-x²)), special-case |x|≥1 → ±π/2
   - acos: π/2 - asin(x)
   - log10: ln(x) / ln(10) (constant 2302585092994045684)
   - log2: ln(x) / ln(2) (constant 693147180559945309)
   - All pass cross-backend suite (VM + C codegen + amd64 codegen)

7. ~~**Hyperbolic functions**~~ — DONE
   - sinh: (exp(x) - exp(-x)) / 2 — two exp calls
   - cosh: (exp(x) + exp(-x)) / 2 — two exp calls
   - tanh: (e^2x - S) / (e^2x + S) — single exp call, no division by exp
   - atanh: ln((S+x)/(S-x)) / 2
   - 216-test cross-backend suite, all pass

8. ~~**Gamma function**~~ — DONE
   - Stirling approximation: lnΓ(z) = (z-0.5)ln(z) - z + 0.5ln(2π) + correction
   - Shift-up loop: while z < 20, accumulate product z*(z+1)*..., increment z
   - 4-term Horner correction in 1/z² for 14+ digit precision
   - Result = exp(lnΓ) / product
   - Uses ~46 registers for positive args; ~111 with reflection (both paths emitted)
   - 237-test cross-backend suite, all pass

### Bug fixes in this round
- **bn_div aliasing bug**: when remainder output register aliased the dividend,
  `*r = *a; r->neg = 0` zeroed the dividend's sign before the quotient sign was computed.
  Fix: save `a->neg` and `b->neg` at function entry, use saved values for `q->neg`.
  Also fixed single-limb fast path which didn't set quotient sign from divisor.
- **MAX_LIMBS 256 → 20000**: old limit caused silent memory corruption for large factorials
  (36500! appeared to work, 37000! segfaulted). Now supports ~180k digit numbers.
  `bn_mul` tmp array moved to static to avoid 320KB stack allocation.

9. ~~**Known bugs fixed**~~
   - `0xFF` uppercase hex: `_ishex`/`_hexval` used `translit` to lowercase before lookup.
     Now handles `0xFF`, `0xDEAD`, `0xAbCd` (mixed case).
   - `1.0+2.0` → 4: `_emit_set_fp` had `{ __scaled}` in `_ins()` call — braces
     prevented m4 expansion at call time, so `__scaled` resolved to last definition
     when `_CODE` dumped. Fix: `{ }__scaled` (expand immediately, quote only the space).
   - 249-test cross-backend suite, all pass.

10. ~~**Negative-argument gamma**~~ — DONE
   - Reflection formula: Γ(z) = π / (sin(πz) · Γ(1-z)) when z < 0
   - Wrapped existing Stirling in `_emit_gamma_pos`, new `_emit_gamma` dispatches via CMP+BGE
   - Both code paths emitted at compile time (m4 limitation), ~111 registers needed
   - NREG increased 64 → 128 to accommodate (bignum.h)
   - 13+ digit agreement with Wolfram Alpha for gamma(-0.5), gamma(-1.5), gamma(-2.5), gamma(-3.5)
   - Negative integer poles (gamma(-1), gamma(-2)) → division by zero (sin(πn)=0)

11. ~~**Special functions batch**~~ — DONE
   - erf(x): 40-term Taylor, clamp to ±1 for |x|>3.5. 15-16 digits for |x|≤2.
   - phi(x): normal CDF = 0.5*(1 + erf(x/√2)). Trivial wrapper.
   - beta(a,b): Γ(a)·Γ(b)/Γ(a+b). Three gamma calls, ~340 registers. NREG → 512.
   - Ei(x): exponential integral. γ + ln|x| + 40-term power series. 15+ digits.
   - Li(x): logarithmic integral = Ei(ln(x)). Composition of Ei and ln.
   - W(x): Lambert W principal branch. 20-iter Newton: w = w - (w·eʷ-x)/(eʷ(w+1)). 15+ digits.
   - zeta(s): Riemann zeta for s > 1. Direct sum N=200 + Euler-Maclaurin. 4-10 digits (inherent series limitation).
   - eta(s): Dirichlet eta = (1-2^{1-s})·ζ(s). Accuracy matches zeta.

### Infrastructure changes in this round
- **Comma handling**: translit now maps `,` → `@` so multi-arg functions (beta) work
- **Uppercase identifiers**: `_isalpha` extended to A-Z for Ei, Li, W
- **CALC wrapper**: `CALC({$*})` → `_CALC_INNER` to reconstruct comma-split args
- **NREG 128 → 512**: beta with 3 gamma calls needs ~340 registers
- **_ch quoting**: remains `substr(_INPUT,_POS,1)` — comma replaced before setinput

### Future work
- Higher precision modes (configurable FP_DIGITS)
- Better zeta convergence (Borwein/Cohen-Villegas-Zagier acceleration)
