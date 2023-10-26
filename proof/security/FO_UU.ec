require import AllCore Distr List Real SmtMap FSet DInterval FinType KEM_ROM.
require (****) PKE_ROM PlugAndPray Hybrid FelTactic. 

(* This will be the underlying scheme resulting 
   from the T transform, since we will need to
   assume some of the properties that it offers.. *)
require FO_TT.
clone import FO_TT as TT.
import PKE.

(* we inherit the following axioms 
dplaintext_ll: is_lossless dplaintext
 dplaintext_uni: is_uniform dplaintext
 dplaintext_fu: is_full dplaintext
 FinT.enum_spec: forall (x : plaintext), count (pred1 x) enum = 1
 kg_ll: is_lossless kg
 randd_ll: is_lossless randd
 ge0_qH: 0 <= qH
 ge0_qV: 0 <= qV
 ge0_qP: 0 <= qP
 ge0_qHC: 0 <= qHC *)

(* the type of KEM keys *)
type key.
op [lossless uniform full]dkey : key distr.

(*  A PRF *)

require PRF.
print PRF.
clone import PRF as J with
   type D <- ciphertext,
   type R <- key.
clone import RF with 
   op dR <- fun _ => dkey
   proof dR_ll by (move => *;apply dkey_ll)
   proof *.
(* we get the prf key type K from the next clone *)
clone import PseudoRF.
(**********)
clone import KEM_ROM.KEM_ROM_x2 as KEMROMx2 with
   type pkey <- pkey,
   type skey = (pkey * skey) * K,
   type ciphertext <- ciphertext,
   type key <- key,
   op dkey <- dkey,
   type RO1.in_t <- plaintext,
   type RO1.out_t <- randomness,
   op   RO1.dout <- fun _ => randd,
   type RO1.d_in_t <- unit, 
   type RO1.d_out_t <- bool,
   type RO2.in_t <- plaintext,
   type RO2.out_t <- key,
   op   RO2.dout <- fun _ => dkey,
   type RO2.d_in_t <- unit, 
   type RO2.d_out_t <- bool
   proof dkey_ll by apply dkey_ll
   proof dkey_uni by apply dkey_uni
   proof dkey_fu by apply dkey_fu
   proof *.

(******* Query Bounds ******)

(* Max number of calls to RO in attack on UU *)  
const qHU : { int | 0 <= qHU } as ge0_qHU. 
(* Maximum number of calls to Dec on TT *) 
const qD : { int | 0 <= qD } as ge0_qD.

(***************************************)

