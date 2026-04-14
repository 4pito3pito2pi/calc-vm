changequote({,})changecom({;})dnl
; ---- register allocator & instruction buffer ----
define({_N},0)dnl
define({_CODE},{})dnl
define({_alloc},{define({_N},eval(_N+1))eval(_N-1)})dnl
define({_ins},{define({_CODE},_CODE{$1
})})dnl
define({_emit_set},{ifelse(index({$1},{.}),-1,{define({__sr},_alloc)_ins({SET r}__sr{ $1})__sr},{_emit_set_fp({$1})})})dnl
; _emit_set_fp: parse decimal, scale to 10^15, mark fp
define({_emit_set_fp},{define({__dot},index({$1},{.}))define({__ipart},substr({$1},0,__dot))define({__fpart},substr({$1},eval(__dot+1)))define({__flen},len(__fpart))define({__pad},eval(_FP_DIGITS-__flen))define({__scaled},__ipart{}__fpart{}substr({000000000000000000},0,__pad))define({__sr},_alloc)_ins({SET r}__sr{ }__scaled)define({_fp_}__sr,_FP_DIGITS)__sr})dnl
; _emit_op: binary op with fp tracking
; if either operand is fp, result is fp
; ADD/SUB fp+fp: just add (same scale)
; ADD/SUB fp+int: scale int up first
; MUL fp*int or int*fp: result is fp
; MUL fp*fp: result has scale^2, divide by scale
define({_isfp},{ifdef({_fp_$1},1,0)})dnl
define({_emit_op},{ifelse(eval(_isfp($2)+_isfp($3)),0,{define({__r},_alloc)_ins({$1 r$2 r$3 r}__r)__r},{_emit_op_fp({$1},{$2},{$3})})})dnl
define({_emit_op_fp},{ifelse({$1},{MUL},{_emit_mul_fp({$2},{$3})},{_emit_addsub_fp({$1},{$2},{$3})})})dnl
; ADD/SUB fp: scale up non-fp operand
define({_emit_addsub_fp},{define({__aa},ifelse(_isfp($2),1,{$2},{_scale_up($2)}))define({__ab},ifelse(_isfp($3),1,{$3},{_scale_up($3)}))define({__ar},_alloc)_ins({$1 r}__aa{ r}__ab{ r}__ar)define({_fp_}__ar,_FP_DIGITS)__ar})dnl
; MUL fp*fp: result/scale; fp*int or int*fp: result is fp
define({_emit_mul_fp},{define({__mr},_alloc)_ins({MUL r$1 r$2 r}__mr)ifelse(eval(_isfp($1)*_isfp($2)),1,{define({__ms},_emit_set(_FP_SCALE))define({__mq},_alloc)define({__mrem},_alloc)_ins({DIV r}__mr{ r}__ms{ r}__mq{ r}__mrem)define({_fp_}__mq,_FP_DIGITS)__mq},{define({_fp_}__mr,_FP_DIGITS)__mr})})dnl
; scale up an integer register by multiplying by 10^15
define({_scale_up},{define({__su},_emit_set(_FP_SCALE))define({__sp},_alloc)_ins({MUL r$1 r}__su{ r}__sp)define({_fp_}__sp,_FP_DIGITS)__sp})dnl
define({_emit_op1},{define({__r},_alloc)_ins({$1 r$2 r}__r)ifelse(_isfp($2),1,{define({_fp_}__r,_FP_DIGITS)})__r})dnl
; ---- complex/quaternion type system ----
; Values: scalar=N, complex=N:M (real:imag), quaternion=N:M:P:Q (r:i:j:k)
; All components are fp registers.
define({_iscomplex},{ifelse(index({$1},{:}),-1,0,ifelse(index(substr({$1},eval(index({$1},{:})+1)),{:}),-1,1,0))})dnl
define({_isquat},{ifelse(index({$1},{:}),-1,0,{ifelse(_iscomplex({$1}),1,0,1)})})dnl
define({_isscalar},{ifelse(index({$1},{:}),-1,1,0)})dnl
; complex accessors (split on first colon)
define({_cR},{substr({$1},0,index({$1},{:}))})dnl
define({_cI},{substr({$1},eval(index({$1},{:})+1))})dnl
; quaternion accessors
define({_qR},{_cR({$1})})dnl
define({_q_rest},{substr({$1},eval(index({$1},{:})+1))})dnl
define({_qI},{_cR(_q_rest({$1}))})dnl
define({_qJ},{_cR(_q_rest(_q_rest({$1})))})dnl
define({_qK},{_cI(_q_rest(_q_rest({$1})))})dnl
; constructors
define({_mk_complex},{$1:$2})dnl
define({_mk_quat},{$1:$2:$3:$4})dnl
; allocate complex pair (2 fp regs) — returns r:i
define({_alloc_complex},{define({__cr},_alloc)define({__ci},_alloc)_ins({SET r}__cr{ 0})_ins({SET r}__ci{ 0})define({_fp_}__cr,_FP_DIGITS)define({_fp_}__ci,_FP_DIGITS)__cr:__ci})dnl
; allocate quaternion quad (4 fp regs) — returns r:i:j:k
define({_alloc_quat},{define({__qr},_alloc)define({__qi},_alloc)define({__qj},_alloc)define({__qk},_alloc)_ins({SET r}__qr{ 0})_ins({SET r}__qi{ 0})_ins({SET r}__qj{ 0})_ins({SET r}__qk{ 0})define({_fp_}__qr,_FP_DIGITS)define({_fp_}__qi,_FP_DIGITS)define({_fp_}__qj,_FP_DIGITS)define({_fp_}__qk,_FP_DIGITS)__qr:__qi:__qj:__qk})dnl
; ---- complex arithmetic ----
; cadd(a,b): component-wise add
define({_emit_cadd},{define({__ca_rr},_alloc)define({__ca_ri},_alloc)_ins({ADD r}_cR({$1}){ r}_cR({$2}){ r}__ca_rr)_ins({ADD r}_cI({$1}){ r}_cI({$2}){ r}__ca_ri)define({_fp_}__ca_rr,_FP_DIGITS)define({_fp_}__ca_ri,_FP_DIGITS)__ca_rr:__ca_ri})dnl
; csub(a,b): component-wise sub
define({_emit_csub},{define({__cs_rr},_alloc)define({__cs_ri},_alloc)_ins({SUB r}_cR({$1}){ r}_cR({$2}){ r}__cs_rr)_ins({SUB r}_cI({$1}){ r}_cI({$2}){ r}__cs_ri)define({_fp_}__cs_rr,_FP_DIGITS)define({_fp_}__cs_ri,_FP_DIGITS)__cs_rr:__cs_ri})dnl
; cmul(a,b): (ar*br - ai*bi) + (ar*bi + ai*br)i
define({_emit_cmul},{dnl
define({__cm_t1},_alloc)define({__cm_t2},_alloc)define({__cm_t3},_alloc)define({__cm_t4},_alloc)dnl
define({__cm_rr},_alloc)define({__cm_ri},_alloc)dnl
define({__cm_S},_emit_set(_FP_SCALE))dnl
define({__cm_q},_alloc)define({__cm_rem},_alloc)dnl
_ins({MUL r}_cR({$1}){ r}_cR({$2}){ r}__cm_t1)dnl  ar*br
_ins({DIV r}__cm_t1{ r}__cm_S{ r}__cm_t1{ r}__cm_rem)dnl  /S
_ins({MUL r}_cI({$1}){ r}_cI({$2}){ r}__cm_t2)dnl  ai*bi
_ins({DIV r}__cm_t2{ r}__cm_S{ r}__cm_t2{ r}__cm_rem)dnl  /S
_ins({SUB r}__cm_t1{ r}__cm_t2{ r}__cm_rr)dnl  real = ar*br/S - ai*bi/S
_ins({MUL r}_cR({$1}){ r}_cI({$2}){ r}__cm_t3)dnl  ar*bi
_ins({DIV r}__cm_t3{ r}__cm_S{ r}__cm_t3{ r}__cm_rem)dnl  /S
_ins({MUL r}_cI({$1}){ r}_cR({$2}){ r}__cm_t4)dnl  ai*br
_ins({DIV r}__cm_t4{ r}__cm_S{ r}__cm_t4{ r}__cm_rem)dnl  /S
_ins({ADD r}__cm_t3{ r}__cm_t4{ r}__cm_ri)dnl  imag = ar*bi/S + ai*br/S
define({_fp_}__cm_rr,_FP_DIGITS)define({_fp_}__cm_ri,_FP_DIGITS)__cm_rr:__cm_ri})dnl
; cdiv(a,b): (ar*br+ai*bi)/(br²+bi²) + (ai*br-ar*bi)/(br²+bi²) i
define({_emit_cdiv},{dnl
define({__cd_t1},_alloc)define({__cd_t2},_alloc)define({__cd_t3},_alloc)define({__cd_t4},_alloc)dnl
define({__cd_d},_alloc)define({__cd_rr},_alloc)define({__cd_ri},_alloc)dnl
define({__cd_S},_emit_set(_FP_SCALE))define({__cd_rem},_alloc)dnl
_ins({MUL r}_cR({$2}){ r}_cR({$2}){ r}__cd_t1)dnl  br²
_ins({DIV r}__cd_t1{ r}__cd_S{ r}__cd_t1{ r}__cd_rem)dnl
_ins({MUL r}_cI({$2}){ r}_cI({$2}){ r}__cd_t2)dnl  bi²
_ins({DIV r}__cd_t2{ r}__cd_S{ r}__cd_t2{ r}__cd_rem)dnl
_ins({ADD r}__cd_t1{ r}__cd_t2{ r}__cd_d)dnl  denom = br²+bi²
_ins({MUL r}_cR({$1}){ r}_cR({$2}){ r}__cd_t1)dnl  ar*br
_ins({DIV r}__cd_t1{ r}__cd_S{ r}__cd_t1{ r}__cd_rem)dnl
_ins({MUL r}_cI({$1}){ r}_cI({$2}){ r}__cd_t2)dnl  ai*bi
_ins({DIV r}__cd_t2{ r}__cd_S{ r}__cd_t2{ r}__cd_rem)dnl
_ins({ADD r}__cd_t1{ r}__cd_t2{ r}__cd_t3)dnl  num_real = ar*br+ai*bi
_ins({MUL r}__cd_t3{ r}__cd_S{ r}__cd_t3)dnl  scale up for div
_ins({DIV r}__cd_t3{ r}__cd_d{ r}__cd_rr{ r}__cd_rem)dnl  /denom
_ins({MUL r}_cI({$1}){ r}_cR({$2}){ r}__cd_t1)dnl  ai*br
_ins({DIV r}__cd_t1{ r}__cd_S{ r}__cd_t1{ r}__cd_rem)dnl
_ins({MUL r}_cR({$1}){ r}_cI({$2}){ r}__cd_t2)dnl  ar*bi
_ins({DIV r}__cd_t2{ r}__cd_S{ r}__cd_t2{ r}__cd_rem)dnl
_ins({SUB r}__cd_t1{ r}__cd_t2{ r}__cd_t3)dnl  num_imag = ai*br-ar*bi
_ins({MUL r}__cd_t3{ r}__cd_S{ r}__cd_t3)dnl  scale up
_ins({DIV r}__cd_t3{ r}__cd_d{ r}__cd_ri{ r}__cd_rem)dnl  /denom
define({_fp_}__cd_rr,_FP_DIGITS)define({_fp_}__cd_ri,_FP_DIGITS)__cd_rr:__cd_ri})dnl
; cneg(a): negate both components
define({_emit_cneg},{define({__cn_rr},_alloc)define({__cn_ri},_alloc)_ins({NEG r}_cR({$1}){ r}__cn_rr)_ins({NEG r}_cI({$1}){ r}__cn_ri)define({_fp_}__cn_rr,_FP_DIGITS)define({_fp_}__cn_ri,_FP_DIGITS)__cn_rr:__cn_ri})dnl
; promote scalar to complex (set imag=0)
define({_promote_complex},{ifelse(_iscomplex({$1}),1,{$1},_isquat({$1}),1,{$1},{define({__pc_r},ifelse(_isfp($1),1,{$1},{_scale_up($1)}))define({__pc_i},_alloc)_ins({SET r}__pc_i{ 0})define({_fp_}__pc_i,_FP_DIGITS)__pc_r:__pc_i})})dnl
; promote scalar/complex to quaternion
define({_promote_quat},{ifelse(_isquat({$1}),1,{$1},_iscomplex({$1}),1,{define({__pq_j},_alloc)define({__pq_k},_alloc)_ins({SET r}__pq_j{ 0})_ins({SET r}__pq_k{ 0})define({_fp_}__pq_j,_FP_DIGITS)define({_fp_}__pq_k,_FP_DIGITS)_cR({$1}):_cI({$1}):__pq_j:__pq_k},{define({__pq_r},ifelse(_isfp($1),1,{$1},{_scale_up($1)}))define({__pq_i},_alloc)define({__pq_j},_alloc)define({__pq_k},_alloc)_ins({SET r}__pq_i{ 0})_ins({SET r}__pq_j{ 0})_ins({SET r}__pq_k{ 0})define({_fp_}__pq_i,_FP_DIGITS)define({_fp_}__pq_j,_FP_DIGITS)define({_fp_}__pq_k,_FP_DIGITS)__pq_r:__pq_i:__pq_j:__pq_k})})dnl
; ---- quaternion arithmetic ----
; qadd: component-wise
define({_emit_qadd},{define({__qa},_promote_quat({$1}))define({__qb},_promote_quat({$2}))dnl
define({__qa_r},_alloc)define({__qa_i},_alloc)define({__qa_j},_alloc)define({__qa_k},_alloc)dnl
_ins({ADD r}_qR(__qa){ r}_qR(__qb){ r}__qa_r)_ins({ADD r}_qI(__qa){ r}_qI(__qb){ r}__qa_i)_ins({ADD r}_qJ(__qa){ r}_qJ(__qb){ r}__qa_j)_ins({ADD r}_qK(__qa){ r}_qK(__qb){ r}__qa_k)dnl
define({_fp_}__qa_r,_FP_DIGITS)define({_fp_}__qa_i,_FP_DIGITS)define({_fp_}__qa_j,_FP_DIGITS)define({_fp_}__qa_k,_FP_DIGITS)__qa_r:__qa_i:__qa_j:__qa_k})dnl
; qsub: component-wise
define({_emit_qsub},{define({__qa},_promote_quat({$1}))define({__qb},_promote_quat({$2}))dnl
define({__qs_r},_alloc)define({__qs_i},_alloc)define({__qs_j},_alloc)define({__qs_k},_alloc)dnl
_ins({SUB r}_qR(__qa){ r}_qR(__qb){ r}__qs_r)_ins({SUB r}_qI(__qa){ r}_qI(__qb){ r}__qs_i)_ins({SUB r}_qJ(__qa){ r}_qJ(__qb){ r}__qs_j)_ins({SUB r}_qK(__qa){ r}_qK(__qb){ r}__qs_k)dnl
define({_fp_}__qs_r,_FP_DIGITS)define({_fp_}__qs_i,_FP_DIGITS)define({_fp_}__qs_j,_FP_DIGITS)define({_fp_}__qs_k,_FP_DIGITS)__qs_r:__qs_i:__qs_j:__qs_k})dnl
; qhmul: Hamilton product (16 multiplies, 12 add/subs)
; q1*q2 = (a1a2-b1b2-c1c2-d1d2) + (a1b2+b1a2+c1d2-d1c2)i
;        + (a1c2-b1d2+c1a2+d1b2)j + (a1d2+b1c2-c1b2+d1a2)k
define({_emit_qhmul},{define({__qa},_promote_quat({$1}))define({__qb},_promote_quat({$2}))dnl
define({__qm_S},_emit_set(_FP_SCALE))define({__qm_rem},_alloc)dnl
define({__qm_t},_alloc)define({__qm_u},_alloc)define({__qm_v},_alloc)define({__qm_w},_alloc)dnl
define({__qm_rr},_alloc)define({__qm_ri},_alloc)define({__qm_rj},_alloc)define({__qm_rk},_alloc)dnl
_ins({MUL r}_qR(__qa){ r}_qR(__qb){ r}__qm_t)_ins({DIV r}__qm_t{ r}__qm_S{ r}__qm_t{ r}__qm_rem)dnl
_ins({MUL r}_qI(__qa){ r}_qI(__qb){ r}__qm_u)_ins({DIV r}__qm_u{ r}__qm_S{ r}__qm_u{ r}__qm_rem)dnl
_ins({SUB r}__qm_t{ r}__qm_u{ r}__qm_v)dnl
_ins({MUL r}_qJ(__qa){ r}_qJ(__qb){ r}__qm_t)_ins({DIV r}__qm_t{ r}__qm_S{ r}__qm_t{ r}__qm_rem)dnl
_ins({SUB r}__qm_v{ r}__qm_t{ r}__qm_w)dnl
_ins({MUL r}_qK(__qa){ r}_qK(__qb){ r}__qm_t)_ins({DIV r}__qm_t{ r}__qm_S{ r}__qm_t{ r}__qm_rem)dnl
_ins({SUB r}__qm_w{ r}__qm_t{ r}__qm_rr)dnl
_ins({MUL r}_qR(__qa){ r}_qI(__qb){ r}__qm_t)_ins({DIV r}__qm_t{ r}__qm_S{ r}__qm_t{ r}__qm_rem)dnl
_ins({MUL r}_qI(__qa){ r}_qR(__qb){ r}__qm_u)_ins({DIV r}__qm_u{ r}__qm_S{ r}__qm_u{ r}__qm_rem)dnl
_ins({ADD r}__qm_t{ r}__qm_u{ r}__qm_v)dnl
_ins({MUL r}_qJ(__qa){ r}_qK(__qb){ r}__qm_t)_ins({DIV r}__qm_t{ r}__qm_S{ r}__qm_t{ r}__qm_rem)dnl
_ins({ADD r}__qm_v{ r}__qm_t{ r}__qm_w)dnl
_ins({MUL r}_qK(__qa){ r}_qJ(__qb){ r}__qm_t)_ins({DIV r}__qm_t{ r}__qm_S{ r}__qm_t{ r}__qm_rem)dnl
_ins({SUB r}__qm_w{ r}__qm_t{ r}__qm_ri)dnl
_ins({MUL r}_qR(__qa){ r}_qJ(__qb){ r}__qm_t)_ins({DIV r}__qm_t{ r}__qm_S{ r}__qm_t{ r}__qm_rem)dnl
_ins({MUL r}_qI(__qa){ r}_qK(__qb){ r}__qm_u)_ins({DIV r}__qm_u{ r}__qm_S{ r}__qm_u{ r}__qm_rem)dnl
_ins({SUB r}__qm_t{ r}__qm_u{ r}__qm_v)dnl
_ins({MUL r}_qJ(__qa){ r}_qR(__qb){ r}__qm_t)_ins({DIV r}__qm_t{ r}__qm_S{ r}__qm_t{ r}__qm_rem)dnl
_ins({ADD r}__qm_v{ r}__qm_t{ r}__qm_w)dnl
_ins({MUL r}_qK(__qa){ r}_qI(__qb){ r}__qm_t)_ins({DIV r}__qm_t{ r}__qm_S{ r}__qm_t{ r}__qm_rem)dnl
_ins({ADD r}__qm_w{ r}__qm_t{ r}__qm_rj)dnl
_ins({MUL r}_qR(__qa){ r}_qK(__qb){ r}__qm_t)_ins({DIV r}__qm_t{ r}__qm_S{ r}__qm_t{ r}__qm_rem)dnl
_ins({MUL r}_qI(__qa){ r}_qJ(__qb){ r}__qm_u)_ins({DIV r}__qm_u{ r}__qm_S{ r}__qm_u{ r}__qm_rem)dnl
_ins({ADD r}__qm_t{ r}__qm_u{ r}__qm_v)dnl
_ins({MUL r}_qJ(__qa){ r}_qI(__qb){ r}__qm_t)_ins({DIV r}__qm_t{ r}__qm_S{ r}__qm_t{ r}__qm_rem)dnl
_ins({SUB r}__qm_v{ r}__qm_t{ r}__qm_w)dnl
_ins({MUL r}_qK(__qa){ r}_qR(__qb){ r}__qm_t)_ins({DIV r}__qm_t{ r}__qm_S{ r}__qm_t{ r}__qm_rem)dnl
_ins({ADD r}__qm_w{ r}__qm_t{ r}__qm_rk)dnl
define({_fp_}__qm_rr,_FP_DIGITS)define({_fp_}__qm_ri,_FP_DIGITS)define({_fp_}__qm_rj,_FP_DIGITS)define({_fp_}__qm_rk,_FP_DIGITS)__qm_rr:__qm_ri:__qm_rj:__qm_rk})dnl
; qconj: negate i,j,k
define({_emit_qconj},{define({__qc},_promote_quat({$1}))dnl
define({__qc_i},_alloc)define({__qc_j},_alloc)define({__qc_k},_alloc)dnl
_ins({NEG r}_qI(__qc){ r}__qc_i)_ins({NEG r}_qJ(__qc){ r}__qc_j)_ins({NEG r}_qK(__qc){ r}__qc_k)dnl
define({_fp_}__qc_i,_FP_DIGITS)define({_fp_}__qc_j,_FP_DIGITS)define({_fp_}__qc_k,_FP_DIGITS)_qR(__qc):__qc_i:__qc_j:__qc_k})dnl
; qnorm2: |q|² = r²+i²+j²+k² (scalar, fp)
define({_emit_qnorm2},{define({__qn},_promote_quat({$1}))dnl
define({__qn_S},_emit_set(_FP_SCALE))define({__qn_rem},_alloc)dnl
define({__qn_t},_alloc)define({__qn_u},_alloc)define({__qn_v},_alloc)define({__qn_w},_alloc)dnl
_ins({MUL r}_qR(__qn){ r}_qR(__qn){ r}__qn_t)_ins({DIV r}__qn_t{ r}__qn_S{ r}__qn_t{ r}__qn_rem)dnl
_ins({MUL r}_qI(__qn){ r}_qI(__qn){ r}__qn_u)_ins({DIV r}__qn_u{ r}__qn_S{ r}__qn_u{ r}__qn_rem)dnl
_ins({ADD r}__qn_t{ r}__qn_u{ r}__qn_v)dnl
_ins({MUL r}_qJ(__qn){ r}_qJ(__qn){ r}__qn_t)_ins({DIV r}__qn_t{ r}__qn_S{ r}__qn_t{ r}__qn_rem)dnl
_ins({ADD r}__qn_v{ r}__qn_t{ r}__qn_w)dnl
_ins({MUL r}_qK(__qn){ r}_qK(__qn){ r}__qn_t)_ins({DIV r}__qn_t{ r}__qn_S{ r}__qn_t{ r}__qn_rem)dnl
_ins({ADD r}__qn_w{ r}__qn_t{ r}__qn_v)dnl
define({_fp_}__qn_v,_FP_DIGITS)__qn_v})dnl
; qinv: conj(q)/|q|²
define({_emit_qinv},{dnl
define({__qi_n2},_emit_qnorm2({$1}))dnl
define({__qi_cj},_emit_qconj({$1}))dnl
define({__qi_S},_emit_set(_FP_SCALE))define({__qi_rem},_alloc)dnl
define({__qi_r},_alloc)define({__qi_i},_alloc)define({__qi_j},_alloc)define({__qi_k},_alloc)dnl
_ins({MUL r}_qR(__qi_cj){ r}__qi_S{ r}__qi_r)_ins({DIV r}__qi_r{ r}__qi_n2{ r}__qi_r{ r}__qi_rem)dnl
_ins({MUL r}_qI(__qi_cj){ r}__qi_S{ r}__qi_i)_ins({DIV r}__qi_i{ r}__qi_n2{ r}__qi_i{ r}__qi_rem)dnl
_ins({MUL r}_qJ(__qi_cj){ r}__qi_S{ r}__qi_j)_ins({DIV r}__qi_j{ r}__qi_n2{ r}__qi_j{ r}__qi_rem)dnl
_ins({MUL r}_qK(__qi_cj){ r}__qi_S{ r}__qi_k)_ins({DIV r}__qi_k{ r}__qi_n2{ r}__qi_k{ r}__qi_rem)dnl
define({_fp_}__qi_r,_FP_DIGITS)define({_fp_}__qi_i,_FP_DIGITS)define({_fp_}__qi_j,_FP_DIGITS)define({_fp_}__qi_k,_FP_DIGITS)__qi_r:__qi_i:__qi_j:__qi_k})dnl
; ---- polymorphic arithmetic dispatch ----
; These check types of both operands and dispatch to scalar/complex/quaternion
define({_poly_add},{ifelse(_isquat({$1})_isquat({$2}),{00},{ifelse(_iscomplex({$1})_iscomplex({$2}),{00},{_emit_op(ADD,{$1},{$2})},{_emit_cadd(_promote_complex({$1}),_promote_complex({$2}))})},{_emit_qadd({$1},{$2})})})dnl
define({_poly_sub},{ifelse(_isquat({$1})_isquat({$2}),{00},{ifelse(_iscomplex({$1})_iscomplex({$2}),{00},{_emit_op(SUB,{$1},{$2})},{_emit_csub(_promote_complex({$1}),_promote_complex({$2}))})},{_emit_qsub({$1},{$2})})})dnl
define({_poly_mul},{ifelse(_isquat({$1})_isquat({$2}),{00},{ifelse(_iscomplex({$1})_iscomplex({$2}),{00},{_emit_op(MUL,{$1},{$2})},{_emit_cmul(_promote_complex({$1}),_promote_complex({$2}))})},{_emit_qhmul({$1},{$2})})})dnl
define({_poly_neg},{ifelse(_isquat({$1}),1,{_emit_qneg({$1})},_iscomplex({$1}),1,{_emit_cneg({$1})},{_emit_op1(NEG,{$1})})})dnl
define({_poly_div},{ifelse(_isquat({$1})_isquat({$2}),{00},{ifelse(_iscomplex({$1})_iscomplex({$2}),{00},{_emit_div({$1},{$2})},{_emit_cdiv(_promote_complex({$1}),_promote_complex({$2}))})},{_emit_qdiv({$1},{$2})})})dnl
; qdiv: q1 * q2^-1
define({_emit_qdiv},{_emit_qhmul({$1},_emit_qinv({$2}))})dnl
; qneg: negate all 4 components
define({_emit_qneg},{define({__qn_qa},_promote_quat({$1}))dnl
define({__qn_r},_alloc)define({__qn_i},_alloc)define({__qn_j},_alloc)define({__qn_k},_alloc)dnl
_ins({NEG r}_qR(__qn_qa){ r}__qn_r)_ins({NEG r}_qI(__qn_qa){ r}__qn_i)_ins({NEG r}_qJ(__qn_qa){ r}__qn_j)_ins({NEG r}_qK(__qn_qa){ r}__qn_k)dnl
define({_fp_}__qn_r,_FP_DIGITS)define({_fp_}__qn_i,_FP_DIGITS)define({_fp_}__qn_j,_FP_DIGITS)define({_fp_}__qn_k,_FP_DIGITS)__qn_r:__qn_i:__qn_j:__qn_k})dnl
; ---- scanner (from calc5) ----
define({_POS},0)dnl
define({_setpos},{define({_POS},{$1})})dnl
define({_setinput},{define({_INPUT},{$1})})dnl
define({_ch},{substr(_INPUT,_POS,1)})dnl
define({_advance},{_setpos(eval(_POS+1))})dnl
define({_skip},{ifelse(_ch,{ },{_advance()_skip()})})dnl
define({_isdigit},{ifelse({$1},{0},1,{$1},{1},1,{$1},{2},1,{$1},{3},1,{$1},{4},1,{$1},{5},1,{$1},{6},1,{$1},{7},1,{$1},{8},1,{$1},{9},1,0)})dnl
define({_isalpha},{ifelse({$1},,0,eval(index({abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ},{$1})>=0),1,1,0)})dnl
define({_isalnum},{ifelse(_isdigit({$1}),1,1,_isalpha({$1}),1,1,0)})dnl
define({_rdnum},{ifelse(_isdigit(_ch),1,{_ch()_advance()_rdnum()},_ch,{.},{.{}_advance()_rdnum()})})dnl
define({_rdid},{_rdid_e(_POS)})dnl
define({_rdid_e},{ifelse(_isalnum(substr(_INPUT,{$1},1)),1,{_rdid_e(eval({$1}+1))},{_rdid_x({$1})})})dnl
define({_rdid_x},{define({__rid},substr(_INPUT,_POS,eval({$1}-_POS)))_setpos({$1})__rid})dnl
; ---- hex/binary literals ----
define({_ishex},{ifelse({$1},,0,eval(index({0123456789abcdef},translit({$1},{ABCDEF},{abcdef}))>=0),1,1,0)})dnl
define({_hexval},{index({0123456789abcdef},translit({$1},{ABCDEF},{abcdef}))})dnl
define({_rdhexstr},{ifelse(_ishex(_ch),1,{_ch{}_advance()_rdhexstr()})})dnl
define({_emit_hex},{define({__hr},_emit_set(0))_emit_hex2(__hr,{$1})})dnl
define({_emit_hex2},{ifelse({$2},,{$1},{_emit_hex2(_emit_hexdigit({$1},substr({$2},0,1)),substr({$2},1))})})dnl
define({_emit_hexdigit},{define({__hm},_alloc)_ins({SMUL r$1 16 r}__hm)define({__hd},_emit_set(_hexval({$2})))define({__ha},_alloc)_ins({ADD r}__hm{ r}__hd{ r}__ha)__ha})dnl
define({_isbin},{ifelse({$1},{0},1,{$1},{1},1,0)})dnl
define({_rdbinstr},{ifelse(_isbin(_ch),1,{_ch()_advance()_rdbinstr()})})dnl
define({_emit_bin},{define({__br},_emit_set(0))_emit_bin2(__br,{$1})})dnl
define({_emit_bin2},{ifelse({$2},,{$1},{_emit_bin2(_emit_bindigit({$1},substr({$2},0,1)),substr({$2},1))})})dnl
define({_emit_bindigit},{define({__bm},_alloc)_ins({SMUL r$1 2 r}__bm)define({__bd},_emit_set(substr({$2},0,1)))define({__ba},_alloc)_ins({ADD r}__bm{ r}__bd{ r}__ba)__ba})dnl
; ---- parser -> bytecode ----
; _atom: number | '(' expr ')' | identifier | 0x... | 0b...
define({_atom},{_skip()ifelse(_ch,{<},{_advance()_atom_p(_expr())},_isdigit(_ch),1,{_atom_num()},_isalpha(_ch),1,{_atom_id(_rdid())},{ERR})})dnl
define({_atom_num},{ifelse(_ch,{0},{_atom_num0()},{_emit_set(_rdnum())})})dnl
define({_atom_num0},{_advance()ifelse(_ch,{x},{_advance()_emit_hex(_rdhexstr())},_ch,{b},{_advance()_emit_bin(_rdbinstr())},{_emit_set(0{}_rdnum())})})dnl
define({_atom_p},{_skip()_advance(){$1}})dnl
; _atom_id: constants, i/j/k units, or function call
define({_emit_imag_unit},{define({__iu_r},_alloc)define({__iu_i},_alloc)_ins({SET r}__iu_r{ 0})_ins({SET r}__iu_i{ _FP_SCALE})define({_fp_}__iu_r,_FP_DIGITS)define({_fp_}__iu_i,_FP_DIGITS)__iu_r:__iu_i})dnl
define({_emit_qunit_j},{define({__uj_r},_alloc)define({__uj_i},_alloc)define({__uj_j},_alloc)define({__uj_k},_alloc)_ins({SET r}__uj_r{ 0})_ins({SET r}__uj_i{ 0})_ins({SET r}__uj_j{ _FP_SCALE})_ins({SET r}__uj_k{ 0})define({_fp_}__uj_r,_FP_DIGITS)define({_fp_}__uj_i,_FP_DIGITS)define({_fp_}__uj_j,_FP_DIGITS)define({_fp_}__uj_k,_FP_DIGITS)__uj_r:__uj_i:__uj_j:__uj_k})dnl
define({_emit_qunit_k},{define({__uk_r},_alloc)define({__uk_i},_alloc)define({__uk_j},_alloc)define({__uk_k},_alloc)_ins({SET r}__uk_r{ 0})_ins({SET r}__uk_i{ 0})_ins({SET r}__uk_j{ 0})_ins({SET r}__uk_k{ _FP_SCALE})define({_fp_}__uk_r,_FP_DIGITS)define({_fp_}__uk_i,_FP_DIGITS)define({_fp_}__uk_j,_FP_DIGITS)define({_fp_}__uk_k,_FP_DIGITS)__uk_r:__uk_i:__uk_j:__uk_k})dnl
define({_atom_id},{ifelse({$1},{pi},{_emit_set(3.141592653589793238)},{$1},{e},{_emit_set(2.718281828459045235)},{$1},{i},{_emit_imag_unit()},{$1},{j},{_emit_qunit_j()},{$1},{k},{_emit_qunit_k()},{_atom_fn({$1})})})dnl
; _atom_fn: parse function(arg), emit instruction
define({_atom_fn},{_skip()_advance()_atom_fn2({$1},_expr())})dnl
define({_atom_fn2},{_skip()ifelse({$1},{tan},{_advance()_emit_tan({$2})},{$1},{beta},{_atom_fn2_beta({$2})},{$1},{gcd},{_atom_fn2_gcd({$2})},{$1},{lcm},{_atom_fn2_lcm({$2})},{$1},{modinv},{_atom_fn2_modinv({$2})},{_advance()_emit_fn({$1},{$2})})})dnl
; beta: at this point POS is at @ (was comma). advance past @, parse arg2, advance past >
define({_atom_fn2_beta},{_advance()_atom_fn2_beta2({$1},_expr())})dnl
define({_atom_fn2_beta2},{_skip()_advance()_emit_beta({$1},{$2})})dnl
; gcd: same pattern as beta
define({_atom_fn2_gcd},{_advance()_atom_fn2_gcd2({$1},_expr())})dnl
define({_atom_fn2_gcd2},{_skip()_advance()_emit_gcd({$1},{$2})})dnl
; lcm: same pattern as gcd
define({_atom_fn2_lcm},{_advance()_atom_fn2_lcm2({$1},_expr())})dnl
define({_atom_fn2_lcm2},{_skip()_advance()_emit_lcm({$1},{$2})})dnl
; modinv(a, m): modular inverse
define({_atom_fn2_modinv},{_advance()_atom_fn2_modinv2({$1},_expr())})dnl
define({_atom_fn2_modinv2},{_skip()_advance()_emit_modinv({$1},{$2})})dnl
; _emit_fn: dispatch to m4-side implementations or VM opcodes
define({_emit_fn},{ifelse(_iscomplex($2),1,{_emit_fn_poly({$1},{$2})},_isquat($2),1,{_emit_fn_poly({$1},{$2})},{define({__fa},ifelse(_isfp($2),1,{$2},{_scale_up($2)}))_emit_fn_scalar({$1},__fa)})})dnl
define({_emit_fn_scalar},{ifelse({$1},{exp},{_emit_exp({$2})},{$1},{sin},{_emit_sin({$2})},{$1},{cos},{_emit_cos({$2})},{$1},{ln},{_emit_ln({$2})},{$1},{log},{_emit_ln({$2})},{$1},{sqrt},{_emit_sqrt_safe({$2})},{$1},{atan},{_emit_atan({$2})},{$1},{asin},{_emit_asin({$2})},{$1},{acos},{_emit_acos({$2})},{$1},{log10},{_emit_log10({$2})},{$1},{log2},{_emit_log2({$2})},{$1},{sinh},{_emit_sinh({$2})},{$1},{cosh},{_emit_cosh({$2})},{$1},{tanh},{_emit_tanh({$2})},{$1},{atanh},{_emit_atanh({$2})},{$1},{gamma},{_emit_gamma({$2})},{$1},{erf},{_emit_erf({$2})},{$1},{phi},{_emit_phi({$2})},{$1},{Ei},{_emit_ei({$2})},{$1},{Li},{_emit_li({$2})},{$1},{W},{_emit_lambertw({$2})},{$1},{zeta},{_emit_zeta({$2})},{$1},{eta},{_emit_eta({$2})},{$1},{conj},{$2},{$1},{abs},{define({__ab_r},_alloc)_ins({ABS r$2 r}__ab_r)ifelse(_isfp($2),1,{define({_fp_}__ab_r,_FP_DIGITS)})__ab_r},{$1},{arg},{_emit_set(0)},{_emit_fn_vm({$1},{$2})})})dnl
define({_emit_fn_vm},{define({__fr},_alloc)_ins(_fn_name({$1}){ r$2 r}__fr)define({_fp_}__fr,_FP_DIGITS)__fr})dnl
define({_fn_name},{ifelse({$1},{ln},{LN},{$1},{sqrt},{SQRT},{$1},{log},{LN},{ERR:fn})})dnl
; ---- unique label generator ----
define({_GENSYM},0)dnl
define({_gensym},{define({_GENSYM},eval(_GENSYM+1))L{}_GENSYM})dnl
; ---- m4-side exp(x): range reduction + unrolled Taylor ----
; _exp_taylor(k): emit one Taylor iteration, recurse up to 20
define({_exp_taylor},{ifelse(eval({$1}>20),1,,{_ins({MUL r}__ex_term{ r}__ex_x{ r}__ex_t1)_ins({DIV r}__ex_t1{ r}__ex_S{ r}__ex_t2{ r}__ex_t3)_ins({SDIV r}__ex_t2{ $1 r}__ex_t1)_ins({COPY r}__ex_t1{ r}__ex_term)_ins({ADD r}__ex_sum{ r}__ex_term{ r}__ex_t1)_ins({COPY r}__ex_t1{ r}__ex_sum)_exp_taylor(eval({$1}+1))})})dnl
; _emit_exp(rArg): emit full exp bytecode, returns result register (fp)
define({_emit_exp},{dnl
define({__ex_S},_alloc)dnl
define({__ex_H},_alloc)dnl
define({__ex_cnt},_alloc)dnl
define({__ex_one},_alloc)dnl
define({__ex_zero},_alloc)dnl
define({__ex_sum},_alloc)dnl
define({__ex_term},_alloc)dnl
define({__ex_t1},_alloc)dnl
define({__ex_t2},_alloc)dnl
define({__ex_t3},_alloc)dnl
define({__ex_x},_alloc)dnl
define({__ex_neg},_alloc)dnl
define({__L_halve},_gensym)dnl
define({__L_taylor},_gensym)dnl
define({__L_square},_gensym)dnl
define({__L_sqdone},_gensym)dnl
define({__L_notneg},_gensym)dnl
_ins({SET r}__ex_S{ _FP_SCALE})dnl
_ins({SET r}__ex_H{ 500000000000000000})dnl
_ins({SET r}__ex_cnt{ 0})dnl
_ins({SET r}__ex_one{ 1})dnl
_ins({SET r}__ex_zero{ 0})dnl
_ins({ISNEG r$1 r}__ex_neg)dnl
_ins({ABS r$1 r}__ex_x)dnl
_ins({LABEL }__L_halve)dnl
_ins({CMP r}__ex_x{ r}__ex_H)dnl
_ins({BLE }__L_taylor)dnl
_ins({SDIV r}__ex_x{ 2 r}__ex_t1)dnl
_ins({COPY r}__ex_t1{ r}__ex_x)dnl
_ins({ADD r}__ex_cnt{ r}__ex_one{ r}__ex_t1)dnl
_ins({COPY r}__ex_t1{ r}__ex_cnt)dnl
_ins({JMP }__L_halve)dnl
_ins({LABEL }__L_taylor)dnl
_ins({COPY r}__ex_S{ r}__ex_sum)dnl
_ins({COPY r}__ex_S{ r}__ex_term)dnl
_exp_taylor(1)dnl
_ins({LABEL }__L_square)dnl
_ins({CMP r}__ex_cnt{ r}__ex_zero)dnl
_ins({BLE }__L_sqdone)dnl
_ins({MUL r}__ex_sum{ r}__ex_sum{ r}__ex_t1)dnl
_ins({DIV r}__ex_t1{ r}__ex_S{ r}__ex_t2{ r}__ex_t3)dnl
_ins({COPY r}__ex_t2{ r}__ex_sum)dnl
_ins({SUB r}__ex_cnt{ r}__ex_one{ r}__ex_t1)dnl
_ins({COPY r}__ex_t1{ r}__ex_cnt)dnl
_ins({JMP }__L_square)dnl
_ins({LABEL }__L_sqdone)dnl
_ins({CMP r}__ex_neg{ r}__ex_zero)dnl
_ins({BLE }__L_notneg)dnl
_ins({MUL r}__ex_S{ r}__ex_S{ r}__ex_t1)dnl
_ins({DIV r}__ex_t1{ r}__ex_sum{ r}__ex_t2{ r}__ex_t3)dnl
_ins({COPY r}__ex_t2{ r}__ex_sum)dnl
_ins({LABEL }__L_notneg)dnl
define({_fp_}__ex_sum,_FP_DIGITS)__ex_sum})dnl
; ---- m4-side sin(x): range reduction + unrolled Taylor ----
; _sin_taylor(k): one iteration k=1..10
; term = term * x2 / S / ((2k)(2k+1)); sum +/- term
define({_sin_taylor},{ifelse(eval({$1}>10),1,,{dnl
_ins({MUL r}__si_term{ r}__si_x2{ r}__si_t1)dnl
_ins({DIV r}__si_t1{ r}__si_S{ r}__si_t2{ r}__si_t3)dnl
_ins({SDIV r}__si_t2{ eval(2*{$1}*(2*{$1}+1)) r}__si_t1)dnl
_ins({COPY r}__si_t1{ r}__si_term)dnl
_ins(ifelse(eval({$1}%2),1,{SUB},{ADD}){ r}__si_sum{ r}__si_term{ r}__si_t1)dnl
_ins({COPY r}__si_t1{ r}__si_sum)dnl
_sin_taylor(eval({$1}+1))})})dnl
; _emit_sin(rArg): emit full sin bytecode, returns result register (fp)
define({_emit_sin},{dnl
define({__si_S},_alloc)dnl
define({__si_2pi},_alloc)dnl
define({__si_pi},_alloc)dnl
define({__si_pih},_alloc)dnl
define({__si_zero},_alloc)dnl
define({__si_one},_alloc)dnl
define({__si_neg},_alloc)dnl
define({__si_x},_alloc)dnl
define({__si_sum},_alloc)dnl
define({__si_term},_alloc)dnl
define({__si_x2},_alloc)dnl
define({__si_t1},_alloc)dnl
define({__si_t2},_alloc)dnl
define({__si_t3},_alloc)dnl
define({__L_smod},_gensym)dnl
define({__L_spi},_gensym)dnl
define({__L_spih},_gensym)dnl
define({__L_sdone},_gensym)dnl
define({__L_snoneg},_gensym)dnl
_ins({SET r}__si_S{ _FP_SCALE})dnl
_ins({SET r}__si_2pi{ 6283185307179586476})dnl
_ins({SET r}__si_pi{ 3141592653589793238})dnl
_ins({SET r}__si_pih{ 1570796326794896619})dnl
_ins({SET r}__si_zero{ 0})dnl
_ins({SET r}__si_one{ 1})dnl
_ins({ISNEG r$1 r}__si_neg)dnl
_ins({ABS r$1 r}__si_x)dnl
_ins({CMP r}__si_x{ r}__si_2pi)dnl
_ins({BLT }__L_smod)dnl
_ins({DIV r}__si_x{ r}__si_2pi{ r}__si_t1{ r}__si_t2)dnl
_ins({COPY r}__si_t2{ r}__si_x)dnl
_ins({LABEL }__L_smod)dnl
_ins({CMP r}__si_x{ r}__si_pi)dnl
_ins({BLE }__L_spi)dnl
_ins({SUB r}__si_x{ r}__si_pi{ r}__si_t1)dnl
_ins({COPY r}__si_t1{ r}__si_x)dnl
_ins({SUB r}__si_one{ r}__si_neg{ r}__si_t1)dnl
_ins({COPY r}__si_t1{ r}__si_neg)dnl
_ins({LABEL }__L_spi)dnl
_ins({CMP r}__si_x{ r}__si_pih)dnl
_ins({BLE }__L_spih)dnl
_ins({SUB r}__si_pi{ r}__si_x{ r}__si_t1)dnl
_ins({COPY r}__si_t1{ r}__si_x)dnl
_ins({LABEL }__L_spih)dnl
_ins({COPY r}__si_x{ r}__si_sum)dnl
_ins({COPY r}__si_x{ r}__si_term)dnl
_ins({MUL r}__si_x{ r}__si_x{ r}__si_t1)dnl
_ins({DIV r}__si_t1{ r}__si_S{ r}__si_x2{ r}__si_t3)dnl
_sin_taylor(1)dnl
_ins({CMP r}__si_neg{ r}__si_zero)dnl
_ins({BLE }__L_snoneg)dnl
_ins({NEG r}__si_sum{ r}__si_t1)dnl
_ins({COPY r}__si_t1{ r}__si_sum)dnl
_ins({LABEL }__L_snoneg)dnl
define({_fp_}__si_sum,_FP_DIGITS)__si_sum})dnl
; _emit_cos(rArg): cos(x) = sin(x + pi/2)
define({_emit_cos},{dnl
define({__co_pih},_alloc)dnl
define({__co_shifted},_alloc)dnl
_ins({SET r}__co_pih{ 1570796326794896619})dnl
_ins({ADD r$1 r}__co_pih{ r}__co_shifted)dnl
_emit_sin(__co_shifted)})dnl
; _emit_tan: tan(x) = sin(x) / cos(x) as fp divide
define({_emit_tan},{define({__ta},ifelse(_isfp($1),1,{$1},{_scale_up($1)}))dnl
define({__ts},_emit_sin(__ta))dnl
define({__tc},_emit_cos(__ta))dnl
define({__tsc},_emit_set(_FP_SCALE))dnl
define({__tp},_alloc)_ins({MUL r}__ts{ r}__tsc{ r}__tp)dnl
define({__tq},_alloc)define({__tr},_alloc)_ins({DIV r}__tp{ r}__tc{ r}__tq{ r}__tr)dnl
define({_fp_}__tq,_FP_DIGITS)__tq})dnl
; ---- m4-side ln(x): range reduction + atanh series ----
; _atanh_taylor(k): term = term * y2 / S, sum += term / (2k+1), k=1..15
define({_atanh_taylor},{ifelse(eval({$1}>15),1,,{dnl
_ins({MUL r}__ln_term{ r}__ln_y2{ r}__ln_t1)dnl
_ins({DIV r}__ln_t1{ r}__ln_S{ r}__ln_t2{ r}__ln_t3)dnl
_ins({COPY r}__ln_t2{ r}__ln_term)dnl
_ins({SDIV r}__ln_term{ eval(2*{$1}+1) r}__ln_t1)dnl
_ins({ADD r}__ln_sum{ r}__ln_t1{ r}__ln_t2)dnl
_ins({COPY r}__ln_t2{ r}__ln_sum)dnl
_atanh_taylor(eval({$1}+1))})})dnl
; _emit_ln(rArg): emit full ln bytecode, returns result register (fp)
define({_emit_ln},{dnl
define({__ln_S},_alloc)dnl
define({__ln_e},_alloc)dnl
define({__ln_2S},_alloc)dnl
define({__ln_hS},_alloc)dnl
define({__ln_cnt},_alloc)dnl
define({__ln_one},_alloc)dnl
define({__ln_zero},_alloc)dnl
define({__ln_x},_alloc)dnl
define({__ln_sum},_alloc)dnl
define({__ln_term},_alloc)dnl
define({__ln_y2},_alloc)dnl
define({__ln_t1},_alloc)dnl
define({__ln_t2},_alloc)dnl
define({__ln_t3},_alloc)dnl
define({__ln_t4},_alloc)dnl
define({__L_lndown},_gensym)dnl
define({__L_lnup},_gensym)dnl
define({__L_lnrd},_gensym)dnl
define({__L_lnru},_gensym)dnl
define({__L_lnkpos},_gensym)dnl
define({__L_lnkneg},_gensym)dnl
define({__L_lnkz},_gensym)dnl
define({__L_lndone},_gensym)dnl
_ins({SET r}__ln_S{ _FP_SCALE})dnl
_ins({SET r}__ln_e{ 2718281828459045235})dnl
_ins({SET r}__ln_2S{ 2000000000000000000})dnl
_ins({SET r}__ln_hS{ 500000000000000000})dnl
_ins({SET r}__ln_cnt{ 0})dnl
_ins({SET r}__ln_one{ 1})dnl
_ins({SET r}__ln_zero{ 0})dnl
_ins({COPY r$1 r}__ln_x)dnl
_ins({LABEL }__L_lndown)dnl
_ins({CMP r}__ln_x{ r}__ln_2S)dnl
_ins({BLE }__L_lnrd)dnl
_ins({MUL r}__ln_x{ r}__ln_S{ r}__ln_t1)dnl
_ins({DIV r}__ln_t1{ r}__ln_e{ r}__ln_t2{ r}__ln_t3)dnl
_ins({COPY r}__ln_t2{ r}__ln_x)dnl
_ins({ADD r}__ln_cnt{ r}__ln_one{ r}__ln_t1)dnl
_ins({COPY r}__ln_t1{ r}__ln_cnt)dnl
_ins({JMP }__L_lndown)dnl
_ins({LABEL }__L_lnrd)dnl
_ins({LABEL }__L_lnup)dnl
_ins({CMP r}__ln_x{ r}__ln_hS)dnl
_ins({BGE }__L_lnru)dnl
_ins({MUL r}__ln_x{ r}__ln_e{ r}__ln_t1)dnl
_ins({DIV r}__ln_t1{ r}__ln_S{ r}__ln_t2{ r}__ln_t3)dnl
_ins({COPY r}__ln_t2{ r}__ln_x)dnl
_ins({SUB r}__ln_cnt{ r}__ln_one{ r}__ln_t1)dnl
_ins({COPY r}__ln_t1{ r}__ln_cnt)dnl
_ins({JMP }__L_lnup)dnl
_ins({LABEL }__L_lnru)dnl
_ins({SUB r}__ln_x{ r}__ln_S{ r}__ln_t1)dnl
_ins({ADD r}__ln_x{ r}__ln_S{ r}__ln_t2)dnl
_ins({MUL r}__ln_t1{ r}__ln_S{ r}__ln_t3)dnl
_ins({DIV r}__ln_t3{ r}__ln_t2{ r}__ln_t4{ r}__ln_t1)dnl
_ins({COPY r}__ln_t4{ r}__ln_term)dnl
_ins({MUL r}__ln_t4{ r}__ln_t4{ r}__ln_t1)dnl
_ins({DIV r}__ln_t1{ r}__ln_S{ r}__ln_y2{ r}__ln_t3)dnl
_ins({COPY r}__ln_term{ r}__ln_sum)dnl
_atanh_taylor(1)dnl
_ins({SMUL r}__ln_sum{ 2 r}__ln_t1)dnl
_ins({COPY r}__ln_t1{ r}__ln_sum)dnl
_ins({CMP r}__ln_cnt{ r}__ln_zero)dnl
_ins({BEQ }__L_lndone)dnl
_ins({ISNEG r}__ln_cnt{ r}__ln_t1)dnl
_ins({CMP r}__ln_t1{ r}__ln_zero)dnl
_ins({BGT }__L_lnkneg)dnl
_ins({MUL r}__ln_cnt{ r}__ln_S{ r}__ln_t1)dnl
_ins({ADD r}__ln_sum{ r}__ln_t1{ r}__ln_t2)dnl
_ins({COPY r}__ln_t2{ r}__ln_sum)dnl
_ins({JMP }__L_lndone)dnl
_ins({LABEL }__L_lnkneg)dnl
_ins({ABS r}__ln_cnt{ r}__ln_t1)dnl
_ins({MUL r}__ln_t1{ r}__ln_S{ r}__ln_t2)dnl
_ins({SUB r}__ln_sum{ r}__ln_t2{ r}__ln_t1)dnl
_ins({COPY r}__ln_t1{ r}__ln_sum)dnl
_ins({LABEL }__L_lndone)dnl
define({_fp_}__ln_sum,_FP_DIGITS)__ln_sum})dnl
; ---- m4-side sqrt(x): Newton y = (y + x/y) / 2, 60 iterations ----
define({_emit_sqrt},{dnl
define({__sq_S},_alloc)dnl
define({__sq_x},_alloc)dnl
define({__sq_y},_alloc)dnl
define({__sq_cnt},_alloc)dnl
define({__sq_one},_alloc)dnl
define({__sq_zero},_alloc)dnl
define({__sq_t1},_alloc)dnl
define({__sq_t2},_alloc)dnl
define({__sq_t3},_alloc)dnl
define({__sq_t4},_alloc)dnl
define({__L_sqloop},_gensym)dnl
define({__L_sqdone},_gensym)dnl
_ins({SET r}__sq_S{ _FP_SCALE})dnl
_ins({SET r}__sq_cnt{ 60})dnl
_ins({SET r}__sq_one{ 1})dnl
_ins({SET r}__sq_zero{ 0})dnl
_ins({COPY r$1 r}__sq_x)dnl
_ins({COPY r}__sq_S{ r}__sq_y)dnl
_ins({LABEL }__L_sqloop)dnl
_ins({CMP r}__sq_cnt{ r}__sq_zero)dnl
_ins({BLE }__L_sqdone)dnl
_ins({MUL r}__sq_x{ r}__sq_S{ r}__sq_t1)dnl
_ins({DIV r}__sq_t1{ r}__sq_y{ r}__sq_t2{ r}__sq_t3)dnl
_ins({ADD r}__sq_y{ r}__sq_t2{ r}__sq_t1)dnl
_ins({SDIV r}__sq_t1{ 2 r}__sq_t2)dnl
_ins({COPY r}__sq_t2{ r}__sq_y)dnl
_ins({SUB r}__sq_cnt{ r}__sq_one{ r}__sq_t1)dnl
_ins({COPY r}__sq_t1{ r}__sq_cnt)dnl
_ins({JMP }__L_sqloop)dnl
_ins({LABEL }__L_sqdone)dnl
define({_fp_}__sq_y,_FP_DIGITS)__sq_y})dnl
; ---- sqrt_safe: returns complex; handles negative args via sqrt(|x|)*i ----
define({_emit_sqrt_safe},{dnl
define({__ss_flag},_alloc)dnl
define({__ss_zero},_alloc)dnl
define({__ss_abs},_alloc)dnl
define({__ss_rr},_alloc)dnl
define({__ss_ri},_alloc)dnl
define({__L_ss_neg},_gensym)dnl
define({__L_ss_done},_gensym)dnl
_ins({SET r}__ss_zero{ 0})dnl
_ins({SET r}__ss_rr{ 0})define({_fp_}__ss_rr,_FP_DIGITS)dnl
_ins({SET r}__ss_ri{ 0})define({_fp_}__ss_ri,_FP_DIGITS)dnl
_ins({ISNEG r$1 r}__ss_flag)dnl
_ins({ABS r$1 r}__ss_abs)define({_fp_}__ss_abs,_FP_DIGITS)dnl
define({__ss_sq},_emit_sqrt(__ss_abs))dnl
_ins({CMP r}__ss_flag{ r}__ss_zero)dnl
_ins({BNE }__L_ss_neg)dnl
_ins({COPY r}__ss_sq{ r}__ss_rr)dnl
_ins({JMP }__L_ss_done)dnl
_ins({LABEL }__L_ss_neg)dnl
_ins({COPY r}__ss_sq{ r}__ss_ri)dnl
_ins({LABEL }__L_ss_done)dnl
__ss_rr:__ss_ri})dnl
; ---- m4-side atan(x): range reduction + Taylor series ----
; For |x| <= S: atan(x) = x - x^3/3 + x^5/5 - ... (20 terms)
; For |x| > S: atan(x) = sign(x) * (pi/2 - atan(S^2/|x|))
; _atan_taylor(k): term = term * x2 / S; sum +/- term/(2k+1)
define({_atan_taylor},{ifelse(eval({$1}>20),1,,{dnl
_ins({MUL r}__at_term{ r}__at_x2{ r}__at_t1)dnl
_ins({DIV r}__at_t1{ r}__at_S{ r}__at_t2{ r}__at_t3)dnl
_ins({COPY r}__at_t2{ r}__at_term)dnl
_ins({SDIV r}__at_term{ eval(2*{$1}+1) r}__at_t1)dnl
_ins(ifelse(eval({$1}%2),1,{SUB},{ADD}){ r}__at_sum{ r}__at_t1{ r}__at_t2)dnl
_ins({COPY r}__at_t2{ r}__at_sum)dnl
_atan_taylor(eval({$1}+1))})})dnl
; _emit_atan(rArg): emit full atan bytecode, returns result register (fp)
; Uses argument halving: atan(x) = 2*atan(x/(1+sqrt(1+x^2)))
; For |x| > S: atan(x) = sign(x)*(pi/2 - atan(S^2/|x|))
; After reduction, |x| < 0.42 so 20-term Taylor converges well
define({_emit_atan},{dnl
define({__at_S},_alloc)dnl
define({__at_pih},_alloc)dnl
define({__at_zero},_alloc)dnl
define({__at_neg},_alloc)dnl
define({__at_big},_alloc)dnl
define({__at_x},_alloc)dnl
define({__at_sum},_alloc)dnl
define({__at_term},_alloc)dnl
define({__at_x2},_alloc)dnl
define({__at_t1},_alloc)dnl
define({__at_t2},_alloc)dnl
define({__at_t3},_alloc)dnl
define({__at_t4},_alloc)dnl
define({__L_atsmall},_gensym)dnl
define({__L_atreduce},_gensym)dnl
define({__L_atdone},_gensym)dnl
define({__L_atnoneg},_gensym)dnl
_ins({SET r}__at_S{ _FP_SCALE})dnl
_ins({SET r}__at_pih{ 1570796326794896619})dnl
_ins({SET r}__at_zero{ 0})dnl
_ins({ISNEG r$1 r}__at_neg)dnl
_ins({ABS r$1 r}__at_x)dnl
_ins({SET r}__at_big{ 0})dnl
_ins({CMP r}__at_x{ r}__at_S)dnl
_ins({BLE }__L_atsmall)dnl
_ins({SET r}__at_big{ 1})dnl
_ins({MUL r}__at_S{ r}__at_S{ r}__at_t1)dnl
_ins({DIV r}__at_t1{ r}__at_x{ r}__at_t2{ r}__at_t3)dnl
_ins({COPY r}__at_t2{ r}__at_x)dnl
_ins({LABEL }__L_atsmall)dnl
_ins({MUL r}__at_x{ r}__at_x{ r}__at_t1)dnl
_ins({DIV r}__at_t1{ r}__at_S{ r}__at_t2{ r}__at_t3)dnl
_ins({ADD r}__at_t2{ r}__at_S{ r}__at_t1)dnl
define({__at_sq},_emit_sqrt(__at_t1))dnl
_ins({ADD r}__at_sq{ r}__at_S{ r}__at_t1)dnl
_ins({MUL r}__at_x{ r}__at_S{ r}__at_t2)dnl
_ins({DIV r}__at_t2{ r}__at_t1{ r}__at_t3{ r}__at_t4)dnl
_ins({COPY r}__at_t3{ r}__at_x)dnl
_ins({COPY r}__at_x{ r}__at_sum)dnl
_ins({COPY r}__at_x{ r}__at_term)dnl
_ins({MUL r}__at_x{ r}__at_x{ r}__at_t1)dnl
_ins({DIV r}__at_t1{ r}__at_S{ r}__at_x2{ r}__at_t3)dnl
_atan_taylor(1)dnl
_ins({SMUL r}__at_sum{ 2 r}__at_t1)dnl
_ins({COPY r}__at_t1{ r}__at_sum)dnl
_ins({CMP r}__at_big{ r}__at_zero)dnl
_ins({BLE }__L_atdone)dnl
_ins({SUB r}__at_pih{ r}__at_sum{ r}__at_t1)dnl
_ins({COPY r}__at_t1{ r}__at_sum)dnl
_ins({LABEL }__L_atdone)dnl
_ins({CMP r}__at_neg{ r}__at_zero)dnl
_ins({BLE }__L_atnoneg)dnl
_ins({NEG r}__at_sum{ r}__at_t1)dnl
_ins({COPY r}__at_t1{ r}__at_sum)dnl
_ins({LABEL }__L_atnoneg)dnl
define({_fp_}__at_sum,_FP_DIGITS)__at_sum})dnl
; ---- m4-side asin(x) = atan(x / sqrt(1 - x^2)) ----
; Special case: |x| >= S → return sign(x)*pi/2
define({_emit_asin},{dnl
define({__as_S},_alloc)dnl
define({__as_pih},_alloc)dnl
define({__as_neg},_alloc)dnl
define({__as_zero},_alloc)dnl
define({__as_x},_alloc)dnl
define({__as_res},_alloc)dnl
define({__as_t1},_alloc)dnl
define({__as_t2},_alloc)dnl
define({__as_t3},_alloc)dnl
define({__as_t4},_alloc)dnl
define({__L_ascomp},_gensym)dnl
define({__L_asdone},_gensym)dnl
define({__L_asnoneg},_gensym)dnl
_ins({SET r}__as_S{ _FP_SCALE})dnl
_ins({SET r}__as_pih{ 1570796326794896619})dnl
_ins({SET r}__as_zero{ 0})dnl
_ins({ISNEG r$1 r}__as_neg)dnl
_ins({ABS r$1 r}__as_x)dnl
_ins({CMP r}__as_x{ r}__as_S)dnl
_ins({BLT }__L_ascomp)dnl
_ins({COPY r}__as_pih{ r}__as_res)dnl
_ins({JMP }__L_asdone)dnl
_ins({LABEL }__L_ascomp)dnl
_ins({MUL r}__as_x{ r}__as_x{ r}__as_t1)dnl
_ins({DIV r}__as_t1{ r}__as_S{ r}__as_t2{ r}__as_t3)dnl
_ins({SUB r}__as_S{ r}__as_t2{ r}__as_t1)dnl
define({__as_sq},_emit_sqrt(__as_t1))dnl
_ins({MUL r}__as_x{ r}__as_S{ r}__as_t1)dnl
_ins({DIV r}__as_t1{ r}__as_sq{ r}__as_t2{ r}__as_t3)dnl
define({__as_at},_emit_atan(__as_t2))dnl
_ins({COPY r}__as_at{ r}__as_res)dnl
_ins({LABEL }__L_asdone)dnl
_ins({CMP r}__as_neg{ r}__as_zero)dnl
_ins({BLE }__L_asnoneg)dnl
_ins({NEG r}__as_res{ r}__as_t1)dnl
_ins({COPY r}__as_t1{ r}__as_res)dnl
_ins({LABEL }__L_asnoneg)dnl
define({_fp_}__as_res,_FP_DIGITS)__as_res})dnl
; ---- m4-side acos(x) = pi/2 - asin(x) ----
define({_emit_acos},{dnl
define({__ac_pih},_alloc)dnl
define({__ac_t1},_alloc)dnl
_ins({SET r}__ac_pih{ 1570796326794896619})dnl
define({__ac_as},_emit_asin($1))dnl
_ins({SUB r}__ac_pih{ r}__ac_as{ r}__ac_t1)dnl
define({_fp_}__ac_t1,_FP_DIGITS)__ac_t1})dnl
; ---- m4-side log10(x) = ln(x) / ln(10), log2(x) = ln(x) / ln(2) ----
define({_emit_log10},{dnl
define({__l10_S},_alloc)dnl
define({__l10_t1},_alloc)dnl
define({__l10_t2},_alloc)dnl
define({__l10_t3},_alloc)dnl
_ins({SET r}__l10_S{ _FP_SCALE})dnl
define({__l10_num},_emit_ln($1))dnl
_ins({SET r}__l10_t1{ 2302585092994045684})dnl
_ins({MUL r}__l10_num{ r}__l10_S{ r}__l10_t2)dnl
_ins({DIV r}__l10_t2{ r}__l10_t1{ r}__l10_t3{ r}__l10_t2)dnl
define({_fp_}__l10_t3,_FP_DIGITS)__l10_t3})dnl
define({_emit_log2},{dnl
define({__l2_S},_alloc)dnl
define({__l2_t1},_alloc)dnl
define({__l2_t2},_alloc)dnl
define({__l2_t3},_alloc)dnl
_ins({SET r}__l2_S{ _FP_SCALE})dnl
define({__l2_num},_emit_ln($1))dnl
_ins({SET r}__l2_t1{ 693147180559945309})dnl
_ins({MUL r}__l2_num{ r}__l2_S{ r}__l2_t2)dnl
_ins({DIV r}__l2_t2{ r}__l2_t1{ r}__l2_t3{ r}__l2_t2)dnl
define({_fp_}__l2_t3,_FP_DIGITS)__l2_t3})dnl
; ---- m4-side gamma(z) — reflection formula for z<0 ----
; Γ(z) = π / (sin(πz) · Γ(1-z))  when z < 0
define({_emit_gamma},{dnl
define({__gr_S},_alloc)dnl
define({__gr_zero},_alloc)dnl
define({__gr_one},_alloc)dnl
define({__gr_pi},_alloc)dnl
define({__gr_z1},_alloc)dnl
define({__gr_pz},_alloc)dnl
define({__gr_t1},_alloc)dnl
define({__gr_t2},_alloc)dnl
define({__gr_t3},_alloc)dnl
define({__L_gpos},_gensym)dnl
define({__L_gdone},_gensym)dnl
_ins({SET r}__gr_S{ _FP_SCALE})dnl
_ins({SET r}__gr_zero{ 0})dnl
_ins({SET r}__gr_one{ _FP_SCALE})dnl
_ins({SET r}__gr_pi{ 3141592653589793238})dnl
_ins({CMP r$1 r}__gr_zero)dnl
_ins({BGE }__L_gpos)dnl
_ins({SUB r}__gr_one{ r$1 r}__gr_z1)dnl
define({__gr_gpos},_emit_gamma_pos(__gr_z1))dnl
_ins({MUL r$1 r}__gr_pi{ r}__gr_t1)dnl
_ins({DIV r}__gr_t1{ r}__gr_S{ r}__gr_pz{ r}__gr_t2)dnl
define({__gr_sinpz},_emit_sin(__gr_pz))dnl
_ins({MUL r}__gr_sinpz{ r}__gr_gpos{ r}__gr_t1)dnl
_ins({DIV r}__gr_t1{ r}__gr_S{ r}__gr_t2{ r}__gr_t3)dnl
_ins({MUL r}__gr_pi{ r}__gr_S{ r}__gr_t1)dnl
_ins({DIV r}__gr_t1{ r}__gr_t2{ r}__gr_t3{ r}__gr_z1)dnl
define({_fp_}__gr_t3,_FP_DIGITS)dnl
_ins({JMP }__L_gdone)dnl
_ins({LABEL }__L_gpos)dnl
define({__gr_direct},_emit_gamma_pos($1))dnl
_ins({COPY r}__gr_direct{ r}__gr_t3)dnl
_ins({LABEL }__L_gdone)dnl
__gr_t3})dnl
; ---- m4-side gamma(z) via Stirling with shift-up (positive z only) ----
; For z < 20: shift up via Gamma(z) = Gamma(z+n) / (z*(z+1)*...*(z+n-1))
; Then lnG = (z-0.5)*ln(z) - z + 0.5*ln(2pi) + correction
; Correction = (1/z)[1/12 - w(1/360 - w(1/1260 - w/1680))] where w=1/z²
; Result = exp(lnG) / product
define({_emit_gamma_pos},{dnl
define({__gm_S},_alloc)dnl
define({__gm_z},_alloc)dnl
define({__gm_prod},_alloc)dnl
define({__gm_thr},_alloc)dnl
define({__gm_one},_alloc)dnl
define({__gm_half},_alloc)dnl
define({__gm_hln2pi},_alloc)dnl
define({__gm_S2},_alloc)dnl
define({__gm_inv_z},_alloc)dnl
define({__gm_w},_alloc)dnl
define({__gm_p},_alloc)dnl
define({__gm_lnG},_alloc)dnl
define({__gm_t1},_alloc)dnl
define({__gm_t2},_alloc)dnl
define({__gm_t3},_alloc)dnl
define({__gm_t4},_alloc)dnl
define({__L_gs},_gensym)dnl
define({__L_gst},_gensym)dnl
_ins({SET r}__gm_S{ _FP_SCALE})dnl
_ins({SET r}__gm_thr{ 20000000000000000000})dnl
_ins({SET r}__gm_one{ _FP_SCALE})dnl
_ins({SET r}__gm_half{ 500000000000000000})dnl
_ins({SET r}__gm_hln2pi{ 918938533204672741})dnl
_ins({COPY r$1 r}__gm_z)dnl
_ins({COPY r}__gm_one{ r}__gm_prod)dnl
_ins({LABEL }__L_gs)dnl
_ins({CMP r}__gm_z{ r}__gm_thr)dnl
_ins({BGE }__L_gst)dnl
_ins({MUL r}__gm_prod{ r}__gm_z{ r}__gm_t1)dnl
_ins({DIV r}__gm_t1{ r}__gm_S{ r}__gm_t2{ r}__gm_t3)dnl
_ins({COPY r}__gm_t2{ r}__gm_prod)dnl
_ins({ADD r}__gm_z{ r}__gm_one{ r}__gm_t1)dnl
_ins({COPY r}__gm_t1{ r}__gm_z)dnl
_ins({JMP }__L_gs)dnl
_ins({LABEL }__L_gst)dnl
define({__gm_lnz},_emit_ln(__gm_z))dnl
_ins({SUB r}__gm_z{ r}__gm_half{ r}__gm_t1)dnl
_ins({MUL r}__gm_t1{ r}__gm_lnz{ r}__gm_t2)dnl
_ins({DIV r}__gm_t2{ r}__gm_S{ r}__gm_t1{ r}__gm_t3)dnl
_ins({SUB r}__gm_t1{ r}__gm_z{ r}__gm_t2)dnl
_ins({ADD r}__gm_t2{ r}__gm_hln2pi{ r}__gm_lnG)dnl
_ins({MUL r}__gm_S{ r}__gm_S{ r}__gm_S2)dnl
_ins({DIV r}__gm_S2{ r}__gm_z{ r}__gm_inv_z{ r}__gm_t3)dnl
_ins({MUL r}__gm_inv_z{ r}__gm_inv_z{ r}__gm_t1)dnl
_ins({DIV r}__gm_t1{ r}__gm_S{ r}__gm_w{ r}__gm_t3)dnl
_ins({SDIV r}__gm_S{ 1680 r}__gm_p)dnl
_ins({MUL r}__gm_w{ r}__gm_p{ r}__gm_t1)dnl
_ins({DIV r}__gm_t1{ r}__gm_S{ r}__gm_t2{ r}__gm_t3)dnl
_ins({SDIV r}__gm_S{ 1260 r}__gm_t4)dnl
_ins({SUB r}__gm_t4{ r}__gm_t2{ r}__gm_p)dnl
_ins({MUL r}__gm_w{ r}__gm_p{ r}__gm_t1)dnl
_ins({DIV r}__gm_t1{ r}__gm_S{ r}__gm_t2{ r}__gm_t3)dnl
_ins({SDIV r}__gm_S{ 360 r}__gm_t4)dnl
_ins({SUB r}__gm_t4{ r}__gm_t2{ r}__gm_p)dnl
_ins({MUL r}__gm_w{ r}__gm_p{ r}__gm_t1)dnl
_ins({DIV r}__gm_t1{ r}__gm_S{ r}__gm_t2{ r}__gm_t3)dnl
_ins({SDIV r}__gm_S{ 12 r}__gm_t4)dnl
_ins({SUB r}__gm_t4{ r}__gm_t2{ r}__gm_p)dnl
_ins({MUL r}__gm_p{ r}__gm_inv_z{ r}__gm_t1)dnl
_ins({DIV r}__gm_t1{ r}__gm_S{ r}__gm_t2{ r}__gm_t3)dnl
_ins({ADD r}__gm_lnG{ r}__gm_t2{ r}__gm_t1)dnl
_ins({COPY r}__gm_t1{ r}__gm_lnG)dnl
define({__gm_expres},_emit_exp(__gm_lnG))dnl
_ins({MUL r}__gm_expres{ r}__gm_S{ r}__gm_t1)dnl
_ins({DIV r}__gm_t1{ r}__gm_prod{ r}__gm_t2{ r}__gm_t3)dnl
define({_fp_}__gm_t2,_FP_DIGITS)__gm_t2})dnl
; ---- m4-side hyperbolic functions ----
; sinh(x) = (exp(x) - exp(-x)) / 2
define({_emit_sinh},{dnl
define({__sh_neg},_alloc)dnl
define({__sh_t1},_alloc)dnl
define({__sh_t2},_alloc)dnl
define({__sh_t3},_alloc)dnl
_ins({NEG r$1 r}__sh_neg)dnl
define({__sh_ep},_emit_exp($1))dnl
define({__sh_en},_emit_exp(__sh_neg))dnl
_ins({SUB r}__sh_ep{ r}__sh_en{ r}__sh_t1)dnl
_ins({SDIV r}__sh_t1{ 2 r}__sh_t2)dnl
define({_fp_}__sh_t2,_FP_DIGITS)__sh_t2})dnl
; cosh(x) = (exp(x) + exp(-x)) / 2
define({_emit_cosh},{dnl
define({__ch_neg},_alloc)dnl
define({__ch_t1},_alloc)dnl
define({__ch_t2},_alloc)dnl
_ins({NEG r$1 r}__ch_neg)dnl
define({__ch_ep},_emit_exp($1))dnl
define({__ch_en},_emit_exp(__ch_neg))dnl
_ins({ADD r}__ch_ep{ r}__ch_en{ r}__ch_t1)dnl
_ins({SDIV r}__ch_t1{ 2 r}__ch_t2)dnl
define({_fp_}__ch_t2,_FP_DIGITS)__ch_t2})dnl
; tanh(x) = (e^2x - S) / (e^2x + S) — single exp call
define({_emit_tanh},{dnl
define({__th_S},_alloc)dnl
define({__th_2x},_alloc)dnl
define({__th_t1},_alloc)dnl
define({__th_t2},_alloc)dnl
define({__th_t3},_alloc)dnl
define({__th_num},_alloc)dnl
define({__th_den},_alloc)dnl
_ins({SET r}__th_S{ _FP_SCALE})dnl
_ins({SMUL r$1 2 r}__th_2x)dnl
define({__th_e2x},_emit_exp(__th_2x))dnl
_ins({SUB r}__th_e2x{ r}__th_S{ r}__th_num)dnl
_ins({ADD r}__th_e2x{ r}__th_S{ r}__th_den)dnl
_ins({MUL r}__th_num{ r}__th_S{ r}__th_t1)dnl
_ins({DIV r}__th_t1{ r}__th_den{ r}__th_t2{ r}__th_t3)dnl
define({_fp_}__th_t2,_FP_DIGITS)__th_t2})dnl
; atanh(x) = ln((S + x) / (S - x)) / 2  [|x| < S]
define({_emit_atanh},{dnl
define({__ah_S},_alloc)dnl
define({__ah_num},_alloc)dnl
define({__ah_den},_alloc)dnl
define({__ah_t1},_alloc)dnl
define({__ah_t2},_alloc)dnl
define({__ah_t3},_alloc)dnl
_ins({SET r}__ah_S{ _FP_SCALE})dnl
_ins({ADD r}__ah_S{ r$1 r}__ah_num)dnl
_ins({SUB r}__ah_S{ r$1 r}__ah_den)dnl
_ins({MUL r}__ah_num{ r}__ah_S{ r}__ah_t1)dnl
_ins({DIV r}__ah_t1{ r}__ah_den{ r}__ah_t2{ r}__ah_t3)dnl
define({__ah_ln},_emit_ln(__ah_t2))dnl
_ins({SDIV r}__ah_ln{ 2 r}__ah_t1)dnl
define({_fp_}__ah_t1,_FP_DIGITS)__ah_t1})dnl
; ---- erf(x) — Gaussian error function ----
; erf(x) = (2/sqrt(pi)) * sum_{n=0}^{N} (-1)^n * x^(2n+1) / (n! * (2n+1))
; For |x| > 4, erf(x) ≈ ±1 (clamp)
define({_emit_erf},{dnl
define({__ef_S},_alloc)dnl
define({__ef_x},_alloc)dnl
define({__ef_x2},_alloc)dnl
define({__ef_term},_alloc)dnl
define({__ef_sum},_alloc)dnl
define({__ef_t1},_alloc)dnl
define({__ef_t2},_alloc)dnl
define({__ef_t3},_alloc)dnl
define({__ef_t4},_alloc)dnl
define({__ef_sign},_alloc)dnl
define({__ef_abs},_alloc)dnl
define({__ef_thr},_alloc)dnl
define({__ef_one},_alloc)dnl
define({__ef_neg1},_alloc)dnl
define({__ef_2sqrtpi},_alloc)dnl
define({__ef_lbl_pos},_gensym)dnl
define({__ef_lbl_body},_gensym)dnl
define({__ef_lbl_done},_gensym)dnl
define({__ef_lbl_clamp},_gensym)dnl
_ins({SET r}__ef_S{ _FP_SCALE})dnl
_ins({COPY r$1 r}__ef_x)dnl
_ins({ABS r}__ef_x{ r}__ef_abs)dnl
_ins({SET r}__ef_thr{ 3500000000000000000})dnl
_ins({SET r}__ef_one{ _FP_SCALE})dnl
_ins({SET r}__ef_neg1{ _FP_SCALE})dnl
_ins({NEG r}__ef_neg1{ r}__ef_neg1)dnl
_ins({CMP r}__ef_abs{ r}__ef_thr)dnl
_ins({BLE }__ef_lbl_body)dnl
_ins({SET r}__ef_t1{ 0})dnl
_ins({CMP r}__ef_x{ r}__ef_t1)dnl
_ins({BGE }__ef_lbl_pos)dnl
_ins({COPY r}__ef_neg1{ r}__ef_t4)dnl
_ins({JMP }__ef_lbl_done)dnl
_ins({LABEL }__ef_lbl_pos)dnl
_ins({COPY r}__ef_one{ r}__ef_t4)dnl
_ins({JMP }__ef_lbl_done)dnl
_ins({LABEL }__ef_lbl_body)dnl
_ins({MUL r}__ef_x{ r}__ef_x{ r}__ef_t1)dnl
_ins({DIV r}__ef_t1{ r}__ef_S{ r}__ef_x2{ r}__ef_t2)dnl
_ins({COPY r}__ef_x{ r}__ef_term)dnl
_ins({COPY r}__ef_x{ r}__ef_sum)dnl
_emit_erf_terms(1,40)dnl
_ins({SET r}__ef_2sqrtpi{ 1128379167095512574})dnl
_ins({MUL r}__ef_sum{ r}__ef_2sqrtpi{ r}__ef_t1)dnl
_ins({DIV r}__ef_t1{ r}__ef_S{ r}__ef_t4{ r}__ef_t2)dnl
_ins({LABEL }__ef_lbl_done)dnl
define({_fp_}__ef_t4,_FP_DIGITS)__ef_t4})dnl
; helper: unroll erf Taylor terms
define({_emit_erf_terms},{ifelse(eval($1>$2),1,{},{dnl
_ins({NEG r}__ef_term{ r}__ef_t1)dnl
_ins({MUL r}__ef_t1{ r}__ef_x2{ r}__ef_t2)dnl
_ins({DIV r}__ef_t2{ r}__ef_S{ r}__ef_t1{ r}__ef_t3)dnl
_ins({SDIV r}__ef_t1{ $1 r}__ef_term)dnl
_ins({SDIV r}__ef_term{ eval(2*$1+1) r}__ef_t1)dnl
_ins({ADD r}__ef_sum{ r}__ef_t1{ r}__ef_sum)dnl
_emit_erf_terms(eval($1+1),$2)})})dnl
; ---- Ei(x) — exponential integral ----
; Ei(x) = γ + ln|x| + Σ_{n=1}^{40} x^n / (n·n!)
define({_emit_ei},{dnl
define({__ei_S},_alloc)dnl
define({__ei_gamma},_alloc)dnl
define({__ei_x},_alloc)dnl
define({__ei_t1},_alloc)dnl
define({__ei_t2},_alloc)dnl
define({__ei_term},_alloc)dnl
define({__ei_sum},_alloc)dnl
define({__ei_abs},_alloc)dnl
_ins({SET r}__ei_S{ _FP_SCALE})dnl
_ins({SET r}__ei_gamma{ 577215664901532861})dnl
_ins({COPY r$1 r}__ei_x)dnl
_ins({ABS r}__ei_x{ r}__ei_abs)dnl
define({__ei_lnabs},_emit_ln(__ei_abs))dnl
_ins({ADD r}__ei_gamma{ r}__ei_lnabs{ r}__ei_sum)dnl
_ins({COPY r}__ei_x{ r}__ei_term)dnl
_emit_ei_terms(1,40)dnl
define({_fp_}__ei_sum,_FP_DIGITS)__ei_sum})dnl
define({_emit_ei_terms},{ifelse(eval($1>$2),1,{},{dnl
_ins({SDIV r}__ei_term{ $1 r}__ei_t1)dnl
_ins({ADD r}__ei_sum{ r}__ei_t1{ r}__ei_sum)dnl
_ins({MUL r}__ei_term{ r}__ei_x{ r}__ei_t1)dnl
_ins({DIV r}__ei_t1{ r}__ei_S{ r}__ei_term{ r}__ei_t2)dnl
_ins({SDIV r}__ei_term{ eval($1+1) r}__ei_term)dnl
_emit_ei_terms(eval($1+1),$2)})})dnl
; ---- W(x) — Lambert W function (principal branch) ----
; Newton: w = w - (w*exp(w) - x) / (exp(w)*(w+1))
; 30 iterations, initial guess w0 = ln(1+x)
define({_emit_lambertw},{dnl
define({__lw_S},_alloc)dnl
define({__lw_w},_alloc)dnl
define({__lw_x},_alloc)dnl
define({__lw_one},_alloc)dnl
define({__lw_t1},_alloc)dnl
define({__lw_t2},_alloc)dnl
define({__lw_t3},_alloc)dnl
define({__lw_t4},_alloc)dnl
define({__lw_ew},_alloc)dnl
define({__lw_cnt},_alloc)dnl
define({__lw_lim},_alloc)dnl
define({__lw_lbl_top},_gensym)dnl
define({__lw_lbl_done},_gensym)dnl
_ins({SET r}__lw_S{ _FP_SCALE})dnl
_ins({SET r}__lw_one{ _FP_SCALE})dnl
_ins({COPY r$1 r}__lw_x)dnl
_ins({ADD r}__lw_x{ r}__lw_one{ r}__lw_t1)dnl
define({__lw_init},_emit_ln(__lw_t1))dnl
_ins({COPY r}__lw_init{ r}__lw_w)dnl
_ins({SET r}__lw_cnt{ 0})dnl
_ins({SET r}__lw_lim{ 20})dnl
_ins({LABEL }__lw_lbl_top)dnl
_ins({CMP r}__lw_cnt{ r}__lw_lim)dnl
_ins({BGE }__lw_lbl_done)dnl
define({__lw_expw},_emit_exp(__lw_w))dnl
_ins({COPY r}__lw_expw{ r}__lw_ew)dnl
_ins({MUL r}__lw_w{ r}__lw_ew{ r}__lw_t1)dnl
_ins({DIV r}__lw_t1{ r}__lw_S{ r}__lw_t2{ r}__lw_t3)dnl
_ins({SUB r}__lw_t2{ r}__lw_x{ r}__lw_t1)dnl
_ins({ADD r}__lw_w{ r}__lw_one{ r}__lw_t2)dnl
_ins({MUL r}__lw_ew{ r}__lw_t2{ r}__lw_t3)dnl
_ins({DIV r}__lw_t3{ r}__lw_S{ r}__lw_t2{ r}__lw_t4)dnl
_ins({MUL r}__lw_t1{ r}__lw_S{ r}__lw_t3)dnl
_ins({DIV r}__lw_t3{ r}__lw_t2{ r}__lw_t4{ r}__lw_t1)dnl
_ins({SUB r}__lw_w{ r}__lw_t4{ r}__lw_w)dnl
_ins({SET r}__lw_t1{ 1})dnl
_ins({ADD r}__lw_cnt{ r}__lw_t1{ r}__lw_cnt)dnl
_ins({JMP }__lw_lbl_top)dnl
_ins({LABEL }__lw_lbl_done)dnl
define({_fp_}__lw_w,_FP_DIGITS)__lw_w})dnl
; ---- zeta(s) — Riemann zeta for real s > 1 ----
; Direct sum Σ_{k=1}^{N} 1/k^s + Euler-Maclaurin correction:
; + N^{1-s}/(s-1) + 1/(2·N^s) + s/(12·N^{s+1})
define({_emit_zeta},{dnl
define({__z_S},_alloc)dnl
define({__z_s},_alloc)dnl
define({__z_one},_alloc)dnl
define({__z_k},_alloc)dnl
define({__z_kfp},_alloc)dnl
define({__z_sum},_alloc)dnl
define({__z_lim},_alloc)dnl
define({__z_t1},_alloc)dnl
define({__z_t2},_alloc)dnl
define({__z_t3},_alloc)dnl
define({__z_t4},_alloc)dnl
define({__z_ks},_alloc)dnl
define({__z_lbl_top},_gensym)dnl
define({__z_lbl_done},_gensym)dnl
_ins({SET r}__z_S{ _FP_SCALE})dnl
_ins({COPY r$1 r}__z_s)dnl
_ins({SET r}__z_one{ _FP_SCALE})dnl
_ins({SET r}__z_sum{ 0})dnl
_ins({SET r}__z_k{ 1})dnl
_ins({SET r}__z_lim{ 200})dnl
_ins({LABEL }__z_lbl_top)dnl
_ins({CMP r}__z_k{ r}__z_lim)dnl
_ins({BGT }__z_lbl_done)dnl
_ins({MUL r}__z_k{ r}__z_S{ r}__z_kfp)dnl
define({__z_lnk},_emit_ln(__z_kfp))dnl
_ins({MUL r}__z_s{ r}__z_lnk{ r}__z_t1)dnl
_ins({DIV r}__z_t1{ r}__z_S{ r}__z_t2{ r}__z_t3)dnl
define({__z_expslnk},_emit_exp(__z_t2))dnl
_ins({COPY r}__z_expslnk{ r}__z_ks)dnl
_ins({MUL r}__z_S{ r}__z_S{ r}__z_t1)dnl
_ins({DIV r}__z_t1{ r}__z_ks{ r}__z_t2{ r}__z_t3)dnl
_ins({ADD r}__z_sum{ r}__z_t2{ r}__z_sum)dnl
_ins({SET r}__z_t1{ 1})dnl
_ins({ADD r}__z_k{ r}__z_t1{ r}__z_k)dnl
_ins({JMP }__z_lbl_top)dnl
_ins({LABEL }__z_lbl_done)dnl
_ins({SUB r}__z_s{ r}__z_one{ r}__z_t1)dnl
define({__z_Nfp},_alloc)dnl
_ins({SET r}__z_Nfp{ 200000000000000000000})dnl
define({__z_lnN},_emit_ln(__z_Nfp))dnl
_ins({MUL r}__z_t1{ r}__z_lnN{ r}__z_t2)dnl
_ins({DIV r}__z_t2{ r}__z_S{ r}__z_t3{ r}__z_t4)dnl
_ins({NEG r}__z_t3{ r}__z_t2)dnl
define({__z_N1ms},_emit_exp(__z_t2))dnl
_ins({SUB r}__z_s{ r}__z_one{ r}__z_t1)dnl
_ins({MUL r}__z_S{ r}__z_S{ r}__z_t2)dnl
_ins({DIV r}__z_t2{ r}__z_t1{ r}__z_t3{ r}__z_t4)dnl
_ins({MUL r}__z_N1ms{ r}__z_t3{ r}__z_t1)dnl
_ins({DIV r}__z_t1{ r}__z_S{ r}__z_t2{ r}__z_t3)dnl
_ins({ADD r}__z_sum{ r}__z_t2{ r}__z_sum)dnl
_ins({MUL r}__z_S{ r}__z_S{ r}__z_t1)dnl
_ins({SDIV r}__z_ks{ 2 r}__z_t2)dnl
_ins({MUL r}__z_S{ r}__z_S{ r}__z_t1)dnl
_ins({DIV r}__z_t1{ r}__z_t2{ r}__z_t3{ r}__z_t4)dnl
_ins({ADD r}__z_sum{ r}__z_t3{ r}__z_sum)dnl
define({_fp_}__z_sum,_FP_DIGITS)__z_sum})dnl
; ---- eta(s) — Dirichlet eta: η(s) = (1 - 2^(1-s)) · ζ(s) ----
define({_emit_eta},{dnl
define({__eta_S},_alloc)dnl
define({__eta_one},_alloc)dnl
define({__eta_t1},_alloc)dnl
define({__eta_t2},_alloc)dnl
define({__eta_t3},_alloc)dnl
_ins({SET r}__eta_S{ _FP_SCALE})dnl
_ins({SET r}__eta_one{ _FP_SCALE})dnl
define({__eta_zeta},_emit_zeta($1))dnl
_ins({SUB r}__eta_one{ r$1 r}__eta_t1)dnl
define({__eta_ln2},_alloc)dnl
_ins({SET r}__eta_ln2{ 693147180559945309})dnl
_ins({MUL r}__eta_t1{ r}__eta_ln2{ r}__eta_t2)dnl
_ins({DIV r}__eta_t2{ r}__eta_S{ r}__eta_t3{ r}__eta_t1)dnl
define({__eta_exp},_emit_exp(__eta_t3))dnl
_ins({SUB r}__eta_one{ r}__eta_exp{ r}__eta_t1)dnl
_ins({MUL r}__eta_zeta{ r}__eta_t1{ r}__eta_t2)dnl
_ins({DIV r}__eta_t2{ r}__eta_S{ r}__eta_t3{ r}__eta_t1)dnl
define({_fp_}__eta_t3,_FP_DIGITS)__eta_t3})dnl
; ---- Li(x) — logarithmic integral: Li(x) = Ei(ln(x)) ----
define({_emit_li},{dnl
define({__li_ln},_emit_ln($1))dnl
_emit_ei(__li_ln)})dnl
; ---- phi(x) — normal CDF: Φ(x) = 0.5 * (1 + erf(x/√2)) ----
define({_emit_phi},{dnl
define({__ph_S},_alloc)dnl
define({__ph_sqrt2},_alloc)dnl
define({__ph_t1},_alloc)dnl
define({__ph_t2},_alloc)dnl
define({__ph_t3},_alloc)dnl
define({__ph_half},_alloc)dnl
_ins({SET r}__ph_S{ _FP_SCALE})dnl
_ins({SET r}__ph_sqrt2{ 1414213562373095048})dnl
_ins({MUL r$1 r}__ph_S{ r}__ph_t1)dnl
_ins({DIV r}__ph_t1{ r}__ph_sqrt2{ r}__ph_t2{ r}__ph_t3)dnl
define({__ph_erf},_emit_erf(__ph_t2))dnl
_ins({ADD r}__ph_erf{ r}__ph_S{ r}__ph_t1)dnl
_ins({SDIV r}__ph_t1{ 2 r}__ph_t2)dnl
define({_fp_}__ph_t2,_FP_DIGITS)__ph_t2})dnl
; ---- beta(a,b) = Γ(a)·Γ(b) / Γ(a+b) ----
define({_emit_beta},{dnl
define({__bt_arg1},{$1})dnl
define({__bt_arg2},{$2})dnl
define({__bt_a},ifelse(_isfp(__bt_arg1),1,{__bt_arg1},{_scale_up(__bt_arg1)}))dnl
define({__bt_b},ifelse(_isfp(__bt_arg2),1,{__bt_arg2},{_scale_up(__bt_arg2)}))dnl
define({__bt_t1},_alloc)dnl
define({__bt_t2},_alloc)dnl
define({__bt_t3},_alloc)dnl
define({__bt_t4},_alloc)dnl
define({__bt_S},_alloc)dnl
_ins({SET r}__bt_S{ _FP_SCALE})dnl
_ins({ADD r}__bt_a{ r}__bt_b{ r}__bt_t1)dnl
define({__bt_ga},_emit_gamma(__bt_a))dnl
define({__bt_gb},_emit_gamma(__bt_b))dnl
define({__bt_gab},_emit_gamma(__bt_t1))dnl
_ins({MUL r}__bt_ga{ r}__bt_gb{ r}__bt_t1)dnl
_ins({DIV r}__bt_t1{ r}__bt_S{ r}__bt_t2{ r}__bt_t3)dnl
_ins({MUL r}__bt_t2{ r}__bt_S{ r}__bt_t1)dnl
_ins({DIV r}__bt_t1{ r}__bt_gab{ r}__bt_t4{ r}__bt_t3)dnl
define({_fp_}__bt_t4,_FP_DIGITS)__bt_t4})dnl
; ---- gcd(a,b) — Euclidean algorithm ----
define({_emit_gcd},{dnl
define({__gcd_a},{$1})define({__gcd_b},{$2})dnl
define({__gcd_oldb},_alloc)define({__gcd_q},_alloc)define({__gcd_r},_alloc)dnl
define({__gcd_zero},_emit_set({0}))dnl
define({__gcd_loop},_gensym)define({__gcd_done},_gensym)dnl
_ins({LABEL }__gcd_loop)dnl
_ins({CMP r}__gcd_b{ r}__gcd_zero)dnl
_ins({BEQ }__gcd_done)dnl
_ins({COPY r}__gcd_b{ r}__gcd_oldb)dnl
_ins({DIV r}__gcd_a{ r}__gcd_b{ r}__gcd_q{ r}__gcd_r)dnl
_ins({COPY r}__gcd_oldb{ r}__gcd_a)dnl
_ins({COPY r}__gcd_r{ r}__gcd_b)dnl
_ins({JMP }__gcd_loop)dnl
_ins({LABEL }__gcd_done)dnl
__gcd_a})dnl
; ---- lcm(a,b) = a*b/gcd(a,b) ----
define({_emit_lcm},{dnl
define({__lcm_sa},_alloc)define({__lcm_sb},_alloc)dnl
_ins({COPY r$1 r}__lcm_sa)dnl
_ins({COPY r$2 r}__lcm_sb)dnl
define({__lcm_prod},_alloc)define({__lcm_q},_alloc)define({__lcm_r},_alloc)dnl
_ins({MUL r}__lcm_sa{ r}__lcm_sb{ r}__lcm_prod)dnl
define({__lcm_g},_emit_gcd({$1},{$2}))dnl
_ins({DIV r}__lcm_prod{ r}__lcm_g{ r}__lcm_q{ r}__lcm_r)dnl
__lcm_q})dnl
; ---- modinv(a,m) — extended Euclidean algorithm ----
; Returns x such that a*x ≡ 1 (mod m), or 0 if no inverse
define({_emit_modinv},{dnl
define({__mi_a},{$1})define({__mi_m},{$2})dnl
define({__mi_r},_alloc)define({__mi_newr},_alloc)dnl
define({__mi_t},_alloc)define({__mi_newt},_alloc)dnl
define({__mi_q},_alloc)define({__mi_tmp},_alloc)define({__mi_tmp2},_alloc)dnl
define({__mi_zero},_emit_set({0}))define({__mi_one},_emit_set({1}))dnl
define({__mi_loop},_gensym)define({__mi_done},_gensym)dnl
define({__mi_noinv},_gensym)define({__mi_fixneg},_gensym)define({__mi_end},_gensym)dnl
_ins({COPY r}__mi_m{ r}__mi_r)dnl
_ins({COPY r}__mi_a{ r}__mi_newr)dnl
_ins({COPY r}__mi_zero{ r}__mi_t)dnl
_ins({COPY r}__mi_one{ r}__mi_newt)dnl
_ins({LABEL }__mi_loop)dnl
_ins({CMP r}__mi_newr{ r}__mi_zero)dnl
_ins({BEQ }__mi_done)dnl
_ins({DIV r}__mi_r{ r}__mi_newr{ r}__mi_q{ r}__mi_tmp)dnl
_ins({COPY r}__mi_newt{ r}__mi_tmp2)dnl
_ins({MUL r}__mi_q{ r}__mi_newt{ r}__mi_tmp)dnl
_ins({SUB r}__mi_t{ r}__mi_tmp{ r}__mi_newt)dnl
_ins({COPY r}__mi_tmp2{ r}__mi_t)dnl
_ins({COPY r}__mi_newr{ r}__mi_tmp2)dnl
_ins({DIV r}__mi_r{ r}__mi_newr{ r}__mi_q{ r}__mi_tmp)dnl
_ins({COPY r}__mi_tmp2{ r}__mi_r)dnl
_ins({COPY r}__mi_tmp{ r}__mi_newr)dnl
_ins({JMP }__mi_loop)dnl
_ins({LABEL }__mi_done)dnl
_ins({CMP r}__mi_r{ r}__mi_one)dnl
_ins({BNE }__mi_noinv)dnl
_ins({CMPS r}__mi_t{ r}__mi_zero)dnl
_ins({BLT }__mi_fixneg)dnl
_ins({JMP }__mi_end)dnl
_ins({LABEL }__mi_fixneg)dnl
_ins({ADD r}__mi_t{ r}__mi_m{ r}__mi_t)dnl
_ins({JMP }__mi_end)dnl
_ins({LABEL }__mi_noinv)dnl
_ins({COPY r}__mi_zero{ r}__mi_t)dnl
_ins({LABEL }__mi_end)dnl
__mi_t})dnl
; ---- complex functions ----
; conj(z): negate imaginary part (complex), or negate i,j,k (quaternion), scalar passthrough
define({_emit_conj},{ifelse(_isquat({$1}),1,{_emit_qconj({$1})},_iscomplex({$1}),1,{define({__cj_r},_cR({$1}))define({__cj_ni},_alloc)_ins({NEG r}_cI({$1}){ r}__cj_ni)define({_fp_}__cj_ni,_FP_DIGITS)__cj_r:__cj_ni},{$1})})dnl
; cabs(z): sqrt(re² + im²) — returns scalar fp
define({_emit_cabs},{ifelse(_iscomplex({$1}),1,{dnl
define({__ca_S},_emit_set(_FP_SCALE))define({__ca_rem},_alloc)dnl
define({__ca_t1},_alloc)define({__ca_t2},_alloc)define({__ca_t3},_alloc)dnl
_ins({MUL r}_cR({$1}){ r}_cR({$1}){ r}__ca_t1)_ins({DIV r}__ca_t1{ r}__ca_S{ r}__ca_t1{ r}__ca_rem)dnl
_ins({MUL r}_cI({$1}){ r}_cI({$1}){ r}__ca_t2)_ins({DIV r}__ca_t2{ r}__ca_S{ r}__ca_t2{ r}__ca_rem)dnl
_ins({ADD r}__ca_t1{ r}__ca_t2{ r}__ca_t3)dnl
define({_fp_}__ca_t3,_FP_DIGITS)_emit_sqrt(__ca_t3)},_isquat({$1}),1,{dnl
define({__ca_n2},_emit_qnorm2({$1}))_emit_sqrt(__ca_n2)},{dnl
define({__ca_ar},_alloc)_ins({ABS r$1 r}__ca_ar)ifelse(_isfp($1),1,{define({_fp_}__ca_ar,_FP_DIGITS)})__ca_ar})})dnl
; carg(z): atan2(im, re) — returns scalar fp
; Full quadrant-aware: handles re=0, re<0 cases
define({_emit_carg},{ifelse(_iscomplex({$1}),1,{dnl
define({__cg_S},_emit_set(_FP_SCALE))define({__cg_rem},_alloc)dnl
define({__cg_zero},_emit_set(0))dnl
define({__cg_pi},_emit_set(3141592653589793238))define({_fp_}__cg_pi,_FP_DIGITS)dnl
define({__cg_hpi},_alloc)_ins({SDIV r}__cg_pi{ 2 r}__cg_hpi)define({_fp_}__cg_hpi,_FP_DIGITS)dnl
define({__cg_nhpi},_alloc)_ins({NEG r}__cg_hpi{ r}__cg_nhpi)define({_fp_}__cg_nhpi,_FP_DIGITS)dnl
define({__cg_result},_alloc)define({_fp_}__cg_result,_FP_DIGITS)dnl
define({__cg_t1},_alloc)define({__cg_t2},_alloc)dnl
define({__cg_lbl_xneg},_gensym)dnl
define({__cg_lbl_xzero},_gensym)dnl
define({__cg_lbl_done},_gensym)dnl
define({__cg_lbl_ypos},_gensym)dnl
define({__cg_lbl_xneg2},_gensym)dnl
_ins({CMPS r}_cR({$1}){ r}__cg_zero)dnl
_ins({BEQ }__cg_lbl_xzero)dnl
_ins({BLT }__cg_lbl_xneg)dnl
_ins({MUL r}_cI({$1}){ r}__cg_S{ r}__cg_t1)dnl
_ins({DIV r}__cg_t1{ r}_cR({$1}){ r}__cg_t2{ r}__cg_rem)dnl
define({_fp_}__cg_t2,_FP_DIGITS)dnl
define({__cg_atan_pos},_emit_atan(__cg_t2))dnl
_ins({COPY r}__cg_atan_pos{ r}__cg_result)dnl
_ins({JMP }__cg_lbl_done)dnl
_ins({LABEL }__cg_lbl_xzero)dnl
_ins({CMPS r}_cI({$1}){ r}__cg_zero)dnl
_ins({BGT }__cg_lbl_ypos)dnl
_ins({COPY r}__cg_nhpi{ r}__cg_result)dnl
_ins({JMP }__cg_lbl_done)dnl
_ins({LABEL }__cg_lbl_ypos)dnl
_ins({COPY r}__cg_hpi{ r}__cg_result)dnl
_ins({JMP }__cg_lbl_done)dnl
_ins({LABEL }__cg_lbl_xneg)dnl
_ins({MUL r}_cI({$1}){ r}__cg_S{ r}__cg_t1)dnl
_ins({DIV r}__cg_t1{ r}_cR({$1}){ r}__cg_t2{ r}__cg_rem)dnl
define({_fp_}__cg_t2,_FP_DIGITS)dnl
define({__cg_atan_neg},_emit_atan(__cg_t2))dnl
_ins({CMPS r}_cI({$1}){ r}__cg_zero)dnl
_ins({BLT }__cg_lbl_xneg2)dnl
_ins({ADD r}__cg_atan_neg{ r}__cg_pi{ r}__cg_result)dnl
_ins({JMP }__cg_lbl_done)dnl
_ins({LABEL }__cg_lbl_xneg2)dnl
_ins({SUB r}__cg_atan_neg{ r}__cg_pi{ r}__cg_result)dnl
_ins({LABEL }__cg_lbl_done)dnl
__cg_result},{dnl
_emit_set(0)})})dnl
; cexp(a+bi) = exp(a)*(cos(b) + i*sin(b))
define({_emit_cexp},{ifelse(_iscomplex({$1}),1,{dnl
define({__ce_ea},_emit_exp(_cR({$1})))dnl
define({__ce_cb},_emit_cos(_cI({$1})))dnl
define({__ce_sb},_emit_sin(_cI({$1})))dnl
define({__ce_S},_emit_set(_FP_SCALE))define({__ce_rem},_alloc)dnl
define({__ce_rr},_alloc)define({__ce_ri},_alloc)dnl
_ins({MUL r}__ce_ea{ r}__ce_cb{ r}__ce_rr)_ins({DIV r}__ce_rr{ r}__ce_S{ r}__ce_rr{ r}__ce_rem)dnl
_ins({MUL r}__ce_ea{ r}__ce_sb{ r}__ce_ri)_ins({DIV r}__ce_ri{ r}__ce_S{ r}__ce_ri{ r}__ce_rem)dnl
define({_fp_}__ce_rr,_FP_DIGITS)define({_fp_}__ce_ri,_FP_DIGITS)__ce_rr:__ce_ri},{_emit_exp({$1})})})dnl
; cln(a+bi) = ln|z| + i*atan2(b,a)
define({_emit_cln},{ifelse(_iscomplex({$1}),1,{dnl
define({__cl_abs},_emit_cabs({$1}))dnl
define({__cl_lnabs},_emit_ln(__cl_abs))dnl
define({__cl_arg},_emit_carg({$1}))dnl
__cl_lnabs:__cl_arg},{_emit_ln({$1})})})dnl
; csqrt(a+bi) = sqrt(|z|)*(cos(arg/2) + i*sin(arg/2))
define({_emit_csqrt},{ifelse(_iscomplex({$1}),1,{dnl
define({__cq_abs},_emit_cabs({$1}))dnl
define({__cq_sqrtabs},_emit_sqrt(__cq_abs))dnl
define({__cq_arg},_emit_carg({$1}))dnl
define({__cq_S},_emit_set(_FP_SCALE))define({__cq_rem},_alloc)dnl
define({__cq_half},_alloc)_ins({SET r}__cq_half{ 2})dnl
define({__cq_harg},_alloc)_ins({DIV r}__cq_arg{ r}__cq_half{ r}__cq_harg{ r}__cq_rem)dnl
define({_fp_}__cq_harg,_FP_DIGITS)dnl
define({__cq_c},_emit_cos(__cq_harg))dnl
define({__cq_s},_emit_sin(__cq_harg))dnl
define({__cq_rr},_alloc)define({__cq_ri},_alloc)dnl
_ins({MUL r}__cq_sqrtabs{ r}__cq_c{ r}__cq_rr)_ins({DIV r}__cq_rr{ r}__cq_S{ r}__cq_rr{ r}__cq_rem)dnl
_ins({MUL r}__cq_sqrtabs{ r}__cq_s{ r}__cq_ri)_ins({DIV r}__cq_ri{ r}__cq_S{ r}__cq_ri{ r}__cq_rem)dnl
define({_fp_}__cq_rr,_FP_DIGITS)define({_fp_}__cq_ri,_FP_DIGITS)__cq_rr:__cq_ri},{_emit_sqrt({$1})})})dnl
; ---- polymorphic function dispatch ----
; For functions that have complex variants, check type and dispatch
define({_emit_fn_poly},{ifelse(_iscomplex({$2}),1,{ifelse({$1},{exp},{_emit_cexp({$2})},{$1},{ln},{_emit_cln({$2})},{$1},{log},{_emit_cln({$2})},{$1},{sqrt},{_emit_csqrt({$2})},{$1},{conj},{_emit_conj({$2})},{$1},{abs},{_emit_cabs({$2})},{$1},{arg},{_emit_carg({$2})},{ERR:cfn})},_isquat({$2}),1,{ifelse({$1},{conj},{_emit_conj({$2})},{$1},{abs},{_emit_cabs({$2})},{ERR:qfn})},{_emit_fn_scalar({$1},{$2})})})dnl
; _postfix: atom '!'?
define({_postfix},{_pf2(_atom())})dnl
define({_pf2},{_skip()ifelse(_ch,{!},{_advance()_emit_op1(FACT,{$1})},{$1})})dnl
; _unary: '-'? postfix
define({_unary},{_skip()ifelse(_ch,{-},{_advance()_poly_neg(_unary())},_postfix())})dnl
; _power: unary ('^' power)? [right-assoc]
define({_power},{_pw_tail(_unary())})dnl
define({_pw_tail},{_skip()ifelse(_ch,{^},{_advance()_emit_op(POW,{$1},_power())},{$1})})dnl
; _term: power (('*'|'/'|'%') power)* [left-assoc]
define({_term},{_tm_rest(_power())})dnl
define({_tm_rest},{_skip()ifelse(_ch,{*},{_advance()_tm_rest(_poly_mul({$1},_power()))},_ch,{/},{_advance()_tm_rest(_poly_div({$1},_power()))},_ch,{%},{_advance()_tm_rest(_emit_mod({$1},_power()))},{$1})})dnl
; div emits: scale numerator by 10^15, integer DIV, mark result fp
define({_FP_DIGITS},18)dnl
define({_FP_SCALE},{1000000000000000000})dnl
define({_emit_div},{define({__rs},_alloc)_ins({SET r}__rs{ _FP_SCALE})define({__rp},_alloc)_ins({MUL r$1 r}__rs{ r}__rp)define({__rq},_alloc)define({__rr},_alloc)_ins({DIV r}__rp{ r$2 r}__rq{ r}__rr)define({_fp_}__rq,_FP_DIGITS)__rq})dnl
; mod is always integer
define({_emit_mod},{define({__rq},_alloc)define({__rr},_alloc)_ins({DIV r$1 r$2 r}__rq{ r}__rr)__rr})dnl
; _expr: term (('+' | '-') term)* [left-assoc]
define({_expr},{_ex_rest(_term())})dnl
define({_ex_rest},{_skip()ifelse(_ch,{+},{_advance()_ex_rest(_poly_add({$1},_term()))},_ch,{-},{_advance()_ex_rest(_poly_sub({$1},_term()))},{$1})})dnl
; ---- entry: translit parens, parse, dump ----
; ---- output: scalar, complex (a+bi), quaternion (a+bi+cj+dk) ----
define({_print_result},{ifelse(_isquat({$1}),1,{_print_quat({$1})},_iscomplex({$1}),1,{_print_complex({$1})},{ifelse(defn({_fp_}$1),,{PRINT r{}{$1}},{PRINTFP r{}{$1} defn({_fp_}{$1})})})})dnl
define({_print_complex},{dnl
PRINTFPC r{}_cR({$1}) _FP_DIGITS
PRINTFPP r{}_cI({$1}) _FP_DIGITS
PRINTS i
})dnl
define({_print_quat},{dnl
PRINTFPC r{}_qR({$1}) _FP_DIGITS
PRINTFPP r{}_qI({$1}) _FP_DIGITS
PRINTS i
PRINTFPP r{}_qJ({$1}) _FP_DIGITS
PRINTS j
PRINTFPP r{}_qK({$1}) _FP_DIGITS
PRINTS k
})dnl
define({_CALC_INNER},{_setinput(translit({$1},{(),},{<>@}))_setpos(0)define({__result},_expr())_CODE{}_print_result(__result)
HALT
})dnl
define({CALC},{_CALC_INNER({$*})})dnl
CALC(TARGET)
