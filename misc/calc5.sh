#!/bin/sh
# calc5 — Pure m4 RISC-VM arbitrary-precision calculator
# O(n) limb ops, binary exponentiation, fixed-point transcendentals,
# quaternion arithmetic, error handling.
# No python. No bc. No external deps. Just m4.
set -e
[ $# -eq 0 ] && { echo "Usage: calc5 'expression'" >&2; exit 1; }
EXPR="$*"
printf "%s" "$EXPR" | grep -qP '[^0-9a-z +\-*/!().%^,]' && { echo "Error: invalid characters" >&2; exit 1; }
{ cat <<'M4'
changequote({,})changecom({;})dnl
dnl ============================================================
dnl CALC v5 — RISC bignum engine + fixed-point transcendentals
dnl          + quaternion arithmetic (Hamilton product)
dnl Base-10000 limbs, eval() ALU, NO external dependencies
dnl ============================================================
define({_B},10000)dnl
define({_BW},4)dnl
dnl --- helpers ---
define({_stripz},{ifelse({$1},,{0},substr({$1},0,1),{0},{_stripz(substr({$1},1))},{$1})})dnl
define({_pad},{ifelse(eval(len({$1})<_BW),1,{_pad({0$1})},{$1})})dnl
dnl ============================================================
dnl L1: RISC BIGNUM — limbs are ~-separated, little-endian
dnl ============================================================
dnl --- load: decimal string -> limb string ---
define({_load},{_ld2(_stripz({$1}))})dnl
define({_ld2},{ifelse({$1},,{0000},{ifelse(eval(len({$1})<=_BW),1,{_pad({$1})},{_pad(substr({$1},eval(len({$1})-_BW)))~_ld2(substr({$1},0,eval(len({$1})-_BW)))})})})dnl
dnl --- emit: limb string -> decimal string ---
define({_emit},{ifelse(substr({$1},0,1),{-},{-_stripz(_em2(substr({$1},1)))},{_stripz(_em2({$1}))})})dnl
define({_em2},{ifelse(index({$1},{~}),-1,{$1},{_em2(substr({$1},eval(index({$1},{~})+1)))substr({$1},0,index({$1},{~}))})})dnl
dnl --- limb access ---
define({_limb},{_lb2({$1},{$2},0)})dnl
define({_lb2},{ifelse(index({$1},{~}),-1,{ifelse({$2},{$3},{$1},{0000})},{ifelse({$2},{$3},{substr({$1},0,index({$1},{~}))},{_lb2(substr({$1},eval(index({$1},{~})+1)),{$2},eval({$3}+1))})})})dnl
define({_nlimbs},{_nl2({$1},1)})dnl
define({_nl2},{ifelse(index({$1},{~}),-1,{$2},{_nl2(substr({$1},eval(index({$1},{~})+1)),eval({$2}+1))})})dnl
dnl --- normalize: strip high zero limbs ---
define({_norm},{ifelse(_nlimbs({$1}),1,{$1},{ifelse(_stripz(_limb({$1},eval(_nlimbs({$1})-1))),{0},{_norm(substr({$1},0,eval(len({$1})-5)))},{$1})})})dnl
dnl --- addition: O(n) left-to-right limb consumption ---
define({_Radd},{_norm(_Ra2({$1},{$2},0))})dnl
define({_Ra2},{ifelse(eval(len({$1})==0&&len({$2})==0&&{$3}==0),1,,{define({__as},eval(ifelse({$1},,0,{_stripz(substr({$1},0,4))})+ifelse({$2},,0,{_stripz(substr({$2},0,4))})+{$3}))_pad(eval(__as%_B))ifelse(eval(len(ifelse({$1},,{},{substr({$1},5)}))>0||len(ifelse({$2},,{},{substr({$2},5)}))>0||__as/_B>0),1,{~_Ra2(ifelse({$1},,{},{substr({$1},5)}),ifelse({$2},,{},{substr({$2},5)}),eval(__as/_B))})})})dnl
dnl --- subtraction (A >= B): O(n) left-to-right ---
define({_Rsub},{_norm(_Rs2({$1},{$2},0))})dnl
define({_Rs2},{ifelse(eval(len({$1})==0&&len({$2})==0&&{$3}==0),1,,{define({__ds},eval(ifelse({$1},,0,{_stripz(substr({$1},0,4))})-ifelse({$2},,0,{_stripz(substr({$2},0,4))})-{$3}))ifelse(eval(__ds<0),1,{_pad(eval(__ds+_B))},{_pad(eval(__ds))})ifelse(eval(len(ifelse({$1},,{},{substr({$1},5)}))>0||len(ifelse({$2},,{},{substr({$2},5)}))>0||eval(__ds<0)),1,{~_Rs2(ifelse({$1},,{},{substr({$1},5)}),ifelse({$2},,{},{substr({$2},5)}),ifelse(eval(__ds<0),1,1,0))})})})dnl
dnl --- single-limb multiply: O(n) left-to-right ---
define({_Rsmul},{_norm(_Rsm2({$1},{$2},0))})dnl
define({_Rsm2},{ifelse({$1},,{ifelse({$3},0,,{_pad({$3})})},{define({__sp},eval(_stripz(substr({$1},0,4))*{$2}+{$3}))_pad(eval(__sp%_B))ifelse(eval(len({$1})>4),1,{~_Rsm2(substr({$1},5),{$2},eval(__sp/_B))},{ifelse(eval(__sp/_B>0),1,{~_pad(eval(__sp/_B))})})})})dnl
dnl --- shift left by n limbs ---
define({_Rshift},{ifelse({$2},0,{$1},{_Rshift({0000~$1},eval({$2}-1))})})dnl
dnl --- limb string splitting for Karatsuba ---
define({_Rlo},{ifelse(eval(_nlimbs({$1})<={$2}),1,{$1},{substr({$1},0,eval({$2}*5-1))})})dnl
define({_Rhi},{ifelse(eval(_nlimbs({$1})<={$2}),1,{0000},{_norm(substr({$1},eval({$2}*5)))})})dnl
dnl --- Karatsuba: 3 half-size multiplies instead of 4 ---
define({_Rkara},{_Rk2({$1},{$2},eval((ifelse(eval(_nlimbs({$1})>=_nlimbs({$2})),1,{_nlimbs({$1})},{_nlimbs({$2})})+1)/2))})dnl
define({_Rk2},{_Rk3({$3},_Rlo({$1},{$3}),_Rhi({$1},{$3}),_Rlo({$2},{$3}),_Rhi({$2},{$3}))})dnl
define({_Rk3},{_Rk4({$1},_Rmul({$2},{$4}),_Rmul({$3},{$5}),_Rmul(_Radd({$2},{$3}),_Radd({$4},{$5})))})dnl
define({_Rk4},{_Radd(_Radd(_Rshift({$3},eval(2*{$1})),_Rshift(_Rsub(_Rsub({$4},{$2}),{$3}),{$1})),{$2})})dnl
dnl --- full multiply: Karatsuba for large, schoolbook for small ---
define({_Rmul},{ifelse(eval(len({$1})>=80&&len({$2})>=80),1,{_Rkara({$1},{$2})},{_Rml({$1},{$2},0,{0000})})})dnl
define({_Rml},{ifelse({$2},,{$4},{_Rml({$1},ifelse(eval(len({$2})>4),1,{substr({$2},5)}),eval({$3}+1),_Radd({$4},_Rshift(_Rsmul({$1},_stripz(substr({$2},0,4))),{$3})))})})dnl
dnl --- comparison (ternary: -1/0/1) ---
define({_Rcmp},{_Rcmp2(_norm({$1}),_norm({$2}))})dnl
define({_Rcmp2},{ifelse(eval(_nlimbs({$1})>_nlimbs({$2})),1,1,{ifelse(eval(_nlimbs({$1})<_nlimbs({$2})),1,-1,{_Rclex({$1},{$2},eval(_nlimbs({$1})-1))})})})dnl
define({_Rclex},{ifelse(eval({$3}<0),1,0,{ifelse(eval(_stripz(_limb({$1},{$3}))>_stripz(_limb({$2},{$3}))),1,1,{ifelse(eval(_stripz(_limb({$1},{$3}))<_stripz(_limb({$2},{$3}))),1,-1,{_Rclex({$1},{$2},eval({$3}-1))})})})})dnl
define({_Rgt},{ifelse(_Rcmp({$1},{$2}),1,1,0)})dnl
define({_Rgte},{ifelse(_Rcmp({$1},{$2}),-1,0,1)})dnl
dnl --- single-limb division: A / d -> Q_be:R_int ---
define({_Rd1},{_Rd1g({$1},{$2},eval(_nlimbs({$1})-1),0,{})})dnl
define({_Rd1g},{ifelse(eval({$3}<0),1,{$5:{$4}},{define({__x},eval({$4}*_B+_stripz(_limb({$1},{$3}))))_Rd1g({$1},{$2},eval({$3}-1),eval(__x%{$2}),ifelse({$5},,{_pad(eval(__x/{$2}))},{$5}~_pad(eval(__x/{$2}))))})})dnl
dnl --- reverse limb string ---
define({_Rrev},{_Rrv({$1},{})})dnl
define({_Rrv},{ifelse(index({$1},{~}),-1,{ifelse({$2},,{$1},{$1}~{$2})},{_Rrv(substr({$1},eval(index({$1},{~})+1)),ifelse({$2},,{substr({$1},0,index({$1},{~}))},{substr({$1},0,index({$1},{~}))~{$2}}))})})dnl
dnl --- multi-limb divmod ---
define({_Rdivmod},{ifelse(_nlimbs({$2}),1,{dnl
define({__d1},_Rd1({$1},_stripz({$2})))dnl
_norm(_Rrev(substr(__d1,0,index(__d1,{:})))):_load(substr(__d1,eval(index(__d1,{:})+1)))},{dnl
_Rdm_multi({$1},{$2})})})dnl
define({_Rdm_multi},{_Rdm_loop({$1},{$2},eval(_nlimbs({$1})-_nlimbs({$2})),{})})dnl
define({_Rdm_loop},{ifelse(eval({$3}<0),1,{dnl
ifelse({$4},,{_load({0})}:{_norm({$1})},{_norm(_Rrev({$4}))}:{_norm({$1})})},{dnl
_Rdm_est({$1},{$2},{$3},{$4},_Rshift({$2},{$3}))})})dnl
define({_Rdm_est},{dnl
define({__rl},_nlimbs({$1}))dnl
define({__qe},ifelse(eval(__rl>_nlimbs({$5})),1,{eval((_stripz(_limb({$1},eval(__rl-1)))*_B+_stripz(_limb({$1},eval(__rl-2))))/(_stripz(_limb({$5},eval(_nlimbs({$5})-1)))))},eval(__rl==_nlimbs({$5})),1,{eval(_stripz(_limb({$1},eval(__rl-1)))/(_stripz(_limb({$5},eval(_nlimbs({$5})-1)))))},{0}))dnl
ifelse(eval(__qe>=_B),1,{define({__qe},eval(_B-1))})dnl
ifelse(eval(__qe==0),1,{ifelse(_Rgte({$1},{$5}),1,{define({__qe},1)})})dnl
_Rdm_verify({$1},{$2},{$3},{$4},{$5},__qe)})dnl
define({_Rdm_verify},{dnl
define({__tv},_Rsmul({$5},{$6}))dnl
ifelse(_Rgt(__tv,{$1}),1,{_Rdm_verify({$1},{$2},{$3},{$4},{$5},eval({$6}-1))},{dnl
_Rdm_loop(_norm(_Rsub({$1},__tv)),{$2},eval({$3}-1),ifelse({$4},,{_pad({$6})},{$4}~_pad({$6})))})})dnl
dnl --- division wrappers via _Rdivmod ---
define({_Rdiv},{define({__dm},_Rdivmod({$1},{$2}))substr(__dm,0,index(__dm,{:}))})dnl
define({_Rmod},{define({__dm},_Rdivmod({$1},{$2}))substr(__dm,eval(index(__dm,{:})+1))})dnl
dnl --- factorial: use _Rsmul for k<10000, skip _Rmul overhead ---
dnl --- factorial: sequential for small n, binary split for large n ---
define({_Rfact},{ifelse(eval({$1}<=1),1,{_load({1})},eval({$1}<=10),1,{_Rsmul(_Rfact(eval({$1}-1)),{$1})},{_Rprod(2,{$1})})})dnl
define({_Rprod},{ifelse(eval({$1}>={$2}),1,{_load({$1})},eval({$2}-{$1}<30),1,{_Rprod_s({$1},{$2},_load({$1}))},{_Rmul(_Rprod({$1},eval(({$1}+{$2})/2)),_Rprod(eval(({$1}+{$2})/2+1),{$2}))})})dnl
define({_Rprod_s},{ifelse(eval({$1}>={$2}),1,{$3},{_Rprod_s(eval({$1}+1),{$2},_Rsmul({$3},eval({$1}+1)))})})dnl
dnl --- integer power (binary exponentiation) ---
define({_Rpow},{ifelse({$2},0,{_load({1})},{$2},1,{$1},eval({$2}%2),0,{define({__rph},_Rpow({$1},eval({$2}/2)))_Rmul(__rph,__rph)},{_Rmul({$1},_Rpow({$1},eval({$2}-1)))})})dnl
dnl --- GCD ---
define({_Rgcd},{ifelse(_emit({$2}),{0},{$1},{_Rgcd({$2},_Rmod({$1},{$2}))})})dnl
dnl ============================================================
dnl L2: SIGNED ARITHMETIC
dnl ============================================================
define({_Ris0},{ifelse(_emit({$1}),{0},1,0)})dnl
define({_Rneg},{ifelse(substr({$1},0,1),{-},{substr({$1},1)},{ifelse(_Ris0({$1}),1,{$1},{-{$1}})})})dnl
define({_Rabs},{ifelse(substr({$1},0,1),{-},{substr({$1},1)},{$1})})dnl
define({_Rispos},{ifelse(substr({$1},0,1),{-},0,1)})dnl
define({_Rsadd},{ifelse(_Rispos({$1}),1,{ifelse(_Rispos({$2}),1,{_Radd({$1},{$2})},{ifelse(_Rgte({$1},_Rabs({$2})),1,{_Rsub({$1},_Rabs({$2}))},{_Rneg(_Rsub(_Rabs({$2}),{$1}))})})},{ifelse(_Rispos({$2}),1,{ifelse(_Rgte({$2},_Rabs({$1})),1,{_Rsub({$2},_Rabs({$1}))},{_Rneg(_Rsub(_Rabs({$1}),{$2}))})},{_Rneg(_Radd(_Rabs({$1}),_Rabs({$2})))})})})dnl
define({_Rssub},{_Rsadd({$1},_Rneg({$2}))})dnl
define({_Rsmul2},{ifelse(eval(_Rispos({$1})+_Rispos({$2})),2,{_Rmul({$1},{$2})},eval(_Rispos({$1})+_Rispos({$2})),0,{_Rmul(_Rabs({$1}),_Rabs({$2}))},{_Rneg(_Rmul(_Rabs({$1}),_Rabs({$2})))})})dnl
dnl ============================================================
dnl L3: RATIONAL ARITHMETIC
dnl ============================================================
define({_rP},{substr({$1},0,index({$1},{/}))})dnl
define({_rQ},{substr({$1},eval(index({$1},{/})+1))})dnl
define({_itor},{$1/_load({1})})dnl
define({_rat},{define({__g},_Rgcd({$1},{$2}))_Rdiv({$1},__g)/_Rdiv({$2},__g)})dnl
define({_srat},{ifelse(_Rispos({$1}),1,{_rat({$1},{$2})},{dnl
define({__sg},_Rgcd(_Rabs({$1}),{$2}))_Rneg(_Rdiv(_Rabs({$1}),__sg))/_Rdiv({$2},__sg)})})dnl
define({_radd},{_srat(_Rsadd(_Rsmul2(_rP({$1}),_rQ({$2})),_Rsmul2(_rQ({$1}),_rP({$2}))),_Rmul(_rQ({$1}),_rQ({$2})))})dnl
define({_rsub},{_srat(_Rssub(_Rsmul2(_rP({$1}),_rQ({$2})),_Rsmul2(_rQ({$1}),_rP({$2}))),_Rmul(_rQ({$1}),_rQ({$2})))})dnl
define({_rmul},{_srat(_Rsmul2(_rP({$1}),_rP({$2})),_Rmul(_rQ({$1}),_rQ({$2})))})dnl
define({_rdiv},{define({__rdn},_Rsmul2(_rP({$1}),_rQ({$2})))define({__rdd},_Rsmul2(_rQ({$1}),_rP({$2})))ifelse(_Rispos(__rdd),1,{_srat(__rdn,__rdd)},{_srat(_Rneg(__rdn),_Rabs(__rdd))})})dnl
define({_radd_raw},{_Radd(_Rmul(_rP({$1}),_rQ({$2})),_Rmul(_rQ({$1}),_rP({$2})))/_Rmul(_rQ({$1}),_rQ({$2}))})dnl
define({_rsub_raw},{_Rsub(_Rmul(_rP({$1}),_rQ({$2})),_Rmul(_rQ({$1}),_rP({$2})))/_Rmul(_rQ({$1}),_rQ({$2}))})dnl
define({_rmul_raw},{_Rmul(_rP({$1}),_rP({$2}))/_Rmul(_rQ({$1}),_rQ({$2}))})dnl
define({_rdiv_raw},{_Rmul(_rP({$1}),_rQ({$2}))/_Rmul(_rQ({$1}),_rP({$2}))})dnl
define({_rreduce},{_srat(_rP({$1}),_rQ({$1}))})dnl
define({_rtod},{_rtod2(_rP({$1}),_rQ({$1}),{$2})})dnl
define({_rtod2},{ifelse(_Rispos({$1}),1,{_emit(_Rdiv({$1},{$2}))._rtod_f(_Rmod({$1},{$2}),{$2},{$3})},{-_rtod2(_Rabs({$1}),{$2},{$3})})})dnl
define({_rtod_f},{ifelse({$3},0,,{_emit(_Rdiv(_Rsmul({$1},10),{$2}))_rtod_f(_Rmod(_Rsmul({$1},10),{$2}),{$2},eval({$3}-1))})})dnl
define({_dtor},{ifelse(substr({$1},0,1),{-},{_dtor_neg(substr({$1},1))},{_dtor_pos({$1})})})dnl
define({_dtor_neg},{define({__dnv},_dtor_pos({$1}))_Rneg(_rP(__dnv))/_rQ(__dnv)})dnl
define({_dtor_pos},{ifelse(index({$1},{.}),-1,{_load({$1})/_load({1})},{_dtor2(translit({$1},{.}),eval(len({$1})-index({$1},{.})-1))})})dnl
define({_dtor2},{_rat(_load({$1}),_Rpow(_load({10}),{$2}))})dnl
dnl ============================================================
dnl L4: FIXED-POINT TRANSCENDENTALS
dnl ============================================================
define({_OUT},15)dnl
define({_GUARD},3)dnl
define({_FP_S},{0000~0000~0000~0000~0100})dnl
define({_FP_SH},{0000~0000~0000~0000~0050})dnl
define({_FP_S2},{0000~0000~0000~0000~0000~0000~0000~0100})dnl
define({_FP_SOUT},{0000~0000~0000~1000})dnl
define({_fpexp},{dnl
define({__X},_Rdiv(_Rmul(_rP({$1}),_FP_S),_rQ({$1})))dnl
_fpexp_reduce(__X,_FP_S,0,_FP_SH)/_FP_S})dnl
define({_fpexp_reduce},{ifelse(_Rgt({$1},{$4}),1,{_fpexp_reduce(_Rdiv({$1},_load({2})),{$2},eval({$3}+1),{$4})},{_fpexp_square(_fpexp_l({$1},{$2},14,1,{$2},{$2}),{$2},{$3})})})dnl
define({_fpexp_square},{ifelse({$3},0,{$1},{_fpexp_square(_Rdiv(_Rmul({$1},{$1}),{$2}),{$2},eval({$3}-1))})})dnl
define({_fpexp_l},{ifelse({$3},0,{$6},{define({__nt},_Rdiv(_Rmul({$5},{$1}),_Rsmul({$2},{$4})))_fpexp_l({$1},{$2},eval({$3}-1),eval({$4}+1),__nt,_Radd({$6},__nt))})})dnl
define({_PI18},{3141592653589793238})dnl
define({_fpsin},{dnl
define({__PIS},_load(_PI18))dnl
define({__X},_Rdiv(_Rmul(_rP({$1}),_FP_S),_rQ({$1})))dnl
define({__TWOPIS},_Rsmul(__PIS,2))dnl
define({__X},_Rmod(__X,__TWOPIS))dnl
define({_TRIG_NEG},ifelse(_Rgte(__X,__PIS),1,{define({__X},_Rsub(__X,__PIS))1},{0}))dnl
define({__HPIS},_Rdiv(__PIS,_load({2})))dnl
ifelse(_Rgt(__X,__HPIS),1,{define({__X},_Rsub(__PIS,__X))})dnl
define({__X2},_Rdiv(_Rmul(__X,__X),_FP_S))dnl
_fpsin_l(__X2,_FP_S,12,1,__X,__X)/_FP_S})dnl
define({_fpsin_l},{ifelse({$3},0,{$6},{_fpsin_s({$1},{$2},eval({$3}-1),eval({$4}+1),_Rdiv(_Rmul({$5},{$1}),{$2}),{$6},{$4})})})dnl
define({_fpsin_s},{define({__st},_Rdiv({$5},_load(eval(2*{$7}*(2*{$7}+1)))))ifelse(eval({$7}%2),1,{_fpsin_l({$1},{$2},{$3},{$4},__st,_Rsub({$6},__st))},{_fpsin_l({$1},{$2},{$3},{$4},__st,_Radd({$6},__st))})})dnl
define({_fpcos},{dnl
define({__PIS},_load(_PI18))dnl
define({__X},_Rdiv(_Rmul(_rP({$1}),_FP_S),_rQ({$1})))dnl
define({__TWOPIS},_Rsmul(__PIS,2))dnl
define({__X},_Rmod(__X,__TWOPIS))dnl
define({_TRIG_NEG},ifelse(_Rgte(__X,__PIS),1,{define({__X},_Rsub(__X,__PIS))1},{0}))dnl
define({__HPIS},_Rdiv(__PIS,_load({2})))dnl
ifelse(_Rgt(__X,__HPIS),1,{define({__X},_Rsub(__PIS,__X))define({_TRIG_NEG},eval(1-_TRIG_NEG))})dnl
define({__X2},_Rdiv(_Rmul(__X,__X),_FP_S))dnl
_fpcos_l(__X2,_FP_S,12,1,_FP_S,_FP_S)/_FP_S})dnl
define({_fpcos_l},{ifelse({$3},0,{$6},{_fpcos_s({$1},{$2},eval({$3}-1),eval({$4}+1),_Rdiv(_Rmul({$5},{$1}),{$2}),{$6},{$4})})})dnl
define({_fpcos_s},{define({__ct},_Rdiv({$5},_load(eval((2*{$7}-1)*2*{$7}))))ifelse(eval({$7}%2),1,{_fpcos_l({$1},{$2},{$3},{$4},__ct,_Rssub({$6},__ct))},{_fpcos_l({$1},{$2},{$3},{$4},__ct,_Rsadd({$6},__ct))})})dnl
define({_LN2_FP},{_load({693147180559945309})})dnl
define({_fpln},{dnl
define({__X},_Rdiv(_Rmul(_rP({$1}),_FP_S),_rQ({$1})))dnl
define({__2S},_Rsmul(_FP_S,2))dnl
_fpln_h(__X,_FP_S,0,__2S)/_FP_S})dnl
define({_fpln_h},{ifelse(_Rgte({$1},{$4}),1,{_fpln_h(_Rdiv({$1},_load({2})),{$2},eval({$3}+1),{$4})},{_fpln_a({$1},{$2},{$3})})})dnl
define({_fpln_a},{dnl
define({__U},_Rdiv(_Rmul(_Rsub({$1},{$2}),{$2}),_Radd({$1},{$2})))dnl
define({__U2},_Rdiv(_Rmul(__U,__U),{$2}))dnl
define({__ath},_fpath_l(__U,__U2,{$2},12,1,__U,__U))dnl
_Radd(_Rsmul(__ath,2),_Rsmul(_LN2_FP,{$3}))})dnl
define({_fpath_l},{ifelse({$4},0,{$7},{define({__al},_Rdiv(_Rmul({$6},{$2}),{$3}))_fpath_l({$1},{$2},{$3},eval({$4}-1),eval({$5}+1),__al,_Radd({$7},_Rdiv(__al,_load(eval(2*{$5}+1)))))})})dnl
define({_rsqrt_guess},{_Rpow(_load({10}),eval(len(_emit({$1}))/2))})dnl
define({_rstep},{_Rdiv(_Radd({$1},_Rdiv({$2},{$1})),_load({2}))})dnl
define({_risqrt},{_ri_loop({$1},8,_rsqrt_guess({$1}))})dnl
define({_ri_loop},{ifelse({$2},0,{$3},{_ri_loop({$1},eval({$2}-1),_rstep({$3},{$1}))})})dnl
define({_rsqrt},{define({__sn},_rP({$1}))define({__sd},_rQ({$1}))define({__sp},_Rdiv(_Rmul(__sn,_FP_S2),__sd))define({__sq},_risqrt(__sp,10))__sq/_FP_SOUT})dnl
dnl ============================================================
dnl L5: SMART DISPATCH (polymorphic: scalar + quaternion)
dnl ============================================================
define({_isfp},{ifelse(index({$1},{.}),-1,0,1)})dnl
define({_isneg},{ifelse(substr({$1},0,1),{-},1,0)})dnl
define({_hasfp},{eval(_isfp({$1})+_isfp({$2})>0)})dnl
define({_isquat},{ifelse(index({$1},{|}),-1,0,1)})dnl
define({_hasquat},{eval(_isquat({$1})+_isquat({$2})>0)})dnl
dnl --- string negation for decimal strings ---
define({_sneg},{ifelse(substr({$1},0,1),{-},{substr({$1},1)},ifelse({$1},{0},{0},{-{$1}}))})dnl
define({_sload},{ifelse(substr({$1},0,1),{-},{_Rneg(_load(substr({$1},1)))},{_load({$1})})})dnl
dnl --- scalar ops with zero short-circuit (used by quaternion layer) ---
define({_smul0},{ifelse({$1},0,{0},{$2},0,{0},{_smul({$1},{$2})})})dnl
define({_sadd0},{ifelse({$1},0,{$2},{$2},0,{$1},{_sadd({$1},{$2})})})dnl
define({_ssub0},{ifelse({$2},0,{$1},{$1},0,{_sneg({$2})},{_ssub({$1},{$2})})})dnl
dnl --- polymorphic add ---
define({_sadd},{ifelse(_hasquat({$1},{$2}),1,{_qadd({$1},{$2})},_hasfp({$1},{$2}),1,{_rtod(_radd(_dtor({$1}),_dtor({$2})),_OUT)},{_emit(_Rsadd(_sload({$1}),_sload({$2})))})})dnl
dnl --- polymorphic sub ---
define({_ssub},{ifelse(_hasquat({$1},{$2}),1,{_qsub({$1},{$2})},_hasfp({$1},{$2}),1,{_rtod(_rsub(_dtor({$1}),_dtor({$2})),_OUT)},{_emit(_Rssub(_sload({$1}),_sload({$2})))})})dnl
dnl --- polymorphic mul ---
define({_smul},{ifelse(_hasquat({$1},{$2}),1,{_qhmul(_qpromote({$1}),_qpromote({$2}))},_hasfp({$1},{$2}),1,{_rtod(_rmul(_dtor({$1}),_dtor({$2})),_OUT)},{_emit(_Rsmul2(_sload({$1}),_sload({$2})))})})dnl
dnl --- polymorphic div ---
define({_sdiv},{ifelse(_hasquat({$1},{$2}),1,{_qdiv({$1},{$2})},{$2},0,{ERR:div0},{$2},{0.0},ERR:div0,{define({__dvr},_rdiv(_dtor({$1}),_dtor({$2})))ifelse(_emit(_rQ(__dvr)),{1},{ifelse(_Rispos(_rP(__dvr)),1,{_emit(_rP(__dvr))},{-_emit(_Rabs(_rP(__dvr)))})},{_rtod(__dvr,_OUT)})})})dnl
define({_smod},{ifelse({$2},0,ERR:mod0,{_emit(_Rmod(_load({$1}),_load({$2})))})})dnl
dnl --- polymorphic pow ---
define({_spow},{ifelse(_isquat({$1}),1,{_qpow_d({$1},{$2})},_hasfp({$1},{$2}),0,{ifelse(_isneg({$1}),1,{ifelse(eval({$2}%2),1,{-_emit(_Rpow(_load(substr({$1},1)),{$2}))},{_emit(_Rpow(_load(substr({$1},1)),{$2}))})},{_emit(_Rpow(_load({$1}),{$2}))})},{_spow2({$1},{$2})})})dnl
define({_spow2},{ifelse(_is_half({$2}),1,{_rtod(_rsqrt(_dtor({$1})),_OUT)},{_spow3({$1},{$2})})})dnl
define({_spow3},{ifelse(_isfp({$2}),0,{_rtod(_rpow_rat(_dtor({$1}),{$2}),_OUT)},{_spow_expln({$1},{$2})})})dnl
dnl --- _rpow_rat: rational^int via binary exponentiation, lazy GCD ---
dnl Uses raw signed multiply (no GCD), reduces only at base case and merge
define({_rmul_sraw},{_Rsmul2(_rP({$1}),_rP({$2}))/_Rmul(_rQ({$1}),_rQ({$2}))})dnl
define({_rpow_rat},{ifelse({$2},0,{_load({1})/_load({1})},{$2},1,{_rreduce({$1})},eval({$2}%2),0,{define({__rrh},_rpow_rat({$1},eval({$2}/2)))_rreduce(_rmul_sraw(__rrh,__rrh))},{_rreduce(_rmul_sraw({$1},_rpow_rat({$1},eval({$2}-1))))})})dnl
define({_spow_expln},{ifelse(_Rcmp(_rP(_dtor({$1})),_rQ(_dtor({$1}))),-1,{dnl
define({__inv},_rdiv(_itor(_load({1})),_dtor({$1})))dnl
define({__invpow},_fpexp(_rmul(_fpln(__inv,_OUT),_dtor({$2})),_OUT))dnl
_rtod(_rdiv(_itor(_load({1})),__invpow),_OUT)},{dnl
_rtod(_fpexp(_rmul(_fpln(_dtor({$1}),_OUT),_dtor({$2})),_OUT),_OUT)})})dnl
define({_is_half},{ifelse({$1},{0.5},1,{$1},{0.500000000000000},1,0)})dnl
dnl ============================================================
dnl L7: QUATERNION ARITHMETIC
dnl Representation: a|b|c|d (pipe-separated decimal strings)
dnl Hamilton product with cached intermediate products.
dnl Binary exponentiation for q^n.
dnl ============================================================
dnl --- accessors ---
define({_qfirst},{ifelse(index({$1},{|}),-1,{$1},{substr({$1},0,index({$1},{|}))})})dnl
define({_qrest},{substr({$1},eval(index({$1},{|})+1))})dnl
define({_qR},{_qfirst({$1})})dnl
define({_qI},{_qfirst(_qrest({$1}))})dnl
define({_qJ},{_qfirst(_qrest(_qrest({$1})))})dnl
define({_qK},{_qrest(_qrest(_qrest({$1})))})dnl
dnl --- constructor / promote ---
define({_qmk},{$1|$2|$3|$4})dnl
define({_qpromote},{ifelse(_isquat({$1}),1,{$1},{$1|0|0|0})})dnl
dnl --- quaternion addition (component-wise, with promotion) ---
define({_qadd},{dnl
define({__qa},_qpromote({$1}))define({__qb},_qpromote({$2}))dnl
_qmk(_sadd0(_qR(__qa),_qR(__qb)),_sadd0(_qI(__qa),_qI(__qb)),_sadd0(_qJ(__qa),_qJ(__qb)),_sadd0(_qK(__qa),_qK(__qb)))})dnl
dnl --- quaternion subtraction ---
define({_qsub},{dnl
define({__qa},_qpromote({$1}))define({__qb},_qpromote({$2}))dnl
_qmk(_ssub0(_qR(__qa),_qR(__qb)),_ssub0(_qI(__qa),_qI(__qb)),_ssub0(_qJ(__qa),_qJ(__qb)),_ssub0(_qK(__qa),_qK(__qb)))})dnl
dnl --- Hamilton product: 16 cached multiplies, zero short-circuit ---
dnl q1*q2 = (a1a2−b1b2−c1c2−d1d2)
dnl       + (a1b2+b1a2+c1d2−d1c2)i
dnl       + (a1c2−b1d2+c1a2+d1b2)j
dnl       + (a1d2+b1c2−c1b2+d1a2)k
define({_qhmul},{dnl
define({__a1},_qR({$1}))define({__b1},_qI({$1}))define({__c1},_qJ({$1}))define({__d1},_qK({$1}))dnl
define({__a2},_qR({$2}))define({__b2},_qI({$2}))define({__c2},_qJ({$2}))define({__d2},_qK({$2}))dnl
define({__p01},_smul0(__a1,__a2))dnl
define({__p02},_smul0(__b1,__b2))dnl
define({__p03},_smul0(__c1,__c2))dnl
define({__p04},_smul0(__d1,__d2))dnl
define({__p05},_smul0(__a1,__b2))dnl
define({__p06},_smul0(__b1,__a2))dnl
define({__p07},_smul0(__c1,__d2))dnl
define({__p08},_smul0(__d1,__c2))dnl
define({__p09},_smul0(__a1,__c2))dnl
define({__p10},_smul0(__b1,__d2))dnl
define({__p11},_smul0(__c1,__a2))dnl
define({__p12},_smul0(__d1,__b2))dnl
define({__p13},_smul0(__a1,__d2))dnl
define({__p14},_smul0(__b1,__c2))dnl
define({__p15},_smul0(__c1,__b2))dnl
define({__p16},_smul0(__d1,__a2))dnl
_qmk(_ssub0(_ssub0(_ssub0(__p01,__p02),__p03),__p04),_ssub0(_sadd0(_sadd0(__p05,__p06),__p07),__p08),_sadd0(_sadd0(_ssub0(__p09,__p10),__p11),__p12),_sadd0(_ssub0(_sadd0(__p13,__p14),__p15),__p16))})dnl
dnl --- conjugate ---
define({_qconj},{_qmk(_qR({$1}),_sneg(_qI({$1})),_sneg(_qJ({$1})),_sneg(_qK({$1})))})dnl
dnl --- squared norm (returns scalar) ---
define({_qnorm2},{_sadd0(_sadd0(_sadd0(_smul0(_qR({$1}),_qR({$1})),_smul0(_qI({$1}),_qI({$1}))),_smul0(_qJ({$1}),_qJ({$1}))),_smul0(_qK({$1}),_qK({$1})))})dnl
dnl --- inverse: conj(q)/|q|^2 ---
define({_qinv},{dnl
define({__qn2},_qnorm2({$1}))dnl
ifelse(__qn2,0,{ERR:qinv0|ERR|ERR|ERR},{dnl
define({__qcj},_qconj({$1}))dnl
_qmk(_sdiv(_qR(__qcj),__qn2),_sdiv(_qI(__qcj),__qn2),_sdiv(_qJ(__qcj),__qn2),_sdiv(_qK(__qcj),__qn2))})})dnl
dnl --- quaternion right-division: q1 * q2^{-1} ---
define({_qdiv},{_qhmul(_qpromote({$1}),_qinv(_qpromote({$2})))})dnl
dnl --- quaternion power: binary exponentiation with Hamilton product ---
define({_qpow},{ifelse({$2},0,{1|0|0|0},{$2},1,{$1},eval({$2}%2),0,{define({__qph},_qpow({$1},eval({$2}/2)))_qhmul(__qph,__qph)},{_qhmul({$1},_qpow({$1},eval({$2}-1)))})})dnl
dnl --- power dispatch for quaternion base ---
define({_qpow_d},{ifelse(_isquat({$2}),1,{ERR:q_exp_q},_isfp({$2}),1,{ERR:q_exp_flt},_isneg({$2}),1,{_qinv(_qpow({$1},substr({$2},1)))},{_qpow({$1},{$2})})})dnl
dnl --- output formatting: purely functional (no mutable state) ---
dnl _qfl: leading format (first non-zero component, no + prefix)
define({_qfl},{ifelse({$1},-1,{-{$2}},{$1},1,{{$2}},substr({$1},0,1),{-},{{$1}{$2}},{{$1}{$2}})})dnl
dnl _qft: trailing format (subsequent component, + prefix for positive)
define({_qft},{ifelse({$1},-1,{-{$2}},{$1},1,{+{$2}},substr({$1},0,1),{-},{{$1}{$2}},{+{$1}{$2}})})dnl
dnl _qf_r: real part (omit if zero)
define({_qf_r},{ifelse({$1},0,,{$1})})dnl
dnl _qf_i: i component — leading if real was zero
define({_qf_i},{ifelse({$1},0,,{ifelse({$3},0,{_qfl({$1},{$2})},{_qft({$1},{$2})})})})dnl
dnl _qf_j: j component — leading if real and i were both zero
define({_qf_j},{ifelse({$1},0,,{ifelse({$3},0,{ifelse({$4},0,{_qfl({$1},{$2})},{_qft({$1},{$2})})},{_qft({$1},{$2})})})})dnl
dnl _qf_k: k component — leading if all prior were zero
define({_qf_k},{ifelse({$1},0,,{ifelse({$3},0,{ifelse({$4},0,{ifelse({$5},0,{_qfl({$1},{$2})},{_qft({$1},{$2})})},{_qft({$1},{$2})})},{_qft({$1},{$2})})})})dnl
dnl _qf_z: output 0 only if all four components are zero
define({_qf_z},{ifelse({$1},0,{ifelse({$2},0,{ifelse({$3},0,{ifelse({$4},0,{0})})})})})dnl
dnl _qfmt: main entry — extract components, dispatch
define({_qfmt},{_qf_go(_qR({$1}),_qI({$1}),_qJ({$1}),_qK({$1}))})dnl
define({_qf_go},{_qf_r({$1})_qf_i({$2},i,{$1})_qf_j({$3},j,{$1},{$2})_qf_k({$4},k,{$1},{$2},{$3})_qf_z({$1},{$2},{$3},{$4})})dnl
dnl --- output: collapse pure-scalar quaternions, else format ---
define({_qoutput},{ifelse(_isquat({$1}),1,{ifelse(_qI({$1}),0,{ifelse(_qJ({$1}),0,{ifelse(_qK({$1}),0,{_qR({$1})},{_qfmt({$1})})},{_qfmt({$1})})},{_qfmt({$1})})},{$1})})dnl
dnl ============================================================
dnl L6: RECURSIVE-DESCENT PARSER
dnl ============================================================
define({_POS},0)dnl
define({_INPUT},{})dnl
define({_setpos},{define({_POS},{$1})})dnl
define({_setinput},{define({_INPUT},{$1})})dnl
define({_ch},{substr(_INPUT,_POS,1)})dnl
define({_advance},{_setpos(eval(_POS+1))})dnl
define({_skip},{ifelse(_ch,{ },{_advance()_skip()})})dnl
define({_isdigit},{ifelse({$1},{0},1,{$1},{1},1,{$1},{2},1,{$1},{3},1,{$1},{4},1,{$1},{5},1,{$1},{6},1,{$1},{7},1,{$1},{8},1,{$1},{9},1,0)})dnl
define({_isalpha},{ifelse({$1},,0,eval(index({abcdefghijklmnopqrstuvwxyz},{$1})>=0),1,1,0)})dnl
define({_rdnum},{ifelse(_isdigit(_ch),1,{_ch()_advance()_rdnum()},_ch,{.},{.{}_advance()_rdnum()})})dnl
define({_rdid},{_rdid_e(_POS)})dnl
define({_isalnum},{ifelse(_isalpha({$1}),1,1,_isdigit({$1}),1,1,0)})dnl
define({_rdid_e},{ifelse(_isalnum(substr(_INPUT,{$1},1)),1,{_rdid_e(eval({$1}+1))},{_rdid_x({$1})})})dnl
define({_rdid_x},{define({__rid},substr(_INPUT,_POS,eval({$1}-_POS)))_setpos({$1})__rid})dnl
dnl --- atom: recognizes i/j/k as quaternion units ---
define({_atom},{_skip()ifelse(_ch,{<},{_advance()_atom_p(_expr())},_isdigit(_ch),1,{_atom_num()},_ch,{.},{_rdnum()},_isalpha(_ch),1,{_atom_id(_rdid())},{ERR})})dnl
dnl --- number entry: detect 0x / 0b prefix ---
define({_atom_num},{ifelse(_ch,{0},{_advance()ifelse(_ch,{x},{_advance()_emit(_rdhex(_load({0})))},_ch,{b},{_advance()_emit(_rdbin(_load({0})))},{0_rdnum()})},{_rdnum()})})dnl
dnl --- hex reader: accumulate digits via _Rsmul(acc,16)+digit ---
define({_ishex},{ifelse({$1},{0},1,{$1},{1},1,{$1},{2},1,{$1},{3},1,{$1},{4},1,{$1},{5},1,{$1},{6},1,{$1},{7},1,{$1},{8},1,{$1},{9},1,{$1},{a},1,{$1},{b},1,{$1},{c},1,{$1},{d},1,{$1},{e},1,{$1},{f},1,0)})dnl
define({_hexval},{ifelse({$1},{a},10,{$1},{b},11,{$1},{c},12,{$1},{d},13,{$1},{e},14,{$1},{f},15,{$1})})dnl
define({_rdhex},{ifelse(_ishex(_ch),1,{_rdhex2({$1},_hexval(_ch))},{$1})})dnl
define({_rdhex2},{_advance()_rdhex(_Radd(_Rsmul({$1},16),_load({$2})))})dnl
dnl --- binary reader: accumulate bits ---
define({_rdbin},{ifelse(_ch,{0},{_advance()_rdbin(_Rsmul({$1},2))},_ch,{1},{_advance()_rdbin(_Radd(_Rsmul({$1},2),_load({1})))},{$1})})dnl
define({_atom_p},{_skip()_advance(){$1}})dnl
dnl --- identifier dispatch: i/j/k as units, else function call ---
define({_atom_id},{ifelse({$1},{i},{0|1|0|0},{$1},{j},{0|0|1|0},{$1},{k},{0|0|0|1},{$1},{pi},{3.141592653589793},{$1},{e},{2.718281828459045},{$1},{phi},{1.618033988749894},{$1},{gcd},{_skip()_advance()_atom_2arg({$1})},{$1},{choose},{_skip()_advance()_atom_2arg({$1})},{$1},{atan2},{_skip()_advance()_atom_2arg({$1})},{_skip()_advance()_atom_fn2({$1},_expr())})})dnl
dnl --- 2-arg function call: fn(expr1, expr2) ---
define({_atom_2arg},{define({__2a1},_expr())_skip()ifelse(_ch,{@},{_advance()},{})_skip()_atom_2arg2({$1},__2a1,_expr())})dnl
define({_atom_2arg2},{_skip()_advance()ifelse({$1},{gcd},{_do_gcd({$2},{$3})},{$1},{choose},{_do_choose({$2},{$3})},{$1},{atan2},{_do_atan2({$2},{$3})},{ERR:fn2})})dnl
dnl --- gcd(a,b) ---
define({_do_gcd},{_emit(_Rgcd(_load({$1}),_load({$2})))})dnl
dnl --- choose(n,k) = n! / (k! * (n-k)!) ---
define({_do_choose},{_emit(_Rdiv(_Rfact({$1}),_Rmul(_Rfact({$2}),_Rfact(eval({$1}-{$2})))))})dnl
dnl --- atan2(y,x) ---
define({_do_atan2},{ifelse({$2},0,{ifelse(_is_neg_str({$1}),1,{-1.570796326794897},{1.570796326794897})},_is_neg_str({$2}),1,{ifelse(_is_neg_str({$1}),1,{_ssub(_do_atan(_sdiv({$1},{$2})),3.141592653589793)},{_sadd(_do_atan(_sdiv({$1},{$2})),3.141592653589793)})},{_do_atan(_sdiv({$1},{$2}))})})dnl
dnl --- helpers for negative argument handling ---
define({_strip_neg},{ifelse(substr({$1},0,1),{-},{substr({$1},1)},{$1})})dnl
define({_is_neg_str},{ifelse(substr({$1},0,1),{-},1,0)})dnl
dnl --- ln ---
define({_ln_out},{ifelse({$1},{0},ERR:ln0,_is_neg_str({$1}),1,ERR:ln_neg,{dnl
ifelse(_Rcmp(_rP(_dtor({$1})),_rQ(_dtor({$1}))),-1,{-_rtod(_fpln(_rdiv(_itor(_load({1})),_dtor({$1})),_OUT),_OUT)},{_rtod(_fpln(_dtor({$1}),_OUT),_OUT)})})})dnl
dnl --- sqrt ---
define({_do_sqrt},{ifelse(_is_neg_str({$1}),1,ERR:sqrt_neg,{_rtod(_rsqrt(_dtor({$1})),_OUT)})})dnl
dnl --- sin ---
define({_do_sin},{dnl
define({__sa},_strip_neg({$1}))dnl
define({__sr},_fpsin(_dtor(__sa),_OUT))dnl
ifelse(eval(_is_neg_str({$1})!=_TRIG_NEG),1,{-_rtod(__sr,_OUT)},{_rtod(__sr,_OUT)})})dnl
dnl --- cos ---
define({_do_cos},{dnl
define({__ca},_strip_neg({$1}))dnl
define({__cr},_fpcos(_dtor(__ca),_OUT))dnl
ifelse(_TRIG_NEG,1,{-_rtod(__cr,_OUT)},{_rtod(__cr,_OUT)})})dnl
dnl --- exp ---
dnl --- quaternion exp: exp(a+v) = exp(a)*(cos|v| + sin|v|/|v| * v) ---
define({_qvnorm2},{_sadd0(_sadd0(_smul0(_qI({$1}),_qI({$1})),_smul0(_qJ({$1}),_qJ({$1}))),_smul0(_qK({$1}),_qK({$1})))})dnl
define({_qexp},{dnl
define({__qa},_qR({$1}))dnl
define({__vn2},_qvnorm2({$1}))dnl
ifelse(__vn2,0,{_do_exp_s(__qa)},{dnl
define({__vn},_do_sqrt(__vn2))dnl
define({__cv},_do_cos(__vn))dnl
define({__sv},_do_sin(__vn))dnl
define({__sinc},_sdiv(__sv,__vn))dnl
ifelse(__qa,0,{dnl
_qmk(__cv,_smul0(__sinc,_qI({$1})),_smul0(__sinc,_qJ({$1})),_smul0(__sinc,_qK({$1})))},{dnl
define({__ea},_do_exp_s(__qa))dnl
define({__eacv},_smul(__ea,__cv))dnl
define({__easinc},_smul(__ea,__sinc))dnl
_qmk(__eacv,_smul0(__easinc,_qI({$1})),_smul0(__easinc,_qJ({$1})),_smul0(__easinc,_qK({$1})))})})})dnl
dnl --- scalar exp (extracted so _qexp can call without recursion) ---
define({_do_exp_s},{dnl
define({__ea},_strip_neg({$1}))dnl
define({__er},_fpexp(_dtor(__ea),_OUT))dnl
ifelse(_is_neg_str({$1}),1,{_rtod(_rdiv(_itor(_load({1})),__er),_OUT)},{_rtod(__er,_OUT)})})dnl
dnl --- exp wrapper: quaternion or scalar ---
define({_do_exp},{ifelse(_isquat({$1}),1,{_qexp({$1})},{_do_exp_s({$1})})})dnl
dnl --- tan: sin/cos ---
define({_do_tan},{_sdiv(_do_sin({$1}),_do_cos({$1}))})dnl
dnl --- hyperbolic trig: compositions of exp ---
define({_do_sinh},{define({__ep},_do_exp_s({$1}))define({__en},_do_exp_s(_sneg({$1})))_sdiv(_ssub(__ep,__en),2)})dnl
define({_do_cosh},{define({__ep},_do_exp_s({$1}))define({__en},_do_exp_s(_sneg({$1})))_sdiv(_sadd(__ep,__en),2)})dnl
define({_do_tanh},{define({__ep},_do_exp_s({$1}))define({__en},_do_exp_s(_sneg({$1})))_sdiv(_ssub(__ep,__en),_sadd(__ep,__en))})dnl
dnl --- atan via fixed-point Taylor: x - x^3/3 + x^5/5 - ... ---
define({_fpatan},{dnl
define({__X},_Rdiv(_Rmul(_Rabs(_rP({$1})),_FP_S),_rQ({$1})))dnl
define({__atneg},_isneg(_emit(_rP({$1}))))dnl
ifelse(_Rgt(__X,_FP_S),1,{dnl
define({__atr},_Rsub(_Rdiv(_load(_PI18),_load({2})),_fpatan_red(_Rdiv(_Rmul(_FP_S,_FP_S),__X),0)))dnl
},{define({__atr},_fpatan_red(__X,0))})dnl
ifelse(__atneg,1,{_Rneg(__atr)},{__atr})/_FP_S})dnl
dnl _fpatan_red: halve x until < 0.4*scale, then Taylor, then double back
define({_fpatan_red},{ifelse(_Rgt({$1},_FP_SH),0,{dnl
_fpatan_core({$1},{$2})},{dnl
define({__ax2},_Rdiv(_Rmul({$1},{$1}),_FP_S))dnl
define({__ad},_Radd(_FP_S,_risqrt(_Radd(_Rmul(_FP_S,_FP_S),_Rmul({$1},{$1})))))dnl
define({__ah},_Rdiv(_Rmul({$1},_FP_S),__ad))dnl
_fpatan_red(__ah,eval({$2}+1))})})dnl
define({_fpatan_core},{dnl
define({__X2},_Rdiv(_Rmul({$1},{$1}),_FP_S))dnl
define({_RX2},__X2)define({_RS},_FP_S)define({_Rt},{$1})define({_Ru},{$1})dnl
_fpatan_lr(15,1)dnl
_Rsmul(_Ru,eval(1<<{$2}))})dnl
define({_fpatan_lr},{ifelse({$1},0,,{dnl
define({_Rt},_Rdiv(_Rmul(_Rt,_RX2),_RS))dnl
ifelse(eval({$2}%2),1,{define({_Ru},_Rssub(_Ru,_Rdiv(_Rt,_load(eval(2*{$2}+1)))))},{define({_Ru},_Rsadd(_Ru,_Rdiv(_Rt,_load(eval(2*{$2}+1)))))})dnl
_fpatan_lr(eval({$1}-1),eval({$2}+1))})})dnl
define({_do_atan},{_rtod(_fpatan(_dtor({$1}),_OUT),_OUT)})dnl
dnl --- asin(x) = atan(x / sqrt(1-x^2)) ---
define({_do_asin},{ifelse({$1},1,{_rtod(_Rdiv(_load(_PI18),_load({2}))/_FP_S,_OUT)},{$1},-1,{-_rtod(_Rdiv(_load(_PI18),_load({2}))/_FP_S,_OUT)},{dnl
define({__as_x2},_smul({$1},{$1}))dnl
define({__as_d},_do_sqrt(_ssub(1,__as_x2)))dnl
_do_atan(_sdiv({$1},__as_d))})})dnl
dnl --- acos(x) = pi/2 - asin(x) ---
define({_do_acos},{_ssub(_rtod(_Rdiv(_load(_PI18),_load({2}))/_FP_S,_OUT),_do_asin({$1}))})dnl
dnl --- inverse hyperbolic via ln ---
define({_do_asinh},{_ln_out(_sadd({$1},_do_sqrt(_sadd(_smul({$1},{$1}),1))))})dnl
define({_do_acosh},{_ln_out(_sadd({$1},_do_sqrt(_ssub(_smul({$1},{$1}),1))))})dnl
define({_do_atanh},{_smul(0.5,_ln_out(_sdiv(_sadd(1,{$1}),_ssub(1,{$1}))))})dnl
dnl --- abs ---
define({_do_abs},{ifelse(_is_neg_str({$1}),1,{substr({$1},1)},{$1})})dnl
dnl --- log base 10: ln(x)/ln(10) ---
define({_do_log},{_sdiv(_ln_out({$1}),2.302585092994045)})dnl
dnl --- floor/ceil/round: extract integer part of decimal string ---
define({_do_floor},{ifelse(index({$1},{.}),-1,{$1},{ifelse(_is_neg_str({$1}),1,{define({__fi},substr({$1},1,eval(index({$1},{.})-1)))ifelse(_rtod_frac_nonzero(substr({$1},eval(index({$1},{.})+1))),1,{-_sadd(__fi,1)},{-__fi})},{substr({$1},0,index({$1},{.}))})})})dnl
define({_rtod_frac_nonzero},{ifelse({$1},,0,{ifelse(_stripz({$1}),0,0,1)})})dnl
define({_do_ceil},{ifelse(index({$1},{.}),-1,{$1},{ifelse(_is_neg_str({$1}),1,{-substr({$1},1,eval(index({$1},{.})-1))},{define({__ci},substr({$1},0,index({$1},{.})))ifelse(_rtod_frac_nonzero(substr({$1},eval(index({$1},{.})+1))),1,{_sadd(__ci,1)},__ci)})})})dnl
define({_do_round},{_do_floor(_sadd({$1},0.5))})dnl
dnl --- gamma: Stirling series with recurrence shift for small x ---
dnl ln(2*pi) at scale 10^18
define({_LN2PI_FP},{_load({1837877066409345484})})dnl
dnl _do_lngamma_s: Stirling for x>=7 (fixed-point, x is FP-scaled integer)
define({_do_lngamma_s},{dnl
define({__gx},{$1})dnl
define({__gxh},_Rssub(__gx,_Rdiv(_FP_S,_load({2}))))dnl
define({__glnx},_rP(_fpln(__gx/_FP_S,_OUT)))dnl
define({__gt1},_Rdiv(_Rsmul2(__gxh,__glnx),_FP_S))dnl
define({__gt2},_Rssub(__gt1,__gx))dnl
define({__gt3},_Rsadd(__gt2,_Rdiv(_LN2PI_FP,_load({2}))))dnl
define({__ginv},_Rdiv(_Rmul(_FP_S,_FP_S),__gx))dnl
define({__gi2},_Rdiv(_Rmul(__ginv,__ginv),_FP_S))dnl
define({__gs1},_Rdiv(__ginv,_load({12})))dnl
define({__gs2},_Rdiv(_Rdiv(_Rmul(__ginv,__gi2),_FP_S),_load({360})))dnl
define({__gs3},_Rdiv(_Rdiv(_Rmul(_Rdiv(_Rmul(__ginv,__gi2),_FP_S),__gi2),_FP_S),_load({1260})))dnl
define({__gs4},_Rdiv(_Rdiv(_Rmul(_Rdiv(_Rmul(_Rdiv(_Rmul(__ginv,__gi2),_FP_S),__gi2),_FP_S),__gi2),_FP_S),_load({1680})))dnl
_Rsadd(_Rssub(_Rsadd(_Rssub(_Rsadd(__gt3,__gs1),__gs2),__gs3),__gs4))})dnl
dnl _do_gamma: shift x up until >=7, compute Stirling, divide back
define({_do_gamma},{ifelse(_is_neg_str({$1}),1,{ERR:gamma_neg},{ifelse({$1},0,ERR:gamma0,{dnl
define({__garg},_Rdiv(_Rmul(_rP(_dtor({$1})),_FP_S),_rQ(_dtor({$1}))))dnl
define({__gshift},0)dnl
define({__gprod},{1})dnl
_gamma_shift()dnl
define({__glng},_do_lngamma_s(__garg))dnl
define({__gresult},_rtod(_fpexp(__glng/_FP_S,_OUT),_OUT))dnl
ifelse(__gshift,0,{__gresult},{_sdiv(__gresult,__gprod)})})})})dnl
dnl _gamma_shift: iteratively shift arg up, accumulate product
define({_gamma_shift},{ifelse(_Rgt(__garg,_Rsmul(_FP_S,12)),0,{dnl
define({__gprod},_smul(__gprod,_rtod(__garg/_FP_S,_OUT)))dnl
define({__garg},_Radd(__garg,_FP_S))dnl
define({__gshift},eval(__gshift+1))dnl
_gamma_shift()})})dnl
dnl --- conj: quaternion conjugate (scalar passthrough) ---
define({_do_conj},{ifelse(_isquat({$1}),1,{_qconj({$1})},{$1})})dnl
dnl --- norm: quaternion norm = sqrt(|q|^2) (scalar → abs) ---
define({_do_norm},{ifelse(_isquat({$1}),1,{_do_sqrt(_qnorm2({$1}))},{ifelse(_is_neg_str({$1}),1,{substr({$1},1)},{$1})})})dnl
dnl --- inv: quaternion inverse ---
define({_do_inv},{ifelse(_isquat({$1}),1,{_qinv({$1})},{_sdiv(1,{$1})})})dnl
dnl --- function dispatch (includes quaternion functions) ---
define({_atom_fn2},{_skip()_advance()ifelse({$1},{ln},{_ln_out({$2})},{$1},{sin},{_do_sin({$2})},{$1},{cos},{_do_cos({$2})},{$1},{tan},{_do_tan({$2})},{$1},{exp},{_do_exp({$2})},{$1},{sqrt},{_do_sqrt({$2})},{$1},{sinh},{_do_sinh({$2})},{$1},{cosh},{_do_cosh({$2})},{$1},{tanh},{_do_tanh({$2})},{$1},{atan},{_do_atan({$2})},{$1},{asin},{_do_asin({$2})},{$1},{acos},{_do_acos({$2})},{$1},{asinh},{_do_asinh({$2})},{$1},{acosh},{_do_acosh({$2})},{$1},{atanh},{_do_atanh({$2})},{$1},{gamma},{_do_gamma({$2})},{$1},{abs},{_do_abs({$2})},{$1},{log},{_do_log({$2})},{$1},{floor},{_do_floor({$2})},{$1},{ceil},{_do_ceil({$2})},{$1},{round},{_do_round({$2})},{$1},{conj},{_do_conj({$2})},{$1},{norm},{_do_norm({$2})},{$1},{inv},{_do_inv({$2})},{ERR:fn})})dnl
dnl --- postfix ---
define({_postfix},{_postfix2(_atom())})dnl
define({_postfix2},{_skip()ifelse(_ch,{!},{_advance()_emit(_Rfact({$1}))},{$1})})dnl
dnl --- unary ---
define({_unary},{_skip()ifelse(_ch,{-},{_advance()_unary_n(_unary())},_postfix())})dnl
define({_unary_n},{ifelse(_isquat({$1}),1,{_qmk(_sneg(_qR({$1})),_sneg(_qI({$1})),_sneg(_qJ({$1})),_sneg(_qK({$1})))},substr({$1},0,1),{-},{substr({$1},1)},ifelse({$1},{0},{0},{-{$1}}))})dnl
dnl --- power ---
define({_power},{_pw_tail(_unary())})dnl
define({_pw_tail},{_skip()ifelse(_ch,{^},{_advance()_pw_do({$1},_power())},_ch,{*},{define({__pp},_POS)_advance()ifelse(_ch,{*},{_advance()_pw_do({$1},_power())},{_setpos(__pp){$1}})},{$1})})dnl
define({_pw_do},{_spow({$1},{$2})})dnl
dnl --- term ---
define({_term},{_tm_rest(_power())})dnl
define({_tm_rest},{_skip()ifelse(_ch,{*},{define({__tp},_POS)_advance()ifelse(_ch,{*},{_setpos(__tp){$1}},{_tm_mul({$1},_power())})},_ch,{/},{_advance()_tm_div({$1},_power())},_ch,{%},{_advance()_tm_mod({$1},_power())},{$1})})dnl
define({_tm_mul},{_tm_rest(_smul({$1},{$2}))})dnl
define({_tm_div},{_tm_rest(_sdiv({$1},{$2}))})dnl
define({_tm_mod},{_tm_rest(_smod({$1},{$2}))})dnl
dnl --- expr ---
define({_expr},{_ex_rest(_term())})dnl
define({_ex_rest},{_skip()ifelse(_ch,{+},{_advance()_ex_add({$1},_term())},_ch,{-},{_advance()_ex_sub({$1},_term())},{$1})})dnl
define({_ex_add},{_ex_rest(_sadd({$1},{$2}))})dnl
define({_ex_sub},{_ex_rest(_ssub({$1},{$2}))})dnl
dnl ============================================================
define({CALC},{_setinput(translit({$1},{(),},{<>@}))_setpos(0)_qoutput(_expr())})dnl
M4
printf 'CALC({%s})\n' "$EXPR"
} | m4 -L 10000 2>/dev/null | tr -d ' \n'
echo
