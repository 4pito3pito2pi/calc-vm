CC      = gcc
CFLAGS  = -O2 -Wall
M4      = m4 -L 10000
TIMEOUT = timeout 10

# Core targets
vm: vm.c bignum.c bignum.h
	$(CC) $(CFLAGS) -o vm vm.c bignum.c

vm_test: vm.c bignum.c bignum.h
	$(CC) $(CFLAGS) -DSELF_TEST -o vm_test vm.c bignum.c

# Native codegen from expression: make calc EXPR='2*3+4'
# C target (portable)
gen.c: compiler.m4 codegen.py
	$(TIMEOUT) $(M4) -DTARGET='$(EXPR)' compiler.m4 | python3 codegen.py -t c > gen.c

calc_c: gen.c bignum.c bignum.h
	$(CC) $(CFLAGS) -o calc_c gen.c bignum.c

# amd64 target (native asm)
gen.s: compiler.m4 codegen.py
	$(TIMEOUT) $(M4) -DTARGET='$(EXPR)' compiler.m4 | python3 codegen.py -t amd64 > gen.s

calc_amd64: gen.s bignum.c bignum.h
	$(CC) $(CFLAGS) -o calc_amd64 gen.s bignum.c

# Convenience: build and run all three backends for EXPR
run: vm compiler.m4
	@echo "=== VM interpreter ==="
	@$(TIMEOUT) $(M4) -DTARGET='$(EXPR)' compiler.m4 | $(TIMEOUT) ./vm
	@echo "=== C codegen ==="
	@$(TIMEOUT) $(M4) -DTARGET='$(EXPR)' compiler.m4 | python3 codegen.py -t c > /tmp/calc_gen.c
	@$(CC) $(CFLAGS) -I. -o /tmp/calc_c /tmp/calc_gen.c bignum.c && $(TIMEOUT) /tmp/calc_c
	@echo "=== amd64 codegen ==="
	@$(TIMEOUT) $(M4) -DTARGET='$(EXPR)' compiler.m4 | python3 codegen.py -t amd64 > /tmp/calc_gen.s
	@$(CC) $(CFLAGS) -o /tmp/calc_amd64 /tmp/calc_gen.s bignum.c && $(TIMEOUT) /tmp/calc_amd64

# Full test suite — compare all backends (VM, C codegen, amd64 codegen)
test: vm
	@./test_all.sh

self_test: vm_test
	./vm_test

clean:
	rm -f vm vm_test calc_c calc_amd64 gen.c gen.s /tmp/calc_gen.* /tmp/calc_c /tmp/calc_amd64

.PHONY: run test self_test clean