module (UU : KEMROMx2.Scheme) (H : POracle_x2) = {

  module HT : PKEROM.POracle = {
     proc get = H.get1
  }

  module HU = {
     proc get = H.get2
  }

  proc kg() : pkey * skey = {
     var pk, sk, k;
     (pk,sk) <$ kg;
     k <$ dK;
     return (pk, ((pk,sk),k));
  }
  
  proc enc(pk : pkey) : ciphertext * key = {
     var m, c, k;
     m <$ dplaintext;
     c <@TT(HT).enc(pk,m);
     k <@ HU.get(m);
     return (c,k);
  }
  
  proc dec(sk : skey, c : ciphertext) : key option = {
     var m', k;
     k <- witness;
     m' <@ TT(HT).dec(sk.`1,c);
     if (m' = None) {
        k <- F sk.`2 c;
     }
     else {
        k <@ HU.get(oget m');
     }
     return (Some k);
  }
}.


(* Correctness proof *)

module (B_UC : PKEROM.CORR_ADV)  (HT : PKEROM.POracle)= {
   proc find(pk : pkey, sk : PKEROM.skey) : plaintext = {
      var m;
      m <$ dplaintext;
      return m;
   }
}.

lemma correctness &m : 
   Pr [ KEMROMx2.Correctness(RO_x2(RO1.RO,RO2.RO),UU).main() @ &m : res ] <=
     Pr [ PKEROM.Correctness_Adv(PKEROM.RO.RO,TT,B_UC).main() @ &m : res ].
proof.
byequiv => //.
proc.
inline {1} 1; inline {1} 3; inline {1} 6. 
inline {2} 2;inline {2} 4.
seq 4 2 : ( KEMROMx2.RO1.RO.m{1} = PKEROM.RO.RO.m{2} /\ 
            pk0{1} = kpair{2}.`1 /\ 
            sk0{1} = kpair{2}.`2); 
      1: by inline *;rnd{1};rnd;auto;smt(dK_ll).
sp.
seq 1 1 : (#pre /\ m{1} = m0{2}); 1: by auto.
sp. 
seq 2 1 : (#pre /\ c0{1} = c{2} /\ m{1} \in KEMROMx2.RO2.RO.m{1} /\
         k1{1} = oget KEMROMx2.RO2.RO.m{1}.[m{1}]);1: 
   by inline *;wp;rnd{1};wp;auto;smt(mem_set).
inline {1} 2;sp.
seq 1 1 : (#pre /\ m'{1} = m'{2}); 
  1: by inline *;wp;conseq />;sim;auto => /#.
by inline *;if{1};inline *;auto => />;smt(get_setE).
qed.

(* Security proof *)

module CountCCAO (O : CCA_ORC) = {
  var c_cca : int
  var c_hu   : int
  var c_ht   : int
  proc init () = { c_ht <- 0; c_hu <- 0; c_cca <- 0;  }
 
  proc cca(c : ciphertext) : key option = {
    var k;    
    k <@ O.dec(c);
    c_cca <- c_cca + 1;
    return k;
  }
  
}.

module CountHx2(H : KEMROMx2.POracle_x2) = {
  proc get1(x:plaintext) = {
    var r;
    r <@ H.get1(x);
    CountCCAO.c_ht <- CountCCAO.c_ht + 1;
    return r;
  }  
  proc get2(x:plaintext) = {
    var r;
    r <@ H.get2(x);
    CountCCAO.c_hu <- CountCCAO.c_hu + 1;
    return r;
  }  
}.


(********************************************************)
(* We start with the PRF hop                        *)


module (UU1(PRFO : PRF_Oracles) : KEMROMx2.Scheme) (H : POracle_x2) = {
  include UU(H) [-kg,dec]

  proc kg() : pkey * skey = {
     var pk, sk;
     (pk,sk) <$ kg;
     return (pk, ((pk,sk),witness));
  }

  proc dec(sk : skey, c : ciphertext) : key option = {
     var m', k;
     k <- witness;
     m' <@ TT(UU(H).HT).dec(sk.`1,c);
     if (m' = None) {
        k <@ PRFO.f(c);
     }
     else {
        k <@ UU(H).HU.get(oget m');
     }
     return (Some k);
  }
}.


module Gm1P(H : Oracle_x2, A : CCA_ADV, PRFO : PRF_Oracles) = {
  
  proc main'() : bool = {
    var pk : pkey;
    var k1 : key;
    var ck0 : ciphertext * key;
    var b : bool;
    var b' : bool;
    
    H.init();
    CCA.cstar <- None;
    (pk, CCA.sk) <@ UU1(PRFO,H).kg();
    k1 <$ dkey;
    b <$ {0,1};
    ck0 <@ UU1(PRFO,H).enc(pk);
    CCA.cstar <- Some ck0.`1;
    b' <@ CCA(H, UU1(PRFO),A).A.guess(pk, ck0.`1, if b then k1 else ck0.`2);
    
    return b' = b;
  }
}.

module Gm1(H : Oracle_x2, A : CCA_ADV) = {
    proc main() : bool = {
       var b;
       RF.init();
       b <@ Gm1P(H,A,RF).main'();
       return b;
    }
}.

module D(A : CCA_ADV, PRFO : PRF_Oracles) = {
   proc distinguish = Gm1P(RO_x2(RO1.RO,RO2.RO),A,PRFO).main'
}.

(********************************************************)
(* Next step is to make the TT transform deterministic
   by eagerly sampling the whole random oracle. 
   Note that none of our reductions will need to simulate
   this step, since we are reducing to an assumption that
   already takes care of that. *)
(********************************************************)


clone import KEMROMx2.RO1.FinEager as RO1E
   with op FinFrom.enum = FinT.enum
   proof FinFrom.enum_spec by apply FinT.enum_spec
   proof *.

module RO_x2E = RO_x2(RO1E.FunRO,RO2.RO).
(* Now we proceed with the HHK proof.                         
   We simulate decryption without using SK and just keeping
   track of what happens in H *)


module (UU2 : KEMROMx2.Scheme) (H : POracle_x2) = {
  include UU1(RF,H) [-dec]

  var lD : (ciphertext * key) list

  proc dec(sk : skey, c : ciphertext) : key option = {
     var k, ko;
     ko <- None;
     if (assoc lD c <> None) {
        ko <- assoc lD c;
     }
     else {
        k <$ dkey;
        ko <- Some k;
        (* HHK SAYS INCONSISTENCY IF DEC C <> NONE && ENC (DEC C) <> C 
           HOWEVER, THIS CAN NEVER HAPPEN WHEN DEALING WITH THE FO_TT TRANSFORM *)
        lD <- (c,k) :: lD;
     }
     return ko;
  }
}.

(* For an up-to-bad argument we'll need to trigget bad in both
   Gm1 and Gm2, so we recast everything in the memory of Gm2. *)

  module H1 : POracle_x2 = {
     var bad : bool

     proc init() = {}
     proc get1 = RO_x2E.get1
     proc get2(m : plaintext) : key = {
       var k,cm;
       cm <- enc (RO1E.FunRO.f m) CCA.sk.`1.`1 m;
       bad <- if dec CCA.sk.`1.`2 cm <> Some m then true else bad;
       k <$ dkey;
       if (m \notin RO2.RO.m) {
         RO2.RO.m.[m] <- k;
       }
       return oget RO2.RO.m.[m];
     }
  }.

  module H2 : POracle_x2 = {
     var merr : plaintext option
     var invert : bool
     var mtgt : plaintext
     var mpre : plaintext option
     
     proc init() = {}
     proc get1 = RO_x2E.get1
     proc get2(m : plaintext) : key = {
       var k,cm;
       mtgt <- if CCA.cstar = None then m else mtgt; 
       cm <- enc (RO1E.FunRO.f m) CCA.sk.`1.`1 m;
       (* INCONSISTENCY TO GM1 IF DEC (ENC M) <> SOME M
          CAN BE REDUCED TO CORRECTNESS. *)
       H1.bad <- if dec CCA.sk.`1.`2 cm <> Some m then true else H1.bad;
       H2.merr <- if H2.merr = None && H1.bad then Some m else H2.merr;
       H2.invert <- if CCA.cstar <> None &&  m = mtgt &&
                       dec CCA.sk.`1.`2 (oget CCA.cstar) = Some mtgt
                    then true else H2.invert;
       H2.mpre <- if H2.mpre = None && H2.invert then Some m else H2.mpre;
       k <$ dkey;
       if (m \notin RO2.RO.m) {
         if (assoc UU2.lD cm <> None) {
             k <- oget (assoc UU2.lD cm);
         }
         else {
             UU2.lD <- (cm,k) :: UU2.lD;
         }
         RO2.RO.m <- RO2.RO.m.[m <- k];
       }
       return oget (RO2.RO.m.[m]);
     }
  }.


module Gm2(H : Oracle_x2, S : KEMROMx2.Scheme, A : CCA_ADV) = {

  module O = {
    proc dec(c : ciphertext) : key option = {
      var k : key option;
      
      k <- None;
      if (Some c <> CCA.cstar) 
        k <@ S(H).dec(CCA.sk, c);
      
      return k;
    }
  }

  proc main2() : bool = {
    var pk : pkey;
    var k1 : key;
    var ck0 : ciphertext * key;
    var cstar : ciphertext option;
    var b : bool;
    var b' : bool;
    
    H1.bad <- false;
    H2.merr <- None;
    H2.invert <- false;
    H2.mpre <- None;
    RF.init();
    RO_x2E.init();
    UU2.lD <- [];
    CCA.cstar <- None;
    (pk, CCA.sk) <@ S(H).kg();
    k1 <$ dkey;
    b <$ {0,1};
    ck0 <@ UU2(H).enc(pk);
    CCA.cstar <- Some ck0.`1;
    b' <@ CCA(H, S, A).A.guess(pk, ck0.`1, if b then k1 else ck0.`2);
    return b' = b;
  }

  proc main() : bool = {
    var win,nobias;
    win <@ main2(); 
    nobias <$ {0,1};
    return (if H1.bad then nobias else win);
  }

}.

