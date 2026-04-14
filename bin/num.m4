changequote({,})dnl
; ===== NUMBER THEORY FUNCTIONS =====

; gcd(a,b) - Euclidean algorithm - CORRECT VERSION
define({_emit_gcd},{dnl
  define({__a}, $1)
  define({__b}, $2)
  define({__old_b}, _alloc())    ; Save OLD b before DIV
  define({__remainder}, _alloc()) ; For a % b
  define({__quotient}, _alloc())  ; For a / b (unused but needed)
  define({__zero}, _emit_set("0"))
  define({__L_loop}, _gensym)
  define({__L_done}, _gensym)
  
  _ins({LABEL }__L_loop)
  _ins({CMP r}__b{ r}__zero})
  _ins({BEQ }__L_done})
  
  ; Save OLD b (not quotient!)
  _ins({COPY r}__b{ r}__old_b})
  
  ; DIV rA rB rQ rR
  _ins({DIV r}__a{ r}__b{ r}__quotient{ r}__remainder})
  
  ; a = old_b, b = remainder
  _ins({COPY r}__old_b{ r}__a})
  _ins({COPY r}__remainder{ r}__b})
  
  _ins({JMP }__L_loop)
  _ins({LABEL }__L_done})
  __a  ; Return register with gcd
})dnl

; lcm(a,b) = a*b/gcd(a,b)
define({_emit_lcm},{dnl
  define({__a}, $1)
  define({__b}, $2)
  define({__gcd}, _emit_gcd(__a, __b))
  define({__prod}, _emit_op(MUL, __a, __b))
  _emit_op(DIV, __prod, __gcd)
})dnl
