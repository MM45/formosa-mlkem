require import AllCore  IntDiv Distr List DList KEM_ROM.
require import Array25 Array32 Array64 Array128 Array168 Array256 Array384.
require import Array768 Array960 Array1024 Array1152.
from Jasmin require import JWord.

require import MLWE_PKE_Hash.
require import GFq Rq  VecMat Sampling Symmetric Serialization.
require import InnerPKE MLKEM Correctness EncDecCorrectness KyberLib.

import Zq PolyVec PolyMat InnerPKE.

(* Rewriting the Spec in a way that allows applying computational
   assumptions on PRFs and PRG, as well as defining operators that
   can be used to instantiate the FO_MLKEM theory *)

(*****************************************************
We define a version of Kyber spec that
uses external samplers. This is useful for 
syntactic reasons in the following proof
steps.
******************************************************)

(* The spec defines the semantics of the operator *)
op parse : W64.t Array25.t -> poly * W64.t Array25.t.

axiom parse_sem st : 
  phoare [ Parse(XOF).sample : XOF.state = st ==> 
     res = (parse st).`1 /\ XOF.state = (parse st).`2 ] = 1%r.

(* We know they terminate, but we don't prove it. *)
axiom Parser_ll  : islossless Parse(XOF).sample.

module Hmodule = {
    proc sampleA(sd : W8.t Array32.t) : polymat = { 
     var i,j,c;
     var a : polymat;
     a <- witness;
     i <- 0;
     while (i < kvec) {
        j <- 0;
        while (j < kvec) {
           XOF.init(sd,j,i);
           (c,XOF.state) <- parse XOF.state;
           a.[(i,j)] <- c;
           j <- j + 1;
        }
        i <- i + 1;
     }
     return a;      
    }

    proc sampleAT(sd : W8.t Array32.t) : polymat = { 
     var i,j,c;
     var a : polymat;
     a <- witness;
     i <- 0;
     while (i < kvec) {
        j <- 0;
        while (j < kvec) {
           XOF.init(sd,i,j);
           (c,XOF.state) <- parse XOF.state;
           a.[(i,j)] <- c;
           j <- j + 1;
        }
        i <- i + 1;
     }
     return a;      
    }
}.

lemma KSamplerA_ll  : islossless Hmodule.sampleA.
proc;while(0<=i<=kvec) (kvec - i) => *; last by auto => /#.
move => *;wp;while(0<=i<kvec && 0<=j<=kvec) (kvec - j) => *; last by auto => /#.
by move => *;inline *;auto => /> /#.
qed.

lemma KSamplerAT_ll : islossless Hmodule.sampleAT.
proc;while(0<=i<=kvec) (kvec - i) => *; last by auto => /#.
move => *;wp;while(0<=i<kvec && 0<=j<=kvec) (kvec - j) => *; last by auto => /#.
by move => *;inline *;auto => /> /#.
qed.

import KMatrix.Matrix.
equiv H_sem_equiv : 
 Hmodule.sampleAT  ~ Hmodule.sampleA : ={arg} ==> res{1} = trmx res{2}.
proof. 
proc. 
inline XOF.init.
unroll for {1} 3;unroll for {2} 3.
unroll for {1} 10; unroll for {2} 10.
unroll for {1} 7; unroll for {2} 7.
unroll for {1} 4; unroll for {2} 4.
auto => /> &2. 
apply eq_matrixP => i j rng.
have rnji := mrangeL _ _ rng.
have rnjj := mrangeR _ _ rng.
by rewrite trmxE !setmE /= !offunmE //= !offunmK /mclamp rng /= /#. 
qed.

(* PRF keys in encryption come directly from srand *)
abbrev srand = darray32 W8.dword.

lemma srand_ll: is_lossless srand by smt(darray32_ll W8.dword_ll).

lemma srand_fu : is_full srand.
rewrite /darray32 /is_full => x. 
rewrite supp_dmap.
exists (to_list x).
rewrite to_listK /=.
rewrite supp_dlist 1:/# size_to_list /= allP => *. 
by rewrite dword_fu.
qed.

lemma srand_uni : is_uniform srand. 
rewrite /darray32. admitted. (* uniform darray *)


(* G needs only to be entropy smoothing, which is
   exactly a PRF without any input *)

require PRF.
clone PRF as HS_DEFS with
  type D <- unit,
  type R <- W8.t Array32.t * W8.t Array32.t
  proof *.

clone import HS_DEFS.PseudoRF as HSF with
  type K <- W8.t Array32.t, 
  op dK <- srand,
  op F <- fun i _ => G_coins i
  proof dK_ll by apply srand_ll
  proof *.

module KHS = HSF.PseudoRF.

module G(HS: HSF.PseudoRF) = {
  proc sample(s : W8.t Array32.t) : W8.t Array32.t * W8.t Array32.t = {
     var rhosig;
     rhosig <@ HS.f(s,());
     return rhosig;
  }
}.

clone PRF as PRF_DEFS with
  type D <- W8.t,
  type R <- W8.t Array128.t
  proof *.


clone import PRF_DEFS.PseudoRF as PRF_ with
  type K <- W8.t Array32.t, 
  op dK <- srand,
  op F <- Symmetric.PRF
  proof dK_ll by apply srand_ll
  proof *.

module KPRF = PRF_.PseudoRF.

module CBD2_PRF(PRF : PseudoRF) = {
   proc sample(sig : W8.t Array32.t, _N : int) : poly = {
    var i : int;
    var j : int;
    var a : int;
    var b : int;
    var rr : poly;
    var bytes;
    
    rr <- witness;
     bytes <@ PRF.f(sig, W8.of_int _N);

    i <- 0;
    j <- 0;
    while (i < 128){
      a <- b2i bytes.[i].[j %% 2 * 4 + 0] + b2i bytes.[i].[j %% 2 * 4 + 1];
      b <- b2i bytes.[i].[j %% 2 * 4 + 2] + b2i bytes.[i].[j %% 2 * 4 + 3];
      rr.[j] <- incoeff (a - b);
      j <- j + 1;
      a <- b2i bytes.[i].[j %% 2 * 4 + 0] + b2i bytes.[i].[j %% 2 * 4 + 1];
      b <- b2i bytes.[i].[j %% 2 * 4 + 2] + b2i bytes.[i].[j %% 2 * 4 + 3];
      rr.[j] <- incoeff (a - b);
      j <- j + 1;
      i <- i + 1;
    }
    
    return rr;
   }

   proc sample_spec(sig : W8.t Array32.t, _N : int) : poly = {
      var i,a,b,bytes,bits;
      var rr : poly;
      rr <- witness;
      bytes <@ PRF.f(sig, W8.of_int _N);
      bits <- BytesToBits (to_list bytes);
      i <- 0;
      while (i < 256) { 
        a <- b2i (nth false bits (4*i)) + b2i (nth false bits (4*i+1));
        b <- b2i (nth false bits (4*i+2)) + b2i (nth false bits (4*i+3));
        rr.[i] <- incoeff  (a - b);
        i <- i + 1;
      }
      return rr;

   }
}.

equiv cbd_correct : 
  CBD2_PRF(PseudoRF).sample ~ CBD2.sample :
  arg{2} = SHAKE256_33_128 arg{1}.`1 (W8.of_int arg{1}.`2) ==> ={res}
by proc => /=;inline *;sim;auto.

equiv cbdspec_correct (PRF <: PseudoRF): 
  CBD2_PRF(PRF).sample_spec ~ CBD2_PRF(PRF).sample :  ={arg,glob PRF} ==> ={res}.