module (BUUC(A : CCA_ADV) : PKEROM.CORR_ADV) (H : PKEROM.POracle) = {

   module H2B = {
      include H2 [-get1]
      proc get1= H.get
   }

   proc find(pk : pkey, sk : PKEROM.skey) : plaintext = {
    var k1 : key;
    var ck0 : ciphertext * key;
    var cstar : ciphertext option;
    var b : bool;
    var b' : bool;
    var z : K;
    
    H1.bad <- false;
    H2.merr <- None;
    H2.invert <- false;
    H2.mpre <- None;
    RF.init();
    RO2.RO.init();
    UU2.lD <- [];
    CCA.cstar <- None;
    CCA.sk <- (sk,witness);
    k1 <$ dkey;
    b <$ {0,1};
    ck0 <@ UU2(H2B).enc(pk);
    CCA.cstar <- Some ck0.`1;
    b' <@ CCA(H2B, UU2, A).A.guess(pk, ck0.`1, if b then k1 else ck0.`2);
    return (oget H2.merr);  
   } 
}.

module Gm3(H : Oracle_x2, S : KEMROMx2.Scheme, A : CCA_ADV) = {
  module O = {
    proc dec(c : ciphertext) : key option = {
      var k : key option;
      
      k <- None;
      if (Some c <> CCA.cstar) 
        k <@ S(H).dec(CCA.sk, c);
      
      return k;
    }
  }

  proc main() : bool = {
    var pk : pkey;
    var k1, k2 : key;
    var b : bool;
    var b' : bool;
    var r : randomness;
    var cm : ciphertext;
    var nobias : bool;
    
    H1.bad <- false;
    H2.merr <- None;
    H2.invert <- false;
    H2.mpre <- None;
    RF.init();
    RO_x2E.init();
    UU2.lD <- [];
    CCA.cstar <- None;
    (pk, CCA.sk) <@ S(H).kg();
    k1 <$ dkey; k2 <$ dkey;
    b <$ {0,1};
    H2.mtgt <$ dplaintext;
    r <@ H.get1(H2.mtgt);
    cm <- enc r pk H2.mtgt;
    H1.bad <- if dec CCA.sk.`1.`2 cm <> Some H2.mtgt then true else H1.bad;
    H2.merr <- if H2.merr = None && H1.bad then Some H2.mtgt else H2.merr;
    UU2.lD <- (cm,k2) :: UU2.lD;
    RO2.RO.m.[H2.mtgt] <- witness;
    CCA.cstar <- Some cm;
    b' <@ CCA(H, S, A).A.guess(pk, cm, if b then k1 else k2);
    nobias <$ {0,1};
    return (if H1.bad then nobias else (b' = b));
  }

}.

print FO_TT.find.

module (BUUOW(A : CCA_ADV) : PKEROM.PCVA_ADV) (H : PKEROM.POracle, O : PKEROM.VA_ORC) = {

   module H2B = {
      include H2 [-get1]
      proc get1= H.get
   }

   proc find(pk : pkey, cm : ciphertext) : plaintext = {
    var k1, k2 : key;
    var b : bool;
    var b' : bool;
    var r : randomness;
    
    H1.bad <- false;
    H2.merr <- None;
    H2.invert <- false;
    H2.mpre <- None;
    RF.init();
    RO2.RO.init();
    UU2.lD <- [];
    CCA.cstar <- None;
    CCA.sk <- ((pk,witness),witness);
    k1 <$ dkey; k2 <$ dkey;
    b <$ {0,1};
    UU2.lD <- (cm,k2) :: UU2.lD;
    CCA.cstar <- Some cm;
    b' <@ CCA(H2B, UU2, A).A.guess(pk, cm, if b then k1 else k2);
    return (fst (oget (FO_TT.find (fun m0 _ => 
         enc (FunRO.f m0) CCA.sk.`1.`1 m0 = oget CCA.cstar)  RO2.RO.m)));
   } 
}.


section.

declare module A <: CCA_ADV  {-CCA, -RO1.RO, -RO1.FRO, -RO2.RO, -PRF, -RF, -UU2, 
                    -RO1E.FunRO, -Gm2, -H2, -Gm3, -PKEROM.OW_PCVA} .


lemma Gm0_Gm1 &m : 
   Pr[ KEMROMx2.CCA(RO_x2(RO1.RO,RO2.RO), UU, A).main() @ &m : res ] -
     Pr [ Gm1(RO_x2(RO1.RO,RO2.RO),A).main() @ &m : res ] =
       Pr [ J.IND(PRF,D(A)).main() @ &m : res ] - 
         Pr [ J.IND(RF, D(A)).main() @ &m : res ].
proof. 
have -> : Pr[ KEMROMx2.CCA(RO_x2(RO1.RO,RO2.RO), UU, A).main() @ &m : res ] =
          Pr [ J.IND(PRF,D(A)).main() @ &m : res ].
+ byequiv => //.
  proc;inline {2} 2;inline {2} 1; inline {1} 3.
  swap {1} 4 -3.  
  wp;call(_: ={glob RO1.RO, glob RO2.RO, CCA.cstar} /\ 
              CCA.sk{1}.`1.`1 = CCA.sk{2}.`1.`1 /\
              CCA.sk{1}.`1.`2 = CCA.sk{2}.`1.`2 /\
              CCA.sk{1}.`2 = PRF.k{2} ).  
  + proc;sp; if; 1,3: by auto => />. 
    inline {1} 1;inline {2} 1. 
    inline {1} 4;inline {2} 4.
    sp;if;1:by auto => /> /#.
    + sp;seq 4 4 : (#{/~rv{1}}{~rv{2}}pre /\ ={m'}); 
        1: by inline *;auto => /> /#.
      sp;inline *;if;by auto => /> /#.
      by sp;inline *;if;by auto => /> /#.
    + by proc;inline *; auto => /> /#.
    + by proc;inline *; auto => /> /#.
  wp;call(_: ={glob RO1.RO, glob RO2.RO, CCA.cstar} /\ 
              CCA.sk{1}.`1.`1 = CCA.sk{2}.`1.`1 /\
              CCA.sk{1}.`1.`2 = CCA.sk{2}.`1.`2 /\
              CCA.sk{1}.`2 = PRF.k{2} ).  
  + by inline *;conseq/>;sim.
  by inline *;auto => />.

have -> : Pr[ Gm1(RO_x2(RO1.RO,RO2.RO),A).main() @ &m : res ] =
          Pr [ J.IND(RF,D(A)).main() @ &m : res ].
+ byequiv => //.
  proc;inline {2} 2;inline {2} 1;inline {1} 2; inline {1} 1.
    wp;call(_: ={glob RO1.RO, glob RO2.RO, CCA.cstar, glob RF} /\ 
              CCA.sk{1}.`1.`1 = CCA.sk{2}.`1.`1 /\
              CCA.sk{1}.`1.`2 = CCA.sk{2}.`1.`2).  
  + proc;sp; if; 1,3: by auto => />. 
    inline {1} 1;inline {2} 1. 
    inline {1} 4;inline {2} 4.
    sp;if;1:by auto => /> /#.
    + sp;seq 4 4 : (#{/~rv{1}}{~rv{2}}pre /\ ={m'});
       1: by inline *;auto => /> /#.
      sp;inline *;if; 1: by auto => /> /#.
      + by sp;inline *;if;auto => /> /#.
      by sp;inline *;auto => /> /#.
    by inline *;conseq/>;sim.
    + by proc;inline *; auto => /> /#.
    + by proc;inline *; auto => /> /#.
  by inline *;auto => />.
done.
qed.

local module (DG1  : RO1E.FinRO_Distinguisher) (G : RO1.RO) = {
    proc distinguish() = {
        var b;
        b <@ Gm1(RO_x2(G,RO2.RO),A).main();
        return b;
    }
}.

lemma uu_goal_eager &m: 
    Pr[Gm1(RO_x2(RO1.RO,RO2.RO),A).main() @ &m :res]  =
       Pr[Gm1(RO_x2E,A).main() @ &m : res].
proof.  
have -> : Pr[Gm1(RO_x2(RO1.RO,RO2.RO),A).main() @ &m : res] = 
          Pr[RO1.MainD(DG1,RO1.RO).distinguish() @ &m : res]
    by byequiv => //;proc;inline *;sim.
have -> : Pr[Gm1(RO_x2E,A).main() @ &m : res] = 
          Pr[RO1.MainD(DG1,RO1E.FunRO).distinguish() @ &m : idfun res]
   by rewrite /idfun /=;byequiv => //;proc;inline *;sim;
   auto => />; apply MUniFinFun.dfun_ll;smt(randd_ll).
have := RO1E.pr_FinRO_FunRO_D _ DG1 &m () idfun; 1: by smt(randd_ll).
have := RO1E.pr_RO_FinRO_D _ DG1 &m () idfun; 1: by smt(randd_ll).
by smt().
qed.

(*
REDUCTION TO CORRECTNESS SEEMS STRAIGHTFORWARD.
PROVING UP TO BAD REQUIRES DEALING WITH THE FACT THAT
DEC IS PRE-SAMPLING VALUES OF H2 AS FOLLOWS:

Assume not bad.

lD has three types of entries:
a) values added for invalid ciphertexts (implicit reject)
b) values added for Hash queries the preimage is already
   in H2 and the key is already defined.
   in both games there would be no sampling
c) values added for valid ciphertexts before H2 was
   called. This sets an implicit entry in the ROM.
Note that the game has no clue which case it is.

DEC:
In the proof we can check for the cases in new queries:

a) enc (dec c) <> c, then we are aligned with an RF sampling

b) does not occur, because Hash forced the entry and so it is 
   not a new query

c) we sample a value that is also sampled on the left, 
   but we will only consolidate it later.

*)

op c2m(c : ciphertext, sk : PKEROM.skey) : plaintext option = dec sk.`2 c.

op oc2m(c : ciphertext, sk : PKEROM.skey) : plaintext = oget (dec sk.`2 c).

op m2c(m : plaintext, sk : PKEROM.skey, f : plaintext -> randomness) : ciphertext = enc (f m) sk.`1 m.

op goodc(c : ciphertext, sk : PKEROM.skey, f : plaintext -> randomness) = 
          c2m c sk <> None /\ m2c (oc2m c sk) sk f = c.

local lemma G1_G2 &m :
  (forall (H0 <: POracle_x2{-A} ) (O <: CCA_ORC{ -A} ),
  islossless O.dec => islossless H0.get1 => islossless H0.get2 => islossless A(H0, O).guess) =>

  `| Pr[Gm1(RO_x2E,A).main() @ &m : res] -  Pr[ Gm2(H2,UU2,A).main() @ &m : res /\ !H1.bad] |
     <= Pr[ Gm2(H2,UU2,A).main() @ &m : H1.bad ].
proof. 
move => A_ll.
have -> : Pr[Gm1(RO_x2E,A).main() @ &m : res]  =  Pr[ Gm2(H1,UU1(RF),A).main2() @ &m : res].
+ byequiv => //.
  proc; inline {1} 2; sp; wp.
  call(_: ={glob RF, glob RO1E.FunRO, glob RO2.RO, glob CCA}).
  + by sim. 
  + by sim. 
  + by sim. 
  by conseq />;[by smt() | by sim].

byequiv : H1.bad => //.
proc;rnd{2};inline {2} 1;wp.
seq 11 11 : (
    ={glob A,glob RO1E.FunRO, glob CCA,glob H1,k1,pk,b}  /\  uniq (unzip1 UU2.lD{2}) /\
    (* case a: all occuring badc accounted for *)
    (forall c, c \in UU2.lD{2} => !goodc c.`1 CCA.sk{2}.`1 RO1E.FunRO.f{2} => 
                                  c.`1 \in RF.m{1}) /\
    (* case a: all PRF inputs are occurring badcs *)
    (forall c, c \in RF.m{1} => assoc UU2.lD{2} c = RF.m{1}.[c]) /\
    (* case b: all occurring goodc accounted for *)
    (forall c, c \in UU2.lD{2} => goodc c.`1 CCA.sk{2}.`1 RO1E.FunRO.f{2} => 
                                  oc2m c.`1 CCA.sk{2}.`1 \in RO2.RO.m{1}) /\
    (* case b: all RO2 inputs with an occurrence  *)
    (forall m, m \in RO2.RO.m{2} => 
        (assoc UU2.lD{2} (m2c m CCA.sk{2}.`1 RO1E.FunRO.f{2}) <> None /\
            assoc UU2.lD{2} (m2c m CCA.sk{2}.`1 RO1E.FunRO.f{2}) = RO2.RO.m{2}.[m] /\ 
                 RO2.RO.m{1}.[m] = RO2.RO.m{2}.[m])) /\
    (* case c: RO2 inconsistency for entries not added by dec oracle *)
    (forall m, m \in RO2.RO.m{1} => m \notin RO2.RO.m{2} => 
               assoc UU2.lD{2} (m2c m CCA.sk{2}.`1 RO1E.FunRO.f{2}) = RO2.RO.m{1}.[m]) /\  
                 RO2.RO.m{2} = empty /\ 
                 UU2.lD{2} = [] /\
                 !H1.bad{2}); 1: by
      inline *; auto => />; smt(mem_empty).
seq 2 2 : (={H1.bad,b} /\
   (!H1.bad{2} => (
    ={glob A,glob RO1E.FunRO, glob CCA,k1,pk,ck0} /\  uniq (unzip1 UU2.lD{2}) /\
    (* case a: all occuring badc accounted for *)
    (forall c, c \in UU2.lD{2} => !goodc c.`1 CCA.sk{2}.`1 RO1E.FunRO.f{2} => 
                                  c.`1 \in RF.m{1}) /\
    (* case a: all PRF inputs are occurring badcs *)
    (forall c, c \in RF.m{1} => assoc UU2.lD{2} c = RF.m{1}.[c]) /\
    (* case b: all occurring goodc accounted for *)
    (forall c, c \in UU2.lD{2} => goodc c.`1 CCA.sk{2}.`1 RO1E.FunRO.f{2} => 
                                  oc2m c.`1 CCA.sk{2}.`1 \in RO2.RO.m{1}) /\
    (* case b: all RO2 inputs with an occurrence  *)
    (forall m, m \in RO2.RO.m{2} => 
        (assoc UU2.lD{2} (m2c m CCA.sk{2}.`1 RO1E.FunRO.f{2}) <> None /\
            assoc UU2.lD{2} (m2c m CCA.sk{2}.`1 RO1E.FunRO.f{2}) = RO2.RO.m{2}.[m] /\ 
                 RO2.RO.m{1}.[m] = RO2.RO.m{2}.[m])) /\
    (* case c: RO2 inconsistency for entries not added by dec oracle *)
    (forall m, m \in RO2.RO.m{1} => m \notin RO2.RO.m{2} => 
               assoc UU2.lD{2} (m2c m CCA.sk{2}.`1 RO1E.FunRO.f{2}) = RO2.RO.m{1}.[m]))
     ));1: by wp;conseq />;[smt() | inline *;auto => />;smt(mem_empty get_setE)].
wp;call(:H1.bad,
     ={glob RO1E.FunRO, glob CCA, H1.bad} /\ uniq (unzip1 UU2.lD{2}) /\
    (* case a: all occuring badc accounted for *)
    (forall c, c \in UU2.lD{2} => !goodc c.`1 CCA.sk{2}.`1 RO1E.FunRO.f{2} => 
                                  c.`1 \in RF.m{1}) /\
    (* case a: all PRF inputs are occurring badcs *)
    (forall c, c \in RF.m{1} => assoc UU2.lD{2} c = RF.m{1}.[c]) /\
    (* case b: all occurring goodc accounted for *)
    (forall c, c \in UU2.lD{2} => goodc c.`1 CCA.sk{2}.`1 RO1E.FunRO.f{2} => 
                                  oc2m c.`1 CCA.sk{2}.`1 \in RO2.RO.m{1}) /\
    (* case b: all RO2 inputs with an occurrence  *)
    (forall m, m \in RO2.RO.m{2} => 
        (assoc UU2.lD{2} (m2c m CCA.sk{2}.`1 RO1E.FunRO.f{2}) <> None /\
            assoc UU2.lD{2} (m2c m CCA.sk{2}.`1 RO1E.FunRO.f{2}) = RO2.RO.m{2}.[m] /\ 
                 RO2.RO.m{1}.[m] = RO2.RO.m{2}.[m])) /\
    (* case c: RO2 inconsistency for entries not added by dec oracle *)
    (forall m, m \in RO2.RO.m{1} => m \notin RO2.RO.m{2} => 
               assoc UU2.lD{2} (m2c m CCA.sk{2}.`1 RO1E.FunRO.f{2}) = RO2.RO.m{1}.[m]),={H1.bad}).
+ proc;sp;if;1,3: by auto.
  inline *;sp;if{2}.
  (* repeat ciphertext *)
  + if{1}; last  by auto => />;smt(assoc_none).
    (* badc *) 
    rcondf {1} 2; 1: by auto => />; smt(assoc_none).
    by auto => />;smt(assoc_none).
  (* new ciphertext *)
  if{1}.
  (* badc *) 
  + rcondt {1} 2; 1: by auto => />; smt(assoc_none).
    by auto => />;smt(get_setE assoc_none assoc_cons mapP).
  (* good c *)
  + rcondt {1} 5; 1: by auto => />; smt(assoc_none).
    by auto => />;smt(get_setE assoc_none assoc_cons mapP).
+ move => *;proc;inline *;auto => />; 
  sp;if{1};2:by auto => /> /#.
  sp;if{1}; 2: by auto => />  *;smt(dkey_ll). 
  by sp;if{1};auto => />  *;smt(dkey_ll). 
+ by move => *;proc;inline *;conseq />;islossless.
+ by proc;inline*;auto => />.
+ by move => *;proc;inline *;conseq />;islossless.
+ by move => *;proc;inline *;conseq />;islossless.
+ proc;inline *. 
  swap {1} 3 -2; swap {2} 7 -6;seq 1 1 : (#pre /\ ={k}); 1: by auto.
  sp 2 6;if{2};last by auto => /#.
  by if{1}; auto => />;smt(get_setE assoc_none assoc_cons mapP).
+ by move => *;proc;inline *;auto => />;smt(dkey_ll). 
+ by move => *;proc;inline *;auto => />;smt(dkey_ll). 
+ by auto => /> /#. 
qed.

lemma bound_bad &m :
  Pr[ Gm2(H2,UU2,A).main() @ &m : H1.bad ] <=
    Pr[PKEROM.Correctness_Adv(RO1E.FunRO, TT, BUUC(A)).main() @ &m : res].
byequiv => //.
proc;inline*;wp;rnd{1};wp.
conseq(: _ ==> (H2.merr{2} <> None <=> H1.bad{1}) /\
               (H1.bad{1} => 
               dec sk{2}.`2 (enc (FunRO.f{2} (oget H2.merr{2})) pk{2} (oget H2.merr{2})) <> H2.merr{2} ));1 :smt().
call(: ={glob H1, glob H2, glob RF, glob RO1E.FunRO, glob RO2.RO, glob CCA, glob UU2} /\ (H2.merr{2} <> None <=> H1.bad{1}) /\
               (H1.bad{1} => 
               dec CCA.sk{2}.`1.`2 (enc (FunRO.f{2} (oget H2.merr{2})) CCA.sk.`1.`1{2} (oget H2.merr{2})) <> H2.merr{2} )).
+ proc;inline *; conseq />.
  sp;if;1,3: by auto => /> /#.
  sp;if;1,3: by auto => /> /#.
  by auto => /> /#.
+ proc;inline *; conseq />.
  by auto => /> /#.
+ proc;inline *; conseq />.
  by auto => /> /#. 
swap {1} 4 -3.
by auto => /> /#. 
qed.


local lemma G2_G3 &m :
  (forall (H0 <: POracle_x2{-A} ) (O <: CCA_ORC{ -A} ),
  islossless O.dec => islossless H0.get1 => 
  islossless H0.get2 => islossless A(H0, O).guess) =>

  `| Pr[ Gm2(H2,UU2,A).main() @ &m : res] - 
       Pr[ Gm3(H2,UU2,A).main() @ &m : res] |
     <= Pr[ Gm3(H2,UU2,A).main() @ &m : H2.invert ].
proof. 
move => A_ll.
byequiv : (H2.invert)  => //.
proc.
inline *.
rcondt{1} 30; 1: by auto => />;smt(mem_empty).
rcondf{1} 30; 1: by auto => />;smt().
swap{1} 12 -11;swap {1} 29 -27.
swap{2} [12..13] -11.
seq 2 2 : (={glob A,k1} /\ k0{1} = k2{2}); 1: by auto.
seq 32 21 : (={glob A,k1,pk,b,cm} /\ !H2.invert{2} /\ ck0{1}.`1 = cm {2} /\
      CCA.cstar{2} = Some(m2c H2.mtgt{2} CCA.sk{2}.`1 RO1E.FunRO.f{2})  /\
      ={CCA.sk,CCA.cstar, H2.invert, H2.mtgt, H1.bad, H2.merr, 
      H2.invert, RO1E.FunRO.f, UU2.lD} /\ 
      fdom RO2.RO.m{1} = fdom RO2.RO.m{2} /\ k0{1} = k2{2} /\  
       ck0{1} = (cm{2},k2{2}) /\  H2.mtgt{2} \in RO2.RO.m{2} /\
       (forall m, m <> H2.mtgt{2} => RO2.RO.m{1}.[m] = RO2.RO.m{2}.[m]) /\
     (!H1.bad{2} <=> 
                   Some H2.mtgt{2} = dec  CCA.sk{2}.`1.`2 (oget CCA.cstar{2})));
  1: by auto => />; smt(mem_empty get_setE fdom_set).

case (H1.bad{1}). print c2m.
rnd;wp;call(:H1.bad,false,CCA.cstar{2} <> None /\ 
                Some H2.mtgt{2} <> dec  CCA.sk{2}.`1.`2 (oget CCA.cstar{2}) /\ 
                ={H1.bad,H2.invert,H2.mtgt, CCA.sk,CCA.cstar} /\ H1.bad{1}).
+ by auto => />. 
+ by move => *;auto => />;islossless.
+ by move => *;auto => />;islossless.
+ by move => *;auto => />. 
+ by move => *;auto => />;islossless.
+ by move => *;auto => />;islossless.
+ by move => *;auto => />;islossless.
+ by move => *;proc;auto => />;smt(dkey_ll).
+ by move => *;proc;auto => />;smt(dkey_ll).
by auto => /> /#.  

rnd;wp;call(: H2.invert, 
      CCA.cstar{2} = Some(m2c H2.mtgt{2} CCA.sk{2}.`1 RO1E.FunRO.f{2})  /\ 
     ={CCA.sk,CCA.cstar, H2.mtgt, H2.invert, H1.bad, H2.merr, H2.invert, RO1E.FunRO.f, UU2.lD} /\ 
      fdom RO2.RO.m{1} = fdom RO2.RO.m{2} /\ Some H2.mtgt{2} = dec  CCA.sk{2}.`1.`2 (oget CCA.cstar{2}) /\
       H2.mtgt{2} \in RO2.RO.m{2} /\
         (forall m, m <> H2.mtgt{2} => RO2.RO.m{1}.[m] = RO2.RO.m{2}.[m]),
          ={H2.invert}); last by auto => />;smt(get_setE mem_empty). 
+ proc;sp;if;1:by auto.
  inline {1} 1;inline {2} 1.
  sp;if;by auto => />;smt(assoc_cons). 
  by auto => />.
+ move => *; proc.
  sp;if;2: by auto => />.
  inline 1.
  sp;if; 1: by auto => />.
  by auto => />; smt(dkey_ll).
+ move => *; proc.
  sp;if;2: by auto => />.
  inline 1.
  sp;if; 1: by auto => />.
  by auto => />; smt(dkey_ll).
+ by proc;auto.
+ by move => *;proc;auto.
+ by move => *; proc;auto.
+ by proc;auto => />;smt(fdomP fdom_set get_setE). 
+ by move => *;proc;auto => />; smt(dkey_ll). 
+ by move => *;proc;auto => />; smt(dkey_ll). 
by smt().
qed.

(* WE NEED ANOTHER CORRECTNESS HOP TO SAY THAT 
   `| Pr[PKEROM.OW_PCVA(RO1E.FunRO, TT, BUUOW(A)).main() @ &m : res] -
      Pr[PKEROM.OW_PCVA(RO1E.FunRO, TT, BUUOW(A)).main() @ &m : res /\ !bad] <= 
      Correctness bound 

*)


lemma bound_invert &m :
  Pr[ Gm3(H2,UU2,A).main() @ &m : H2.invert ] <=
    Pr[PKEROM.OW_PCVA(RO1E.FunRO, TT, BUUOW(A)).main() @ &m : res].
byequiv => //.
proc;inline*;wp.

wp;rnd{1};wp.

conseq(: H2.mtgt{1} = m{2} /\ pk{2} = pk1{2} /\
         enc (RO1E.FunRO.f{2} m{2}) PKEROM.OW_PCVA.sk{2}.`1 m{2} = PKEROM.OW_PCVA.cc{2} /\ 
  (H2.invert{1} =>
     (dec PKEROM.OW_PCVA.sk{2}.`2 PKEROM.OW_PCVA.cc{2} = Some m{2} /\
     m{2} = (oget
         ((FO_TT.find (fun (m0_0 : plaintext) (_ : key) => enc (FunRO.f{2} m0_0) CCA.sk{2}.`1.`1 m0_0 = oget CCA.cstar{2})
             RO2.RO.m{2}))%FO_TT).`1))); 1: by auto => /> /#. 

swap {1} 15 -4.
seq 23 26 : (={glob A,cm,k1,k2,RO1E.FunRO.f, pk,UU2.lD,CCA.cstar,RF.m, H2.mpre} /\ 
        H2.mtgt{1} = m{2} /\ pk{1} = pk1{2} /\ CCA.sk{1}.`1.`1 = pk{2} /\
        CCA.sk{1}.`1.`2 = PKEROM.OW_PCVA.sk{2}.`2 /\ 
        b{1} = b0{2} /\ H2.mpre{1} = None /\ !H2.invert{1} /\ CCA.cstar{1} =Some cm{2} /\
        CCA.sk{1}.`1.`1 = CCA.sk{2}.`1.`1 /\ CCA.sk{1}.`1.`1 = PKEROM.OW_PCVA.sk{2}.`1 /\ 
        (forall m0, m0<>m{2} => RO2.RO.m{1}.[m0] = RO2.RO.m{2}.[m0]) /\ 
         CCA.cstar{1} <> None /\ PKEROM.OW_PCVA.cc{2} = oget CCA.cstar{1} /\  
         enc (FunRO.f{2} m{2}) PKEROM.OW_PCVA.sk{2}.`1 m{2} = oget CCA.cstar{1}); 
   1: by auto => />;smt(get_setE).

exists*m{2}; elim * => _m2.

call(: 

={RO1E.FunRO.f, UU2.lD,CCA.cstar,RF.m} /\ H2.mtgt{1} = _m2 /\
      CCA.sk{1}.`1.`2 = PKEROM.OW_PCVA.sk{2}.`2 /\
        CCA.sk{1}.`1.`1 = CCA.sk{2}.`1.`1 /\ CCA.sk{1}.`1.`1 = PKEROM.OW_PCVA.sk{2}.`1 /\ 
        (forall m0, m0<>H2.mtgt{1} => RO2.RO.m{1}.[m0] = RO2.RO.m{2}.[m0]) /\ 
         CCA.cstar{1} <> None /\ PKEROM.OW_PCVA.cc{2} = oget CCA.cstar{1} /\  
         enc (FunRO.f{2} H2.mtgt{1}) PKEROM.OW_PCVA.sk{2}.`1 H2.mtgt{1} = oget CCA.cstar{1} /\

(H2.invert{1} =>
     (dec PKEROM.OW_PCVA.sk{2}.`2 PKEROM.OW_PCVA.cc{2} = Some H2.mtgt{1} /\
     H2.mtgt{1} = (oget
         ((FO_TT.find (fun (m0_0 : plaintext) (_ : key) => enc (FunRO.f{2} m0_0) CCA.sk{2}.`1.`1 m0_0 = oget CCA.cstar{2})
             RO2.RO.m{2}))%FO_TT).`1))

); last by auto.

+ proc;inline *;sp;if;1,3:by auto => />.
  sp;if;by auto => />.
+ by proc;inline *;auto.
+ proc.
  case (m{2} <> _m2). 
  + case (m{1} \notin RO2.RO.m{1}).
    rcondt{1} 8;1: by auto.
    rcondt{2} 8;1: by auto;smt(memE).
    auto => /> &1 &2 *; do split. 
     move => *; do split. 
     move => *; do split. smt(get_setE). smt(get_setE).
     move => *; do split. smt(). 
     + have : enc (RO1E.FunRO.f{2} m{2}) CCA.sk{2}.`1.`1 m{2} <> oget CCA.cstar{2}.
       smt. 
   auto => /> &1 &2 *; split. 

  move => *;do split. 
  move => *;do split. 
  move => *;do split. 
  move => *;do split. smt(@SmtMap).  smt(@SmtMap).    
move =>H;do split;1: by smt(). 
  have HH : (((m{2} = _m2 && dec CCA.sk{1}.`1.`2 (oget CCA.cstar{2}) = Some _m2))\/(H2.invert{1})). smt(). elim HH. 
 move =>[#] ??.   
  
  move => diff; move : H; rewrite diff /=. 
  case(dec CCA.sk{1}.`1.`2 (oget CCA.cstar{2}) <> Some _m2); 1: by smt().
  move => /= *. by smt(). 
  case (m{2} = _m2);last first. 
  + move => *. rewrite get_setE /=. by smt(@SmtMap). 
  move => diff; move : H; rewrite diff /=. 
  case(dec CCA.sk{1}.`1.`2 (oget CCA.cstar{2}) <> Some _m2); 1: by smt().
  move => /= *. by smt().


 last by  smt(@SmtMap).  
qed.


end section.

section.

declare module A <: PKEROM.PCVA_ADV. 

lemma tt_conclusion_eager &m: 
  (*   (forall (H <: PKEROM.POracle{-A} ) (O <: PKEROM.VA_ORC{-A} ),
       islossless O.cvo => islossless O.pco => islossless H.get => islossless A(H, O).find) => *)
    Pr[PKEROM.OW_PCVA(PKEROM.RO.RO, TT, A).main() @ &m : res]  =
       Pr[PKEROM.OW_PCVA(RO1E.FunRO, TT, A).main() @ &m : res].
admitted. (* to do *)

end section.