proc => /=. 
seq 2 2 : (#pre /\ ={rr,bytes});1: by call(_: true);auto => />.
swap {2}1 1.
unroll for {1} ^while;
unroll for {2} ^while;
sim; auto =>/> &2;
have H : forall i, 0<=i<1024 => (nth false (BytesToBits (to_list bytes{2})) i) = 
                   bytes{2}.[i%/8].[i%%8]; last by rewrite !H //=.
move => i Hi. 
rewrite /BytesToBits (BitEncoding.BitChunking.nth_flatten false 8 (map W8.w2bits (to_list bytes{2})) _).
+ rewrite allP => k /=.
  rewrite mapP=> [[x [Hx1 ->]]].
  by rewrite W8.size_w2bits.  
rewrite -get_to_list (nth_map  witness%W8); 1: smt(Array128.size_to_list).
rewrite w2bitsE /= nth_mkseq /#.
qed.

import PolyVec PolyMat.

module InnerPKES(HS : HSF.PseudoRF, PRF1 : PRF_.PseudoRF, PRF2 : PRF_.PseudoRF)  = {
  proc prg_kg(coins:W8.t Array32.t) : W8.t Array32.t * polyvec * polyvec = {
    var noise1 : polyvec;
    var noise2 : polyvec;
    var _N,i,c,rho,noiseseed;
    (rho, noiseseed) <- G_coins coins;
    noise1 <- witness;                     
    noise2 <- witness;                      
    _N <- 0;                      
    i <- 0;                             
    while (i < kvec) {                 
      c <@ CBD2_PRF(PRF1).sample(noiseseed,_N);
      noise1 <- noise1.[i<-c];                   
      _N <- _N + 1;                     
     i <- i + 1;                       
    }                                  
    i <- 0;                             
    while (i < kvec) {                 
      c <@ CBD2_PRF(PRF1).sample(noiseseed,_N);
      noise2 <- noise2.[i<-c];                  
      _N <- _N + 1;                     
      i <- i + 1;                       
    }                                  

    return (rho,noise1,noise2);
  }

   proc prg_enc(noiseseed:W8.t Array32.t) : polyvec * polyvec * poly = {
    var noise1 : polyvec;
    var noise2 : polyvec;
     var e2,_N,i,c;
     noise1 <- witness;                     
     noise2 <- witness;                      
     _N <- 0;                      
     i <- 0;                             
     while (i < kvec) {                 
       c <@ CBD2_PRF(PRF2).sample(noiseseed,_N);
       noise1 <- noise1.[i<-c];                   
       _N <- _N + 1;                     
      i <- i + 1;                       
     }                                  
     i <- 0;                             
     while (i < kvec) {                 
       c <@ CBD2_PRF(PRF2).sample(noiseseed,_N);
      noise2 <- noise2.[i<-c];                   
      _N <- _N + 1;                     
      i <- i + 1;                       
     }                                  
     e2 <@ CBD2_PRF(PRF2).sample(noiseseed,_N);
     return (noise1,noise2, e2);
  }

  (* Spec gives a derandomized enc that matches this code *)
  proc kg_derand(coins: W8.t Array32.t) : pkey * skey = {
     var t,rho;
     var tv,sv : W8.t Array1152.t;
     var a : polymat;
     var s,e : polyvec;
     e <- witness;
     s <- witness;
     sv <- witness;
     tv <- witness;
     (rho,s,e) <@ prg_kg(coins);
     a <@ Hmodule.sampleA(rho);     
     s <- nttv s;
     e <- nttv e; 
     t <- (ntt_mmul a s + e)%PolyVec;
     tv <@ EncDec.encode12_vec(toipolyvec t); (* minimum residues *)
     sv <@ EncDec.encode12_vec(toipolyvec s); (* minimum residues *)
     return ((tv,rho),sv);
  }

  (* Spec gives a derandomized enc that matches this code *)
  proc enc_derand(pk : pkey, m : plaintext, r : W8.t Array32.t) : ciphertext = {
      var tv,rho,rv,e1,e2,rhat,u,v,mp,c2,thati;
      var that : polyvec;
      var aT : polymat;
      var c1 : W8.t Array960.t;
      aT <- witness;
      c1 <- witness;
      e1 <- witness;
      rv <- witness;
      that <- witness;
      (rv,e1,e2) <@ prg_enc(r);
      (tv,rho) <- pk;
      thati <@ EncDec.decode12_vec(tv); 
      that <- ofipolyvec thati;
      aT <@ Hmodule.sampleAT(rho);    
      rhat <- nttv rv;
      u <- (invnttv (ntt_mmul aT rhat) + e1)%PolyVec;
      mp <@ EncDec.decode1(m);
      v <- invntt (ntt_dotp that rhat) &+ e2 &+ decompress_poly 1 mp; 
      c1 <@ EncDec.encode10_vec(compress_polyvec 10 u); 
      c2 <@ EncDec.encode4(compress_poly 4 v);
      return (c1,c2);
  }

  proc dec(sk : skey, cph : ciphertext) : plaintext option = {
      var m,mp,ui,v,vi,si, c1, c2;
      var u,s : polyvec;
      u <- witness;
      s <- witness;
      (c1,c2) <- cph;
      ui <@ EncDec.decode10_vec(c1);
      u <- decompress_polyvec 10 ui;
      vi <@ EncDec.decode4(c2);
      v <- decompress_poly 4 vi;
      si <@ EncDec.decode12_vec(sk);
      s <- ofipolyvec si;
      mp <- v &+ ((&-) (invntt (ntt_dotp s (nttv u))));
      m <@ EncDec.encode1(compress_poly 1 mp);
      return Some m;
  }

}.

import KMatrix Vector.

(* Fixme: move to Matrix *)
lemma getv_setvE x i j (v : polyvec) : 
  (v.[i <- x].[j])%Vector = if (0 <= j < kvec) then if (i = j) then x else (v.[j])%Vector else Rq.zero
   by smt(setvE getvE getv_out offunvE).

(* We have something equivalent to the spec *)
import Symmetric.
lemma kg_sampler_kg  :
  equiv [  InnerPKES(KHS,KPRF,KPRF).kg_derand ~ InnerPKE.kg_derand : 
     ={arg} /\ ={glob XOF} ==> ={res, glob XOF}].
proc. 
sim.
inline {1} 5. proc case {1} 14. (* NEED TO BREAK TUPLE ASSIGNMENT *)
swap {1} 14 -7. swap {1} 17 -9. wp.
inline CBD2_PRF(PseudoRF).sample.
inline CBD2.sample.
inline PseudoRF.f.
while (noise1{1} = s{2} /\ rho{1} = rho{2} /\ noiseseed{1} = sig{2} /\
       ={i,_N,a,XOF.state} /\
       0<=i{1}<=kvec /\ 
       forall k, 0 <=k < i{1} => (noise2{1}.[k])%Vector = (e{2}.[k])%Vector).
+ wp; conseq(_: ={rr0}); 1: by smt(getv_setvE).  
  by inline*; sim; auto => />. 
wp;conseq (: noise1{1} = s{2} /\ 
             rho{1} = rho{2} /\
             noiseseed{1} = sig{2} /\
             ={_N, a, XOF.state}); first by smt(eq_vectorP).

while (rho{1} = rho{2} /\ noiseseed{1} = sig{2} /\
       ={i,_N,a,XOF.state} /\
       0<=i{1}<=kvec /\ 
       forall k, 0 <=k < i{1} => (noise1{1}.[k])%Vector = (s{2}.[k])%Vector).
+ wp; conseq(_: ={rr}); 1: by smt(getv_setvE).  
  by inline*; sim; auto => />. 
swap {2} 7 2. swap {1} [9..10] -1.  
wp;conseq (: rho{1} = rho{2} /\ 
             noiseseed{1} = sig{2} /\
             ={a, XOF.state}); 1: by smt(eq_vectorP).
inline {1} 10;wp; conseq />.
while (#post /\ sd{1} = rho{1} /\ i2{1} = i{2} /\ 0<=i2{1}<=kvec); last by auto => /> /#.
wp;while (#post /\ j1{1} = j{2} /\ 0<=j1{1}<=kvec); 
     last by auto => /> /#.
wp;ecall{2} (parse_sem XOF.state{2}). 
by inline *; auto => /> /#.
qed.

lemma enc_sampler_enc  :
 equiv [
   InnerPKES(KHS,KPRF,KPRF).enc_derand ~ InnerPKE.enc_derand : 
    ={arg} /\ ={glob XOF} ==> ={res, glob XOF}].
proc. 
swap {1} [7..10] -1. inline {1} 10. inline {1} 18. inline {1} 21. inline{2} 16.
sim;wp; 
conseq (: ={that,_N,m,aT,XOF.state} /\
  noise2{1} = e1{2} /\
  noise1{1} = rv{2} /\
  noiseseed{1} = coins{2}); 1: smt().
while (={i, that, _N, m, aT, XOF.state} /\ noise1{1} = rv{2} /\ noiseseed{1} = coins{2} /\
       0<=i{1}<=kvec /\ 
       forall k, 0 <=k < i{1} => (noise2{1}.[k])%Vector = (e1{2}.[k])%Vector).
+ inline *;wp;conseq(_: ={rr0}); 1: by smt(getv_setvE).  by inline*; sim; auto => />. 
wp;conseq (: ={that,_N,m,aT,XOF.state} /\
  noise1{1} = rv{2} /\
  noiseseed{1} = coins{2}); first by smt(eq_vectorP).
while (={i, that, _N, m, aT, XOF.state} /\ noiseseed{1} = coins{2} /\
       0<=i{1}<=kvec /\ 
       forall k, 0 <=k < i{1} => (noise1{1}.[k])%Vector = (rv{2}.[k])%Vector).
+ inline *;wp; conseq(_: ={rr0}); 1: by smt(getv_setvE).  
  by inline*; sim; auto => />. 
swap {2} 7 4. swap {1} [10..12] -1.  
wp;conseq (: ={that, m, aT, XOF.state} /\ noiseseed{1} = coins{2}); 1: by smt(eq_vectorP).
inline {1} 12. 
wp;conseq />. 
while (#post /\ sd{1} = rho{2} /\ noiseseed{1} = coins{2} /\ i1{1} = i{2} /\ 0<=i1{1}<=kvec); last first.
+ wp;conseq />.
  call(_: true); 1: by sim.
  by inline *;auto => />.

wp;while (#post /\ i1{1} = i{2} /\ j0{1} = j{2} /\ 0<=j0{1}<=kvec); 
     last by auto => /> /#.
wp;ecall{2} (parse_sem XOF.state{2}). 
by inline *; auto => />  /#.
qed.

lemma enc_sampler_dec :
  equiv [ InnerPKES(KHS,KPRF,KPRF).dec ~ InnerPKE.dec : 
     ={arg}  ==> res{1} = Some res{2} ] by proc;inline *;sim => /#.

(* NOW THE KEM MOVED TO THE ROM *)

abbrev dsmooth = darray32 W8.dword `*` darray32 W8.dword.

lemma dsmooth_ll: is_lossless dsmooth
  by apply dprod_ll;split;apply darray32_ll;apply W8.dword_ll.

clone import KEM_ROM as SPEC_MODEL with 
  type pkey <- publickey,
  type skey <- secretkey,
  type key <- sharedsecret,
  op dkey <- srand,
  type ciphertext <- ciphertext,
  type RO.in_t <- W8.t Array32.t * W8.t Array32.t,
  type RO.out_t <- W8.t Array32.t * W8.t Array32.t,
  op RO.dout <- fun _ => dsmooth
  proof dkey_ll by apply srand_ll
  proof dkey_fu by apply srand_fu
  proof dkey_uni by apply srand_uni
  proof *.
import RO.

module (KyberS(HS : HSF.PseudoRF, PRF1 : PRF_.PseudoRF, PRF2 : PRF_.PseudoRF) : Scheme) (O : POracle) = {
  proc kg_derand(coins : W8.t Array32.t * W8.t Array32.t) : publickey * secretkey = {
    var kgs : W8.t Array32.t;
    var z : W8.t Array32.t;
    var pk : pkey;
    var sk : skey;
    var hpk : W8.t Array32.t;
    
    kgs <- coins.`1;
    z <- coins.`2;
    (pk, sk) <@ InnerPKES(HS,PRF1,PRF2).kg_derand(kgs);
    hpk <- H_pk pk;
    
    return (pk, (sk, pk, hpk, z));
  }

  proc kg() : publickey * secretkey = {
    var coins;
    var pk : publickey;
    var sk : secretkey;
    
    coins <$ dsmooth;
    (pk, sk) <@ kg_derand(coins);
    
    return (pk,sk);
  }

  
  proc enc_derand(pk : publickey, coins : W8.t Array32.t) : ciphertext * sharedsecret = {
    var m : W8.t Array32.t;
    var hpk : W8.t Array32.t;
    var r : W8.t Array32.t;
    var c : ciphertext;
    var _K : W8.t Array32.t;
    
    m <- coins;
    hpk <- H_pk pk;
    (_K, r) <@ O.get(m,hpk);
    c <@ InnerPKES(HS,PRF1,PRF2).enc_derand(pk, m, r);
    
    return (c, _K);
  }

  proc enc(pk : publickey) : ciphertext * sharedsecret = {
    var coins;
    var c : ciphertext;
    var _K : W8.t Array32.t;
    
    coins <$ srand;
    (c, _K) <@ enc_derand(pk,coins);
    
    return (c,_K);
  }

  
  proc dec(sk : secretkey, cph : ciphertext) : sharedsecret option = {
    var m : plaintext;
    var _K' : W8.t Array32.t;
    var r : W8.t Array32.t;
    var skp : Top.InnerPKE.InnerPKE.skey;
    var pk : Top.InnerPKE.InnerPKE.pkey;
    var hpk : W8.t Array32.t;
    var z : W8.t Array32.t;
    var c : Top.InnerPKE.InnerPKE.ciphertext;
    var _K : W8.t Array32.t;
    
    (skp, pk, hpk, z) <- sk;
    m <@ InnerPKE.dec(skp, cph);
    (_K, r) <@ O.get(m,hpk);
    _K' <- J z cph;
    c <@ InnerPKES(HS,PRF1,PRF2).enc_derand(pk, m, r);
    if (c <> cph) 
      _K <- _K';
    
    return (Some _K);
  }
}.




(*******************************************************************)
(*    The security definitions for the spec                        *)
(*   Types correspond to implementation types                      *)
(*******************************************************************)

import KMatrix PolyVec PolyMat InnerPKE Zq.

op pk_encode(pk : polyvec * W8.t Array32.t) : pkey = 
                                  (encode12_vec (toipolyvec (nttv pk.`1)) ,pk.`2).
op pk_decode(pk : pkey) = (invnttv (ofipolyvec (sem_decode12_vec (pk.`1))),pk.`2).
op sk_encode(sk : polyvec) : skey = encode12_vec (toipolyvec (nttv sk)).
op sk_decode(sk : skey) =  invnttv (ofipolyvec (sem_decode12_vec sk)).
op m_encode(m : plaintext) : poly = decompress_poly 1 (sem_decode1 m).
op m_decode(p : poly) : plaintext = encode1 (compress_poly 1 p). 
op c_encode(c :  polyvec * poly) : ciphertext = 
      (encode10_vec_aux (compress_polyvec 10 c.`1), encode4 (compress_poly 4 c.`2)).
op c_decode(c : ciphertext) =
      (decompress_polyvec 10 (sem_decode10_vec c.`1), decompress_poly 4 (sem_decode4 c.`2)).


lemma pk_encodeK : cancel pk_encode pk_decode.
rewrite /pk_decode /pk_encode /cancel /= => x.
rewrite sem_decode12_vec_corr -sem_encode12_vecK; last by rewrite toipolyvecK invnttvK /#.
move => i ib; rewrite /toipolyvec !mapiE /= 1:ib.
by smt(rg_asint qE).
qed.

lemma sk_encodeK: cancel sk_encode sk_decode.
rewrite /sk_decode /sk_encode /cancel /= => x.
rewrite sem_decode12_vec_corr  -sem_encode12_vecK; last by rewrite toipolyvecK invnttvK /#.
move => i ib; rewrite /toipolyvec !mapiE /= 1:ib.
by smt(rg_asint qE).
qed.

op max_noise = q %/ 4 - 1.
op under_noise_bound (p : poly) (b : int) =
     all (fun cc => `| as_sint cc| <= b) p.

op H : W8.t Array32.t -> polymat.

lemma H_sem _seed :
    phoare [ Hmodule.sampleA : sd = _seed ==> res = H _seed ] = 1%r.
admitted. (* IDEALLY PROC OP *)

op prg_kg_inner :  W8.t Array32.t -> W8.t Array32.t * polyvec * polyvec.
lemma prg_kg_sem _coins : 
   phoare [ InnerPKES(KHS,KPRF,KPRF).prg_kg : coins = _coins ==> res = prg_kg_inner _coins ] = 1%r.
admitted. (* IDEALLY PROC OP *)

op prg_enc_inner :  W8.t Array32.t -> polyvec * polyvec * poly.
lemma prg_enc_sem _coins : 
   phoare [ InnerPKES(KHS,KPRF,KPRF).prg_enc : noiseseed = _coins ==> res = prg_enc_inner _coins ] = 1%r.
admitted. (* IDEALLY PROC OP *)

lemma H_T_sem _seed :
    phoare [ Hmodule.sampleAT : sd = _seed ==> res = trmx (H _seed) ] = 1%r
  by conseq (H_sem_equiv) (H_sem _seed) => /#.

clone import MLWE_PKE_Hash as MLWEPKEHash with
  type MLWE_.seed <- W8.t Array32.t,
  type MLWE_.Matrix_.R <- poly,
  type MLWE_.Matrix_.Matrix.matrix <- polymat,
  type MLWE_.Matrix_.vector <- polyvec,
  type MLWE_.Matrix_.ZR.t <- poly,
  pred MLWE_.Matrix_.ZR.unit <- KMatrix.ZR.unit,
  type FO_MLKEM.UU.key <- sharedsecret,
  type plaintext <- plaintext,
  type randomness <- W8.t Array32.t,
  type FO_MLKEM.UU.PseudoRF.K <- sharedsecret,
  op MLWE_.H <- H,
  op prg_kg <- prg_kg_inner,
  op prg_enc <- prg_enc_inner,
  op MLWE_.Matrix_.ZR.(+) <- Rq.(&+),
  op MLWE_.Matrix_.ZR.([-]) <- Rq.(&-),
  op MLWE_.Matrix_.ZR.zeror <- Rq.zero,
  op MLWE_.Matrix_.ZR.oner <- Rq.one,
  op MLWE_.Matrix_.ZR.( * ) <- Rq.(&*),
  op MLWE_.Matrix_.ZR.invr <- Top.Correctness.invr, (* FIXME: Why Top *)
  op MLWE_.Matrix_.size <- kvec,
  op MLWE_.Matrix_.Vector.(+) <- Top.Correctness.KMatrix.Vector.(+),
  op MLWE_.Matrix_.Vector.dotp <- dotp,
  op MLWE_.Matrix_.Vector.prevector <- prevector,
  op MLWE_.Matrix_.Vector.vclamp <- vclamp,
  op MLWE_.Matrix_.Vector.tofunv <- tofunv,
  op MLWE_.Matrix_.Vector.offunv <- offunv,
  op MLWE_.Matrix_.Matrix.prematrix <- prematrix,
  op MLWE_.Matrix_.Matrix.mclamp <- mclamp,
  op MLWE_.Matrix_.Matrix.tofunm <- tofunm,
  op MLWE_.Matrix_.Matrix.offunm <- offunm, 
  op MLWE_.duni_R <- duni_R,
  op MLWE_.dshort_R <- dshort_R,
  op MLWE_.dseed <- srand,
  op m_encode <- m_encode,
  op m_decode <- m_decode,
  op under_noise_bound <- under_noise_bound,
  op max_noise <- max_noise,
  op drand <- srand,
  op FO_MLKEM.UU.TT.dplaintext <- srand,
  op FO_MLKEM.UU.dkey <- srand,
  op FO_MLKEM.UU.PseudoRF.dK <- srand,
  op FO_MLKEM.UU.PseudoRF.F = J (* FIX ME, CAN'T PRF DECODED VALUES *)
  proof MLWE_.dseed_ll by (apply srand_ll)
  proof MLWE_.dshort_R_ll  by apply dshort_R_ll
  proof MLWE_.duni_R_ll by apply duni_R_ll
  proof MLWE_.duni_R_fu by apply duni_R_fu
  proof MLWE_.Matrix_.ge0_size by smt()
  proof MLWE_.Matrix_.ZR.addrA by apply KMatrix.ZR.addrA
  proof MLWE_.Matrix_.ZR.addrC by apply KMatrix.ZR.addrC
  proof MLWE_.Matrix_.ZR.add0r by apply KMatrix.ZR.add0r
  proof MLWE_.Matrix_.ZR.addNr by apply KMatrix.ZR.addNr
  proof MLWE_.Matrix_.ZR.oner_neq0 by apply KMatrix.ZR.oner_neq0
  proof MLWE_.Matrix_.ZR.mulrA by apply KMatrix.ZR.mulrA
  proof MLWE_.Matrix_.ZR.mulrC by apply KMatrix.ZR.mulrC
  proof MLWE_.Matrix_.ZR.mul1r by apply KMatrix.ZR.mul1r
  proof MLWE_.Matrix_.ZR.mulrDl by apply KMatrix.ZR.mulrDl
  proof MLWE_.Matrix_.ZR.mulVr by apply KMatrix.ZR.mulVr
  proof MLWE_.Matrix_.ZR.unitP by apply KMatrix.ZR.unitP
  proof MLWE_.Matrix_.ZR.unitout by apply KMatrix.ZR.unitout
  proof MLWE_.Matrix_.Vector.tofunv_prevector by apply tofunv_prevector
  proof MLWE_.Matrix_.Vector.tofunvK by apply tofunvK
  proof MLWE_.Matrix_.Vector.offunvK by apply offunvK
  proof MLWE_.Matrix_.Matrix.tofunm_prematrix by apply tofunm_prematrix
  proof MLWE_.Matrix_.Matrix.tofunmK by apply tofunmK
  proof MLWE_.Matrix_.Matrix.offunmK by apply offunmK
  proof MLWE_.duni_R_uni by apply duni_R_uni
  proof drand_ll by apply srand_ll
  proof drand_uni by apply srand_uni
  proof drand_fu by apply srand_fu
  proof prg_kg_correct
  proof prg_enc_correct
  proof good_decode
  proof *.


     FO_MLKEM.UU.TT.dplaintext_ll: is_lossless dplaintext
 FO_MLKEM.UU.TT.dplaintext_uni: is_uniform dplaintext
 FO_MLKEM.UU.TT.dplaintext_fu: is_full dplaintext
 FO_MLKEM.UU.TT.FinT.enum_spec: forall (x : plaintext), count (pred1 x) enum = 1
 FO_MLKEM.UU.TT.ge0_qH: 0 <= qH
 FO_MLKEM.UU.TT.ge0_qV: 0 <= qV
 FO_MLKEM.UU.TT.ge0_qP: 0 <= qP
 FO_MLKEM.UU.TT.ge0_qHC: 0 <= qHC
 FO_MLKEM.UU.dkey_ll: is_lossless UU.dkey
 FO_MLKEM.UU.dkey_uni: is_uniform UU.dkey
 FO_MLKEM.UU.dkey_fu: is_full UU.dkey
 FO_MLKEM.UU.PseudoRF.dK_ll: is_lossless dK
 FO_MLKEM.UU.ge0_qHT: 0 <= qHT
 FO_MLKEM.UU.ge0_qHU: 0 <= qHU
 FO_MLKEM.UU.ge0_qD: 0 <= qD
 FO_MLKEM.KEMROM.dkey_ll: is_lossless UU.dkey
 FO_MLKEM.KEMROM.dkey_uni: is_uniform UU.dkey
 FO_MLKEM.KEMROM.dkey_fu: is_full UU.dkey
 FO_MLKEM.ge0_qHK: 0 <= qHK
  *)

realize prg_kg_correct.
admitted. (* Ideally proc op *)

realize prg_enc_correct.
admitted. (* Ideally proc op *)

realize good_decode.
rewrite /under_noise_bound /m_encode /m_decode /compress_poly 
        /decompress_poly /max_noise qE /= => m n.
rewrite allP  => /=  hgood.
rewrite sem_decode1_corr.
have : decode1 (encode1 (map (compress 1) (map (decompress 1) (decode1 m) &+ n))) = 
       (decode1 m); last by smt(sem_decode1K).
apply Array256.ext_eq => /> x h0x hx256. 
rewrite -sem_encode1K. 
+ move => i ib; rewrite !mapiE /= 1:ib /compress /= /#.
rewrite /(&+) mapiE 1:/# map2E /= initiE /= 1:/# mapiE 1:/#.
rewrite -sem_decode1_corr.
have [->|->] /=: (sem_decode1 m).[x]=0 \/ (sem_decode1 m).[x]=1
 by smt(sem_decode1_bnd).
 rewrite /decompress /=.
 rewrite from_int_round.
 rewrite -{1}zeroE asintK Zq.ZModule.add0r compress1_is0 // Bq1E.
 smt().
rewrite /decompress /round /=.
have ->: q%r / 2%r + inv 2%r = (q%r+1%r)/2%r
 by field; smt().
rewrite qE -fromintD -divz_floor //=.
have: compress 1 (incoeff 1665 + n.[x]) <> 0.
 rewrite compress1_is0 Bq1E.
 move: (hgood x _) => //. 
 rewrite (_:832=831+1) 1://. 
 move=> /absZqP [H|].
 rewrite absZqP negb_or; split.
  smt(incoeffK).
 rewrite qE /=. 
  smt(incoeffK).
 rewrite qE /=.
 smt(incoeffK).
by rewrite /compress /=; smt(ltz_pmod modz_ge0).
qed.


(*******************************************************************)
(*    Entropy Smoothing and PRF hops  for Security                 *)
(*******************************************************************)

clone import HS_DEFS.RF as IdealHSF with
   op dR = fun (_: unit) => dsmooth
   proof dR_ll by smt(dsmooth_ll).

abbrev dnbytes = darray128 W8.dword.

lemma dnbytes_ll: is_lossless dnbytes.
proof.
apply darray128_ll.
by apply W8.dword_ll.
qed.

clone import PRF_DEFS.RF as IdealPRF1 with
   op dR = fun (_: W8.t) => dnbytes
   proof dR_ll by smt(dnbytes_ll).

clone import PRF_DEFS.RF as IdealPRF2 with
   op dR = fun (_: W8.t) => dnbytes
   proof dR_ll by smt(dnbytes_ll).

module DummyHS_D(F : HS_DEFS.PRF_Oracles) = {
   proc keygen() : W8.t Array32.t = { return witness;}
   proc f(inp : W8.t Array32.t * unit) : W8.t Array32.t * W8.t Array32.t = { var out; out <@ F.f(); return out; }
}.

module DummyHS(F : HS_DEFS.PRF_Oracles) = {
   proc keygen() : W8.t Array32.t = { IdealHSF.RF.m <- SmtMap.empty; return witness;}
   proc f(inp : W8.t Array32.t * unit) : W8.t Array32.t * W8.t Array32.t = { var out; out <@ F.f(); return out; }
}.


module (D_ES(As : CCA_ADV) : HS_DEFS.Distinguisher) (F : HS_DEFS.PRF_Oracles)  = {

    proc distinguish() : bool = {
       var b;
       b <@ CCA(LRO,KyberS(DummyHS_D(F),KPRF,KPRF),As).main();
       return b;
    } 
}.

module KyberSIdeal(HS : HSF.PseudoRF, PRF1 : PRF_.PseudoRF, PRF2 : PRF_.PseudoRF, O : POracle) (* : Scheme *) = {

  include KyberS(HS,PRF1,PRF2,O) [-kg]

  proc kg() : publickey * secretkey = {
     var s,rho,sig,kp;
     s <@ HS.keygen();
     rho <$ srand;
     sig <@ PRF1.keygen();
     kp <@ kg_derand(rho,sig);
     return kp;
  }

}.

module DummyPRF1D(F : PRF_DEFS.PRF_Oracles) = {
   proc keygen() : W8.t Array32.t = { return witness;}
   proc f(inp : W8.t Array32.t * W8.t) : W8.t Array128.t = { var out; out <@ F.f(inp.`2); return out; }
}.

module DummyPRF1(F : PRF_DEFS.PRF_Oracles) = {
   proc keygen() : W8.t Array32.t = { IdealPRF1.RF.m <- SmtMap.empty; return witness;}
   proc f(inp : W8.t Array32.t * W8.t) : W8.t Array128.t = { var out; out <@ F.f(inp.`2); return out; }
}.

module (D_PRF1(As : CCA_ADV) : PRF_DEFS.Distinguisher) (F : PRF_DEFS.PRF_Oracles)  = {

    proc distinguish() : bool = {
       var b;
       b <@ CCA(LRO,KyberSIdeal(DummyHS(IdealHSF.RF),DummyPRF1(F),KPRF),As).main();
       return b;
    } 
}.

module DummyPRF2D(F : PRF_DEFS.PRF_Oracles) = {
   proc keygen() : W8.t Array32.t = { return witness;}
   proc f(inp : W8.t Array32.t * W8.t) : W8.t Array128.t = { var out; out <@ F.f(inp.`2); return out; }
}.

module DummyPRF2(F : PRF_DEFS.PRF_Oracles) = {
   proc keygen() : W8.t Array32.t = { IdealPRF2.RF.m <- SmtMap.empty; return witness;}
   proc f(inp : W8.t Array32.t * W8.t) : W8.t Array128.t = { var out; out <@ F.f(inp.`2); return out; }
}.

module (D_PRF2(As : CCA_ADV) : PRF_DEFS.Distinguisher) (F : PRF_DEFS.PRF_Oracles)  = {

    proc distinguish() : bool = {
       var b;
       b <@ CCA(LRO,KyberSIdeal(DummyHS(IdealHSF.RF),DummyPRF1(IdealPRF1.RF),DummyPRF2D(F)),As).main();
       return b;
    } 
}.

section.

declare module As <: CCA_ADV {-CCA, -XOF,-IdealPRF2.RF, -IdealPRF1.RF, -PRF_.PRF, -IdealHSF.RF, -HSF.PRF, -LRO, -KPRF}.

lemma ESHop &m :
  Pr [ CCA(LRO,KyberS(KHS,KPRF,KPRF),As).main() @ &m : res] -
  Pr [ CCA(LRO,KyberS(DummyHS(IdealHSF.RF),KPRF,KPRF),As).main() @ &m : res] = 
  Pr [ HS_DEFS.IND(HSF.PRF,D_ES(As)).main() @ &m : res ] - 
  Pr [ HS_DEFS.IND(IdealHSF.RF,D_ES(As)).main() @ &m : res ].
proof.
have -> : Pr[CCA(LRO,KyberS(KHS, KPRF,KPRF), As).main() @ &m : res]  = 
          Pr[HS_DEFS.IND(HSF.PRF, D_ES(As)).main() @ &m : res] .
+ byequiv => //.
  proc. 
  inline {2} 2. inline {2} 2.
  wp; call(_: ={glob LRO, glob CCA}); 1,2: by sim.
  wp; call(_: ={glob LRO, glob CCA}); 1: by sim.
  rnd;rnd.
  wp; call(_: ={glob LRO}); 1: by sim.
  conseq (_: _ ==> ={glob LRO,CCA.cstar}); 1: smt().
  by inline *; auto => />.

+ have -> : 
    Pr[CCA(LRO,KyberS(DummyHS(IdealHSF.RF), KPRF, KPRF), As).main() @ &m : res] = 
    Pr[HS_DEFS.IND(IdealHSF.RF, D_ES(As)).main() @ &m : res]; 2: by done.
+ byequiv => //.
  proc. 
  inline {2} 2. inline {2} 2.
  wp; call(_: ={glob LRO, glob CCA}); 1,2: by sim.
  wp; call(_: ={glob LRO, glob CCA}); 1: by sim.
  rnd;rnd.
  wp; call(_: ={glob LRO}); 1: by sim.
  conseq (_: _ ==> ={glob LRO,CCA.cstar}); 1: smt().
  by inline *; auto => />.
qed.


module ArraySample = {
   proc sL() = { 
       var r,rho,k;
       r <$ IdealHSF.dR (); 
       rho <- Array32.init (fun (i : int) => r.`1.[i]); 
       k <- Array32.init (fun (i : int) => r.`2.[i]); 
       return (rho,k);
  }

   proc sR() = { 
       var rho,k;
       rho <$ srand; 
       k <$ srand; 
       return (rho,k);
  }
}.


require import DProd.
clone  ProdSampling with
  type t1 <- W8.t Array32.t,
  type t2 <- W8.t Array32.t.

lemma arrsample :
  equiv [ ArraySample.sL ~ ArraySample.sR : true ==> ={res} ].
proc;wp;rndsem {2} 0;auto => />. 
have <- : dlet srand (fun (rho : W8.t Array32.t) => dmap srand (fun (k : W8.t Array32.t) => (rho, k)))  = (IdealHSF.dR ()).
+ by rewrite /dR /dmap dprod_dlet;congr;apply fun_ext => *;congr;rewrite /(\o) /=. 
move => ?rl?;split => *;last by split;rewrite tP => *;rewrite initiE /#.
rewrite supp_dlet /=;exists rl.`1;split => *;1: apply srand_fu.
rewrite supp_dmap /=;exists rl.`2;split => *; last by smt().
by apply srand_fu. 
qed.

lemma KyberS_KyberIdeal &m :
  Pr [ KyberPKE.CPA(O,KyberS(DummyHS(IdealHSF.RF),S,KNS,KPRF,KPRF),As).main() @ &m : res] =
  Pr [ KyberPKE.CPA(O,KyberSIdeal(DummyHS(IdealHSF.RF),S,KNS,KPRF,KPRF),As).main() @ &m : res].
proof.
byequiv => //.
proc. 
  inline {1} 2; inline {2} 2. 
  wp; call(_: ={glob O}); 1: by sim.
  wp; call(_: ={glob O, glob S}); 1: by sim.
  rnd.
  wp; call(_: ={glob O}); 1: by sim.
  conseq (_: _ ==> ={pk, glob O,glob S}); 1: smt().
  seq 1 1 : (={glob As, glob S, glob O}); 1: by sim.
  inline {1} 1. inline {2} 1. 
  wp; call(_: ={glob O, glob S}); 1: by sim.
  conseq => />.
  inline *.
  rcondt{1} 6; 1: by move => *; auto => />;smt(@SmtMap).
  seq {1} 5 2 : (true); 1: by auto.
  wp.
  conseq (_: _ ==> rho{2} = Array32.init (fun i => r{1}.`1.[i]) /\ 
                   k{2} = Array32.init (fun i => r{1}.`2.[i])); first
   by move=> /> &1 *; rewrite SmtMap.get_set_sameE /=;split;rewrite tP => *;rewrite initiE /#.
 
  transitivity {1} { r <@ ArraySample.sL(); }
   (true ==> ={r}) (true ==> rho{2} = Array32.init (fun i =>  r{1}.`1.[i]) /\ k{2} = Array32.init (fun i =>  r{1}.`2.[i])) => //; first
   by inline*; auto => /> &1 ? [rl1 rl2] /= => *;split;rewrite tP => *;rewrite initiE /#.
   
  transitivity {2} { (rho, k) <@ ArraySample.sR(); }
   (true ==> rho{2} = Array32.init (fun i =>  r{1}.`1.[i]) /\ k{2} = Array32.init (fun i =>  r{1}.`2.[i])) (true ==> ={rho,k})=> //.
   call arrsample; 1: by auto => />  *;split;rewrite tP => *;rewrite initiE /#.
   by inline*; auto => /> &1 ? [rl1 rl2] /= => *;split;rewrite tP => *;rewrite initiE /#.
qed.


lemma PRFHop1 &m :
  Pr [ KyberPKE.CPA(O,KyberSIdeal(DummyHS(IdealHSF.RF),S,KNS,KPRF,KPRF),As).main() @ &m : res] -
  Pr [ KyberPKE.CPA(O,KyberSIdeal(DummyHS(IdealHSF.RF),S,KNS,DummyPRF1(IdealPRF1.RF),KPRF),As).main() @ &m : res] = 
  Pr [ PRF_DEFS.IND(PRF_.PRF,D_PRF1(S,O,As)).main() @ &m : res ] - 
  Pr [ PRF_DEFS.IND(IdealPRF1.RF,D_PRF1(S,O,As)).main() @ &m : res ].
proof.
have -> : Pr[CPA(O, KyberSIdeal(DummyHS(IdealHSF.RF), S, KNS, KPRF, KPRF), As).main() @ &m : res] = 
          Pr[PRF_DEFS.IND(PRF_.PRF, D_PRF1(S, O, As)).main() @ &m : res].
+ byequiv => //.
  proc. 
  inline {1} 2; inline {2} 2. inline {2} 2. inline {2} 3.
  wp; call(_: ={glob O}); 1: by sim.
  wp; call(_: ={glob O, glob S}); 1: by sim.
  rnd.
  wp; call(_: ={glob O}); 1: by sim.
  conseq (_: _ ==> ={pk, glob O,glob S}); 1: smt().
  swap {2} 2 -1.
  seq 1 1 : (={glob As, glob S, glob O}); 1: by sim.
  inline {1} 1. inline {2} 2. 
  swap {2} [2..4] -1.
  seq 3 3 : (#pre /\ ={glob IdealHSF.RF, rho,s}). 
  + by inline *; sim.
  seq 1 2 : (#pre /\ sig{1} = PRF_.PRF.k{2});1: by inline *; auto => />.
  inline {1} 1; inline {2} 1.
  sim 8 8.
  seq 7 7 : (#pre /\ ={a,rho0} /\ sig0{1} = PRF_.PRF.k{2}); 1: by  sim. 
  conseq => />.
  inline {1} 1; inline {2} 1. 
  inline *. 
  unroll for {1} 8.
  unroll for {2} 8.
  do 3!( wp; conseq => />; sim).
  wp;auto => />;sim.
  unroll for {1} 6.
  unroll for {2} 6.
  do 3!( wp; conseq => />; sim).
  by wp;auto => />;sim.

have -> : Pr[CPA(O, KyberSIdeal(DummyHS(IdealHSF.RF), S, KNS, DummyPRF1(IdealPRF1.RF), KPRF), As).main() @ &m : res] = 
          Pr[PRF_DEFS.IND(IdealPRF1.RF, D_PRF1(S, O, As)).main() @ &m : res].
+ byequiv => //.
  proc. 
  inline {1} 2; inline {2} 2. inline {2} 2. inline {2} 3.
  wp; call(_: ={glob O}); 1: by sim.
  wp; call(_: ={glob O, glob S}); 1: by sim.
  rnd.
  wp; call(_: ={glob O}); 1: by sim.
  conseq (_: _ ==> ={pk, glob O,glob S}); 1: smt().
  swap {2} 2 -1.
  seq 1 1 : (={glob As, glob S, glob O}); 1: by sim.
  inline {1} 1. inline {2} 2. 
  swap {2} [2..4] -1.
  seq 3 3 : (#pre /\ ={glob IdealHSF.RF, rho,s}). 
  + by inline *; sim.
  seq 1 2 : (#pre /\ ={glob IdealPRF1.RF,sig});1: by inline *; auto => />.
  by inline *;sim.
done.
qed.

lemma PRFHop2 &m :
  Pr [ KyberPKE.CPA(O,KyberSIdeal(DummyHS(IdealHSF.RF),S,KNS,DummyPRF1(IdealPRF1.RF),KPRF),As).main() @ &m : res] -
  Pr [ KyberPKE.CPA(O,KyberSIdeal(DummyHS(IdealHSF.RF),S,KNS,DummyPRF1(IdealPRF1.RF),DummyPRF2(IdealPRF2.RF)),As).main() @ &m : res] = 
  Pr [ PRF_DEFS.IND(PRF_.PRF,D_PRF2(S,O,As)).main() @ &m : res ] - 
  Pr [ PRF_DEFS.IND(IdealPRF2.RF,D_PRF2(S,O,As)).main() @ &m : res ].
proof.
have -> : Pr[CPA(O,KyberSIdeal(DummyHS(IdealHSF.RF), S, KNS, DummyPRF1(IdealPRF1.RF), KPRF), As).main() @ &m : res] = 
          Pr[PRF_DEFS.IND(PRF_.PRF, D_PRF2(S, O, As)).main() @ &m : res].
+ byequiv => //.
  proc. 
   inline {2}2 . inline {2} 2.
  wp; call(_: ={glob O}); 1: by sim.
  swap {2} 1 4.
  seq 4 4 : (={glob S, glob As, glob O,pk,sk,m0,m1} /\ b{1} = b1{2}).
  + rnd;wp; call(_: ={glob O}); 1: by sim.
    wp; call(_: ={glob O, glob S}); 1: by sim.
    by inline *; auto => />; sim. 
  conseq (_: _ ==> ={c, glob O,glob S}); 1: smt().
  inline {1} 1. inline {2} 2. 
  swap {2} [2..3] -1; sp 2 2.
  seq 1 2 : (#pre /\ r{1} = PRF_.PRF.k{2});1: by inline *; auto => />.
  inline {1} 1; inline {2} 1.
  sim 13 13.
  seq 12 12 : (={that, m2, aT, glob S, glob O}  /\ r0{1} = PRF_.PRF.k{2}); 1: by  sim. 
  conseq => />.
  inline {1} 1; inline {2} 1. 
  inline *. 
  wp;auto => />;sim.
  unroll for {1} 8.
  unroll for {2} 8.
  do 3!( wp; conseq => />; sim).
  wp;auto => />;sim.
  unroll for {1} 6.
  unroll for {2} 6.
  do 3!( wp; conseq => />; sim).
  by wp;auto => />;sim.

have -> : Pr[CPA(O, KyberSIdeal(DummyHS(IdealHSF.RF), S, KNS, DummyPRF1(IdealPRF1.RF), DummyPRF2(RF)), As).main
   () @ &m : res] = 
          Pr[PRF_DEFS.IND(RF, D_PRF2(S, O, As)).main() @ &m : res].
+ byequiv => //.
  proc. 
  inline {2} 2. inline {2} 2. 
  wp; call(_: ={glob O}); 1: by sim.
  swap {2} 1 4.
  seq 4 4 : (={glob S, glob As, glob O,pk,sk,m0,m1} /\ b{1} = b1{2}).
  rnd.
  wp; call(_: ={glob O}); 1: by sim.
  wp; call(_: ={glob O, glob S}); 1: by sim.
  by inline *; auto => />; sim. 
  conseq (_: _ ==> ={c, glob O,glob S}); 1: smt().
  inline {1} 1. inline {2} 2. 
  swap {2} [2..3] -1; sp 2 2.
  seq 1 2 : (#pre /\ ={glob IdealPRF2.RF,r});1: by inline *; auto => />.
  by inline *;sim => /> /#.
done.
qed.


end section.

(*******************************************************************)
(* At this point we get some nice equivalences                     *)
(*******************************************************************)

module KyberSI(S : Sampler, O : SMP_RO) = 
   KyberSIdeal(DummyHS(IdealHSF.RF),S,KNS,DummyPRF1(IdealPRF1.RF),DummyPRF2(IdealPRF2.RF), O).

module (NTTSampler(S : Sampler) : Sampler) (O : SMP_RO) = {
    proc sampleA(sd : W8.t Array32.t) : polymat = { 
        var a;
        a <@ S(O).sampleA(sd);
        return invnttm a;
    }

    proc sampleAT(sd : W8.t Array32.t) : polymat = { 
        var a;
        a <@ S(O).sampleAT(sd);
        return invnttm a;
    }

}.

phoare sem_decode1  a : [ EncDec.decode1  : arg = a ==>  res = decode1  a ] = 1%r
 by bypr => &m ->; have /= := (decode1_opsem &m (decode1 a) a).
phoare sem_encode1  a : [ EncDec.encode1  : arg = a ==>  res = encode1  a ] = 1%r
 by bypr => &m ->; have /= := (encode1_opsem &m (encode1 a) a).
phoare sem_encode4  a : [ EncDec.encode4  : arg = a ==>  res = encode4  a ] = 1%r
 by bypr => &m ->; have /= := (encode4_opsem &m (encode4 a) a).
phoare sem_decode4  a : [ EncDec.decode4  : arg = a ==>  res = decode4  a ] = 1%r
 by bypr => &m ->; have /= := (decode4_opsem &m (decode4 a) a).

phoare sem_encode10_vec a : [ EncDec.encode10_vec : arg = a ==> res = encode10_vec_aux a ] = 1%r.
proof. 
 bypr => &m ->; have /= <- := (encode10_vec_aux_opsem &m (encode10_vec_aux a) a).
 by byequiv (encode10_vec_aux) => //.
qed.

phoare sem_decode10_vec a : [ EncDec.decode10_vec : arg = a ==> res = decode10_vec_aux a ] = 1%r.
proof. 
 bypr => &m ->; have /= <- := (decode10_vec_aux_opsem &m (decode10_vec_aux a) a).
 by byequiv (decode10_vec_aux) => //.
qed.

phoare sem_encode12_vec a : [ EncDec.encode12_vec : arg = a ==> res = encode12_vec_aux a ] = 1%r.
proof. 
 bypr => &m ->; have /= <- := (encode12_vec_aux_opsem &m (encode12_vec_aux a) a).
 by byequiv (encode12_vec_aux) => //.
qed.

phoare sem_decode12_vec a : [ EncDec.decode12_vec : arg = a ==> res = decode12_vec_aux a ] = 1%r.
proof. 
 bypr => &m ->; have /= <- := (decode12_vec_aux_opsem &m (decode12_vec_aux a) a).
 by byequiv (decode12_vec_aux) => //.
qed.

section.

declare module O <: RO {-IdealHSF.RF,-RF,-IdealPRF1.RF}.
declare module S <: Sampler {-IdealHSF.RF,-RF, -O, -IdealPRF1.RF}.

equiv keygen_eq : 
  MLWE_PKE(NTTSampler(S,O), O).kg ~ KyberSI(S,O).kg :
   ={glob S, glob O} ==> ={res,glob S, glob O}.
proof.
proc.
inline {2} 4.
wp;ecall{2}(sem_encode12_vec (toipolyvec s0{2})).
wp;ecall{2}(sem_encode12_vec (toipolyvec t{2})).
swap {1} 4 -2.
swap {2} 2 -1. swap {2} 4 -2. swap {2} 10 -7.
seq 2 3 : (#pre /\ nttm _A{1} = a{2} /\ sd{1} = rho0{2}).
+ inline {1} 2; wp; call(_: ={glob O}); 1: by sim.
  by auto => />; smt(nttmK).
swap {2} [2..3] 4.
seq 0 5 : #pre; 1: by inline *;auto.
wp; conseq (_: _ ==> ={e} /\ s{1} = s0{2} /\ sd{1} = rho0{2} /\ nttm _A{1} = a{2}); 
  last first.
+ conseq (_: true ==> ={e} /\ s{1} = s0{2}); 1: smt(). 
  inline {2} 3.
inline*.
transitivity {1}
 { s <@ CBD2rnd.sample_vec_real();
   e <@ CBD2rnd.sample_vec_real(); }
 ( true ==> ={e,s} )
 ( true ==> ={e} /\ s{1}=s0{2} ) => //.
  transitivity {1}
   { s <@ CBD2rnd.sample_vec_ideal();
     e <@ CBD2rnd.sample_vec_ideal(); }
   ( true ==> ={e,s} )
   ( true ==> ={e,s} ) => //.
   inline*; wp; rnd.
   by wp; rnd; auto.
  by symmetry; do 2! call CBD2rnd_vec_equiv; auto.
 seq 0 7: (_N{2} = 0 /\ forall (x:W8.t), SmtMap.dom IdealPRF1.RF.m{2} x => W8.to_uint x < _N{2}).
  by wp; auto => /> *; smt(SmtMap.mem_empty).
 seq 1 2: (s{1}=noise1{2} /\ _N{2} = 3 /\
           forall (x:W8.t), SmtMap.dom IdealPRF1.RF.m{2} x => W8.to_uint x < _N{2}).
  inline*; wp.
  while (={i} /\ 0 <= i{2} <= kvec /\ _N{2}=i{2} /\
         (forall k, 0 <= k < i{2} => (v{1}.[k]=noise1{2}.[k])%PolyVec) /\
         forall (x:W8.t), SmtMap.dom IdealPRF1.RF.m{2} x => W8.to_uint x < _N{2}).
   rcondt {2} 6.
    move=> &m; wp; skip => &hr /> ??? Hm ?.
    rewrite -implybF => H.
    by move: (Hm _ H); rewrite implybF of_uintK /#.
   wp; while (#[/:5,7:]pre /\ ={i0, bytes} /\ 0 <= i0{2} <= 128 /\ j{2} = i0{2}*2 /\
              (forall (x1 : W8.t), SmtMap.dom IdealPRF1.RF.m{2} x1 => to_uint x1 <= _N{2}) /\
              forall k, 0 <= k < j{2} => p0{1}.[k] = rr{2}.[k]).
    wp; skip => /> &1&2 *; split; first smt().    
    split; first smt().
    move=> k ?? /=.
    case: (k= 2*i0{2}) => E1.
     by rewrite set_neqiE 1..2:/# set_eqiE 1..2:/# set_neqiE 1..2:/# set_eqiE /#. 
    case: (k= 2*i0{2}+1) => E2.
     by rewrite set_eqiE 1..2:/# set_eqiE /#.
    by rewrite set_neqiE 1..2:/# set_neqiE 1..2:/# set_neqiE 1..2:/# set_neqiE /#.
   wp; rnd; wp; skip => /> &1 &2; rewrite !setvE !getvE => ?????????; split.
    split.
     by rewrite SmtMap.get_set_sameE.
    move=> x; case: (x=W8.of_int i{2}) => E.
     by move=> _; rewrite E of_uintK modz_small /#.
    rewrite SmtMap.domE SmtMap.get_set_neqE 1:// => H. 
    by apply StdOrder.IntOrder.ltrW; smt().
   move => p1 i0 p2 ?????? H; split; first smt().
   have EE: p1 = p2.
    by apply Array256.tP => k kb; apply H; smt().
   split; last smt().
   move=> k HkL HkR; case: (k = i{2}) => E.
    by rewrite /set E !offunvE /= /#.
   by rewrite /set !offunvE /= 1..2:/# (eq_sym _ k) E /= /#.
  auto => /> &1 &2; split; first smt().
  move=> v1 m i v2 => ??????; split; last smt().
  apply eq_vectorP => k kb;smt(setvE getvE).
 wp; seq 2 2: (e{1}=noise2{2} /\ s{1}=noise1{2} /\ _N{2} = 6 /\
           forall (x:W8.t), SmtMap.dom IdealPRF1.RF.m{2} x => W8.to_uint x < _N{2}).
  inline*; wp.
  while (={i} /\ 0 <= i{2} <= kvec /\ _N{2}=3+i{2} /\ s{1}=noise1{2} /\
         (forall k, 0 <= k < i{2} => (v{1}.[k]=noise2{2}.[k])%PolyVec) /\
         forall (x:W8.t), SmtMap.dom IdealPRF1.RF.m{2} x => W8.to_uint x < _N{2}).
   rcondt {2} 6.
    move=> &m; wp; skip => &hr /> ??? Hm ?.
    rewrite -implybF => H.
    by move: (Hm _ H); rewrite implybF of_uintK /#.
   wp; while (#[/:6,8:]pre /\ bytes{1}=bytes0{2} /\ i0{1}=i1{2} /\ 0 <= i1{2} <= 128 /\ j0{2} = i1{2}*2 /\
              (forall (x1 : W8.t), SmtMap.dom IdealPRF1.RF.m{2} x1 => to_uint x1 <= _N{2}) /\
              forall k, 0 <= k < j0{2} => p0{1}.[k] = rr0{2}.[k]).
    wp; skip => /> &1&2 *; split; first smt().    
    split; first smt().
    move=> k ?? /=.
    case: (k= 2*i1{2}) => E1.
     by rewrite set_neqiE 1..2:/# set_eqiE 1..2:/# set_neqiE 1..2:/# set_eqiE /#. 
    case: (k= 2*i1{2}+1) => E2.
     by rewrite set_eqiE 1..2:/# set_eqiE /#.
    by rewrite set_neqiE 1..2:/# set_neqiE 1..2:/# set_neqiE 1..2:/# set_neqiE /#.
   wp; rnd; wp; skip => /> &1 &2; rewrite !getvE !setvE => ?????????; split.
    split.
     by rewrite SmtMap.get_set_sameE.
    move=> x; case: (x=W8.of_int (3+i{2})) => E.
     by move=> _; rewrite E of_uintK modz_small /#.
    rewrite SmtMap.domE SmtMap.get_set_neqE 1:// => H. 
    by apply StdOrder.IntOrder.ltrW; smt().
   move => p1 i1 p2 ?????? H; split; first smt().
   have EE: p1 = p2.
    by apply Array256.tP => k kb; apply H; smt().
   split; first smt().
   split; last smt().
   move=> k HkL HkR; case: (k = i{2}) => E.
    by rewrite /set E !offunvE /= /#.
   by rewrite /set !offunvE /= 1..2:/# (eq_sym _ k) E /= /#.
  auto => /> &1 &2; split; first smt().
  move=> v1 m i v2 ??????; split; last smt().
  by apply eq_vectorP => k kb;smt(setvE getvE).
 by auto.
auto => /> &1 &2 e s; rewrite /pk_encode /sk_encode /= polyvecD.
by rewrite -!polyvecD comm_nttv_add comm_nttv_mmul.
qed.


equiv enc_eq : 
  MLWE_PKE(NTTSampler(S,O), O).enc ~ KyberSI(S,O).enc :
   ={arg,glob S, glob O} ==> ={res,glob S, glob O}.
proof.
proc.
inline {2} 2.
wp;ecall{2}(sem_encode4 (compress_poly 4 v{2})).
wp;ecall{2}(sem_encode10_vec (compress_polyvec 10 u{2})).
wp;ecall{2}(sem_decode1 (m0{2})).
swap {1} [2..4] -1.
swap {2} [7..8] -6.
swap {2} 14 -7.
swap {2} [6..7] -2.
seq 3 5 : (#pre /\ ={e1,e2} /\ r{1} = rv{2}).
 inline*; simplify.
 transitivity {1}
  { r <@ CBD2rnd.sample_vec_real();
    e1 <@ CBD2rnd.sample_vec_real();
    e2 <@ CBD2rnd.sample_real(); }
  ( ={pk,m,glob S,glob O} ==> ={pk,m,glob S,glob O,r,e1,e2} )
  ( ={pk,m,glob S,glob O} ==> ={pk,m,glob S,glob O,e1,e2} /\ r{1}=rv{2} ) => //; first smt().
  transitivity {1}
   { r <@ CBD2rnd.sample_vec_ideal();
     e1 <@ CBD2rnd.sample_vec_ideal();
     e2 <@ CBD2rnd.sample_ideal(); }
   ( ={pk,m,glob S,glob O} ==> ={pk,m,glob S,glob O,r,e1,e2} )
   ( ={pk,m,glob S,glob O} ==> ={pk,m,glob S,glob O,r,e1,e2} ) => //; first smt().
   inline*; wp; rnd.
   wp; rnd.
   by wp; rnd; auto.
  symmetry; call CBD2rnd_equiv.
  by do 2! call CBD2rnd_vec_equiv; auto.
 seq 0 9: (={pk, m, glob S, glob O} /\ _N{2} = 0 /\ forall (x:W8.t), SmtMap.dom RF.m{2} x => W8.to_uint x < _N{2}).
  by wp; auto => /> *; smt(SmtMap.mem_empty).
 seq 1 2: (r{1}=noise1{2} /\ ={pk, m, glob S, glob O} /\ _N{2} = 3 /\ forall (x:W8.t), SmtMap.dom RF.m{2} x => W8.to_uint x < _N{2}).
  inline*; wp.
  while (={i, pk, m, glob S, glob O} /\ 0 <= i{2} <= kvec /\ _N{2}=i{2} /\
         (forall k, 0 <= k < i{2} => (v0{1}.[k]=noise1{2}.[k])%PolyVec) /\
         forall (x:W8.t), SmtMap.dom RF.m{2} x => W8.to_uint x < _N{2}).
   rcondt {2} 6.
    move=> &m; wp; skip => &hr /> ??? Hm ?.
    rewrite -implybF => H.
    by move: (Hm _ H); rewrite implybF of_uintK /#.
   wp; while (#[/:9,11:]pre /\ ={i0, bytes} /\ 0 <= i0{2} <= 128 /\ j{2} = i0{2}*2 /\
              (forall (x1 : W8.t), SmtMap.dom RF.m{2} x1 => to_uint x1 <= _N{2}) /\
              forall k, 0 <= k < j{2} => p0{1}.[k] = rr{2}.[k]).
    wp; skip => /> &1&2 *; split; first smt().    
    split; first smt().
    move=> k ?? /=.
    case: (k= 2*i0{2}) => E1.
     by rewrite set_neqiE 1..2:/# set_eqiE 1..2:/# set_neqiE 1..2:/# set_eqiE /#. 
    case: (k= 2*i0{2}+1) => E2.
     by rewrite set_eqiE 1..2:/# set_eqiE /#.
    by rewrite set_neqiE 1..2:/# set_neqiE 1..2:/# set_neqiE 1..2:/# set_neqiE /#.
   wp; rnd; wp; skip => /> &1 &2; rewrite !setvE !getvE => ?????????; split.
    split.
     by rewrite SmtMap.get_set_sameE.
    move=> x; case: (x=W8.of_int i{2}) => E.
     by move=> _; rewrite E of_uintK modz_small /#.
    rewrite SmtMap.domE SmtMap.get_set_neqE 1:// => H. 
    by apply StdOrder.IntOrder.ltrW; smt().
   move => p1 i0 p2 ?????? H; split; first smt().
   have EE: p1 = p2.
    by apply Array256.tP => k kb; apply H; smt().
   split; last smt().
   move=> k HkL HkR; case: (k = i{2}) => E.
    by rewrite /set E !offunvE /= /#.
   by rewrite /set !offunvE /= 1..2:/# (eq_sym _ k) E /= /#.
  auto => /> &1 &2; split; first smt().
  move=> v1 m i v2 ??????; split; last smt().
  by apply eq_vectorP => k kb;smt(setvE getvE).
 seq 1 2: (e1{1}=noise2{2} /\ r{1}=noise1{2} /\ ={pk, m, glob S, glob O} /\ _N{2} = 6 /\ forall (x:W8.t), SmtMap.dom RF.m{2} x => W8.to_uint x < _N{2}).
  inline*; wp.
  while (={i, pk, m, glob S, glob O} /\ 0 <= i{2} <= kvec /\ _N{2}=3+i{2} /\ r{1}=noise1{2} /\
         (forall k, 0 <= k < i{2} => (v0{1}.[k]=noise2{2}.[k])%PolyVec) /\
         forall (x:W8.t), SmtMap.dom RF.m{2} x => W8.to_uint x < _N{2}).
   rcondt {2} 6.
    move=> &m; wp; skip => &hr /> ??? Hm ?.
    rewrite -implybF => H.
    by move: (Hm _ H); rewrite implybF of_uintK /#.
   wp; while (#[/:10,12:]pre /\ bytes{1}=bytes0{2} /\ i0{1}=i1{2} /\ 0 <= i1{2} <= 128 /\ j0{2} = i1{2}*2 /\
              (forall (x1 : W8.t), SmtMap.dom RF.m{2} x1 => to_uint x1 <= _N{2}) /\
              forall k, 0 <= k < j0{2} => p0{1}.[k] = rr0{2}.[k]).
    wp; skip => /> &1&2 *; split; first smt().    
    split; first smt().
    move=> k ?? /=.
    case: (k= 2*i1{2}) => E1.
     by rewrite set_neqiE 1..2:/# set_eqiE 1..2:/# set_neqiE 1..2:/# set_eqiE /#. 
    case: (k= 2*i1{2}+1) => E2.
     by rewrite set_eqiE 1..2:/# set_eqiE /#.
    by rewrite set_neqiE 1..2:/# set_neqiE 1..2:/# set_neqiE 1..2:/# set_neqiE /#.
   wp; rnd; wp; skip => /> &1 &2; rewrite !setvE !getvE => ?????????; split.
    split.
     by rewrite SmtMap.get_set_sameE.
    move=> x; case: (x=W8.of_int (3+i{2})) => E.
     by move=> _; rewrite E of_uintK modz_small /#.
    rewrite SmtMap.domE SmtMap.get_set_neqE 1:// => H. 
    by apply StdOrder.IntOrder.ltrW; smt().
   move => p1 i1 p2 ?????? H; split; first smt().
   have EE: p1 = p2.
    by apply Array256.tP => k kb; apply H; smt().
   split; first smt().
   split; last smt().
   move=> k HkL HkR; case: (k = i{2}) => E.
    by rewrite /set E !offunvE /= /#.
   by rewrite /set !offunvE /= 1..2:/# (eq_sym _ k) E /= /#.
  auto => /> &1 &2; split; first smt().
  move=> v1 m i v2 ??????; split; last smt().
  by apply eq_vectorP => k kb;smt(setvE getvE).
 seq 1 12: (e2{1}=e20{2} /\ e1{1}=noise2{2} /\ r{1}=noise1{2} /\ ={pk, m, glob S, glob O}).
  inline*; wp.
  rcondt {2} 6.
   move=> &m; wp; skip => &hr /> Hm. 
   rewrite -implybF => H.
   by move: (Hm _ H); rewrite implybF of_uintK /#.
   while (#[/:-2]pre /\ bytes{1}=bytes1{2} /\ i{1}=i2{2} /\ 0 <= i2{2} <= 128 /\ j1{2} = i2{2}*2 /\
          forall k, 0 <= k < j1{2} => p{1}.[k] = rr1{2}.[k]).
    wp; skip => /> &1&2 *; split; first smt(). 
    split; first smt().
    move=> k ?? /=.
    case: (k= 2*i2{2}) => E1.
     by rewrite set_neqiE 1..2:/# set_eqiE 1..2:/# set_neqiE 1..2:/# set_eqiE /#. 
    case: (k= 2*i2{2}+1) => E2.
     by rewrite set_eqiE 1..2:/# set_eqiE /#.
    by rewrite set_neqiE 1..2:/# set_neqiE 1..2:/# set_neqiE 1..2:/# set_neqiE /#.
   wp; rnd; wp; skip => /> &1 &2 ????; split.
    by rewrite SmtMap.get_set_eqE //=.
   move => p1 i1 p2 ????? H.
   by apply Array256.tP => k kb; apply H; smt().
 by auto.
conseq />; 1: smt().
inline {1} 2.
swap {2} 3 -2. swap {2} 6 -3. swap {2} 9 -5.
seq 4 4 : (#pre /\ tv{2} = pk{1}.`1 /\ t{1} = (pk_decode pk{2}).`1 /\ nttm _A{1} = aT{2}).
 wp; call(_: ={glob O}); 1: by sim.
 by auto => />; smt(nttmK).
wp;ecall{2}(sem_decode12_vec (tv{2})).
auto => /> &1 &2; rewrite /pk_decode /c_encode /m_encode /=.  
split; 1: by rewrite -!polyvecD -comm_nttv_mmul invnttvK.
congr. congr. congr. congr.
by rewrite comm_ntt_dotp sem_decode12_vec_corr.
by rewrite sem_decode1_corr.
qed.

equiv dec_eq : 
  MLWE_PKE(NTTSampler(S,O), O).dec ~ KyberSI(S,O).dec :
   ={arg,glob S, glob O} ==> ={res,glob S, glob O}.
proof.
proc.
ecall{2} (sem_encode1 (compress_poly 1 mp{2})).
wp;ecall{2} (sem_decode12_vec (sk{2})).
wp;ecall{2} (sem_decode4 (c2{2})).
wp;ecall{2} (sem_decode10_vec (c1{2})).
auto => /> &2.
rewrite /m_decode /sk_decode /c_decode /=.
congr. congr. congr. 
by rewrite sem_decode4_corr.
by rewrite comm_ntt_dotp sem_decode10_vec_corr sem_decode12_vec_corr.
qed.

end section.

(***************************************)

section.

declare module O <: RO {-IdealHSF.RF,-IdealPRF1.RF,-RF,-KPRF, -B1ROM, -B2ROM}.
declare module S <: Sampler {-IdealHSF.RF,-IdealPRF1.RF, -RF, -KPRF, -O, -B1ROM, -B2ROM}.
declare module As <: KyberPKE.Adversary {-IdealPRF1.RF,-IdealHSF.RF,-RF,-O, -S, -KPRF, -B1ROM, -B2ROM}.

lemma security_any_sampler &m :  
  islossless O.init =>
  islossless O.get =>
  (forall (O0 <: SMP_RO), islossless O0.get => islossless S(O0).sampleA) =>
  (forall (O0 <: SMP_RO), islossless O0.get => islossless S(O0).sampleAT) =>
  (forall (O0 <: SMP_RO), islossless O0.get => islossless As(O0).guess) =>
  (forall (O0 <: SMP_RO), islossless O0.get => islossless As(O0).choose) =>
  Pr[ KyberPKE.CPA(O,KyberSI(S),As).main() @ &m : res] - 1%r/2%r = 
  Pr[MLWE_SMP(B1ROM(As, NTTSampler(S)), NTTSampler(S), O).main(false, false) @ &m : res] -
 Pr[MLWE_SMP(B1ROM(As, NTTSampler(S)), NTTSampler(S), O).main(false, true) @ &m : res] +
 Pr[MLWE_SMP(B2ROM(As, NTTSampler(S)), NTTSampler(S), O).main(true, false) @ &m : res] -
 Pr[MLWE_SMP(B2ROM(As, NTTSampler(S)), NTTSampler(S), O).main(true, true) @ &m : res].
move => H H0 H1 H2 H3 H4.
have  <- : 
    Pr[ CPA(O,MLWE_PKE(NTTSampler(S,O)),As).main() @ &m : res] =
    Pr[ KyberPKE.CPA(O,KyberSI(S),As).main() @ &m : res]; last first.
+ have <- := (main_theorem_s O (NTTSampler(S)) As &m  H H0 _ _ _ _).
  + by move => O0 HH; islossless; apply (H1 O0 HH).
  + by move => O0 HH; islossless; apply (H2 O0 HH). 
  + by move => O0 HH; apply (H3 O0 HH).
  + by move => O0 HH; apply (H4 O0 HH).
  by congr => //=;byequiv => //;sim.
byequiv => //.
proc.
wp;call(_: ={glob O}); 1: by sim.
call (enc_eq O S).
rnd.
call(_: ={glob O}); 1: by sim.
call (keygen_eq O S).
by conseq />; sim.
qed.

end section.

section.

declare module O <: RO {-IdealPRF2.RF,-PRF_.PRF,-HSF.PRF,-IdealHSF.RF,-IdealPRF1.RF,-RF,-KPRF, -B1ROM, -B2ROM}.
declare module XOF <: XOF_RO_t {-IdealPRF2.RF,-PRF_.PRF,-HSF.PRF,-IdealHSF.RF,-IdealPRF1.RF,-RF,-KPRF, -O, -B1ROM, -B2ROM}.
declare module As <: KyberPKE.Adversary {-IdealPRF2.RF,-PRF_.PRF,-HSF.PRF,-IdealHSF.RF,-IdealPRF1.RF,-RF,-O, -XOF, -KPRF, -B1ROM, -B2ROM}.

(* This theorem yields security for any sampler and we can use
   it to obtain security for the implementation in the standard 
   model under the assumption that MLWE is secure when the matrix
   is sampled how the implementation does it. 
   We can't get any formal correctness bounds though, since
   the distribution of the matrix is not well defined. *)
lemma security_spec &m :  
  islossless O.init =>
  islossless O.get =>
  (forall (O0 <: SMP_RO), islossless O0.get => islossless XOF(O0).init) =>
  (forall (O0 <: SMP_RO), islossless O0.get => islossless XOF(O0).next_bytes) =>

   (forall (O0 <: SMP_RO) (XOF0 <: XOF_RO_t), 
         islossless O0.get => 
         islossless XOF0(O0).next_bytes => 
         islossless Parse(XOF0(O0)).sample) =>

  (forall (O0 <: SMP_RO), islossless O0.get => islossless As(O0).guess) =>
  (forall (O0 <: SMP_RO), islossless O0.get => islossless As(O0).choose) =>

  Pr[ KyberPKE.CPA(O,KyberS(KHS,KSampler(XOF),KNS,KPRF,KPRF),As).main() @ &m : res] - 1%r/2%r = 
  (Pr [ HS_DEFS.IND(HSF.PRF,D_ES(KSampler(XOF),O,As)).main() @ &m : res ] - 
  Pr [ HS_DEFS.IND(IdealHSF.RF,D_ES(KSampler(XOF),O,As)).main() @ &m : res ]) +
  (Pr [ PRF_DEFS.IND(PRF_.PRF,D_PRF1(KSampler(XOF),O,As)).main() @ &m : res ] - 
  Pr [ PRF_DEFS.IND(IdealPRF1.RF,D_PRF1(KSampler(XOF),O,As)).main() @ &m : res ]) +
  (Pr [ PRF_DEFS.IND(PRF_.PRF,D_PRF2(KSampler(XOF),O,As)).main() @ &m : res ] - 
  Pr [ PRF_DEFS.IND(IdealPRF2.RF,D_PRF2(KSampler(XOF),O,As)).main() @ &m : res ]) +
  (Pr[MLWE_SMP(B1ROM(As, NTTSampler(KSampler(XOF))),  NTTSampler(KSampler(XOF)), O).main(false, false) @ &m : res] -
 Pr[MLWE_SMP(B1ROM(As,  NTTSampler(KSampler(XOF))),  NTTSampler(KSampler(XOF)), O).main(false, true) @ &m : res] +
 Pr[MLWE_SMP(B2ROM(As,  NTTSampler(KSampler(XOF))),  NTTSampler(KSampler(XOF)), O).main(true, false) @ &m : res] -
 Pr[MLWE_SMP(B2ROM(As,  NTTSampler(KSampler(XOF))),  NTTSampler(KSampler(XOF)), O).main(true, true) @ &m : res]).
move => Oill Ooll XOF_init_ll XOF_next_ll Parse_ll Asgll Ascll.

(* 
  WE LOST CONNECTION TO THE SPEC IN THE ROM BECAUSE THE TYPE OF THE XOF DOES NOT TAKE AN RO.
  have <- : Pr[ KyberPKE.CPA(O,KyberS(KHS,KSampler(XOF),KNS,KPRF,KPRF),As).main() @ &m : res]= 
          Pr[ KyberPKE.CPA(O,Kyber(KHS,XOF,KPRF),As).main() @ &m : res].
+ byequiv => //.
  proc.
  wp; call(_: ={glob O, glob XOF}); 1: by sim.
  call (enc_sampler_enc O XOF).
  rnd.
  wp; call(_: ={glob O, glob XOF}); 1: by sim.
  call (kg_sampler_kg O XOF).
  by call(_: true); auto => />. *)

have <- := (security_any_sampler O (KSampler(XOF)) As &m Oill Ooll  _ _ Asgll Ascll).
  + by move => O O_ll; apply (KSamplerA_ll XOF O O_ll XOF_init_ll XOF_next_ll Parse_ll).
  by move => O O_ll; apply (KSamplerAT_ll XOF O O_ll XOF_init_ll XOF_next_ll Parse_ll).

have <- := (ESHop O (KSampler(XOF)) As).
have <- := (PRFHop1 O (KSampler(XOF)) As).
have <- := (PRFHop2 O (KSampler(XOF)) As).
have <- := (KyberS_KyberIdeal O (KSampler(XOF)) As).
have <-: Pr[CPA(O, KyberSI(KSampler(XOF)), As).main() @ &m : res] = 
         Pr[CPA(O, KyberSIdeal(DummyHS(IdealHSF.RF), KSampler(XOF), KNS, DummyPRF1(IdealPRF1.RF), DummyPRF2(RF)), As).main
   () @ &m : res] by byequiv => //=; proc; sim.
by ring.
qed.

end section.

import MLWE_.SMP_vs_ROM_IND.

import MLWE_.MLWE_ROM.MLWE_vs_MLWE_ROM.
import MLWE_.MLWE_ROM.
import MLWE_.

(* This theorem yields security for any sampler that can be
   proved indifferentiable from the RO that samples uniform 
   matrices down to standard MLWE. *)

section.

declare module As <: KyberPKE.Adversary {-IdealPRF1.RF,-IdealHSF.RF,-RF,-LRO,-RO_SMP.LRO, -RO_H.RO, -RO_H.FRO, -RO_H.LRO,-KPRF, -B1ROM, -B2ROM, -B,-Bt, -BS, -D}.
declare module S <: Sampler {-IdealPRF1.RF,-IdealHSF.RF,-RF,-As, -B1ROM, -B2ROM, -LRO, -RO_SMP.LRO, -RO_H.RO, -RO_H.FRO, -RO_H.LRO, -B,-Bt, -BS, -D}.
declare module Sim <: Simulator_t {-IdealPRF1.RF,-IdealHSF.RF,-S,-As,-B1ROM, -B2ROM, -LRO, -RO_SMP.LRO, -RO_H.RO, -RO_H.FRO, -RO_H.LRO, -B,-Bt, -BS, -D}.


lemma security_any_sampler_indiff &m epsilon :
  0%r <= epsilon =>  
  (forall (x : in_t), is_lossless (dout x)) => 
  (forall (O <: SMP_RO), islossless O.get => islossless S(O).sampleA) =>
  (forall (O <: SMP_RO), islossless O.get => islossless S(O).sampleAT) =>
  (forall (O <: SMP_RO), islossless O.get => islossless As(O).guess) =>
  (forall (O <: SMP_RO), islossless O.get => islossless As(O).choose) =>

  (forall tr b (D0 <: Distinguisher_t {-S,-Sim,-RO_H.LRO, -RO_SMP.RO, -RO_SMP.LRO, -NTTSampler(S)}),
     `| Pr[ WIndfReal(D0,NTTSampler(S),RO_SMP.LRO).main(tr,b) @ &m : res]  -
        Pr[ WIndfIdeal(D0,Sim,RO_H.LRO).main(tr,b) @ &m : res] | <= epsilon) =>

  `| Pr[ KyberPKE.CPA(LRO,KyberSI(S),As).main() @ &m : res] - 1%r/2%r | <= 
     `| Pr[MLWE(B(BS(B1ROM(As,NTTSampler(S)),Sim),RO_H.LRO)).main(false) @ &m : res] -
         Pr[MLWE(B(BS(B1ROM(As,NTTSampler(S)),Sim),RO_H.LRO)).main(true) @ &m : res] | + 
     `| Pr[MLWE(Bt(BS(B2ROM(As,NTTSampler(S)),Sim),RO_H.LRO)).main(false) @ &m : res] -
       Pr[MLWE(Bt(BS(B2ROM(As,NTTSampler(S)),Sim),RO_H.LRO)).main(true) @ &m : res] | + 4%r * epsilon.
move => eps_ge0 H H0 H1 H2 H3 H4.
have  <- : 
    Pr[ CPA(LRO,MLWE_PKE(NTTSampler(S,LRO)),As).main() @ &m : res] =
    Pr[ KyberPKE.CPA(LRO,KyberSI(S),As).main() @ &m : res].
+ byequiv => //.
  proc.
  wp;call(_: ={glob LRO}); 1: by sim.
  call (enc_eq LRO S).
  rnd.
  call(_: ={glob LRO}); 1: by sim.
  call (keygen_eq LRO S).
  by conseq />; sim.

move : (main_theorem_ref As (NTTSampler(S)) Sim &m epsilon eps_ge0 H _ _ H2 H3 H4).
+ by move => O0 HH; islossless; apply (H0 O0 HH).
by move => O0 HH; islossless; apply (H1 O0 HH).
have -> : Pr[PKE_ROM.CPA(RO_SMP.LRO,MLWE_PKE(NTTSampler(S, RO_SMP.LRO)), As).main() @ &m : res] = Pr[CPA(LRO, MLWE_PKE(NTTSampler(S, LRO)), As).main() @ &m : res]; last by auto.
 + byequiv => //;proc;inline *.
   wp; call(_: RO_SMP.RO.m{1} = RO.m{2}); 1: by proc;inline *; sim;auto.
   wp; call(_: RO_SMP.RO.m{1} = RO.m{2}); 1: by proc;inline *; sim;auto.
   auto;call(_: RO_SMP.RO.m{1} = RO.m{2}); 1: by proc;inline *; sim;auto.
   wp; call(_: RO_SMP.RO.m{1} = RO.m{2}); 1: by proc;inline *; sim;auto.
   by auto => />.   
qed.

end section.

(* The following theorem is the strongest claim we can make
   about the Kyber Spec. It comes with two assumptions on the
   matrix sampling procedure:
   1) that it converges (losslessness of Parse)
      there is some hope of proving this when XOF is a ROM.
   2) that it is indifferentiable (explainable) wrt to the
      random oracle that simply samples uniform matrices.
      this basically means that there must exist a simulator
      that can produce a plausible XOF output for any 
      given Matrix. Easy to claim in paper when XOF is a ROM: 
      just rejection-sample a different matrix and program 
      the coefficients with the ones you want to explain. 
      No clue how to prove this in EC though.
      But note that, in this case we get security down
      to MLWE. *)

section.

declare module As <: KyberPKE.Adversary {-IdealPRF2.RF,-PRF_.PRF,-HSF.PRF,-IdealHSF.RF,-IdealPRF1.RF,-LRO, -RO_H.RO, -RO_H.FRO, -RO_H.LRO, -RO_SMP.LRO, -KPRF, -B1ROM, -B2ROM, -B,-Bt, -BS, -D}.
declare module XOF <: XOF_RO_t {-IdealPRF2.RF,-PRF_.PRF,-HSF.PRF,-IdealHSF.RF,-IdealPRF1.RF,-As, -B1ROM, -B2ROM, -LRO, -RO_H.RO, -RO_H.FRO, -RO_H.LRO, -RO_SMP.LRO, -B,-Bt, -BS, -D}.
declare module Sim <: Simulator_t {-IdealPRF2.RF,-PRF_.PRF,-HSF.PRF,-IdealHSF.RF,-IdealPRF1.RF,-XOF,-As,-B1ROM, -B2ROM, -LRO, -RO_H.RO, -RO_H.FRO, -RO_H.LRO, -RO_SMP.LRO, -B,-Bt, -BS, -D}.

lemma security_spec_indiff &m epsilon:
  0%r <= epsilon =>
  
  (forall (x : in_t), is_lossless (dout x)) => 

  (forall (O0 <: SMP_RO), islossless O0.get => islossless XOF(O0).init) =>
  (forall (O0 <: SMP_RO), islossless O0.get => islossless XOF(O0).next_bytes) =>

   (forall (O0 <: SMP_RO) (XOF0 <: XOF_RO_t), 
         islossless O0.get => 
         islossless XOF0(O0).next_bytes => 
         islossless Parse(XOF0(O0)).sample) =>

  (forall (O0 <: SMP_RO), islossless O0.get => islossless As(O0).guess) =>
  (forall (O0 <: SMP_RO), islossless O0.get => islossless As(O0).choose) =>

  (forall tr b (D0 <: Distinguisher_t {-KSampler(XOF),-Sim, -RO_H.LRO, -RO_SMP.RO, -RO_SMP.LRO,  -KSampler(XOF)}),
     `| Pr[ WIndfReal(D0,NTTSampler(KSampler(XOF)),RO_SMP.LRO).main(tr,b) @ &m : res] -
        Pr[ WIndfIdeal(D0,Sim,RO_H.LRO).main(tr,b) @ &m : res] | <= epsilon) =>


  `| Pr[ KyberPKE.CPA(LRO,KyberS(KHS,KSampler(XOF),KNS,KPRF,KPRF),As).main() @ &m : res] - 1%r/2%r | <= 
  `| Pr [ HS_DEFS.IND(HSF.PRF,D_ES(KSampler(XOF),LRO,As)).main() @ &m : res ] - 
      Pr [ HS_DEFS.IND(IdealHSF.RF,D_ES(KSampler(XOF),LRO,As)).main() @ &m : res ] | +
  `| Pr [ PRF_DEFS.IND(PRF_.PRF,D_PRF1(KSampler(XOF),LRO,As)).main() @ &m : res ] - 
      Pr [ PRF_DEFS.IND(IdealPRF1.RF,D_PRF1(KSampler(XOF),LRO,As)).main() @ &m : res ] | +
  `| Pr [ PRF_DEFS.IND(PRF_.PRF,D_PRF2(KSampler(XOF),LRO,As)).main() @ &m : res ] - 
      Pr [ PRF_DEFS.IND(IdealPRF2.RF,D_PRF2(KSampler(XOF),LRO,As)).main() @ &m : res ] | +
  `| Pr[MLWE(B(BS(B1ROM(As,NTTSampler(KSampler(XOF))),Sim),RO_H.LRO)).main(false) @ &m : res] -
       Pr[MLWE(B(BS(B1ROM(As,NTTSampler(KSampler(XOF))),Sim),RO_H.LRO)).main(true) @ &m : res] | + 
   `| Pr[MLWE(Bt(BS(B2ROM(As,NTTSampler(KSampler(XOF))),Sim),RO_H.LRO)).main(false) @ &m : res]-
       Pr[MLWE(Bt(BS(B2ROM(As,NTTSampler(KSampler(XOF))),Sim),RO_H.LRO)).main(true) @ &m : res] | + 4%r * epsilon.

move => eps_ge0 Oill XOF_init_ll XOF_next_ll Parse_ll Asgll Ascll ind.
(* 
  WE LOST CONNECTION TO THE SPEC IN THE ROM BECAUSE THE TYPE OF THE XOF DOES NOT TAKE AN RO.

have <- : Pr[ KyberPKE.CPA(LRO,KyberS(KHS,KSampler(XOF),KNS,KPRF,KPRF),As).main() @ &m : res]= 
          Pr[ KyberPKE.CPA(LRO,Kyber(KHS,XOF,KPRF),As).main() @ &m : res].
+ byequiv => //.
  proc.
  wp; call(_: ={glob LRO, glob XOF}); 1: by sim.
  call (enc_sampler_enc LRO XOF).
  rnd.
  wp; call(_: ={glob LRO, glob XOF}); 1: by sim.
  call (kg_sampler_kg LRO XOF).
  by inline *; auto.
*)
+ have  := (security_any_sampler_indiff  As (KSampler(XOF)) Sim  &m epsilon eps_ge0 Oill _ _ Asgll Ascll ind).
  + by move => O O_ll; apply (KSamplerA_ll XOF O O_ll XOF_init_ll XOF_next_ll Parse_ll).
  by move => O O_ll; apply (KSamplerAT_ll XOF O O_ll XOF_init_ll XOF_next_ll Parse_ll).

have <- := (ESHop LRO (KSampler(XOF)) As).
have <- := (PRFHop1 LRO (KSampler(XOF)) As).
have <- := (PRFHop2 LRO (KSampler(XOF)) As).
have <- := (KyberS_KyberIdeal LRO (KSampler(XOF)) As).
have <-: Pr[CPA(LRO, KyberSI(KSampler(XOF)), As).main() @ &m : res] = 
         Pr[CPA(LRO, KyberSIdeal(DummyHS(IdealHSF.RF), KSampler(XOF), KNS, DummyPRF1(IdealPRF1.RF), DummyPRF2(RF)), As).main
   () @ &m : res] by byequiv => //=; proc; sim.
by smt().
qed.


end section.

(* The correctness bounds can only be computed when matrices are
   uniform, so we jump directly to results where one can assume
   that the sampler is indifferentiable from the nice RO.
   Note here we are working with the scheme with ideal HS and
   PRFs. *)

section.

declare module A <: CORR_ADV {-IdealPRF1.RF,-IdealHSF.RF,-LRO,-RO_H.LRO, -RO_SMP.RO, -RO_SMP.LRO, -CB}.
declare module S <: Sampler {-IdealPRF1.RF,-IdealHSF.RF,-A,-LRO,-RO_H.LRO, -RO_SMP.RO, -RO_SMP.LRO, -CB}.
declare module Sim <: Simulator_t {-IdealPRF1.RF,-IdealHSF.RF,-S, -A,-LRO,-RO_H.LRO, -RO_SMP.RO, -RO_SMP.LRO, -CB}.


lemma correctness_any_sampler &m cu_bound failprob1 failprob2 epsilon  :
  (glob Bcb2){m} = cu_bound =>

  (forall (O <: Ideal_RO), islossless O.get => islossless Sim(O).init) =>
  (forall (O <: Ideal_RO), islossless O.get => islossless Sim(O).get) =>
  (forall (O <: SMP_RO), islossless O.get => islossless A(O).find) =>

  (forall trb (D0 <: Distinguisher_t {-S,-RO_H.RO, -RO_H.LRO, -RO_SMP.RO, -RO_SMP.LRO,  -NTTSampler(S),-Sim}),
     `| Pr[ WIndfReal(D0,NTTSampler(S),RO_SMP.LRO).main(trb) @ &m : res] - 
         Pr[ WIndfIdeal(D0,Sim,RO_H.LRO).main(trb) @ &m : res] | <= epsilon) =>

  Pr[ CB1.main(cu_bound, cv_bound_max) @ &m : res] <= failprob1 =>
  Pr[ CB2.main(cu_bound) @ &m : res] <= failprob2 =>

  Pr[ KyberPKE.Correctness_Adv(LRO,KyberSI(S),A).main() @ &m : res]  <=
    `|Pr[MLWE(Bcb2).main(false) @ &m : res] -
    Pr[MLWE(Bcb2).main(true) @ &m : res]| + failprob1 + failprob2 + epsilon.
move => initmem Sim_i_ll Sim_h_ll A_ll ind fp1 fp2.

have <- : 
Pr[PKE_ROM.Correctness_Adv(RO_SMP.LRO,MLWE_PKE(NTTSampler(S, RO_SMP.LRO)), A).main() @ &m : res] = 
Pr[Correctness_Adv(LRO,KyberSI(S), A).main() @ &m : res]; last by  apply (correctness_max A (NTTSampler(S)) Sim &m cu_bound epsilon failprob1 failprob2 initmem Sim_i_ll Sim_h_ll A_ll ind fp1 fp2).
have <-: Pr[PKE_ROM.Correctness_Adv(LRO, MLWE_PKE(NTTSampler(S,LRO)), A).main() @ &m : res] = Pr[PKE_ROM.Correctness_Adv(RO_SMP.LRO,MLWE_PKE(NTTSampler(S, RO_SMP.LRO)), A).main() @ &m : res].
+ byequiv => //; proc;inline *.
   wp; call(_: RO_SMP.RO.m{2} = RO.m{1}); 1: by proc;inline *; sim;auto.
   auto => />; 1: by smt().
   wp; call(_: RO_SMP.RO.m{2} = RO.m{1}); 1: by proc;inline *; sim;auto.
   wp; call(_: RO_SMP.RO.m{2} = RO.m{1}); 1: by proc;inline *; sim;auto.
   by auto => />.
byequiv => //.
proc.
wp;call (dec_eq LRO S).
wp;call (enc_eq LRO S).
call(_: ={glob S, glob LRO}); 1: by sim.
wp;call (keygen_eq LRO S).
by conseq => />; sim.
qed. 

end section.

(* For the full spec we get the following result, which does 
   not require losslessness, but does require indifferentiability. 
   However we must first game hop to the ideal scheme. *)

module (DC_ES(S : Sampler, O : RO, Ac : KyberPKE.CORR_ADV) : HS_DEFS.Distinguisher) (F : HS_DEFS.PRF_Oracles)  = {

    proc distinguish() : bool = {
       var b;
       b <@ KyberPKE.Correctness_Adv(O,KyberS(DummyHS_D(F),S,KNS,KPRF,KPRF),Ac).main();
       return b;
    } 
}.

module (DC_PRF1(S : Sampler, O : RO, Ac : KyberPKE.CORR_ADV) : PRF_DEFS.Distinguisher) (F : PRF_DEFS.PRF_Oracles)  = {

    proc distinguish() : bool = {
       var b;
       b <@ KyberPKE.Correctness_Adv(O,KyberSIdeal(DummyHS(IdealHSF.RF),S,KNS,DummyPRF1(F),KPRF),Ac).main();
       return b;
    } 
}.

module (DC_PRF2(S : Sampler, O : RO, Ac : KyberPKE.CORR_ADV) : PRF_DEFS.Distinguisher) (F : PRF_DEFS.PRF_Oracles)  = {

    proc distinguish() : bool = {
       var b;
       b <@ KyberPKE.Correctness_Adv(O,KyberSIdeal(DummyHS(IdealHSF.RF),S,KNS,DummyPRF1(IdealPRF1.RF),DummyPRF2D(F)),Ac).main();
       return b;
    } 
}.

section.

declare module O <: RO {-IdealPRF2.RF, -IdealPRF1.RF, -PRF_.PRF, -IdealHSF.RF, -KPRF, -B1ROM, -B2ROM, -HSF.PRF}.
declare module S <: Sampler {-IdealPRF2.RF, -IdealPRF1.RF, -PRF_.PRF, -IdealHSF.RF, -KPRF, -O, -B1ROM, -B2ROM}.
declare module Ac <: KyberPKE.CORR_ADV {-IdealPRF2.RF, -IdealPRF1.RF, -PRF_.PRF, -IdealHSF.RF, -HSF.PRF, -O, -S, -KPRF, -B1ROM, -B2ROM}.

lemma ESHopC &m :
  Pr [ KyberPKE.Correctness_Adv(O,KyberS(KHS,S,KNS,KPRF,KPRF),Ac).main() @ &m : res] -
  Pr [ KyberPKE.Correctness_Adv(O,KyberS(DummyHS(IdealHSF.RF),S,KNS,KPRF,KPRF),Ac).main() @ &m : res] = 
  Pr [ HS_DEFS.IND(HSF.PRF,DC_ES(S,O,Ac)).main() @ &m : res ] - 
  Pr [ HS_DEFS.IND(IdealHSF.RF,DC_ES(S,O,Ac)).main() @ &m : res ].
proof.
have -> : Pr[Correctness_Adv(O,KyberS(KHS, S, KNS, KPRF,KPRF), Ac).main() @ &m : res]  = 
          Pr[HS_DEFS.IND(HSF.PRF, DC_ES(S, O, Ac)).main() @ &m : res] .
+ byequiv => //.
  proc. 
  inline {2} 2. inline {2} 2. 
  wp; call(_: ={glob O, glob S}); 1: by sim.
  wp; call(_: ={glob O, glob S}); 1: by sim.
  wp; call(_: ={glob O}); 1: by sim.
  conseq (_: _ ==> ={pk,sk, glob O,glob S}); 1: smt().
  swap {2} 2 -1.
  seq 1 1 : (={glob Ac, glob S, glob O}); 1: by sim.
  inline {1} 1. inline {1} 1. inline {2} 2. inline {2} 1.
  seq 3 3 : (#pre /\ ={rho,sig}); 1: by inline *; sim.
  by sim.

+ have -> : 
    Pr[Correctness_Adv(O,KyberS(DummyHS(IdealHSF.RF), S, KNS, KPRF, KPRF), Ac).main() @ &m : res] = 
    Pr[HS_DEFS.IND(IdealHSF.RF, DC_ES(S, O, Ac)).main() @ &m : res].
+ byequiv => //.
  proc. 
  inline {2} 2. inline {2} 2. 
  wp; call(_: ={glob O, glob S}); 1: by sim.
  wp; call(_: ={glob O, glob S}); 1: by sim.
  wp; call(_: ={glob O}); 1: by sim.
  conseq (_: _ ==> ={pk,sk, glob O,glob S}); 1: smt().
  swap {2} 2 -1.
  seq 1 1 : (={glob Ac, glob S, glob O}); 1: by sim.
  inline {1} 1. inline {1} 1. inline {2} 2. inline {2} 1.
  seq 3 3 : (#pre /\ ={rho,sig}); 1: by inline *; sim.
  by sim.
done.
qed.

lemma KyberS_KyberIdeal_C &m :
  Pr [ Correctness_Adv(O,KyberS(DummyHS(IdealHSF.RF),S,KNS,KPRF,KPRF),Ac).main() @ &m : res] =
  Pr [ Correctness_Adv(O,KyberSIdeal(DummyHS(IdealHSF.RF),S,KNS,KPRF,KPRF),Ac).main() @ &m : res].
proof.
byequiv => //.
proc. 
  wp; call(_: ={glob O, glob S}); 1: by sim.
  wp; call(_: ={glob O, glob S}); 1: by sim.
  wp; call(_: ={glob O}); 1: by sim.
  conseq (_: _ ==> ={pk,sk, glob O,glob S}); 1: smt().
  seq 1 1 : (={glob Ac, glob S, glob O}); 1: by sim.
  inline {1} 1. inline {2} 1. 
  wp; call(_: ={glob O, glob S}); 1: by sim.
  conseq => />.
  inline *.
  rcondt{1} 6; 1: by move => *; auto => />;smt(@SmtMap).
  seq {1} 5 2 : (true); 1: by auto.
  wp.
  conseq (_: _ ==> rho{2} = Array32.init (fun i => (r{1}.`1.[i])%PolyVec) /\ 
                   k{2} = Array32.init (fun i => (r{1}.`2.[i])%PolyVec)).
  move => /> [#] &1 r; 
       rewrite !SmtMap.get_set_sameE !oget_some;smt(Array32.tP setvE getvE Array32.initiE).
  transitivity {1} { r <@ ArraySample.sL(); }
   (true ==> ={r}) (true ==> rho{2} = Array32.init (fun i =>  r{1}.`1.[i]) /\ k{2} = Array32.init (fun i =>  r{1}.`2.[i])) => //; first
   by inline*; auto => /> &1 ? [rl1 rl2] /= => *;split;rewrite tP => *;rewrite initiE /#.
   
  transitivity {2} { (rho, k) <@ ArraySample.sR(); }
   (true ==> rho{2} = Array32.init (fun i =>  r{1}.`1.[i]) /\ k{2} = Array32.init (fun i =>  r{1}.`2.[i])) (true ==> ={rho,k})=> //.
   call arrsample; 1: by auto => />  *;split;rewrite tP => *;rewrite initiE /#.
   by inline*; auto => /> &1 ? [rl1 rl2] /= => *;split;rewrite tP => *;rewrite initiE /#.
qed.

lemma PRFHop1C &m :
  Pr [ Correctness_Adv(O,KyberSIdeal(DummyHS(IdealHSF.RF),S,KNS,KPRF,KPRF),Ac).main() @ &m : res] -
  Pr [ Correctness_Adv(O,KyberSIdeal(DummyHS(IdealHSF.RF),S,KNS,DummyPRF1(IdealPRF1.RF),KPRF),Ac).main() @ &m : res] = 
  Pr [ PRF_DEFS.IND(PRF_.PRF,DC_PRF1(S,O,Ac)).main() @ &m : res ] - 
  Pr [ PRF_DEFS.IND(IdealPRF1.RF,DC_PRF1(S,O,Ac)).main() @ &m : res ].
proof.
have -> : Pr[Correctness_Adv(O,KyberSIdeal(DummyHS(IdealHSF.RF), S, KNS, KPRF, KPRF), Ac).main() @ &m : res] = 
          Pr[PRF_DEFS.IND(PRF_.PRF, DC_PRF1(S, O, Ac)).main() @ &m : res].
+ byequiv => //.
  proc. 
  inline {2} 2. inline {2} 2. 
  wp; call(_: ={glob O, glob S}); 1: by sim.
  wp; call(_: ={glob O, glob S}); 1: by sim.
  wp; call(_: ={glob O}); 1: by sim.
  conseq (_: _ ==> ={pk, sk,glob O,glob S}); 1: smt().
  swap {2} 2 -1.
  seq 1 1 : (={glob Ac, glob S, glob O}); 1: by sim.
  inline {1} 1. inline {2} 2. 
  swap {2} [2..3] -1.
  seq 2 2 : (#pre /\ ={glob IdealHSF.RF, rho}). 
  + by inline *; sim.
  seq 1 2 : (#pre /\ sig{1} = PRF_.PRF.k{2});1: by inline *; auto => />.
  inline {1} 1; inline {2} 1.
  sim 8 8.
  seq 7 7 : (#pre /\ ={a,rho0} /\ sig0{1} = PRF_.PRF.k{2}); 1: by  sim. 
  conseq => />.
  inline {1} 1; inline {2} 1. 
  inline *. 
  unroll for {1} 8.
  unroll for {2} 8.
  do 3!( wp; conseq => />; sim).
  wp;auto => />;sim.
  unroll for {1} 6.
  unroll for {2} 6.
  do 3!( wp; conseq => />; sim).
  by wp;auto => />;sim.

have -> : Pr[Correctness_Adv(O,KyberSIdeal(DummyHS(IdealHSF.RF), S, KNS, DummyPRF1(IdealPRF1.RF), KPRF), Ac).main() @ &m : res] = 
          Pr[PRF_DEFS.IND(IdealPRF1.RF, DC_PRF1(S, O, Ac)).main() @ &m : res].
+ byequiv => //.
  proc. 
  inline {2} 2. inline {2} 2. 
  wp; call(_: ={glob O, glob S}); 1: by sim.
  wp; call(_: ={glob O, glob S}); 1: by sim.
  wp; call(_: ={glob O}); 1: by sim.
  conseq (_: _ ==> ={pk, sk, glob O,glob S}); 1: smt().
  swap {2} 2 -1.
  seq 1 1 : (={glob Ac, glob S, glob O}); 1: by sim.
  inline {1} 1. inline {2} 2. 
  swap {2} [2..3] -1.
  seq 2 2 : (#pre /\ ={glob IdealHSF.RF, rho}). 
  + by inline *; sim.
  seq 1 2 : (#pre /\ ={glob IdealPRF1.RF,sig});1: by inline *; auto => />.
  by inline *;sim.
done.
qed.

lemma PRFHop2C &m :
  Pr [ Correctness_Adv(O,KyberSIdeal(DummyHS(IdealHSF.RF),S,KNS,DummyPRF1(IdealPRF1.RF),KPRF),Ac).main() @ &m : res] -
  Pr [ Correctness_Adv(O,KyberSIdeal(DummyHS(IdealHSF.RF),S,KNS,DummyPRF1(IdealPRF1.RF),DummyPRF2(IdealPRF2.RF)),Ac).main() @ &m : res] = 
  Pr [ PRF_DEFS.IND(PRF_.PRF,DC_PRF2(S,O,Ac)).main() @ &m : res ] - 
  Pr [ PRF_DEFS.IND(IdealPRF2.RF,DC_PRF2(S,O,Ac)).main() @ &m : res ].
proof.
have -> : Pr[Correctness_Adv(O,KyberSIdeal(DummyHS(IdealHSF.RF), S, KNS, DummyPRF1(IdealPRF1.RF), KPRF), Ac).main() @ &m : res] = 
          Pr[PRF_DEFS.IND(PRF_.PRF, DC_PRF2(S, O, Ac)).main() @ &m : res].
+ byequiv => //.
  proc. 
  inline {2} 2. inline {2} 2. 
  wp; call(_: ={glob O, glob S}); 1: by sim.
  swap {2} 1 3.
  seq 3 3 : (={glob S, glob Ac, glob O,pk,sk,m}).
  + wp; call(_: ={glob O}); 1: by sim.
    wp; call(_: ={glob O, glob S}); 1: by sim.
    by inline *; auto => />; sim. 
  conseq (_: _ ==> ={c, glob O,glob S}); 1: smt().
  inline {1} 1. inline {2} 2. 
  swap {2} [2..3] -1; sp 2 2.
  seq 1 2 : (#pre /\ r{1} = PRF_.PRF.k{2});1: by inline *; auto => />.
  inline {1} 1; inline {2} 1.
  sim 13 13.
  seq 12 12 : (={that, m1, aT, glob S, glob O}  /\ r0{1} = PRF_.PRF.k{2}); 1: by  sim. 
  conseq => />.
  inline {1} 1; inline {2} 1. 
  inline *. 
  wp;auto => />;sim.
  unroll for {1} 8.
  unroll for {2} 8.
  do 3!( wp; conseq => />; sim).
  wp;auto => />;sim.
  unroll for {1} 6.
  unroll for {2} 6.
  do 3!( wp; conseq => />; sim).
  by wp;auto => />;sim.

have -> : Pr[Correctness_Adv(O,KyberSIdeal(DummyHS(IdealHSF.RF), S, KNS, DummyPRF1(IdealPRF1.RF), DummyPRF2(RF)), Ac).main
   () @ &m : res] = 
          Pr[PRF_DEFS.IND(RF, DC_PRF2(S, O, Ac)).main() @ &m : res].
+ byequiv => //.
  proc. 
  inline {2} 2. inline {2} 2. 
  wp; call(_: ={glob O, glob S}); 1: by sim.
  swap {2} 1 3.
  seq 3 3 : (={glob S, glob Ac, glob O,pk,sk,m}).
  + wp; call(_: ={glob O}); 1: by sim.
    wp; call(_: ={glob O, glob S}); 1: by sim.
    by inline *; auto => />; sim. 
  conseq (_: _ ==> ={c, glob O,glob S}); 1: smt().
  inline {1} 1. inline {2} 2. 
  swap {2} [2..3] -1; sp 2 2.
  seq 1 2 : (#pre /\ ={glob IdealPRF2.RF,r});1: by inline *; auto => />.
  by inline *;sim => /> /#.
done.
qed.


end section.


section.



declare module A <: CORR_ADV {-HSF.PRF, -PRF_.PRF, -B1ROM, -B2ROM, -KPRF, -RF,-IdealHSF.RF, -IdealPRF1.RF, -LRO,-RO_H.LRO,-RO_SMP.RO, -RO_SMP.LRO, -CB}.
declare module XOF <: XOF_RO_t {-HSF.PRF, -PRF_.PRF, -B1ROM, -B2ROM, -KPRF, -RF,-IdealHSF.RF, -IdealPRF1.RF, -A,-LRO,-RO_H.LRO,-RO_SMP.RO, -RO_SMP.LRO, -CB}.
declare module Sim <: Simulator_t {-HSF.PRF, -PRF_.PRF, -B1ROM, -B2ROM, -KPRF, -RF,-IdealHSF.RF, -IdealPRF1.RF, -XOF, -A,-LRO,-RO_H.LRO,-RO_SMP.RO, -RO_SMP.LRO, -CB}.


lemma correctness_spec &m cu_bound failprob1 failprob2 epsilon  :
  (glob Bcb2){m} = cu_bound =>

  (forall (O <: Ideal_RO), islossless O.get => islossless Sim(O).init) =>
  (forall (O <: Ideal_RO), islossless O.get => islossless Sim(O).get) =>
  (forall (O <: SMP_RO), islossless O.get => islossless A(O).find) =>

  (forall (trb : bool * bool)
    (D0 <: Distinguisher_t{ -RO_H.RO, -RO_H.LRO, -RO_SMP.RO, -RO_SMP.LRO, -Sim, -KSampler(XOF), -NTTSampler(KSampler(XOF))}),
    `|Pr[WIndfReal(D0, NTTSampler(KSampler(XOF)), RO_SMP.LRO).main(trb) @ &m :
         res] -
      Pr[WIndfIdeal(D0, Sim, RO_H.LRO).main(trb) @ &m : res]| <=
    epsilon) =>

  Pr[ CB1.main(cu_bound, cv_bound_max) @ &m : res] <= failprob1 =>
  Pr[ CB2.main(cu_bound) @ &m : res] <= failprob2 =>

  Pr[ KyberPKE.Correctness_Adv(LRO,KyberS(KHS, KSampler(XOF), KNS,KPRF,KPRF),A).main() @ &m : res]  <=
    `|Pr[MLWE(Bcb2).main(false) @ &m : res] -
          Pr[MLWE(Bcb2).main(true) @ &m : res]| + failprob1 + failprob2 + epsilon +
  (`|Pr [ HS_DEFS.IND(HSF.PRF,DC_ES(KSampler(XOF),LRO,A)).main() @ &m : res ] - 
  Pr [ HS_DEFS.IND(IdealHSF.RF,DC_ES(KSampler(XOF),LRO,A)).main() @ &m : res ]|) +
  (`|Pr [ PRF_DEFS.IND(PRF_.PRF,DC_PRF1(KSampler(XOF),LRO,A)).main() @ &m : res ] - 
  Pr [ PRF_DEFS.IND(IdealPRF1.RF,DC_PRF1(KSampler(XOF),LRO,A)).main() @ &m : res ]|) +
  (`|Pr [ PRF_DEFS.IND(PRF_.PRF,DC_PRF2(KSampler(XOF),LRO,A)).main() @ &m : res ] - 
  Pr [ PRF_DEFS.IND(IdealPRF2.RF,DC_PRF2(KSampler(XOF),LRO,A)).main() @ &m : res ]|).
move => meminit Sim_i_ll Sim_h_ll A_ll ind fp1 fp2.
(*  
  We lost connection to the spec in the rom
have <-: Pr[Correctness_Adv(LRO,KyberS(KHS, KSampler(XOF), KNS,KPRF,KPRF), A).main() @ &m : res] = 
         Pr[Correctness_Adv(LRO,Kyber(KHS, XOF, KPRF), A).main() @ &m : res].
+ byequiv => //.
  proc. 
  wp; call(_: ={glob LRO, glob XOF}); 1: by sim.
  call (enc_sampler_enc LRO XOF).
  wp; call(_: ={glob LRO}); 1: by sim.
  call (kg_sampler_kg LRO XOF).
  by inline *; auto.
*)

move : (correctness_any_sampler A (KSampler(XOF)) Sim &m cu_bound failprob1 failprob2 epsilon meminit Sim_i_ll Sim_h_ll A_ll ind fp1 fp2).

have <- := (ESHopC LRO (KSampler(XOF)) A).
have <- := (PRFHop1C LRO (KSampler(XOF)) A).
have <- := (PRFHop2C LRO (KSampler(XOF)) A).
have <- := (KyberS_KyberIdeal_C LRO (KSampler(XOF)) A).
have <-: Pr[Correctness_Adv(LRO,KyberSI(KSampler(XOF)), A).main() @ &m : res] = 
         Pr[Correctness_Adv(LRO,KyberSIdeal(DummyHS(IdealHSF.RF), KSampler(XOF), KNS, DummyPRF1(IdealPRF1.RF), DummyPRF2(RF)), A).main
   () @ &m : res] by byequiv => //=; proc; sim.


by smt().
qed.

end section.

