require import AllCore List Distr DBool PROM_Ext.
require (****) IRO PRP.

require LorR. 
clone import LorR as LorR' with
  type input <- unit.  

type pkey.
type skey.
type plaintext.
type ciphertext.

module type Scheme = {
  proc kg() : pkey * skey
  proc enc(pk:pkey, m:plaintext)  : ciphertext
  proc dec(sk:skey, c:ciphertext) : plaintext option
}.

module type Adversary = {
  proc choose(pk:pkey)     : plaintext * plaintext
  proc guess(c:ciphertext) : bool
}.

module CPA (S:Scheme, A:Adversary) = {
  proc main() : bool = {
    var pk : pkey;
    var sk : skey;
    var m0, m1 : plaintext;
    var c : ciphertext;
    var b, b' : bool;

    (pk, sk) <@ S.kg();
    (m0, m1) <@ A.choose(pk);
    b        <$ {0,1};
    c        <@ S.enc(pk, b ? m1 : m0);
    b'       <@ A.guess(c);
    return (b' = b);
  }
}.

module CPA_L (S:Scheme, A:Adversary) = {
  proc main() : bool = {
    var pk : pkey;
    var sk : skey;
    var m0, m1 : plaintext;
    var c : ciphertext;
    var b' : bool;

    (pk, sk) <@ S.kg();
    (m0, m1) <@ A.choose(pk);
    c        <@ S.enc(pk, m0);
    b'       <@ A.guess(c);
    return b';
  }
}.

module CPA_R (S:Scheme, A:Adversary) = {
  proc main() : bool = {
    var pk : pkey;
    var sk : skey;
    var m0, m1 : plaintext;
    var c : ciphertext;
    var b' : bool;

    (pk, sk) <@ S.kg();
    (m0, m1) <@ A.choose(pk);
    c        <@ S.enc(pk, m1);
    b'       <@ A.guess(c);
    return b';
  }
}.

section.

  declare module S <: Scheme.
  declare module A <: Adversary{-S}.

  lemma pr_CPA_LR &m: 
    islossless S.kg => islossless S.enc =>
    islossless A.choose => islossless A.guess => 
    `| Pr[CPA_L(S,A).main () @ &m : res] - Pr[CPA_R(S,A).main () @ &m : res] | =
     2%r * `| Pr[CPA(S,A).main() @ &m : res] - 1%r/2%r |.
  proof.
    move => kg_ll enc_ll choose_ll guess_ll.
    have -> : Pr[CPA(S, A).main() @ &m : res] = 
              Pr[RandomLR(CPA_R(S,A), CPA_L(S,A)).main() @ &m : res].
    + byequiv (_ : ={glob S, glob A} ==> ={res})=> //.
      proc.      
      swap{1} 3-2; seq 1 1 : (={glob S, glob A, b}); first by rnd.
      if{2}; inline *; wp; do 4! call (_: true); auto => /> /#.
    rewrite -(pr_AdvLR_AdvRndLR (CPA_R(S,A)) (CPA_L(S,A)) &m) 2:/#.
    byphoare => //; proc.
    by call guess_ll; call enc_ll; call choose_ll; call kg_ll.
  qed.

end section.

(*
** Based on lists. Several versions can be given as in RandOrcl.
** Also, oracle annotations could be used to provide different oracles during
** the choose and guess stages of the experiment.
*)
const qD : int.

axiom qD_pos : 0 < qD.

module type CCA_ORC = {
  proc dec(c:ciphertext) : plaintext option
}.

module type CCA_ADV (O:CCA_ORC) = {
  proc choose(pk:pkey)     : plaintext * plaintext {O.dec}
  proc guess(c:ciphertext) : bool {O.dec}
}.

module CCA (S:Scheme, A:CCA_ADV) = {
  var log : ciphertext list
  var cstar : ciphertext option
  var sk : skey

  module O = {
    proc dec(c:ciphertext) : plaintext option = {
      var m : plaintext option;

      if (size log < qD && (Some c <> cstar)) {
        log <- c :: log;
        m   <@ S.dec(sk, c);
      }
      else m <- None;
      return m;
    }
  }

  module A = A(O)

  proc main() : bool = {
    var pk : pkey;
    var m0, m1 : plaintext;
    var c : ciphertext;
    var b, b' : bool;

    log      <- [];
    cstar    <- None;
    (pk, sk) <@ S.kg();
    (m0, m1) <@ A.choose(pk);
    b        <$ {0,1};
    c        <@ S.enc(pk, b ? m1 : m0);
    cstar    <- Some c;
    b'       <@ A.guess(c);
    return (b' = b);
  }
}.

module Correctness (S:Scheme) = {
  proc main(m:plaintext) : bool = {
    var pk : pkey;
    var sk : skey;
    var c  : ciphertext;
    var m' : plaintext option;

    (pk, sk) <@ S.kg();
    c        <@ S.enc(pk, m);
    m'       <@ S.dec(sk, c);
    return (m' = Some m);
  }
}.

module type CAdversary = {
   proc find(pk : pkey, sk : skey) : plaintext 
}.

module CorrectnessAdv(S : Scheme, A : CAdversary) = {
  proc main() : bool = {
    var pk, sk, c, m, m';
    (pk,sk) <@ S.kg();
    m <@ A.find(pk,sk);
    c <@ S.enc(pk, m);
    m' <@ S.dec(sk,c);

    return m' = Some m;
  }
}.

(* Extensions to ROM *)

clone import FullRO as RO.

module type SchemeRO(H : ROpub) = {
  include Scheme
}.


module type AdversaryRO(H : ROpub) = {
  include Adversary
}.

module type CAdversaryRO(H : ROpub) = {
  include CAdversary
}.

module type CPAGame(S: Scheme, A : Adversary) = {
   proc main() : bool
}.

module CPAGameROM(G : CPAGame, S : SchemeRO, A : AdversaryRO, O : RO) = {
   module H = Pub(O)
   proc main() : bool = {
     var b;
     O.init();
     b <@ G(S(H),A(H)).main();
     return b;
   }
}.

module CPAROM = CPAGameROM(CPA).
module CPA_L_ROM = CPAGameROM(CPA_L).
module CPA_R_ROM = CPAGameROM(CPA_R).

module type CGame(S: Scheme, A : CAdversary) = {
   proc main() : bool
}.

module CGameROM(G : CGame, S : SchemeRO, A : CAdversaryRO, O : RO) = {
   module H = Pub(O)
   proc main() : bool = {
     var b;
     O.init();
     b <@ G(S(H),A(H)).main();
     return b;
   }
}.

module CorrectnessAdvROM = CGameROM(CorrectnessAdv).


(* Infinite RO *)

clone import IRO as InfRO.

module type IROpub = {
  include IRO [f]
}.

module type SchemeIRO(H : IROpub) = {
  include Scheme
}.


module type AdversaryIRO(H : IROpub) = {
  include Adversary
}.

module type CAdversaryIRO(H : IROpub) = {
  include CAdversary
}.

module IPub(O : IRO) : IROpub = {
  include O [f]
}.

module CPAGameIROM(G : CPAGame, S : SchemeIRO, A : AdversaryIRO, O : IRO) = {
   module H = IPub(O)
   proc main() : bool = {
     var b;
     O.init();
     b <@ G(S(H),A(H)).main();
     return b;
   }
}.

module CPAIROM = CPAGameIROM(CPA).
module CPA_L_IROM = CPAGameIROM(CPA_L).
module CPA_R_IROM = CPAGameIROM(CPA_R).


module CGameIROM(G : CGame, S : SchemeIRO, A : CAdversaryIRO, O : IRO) = {
   module H = IPub(O)
   proc main() : bool = {
     var b;
     O.init();
     b <@ G(S(H),A(H)).main();
     return b;
   }
}.

module CorrectnessAdvIROM = CGameIROM(CorrectnessAdv).

(* Perm Oracle *)

clone export PRP as PRPt
  rename
    [module type] "PRP" as "PRIMITIVE".

clone export StrongPRP as PRPSec.

clone export RP as Perm 
    rename
       [module] "RP" as "Perm".

module type PermPub = {
  include PRIMITIVE [f]
}.

module type SchemePerm(Pi : PermPub) = {
  include Scheme
}.


module type AdversaryPerm(H : PermPub) = {
  include Adversary
}.

module type CAdversaryPerm(H : PermPub) = {
  include CAdversary
}.

module PPub(O : PRIMITIVE) : PermPub = {
  include O [f]
}.

module CPAGamePerm(G : CPAGame, S : SchemePerm, A : AdversaryPerm, O : PRIMITIVE) = {
   module Pi = PPub(O)
   proc main() : bool = {
     var b;
     O.init();
     b <@ G(S(Pi),A(Pi)).main();
     return b;
   }
}.

module CPAPerm = CPAGamePerm(CPA).
module CPA_L_Perm = CPAGamePerm(CPA_L).
module CPA_R_Perm = CPAGamePerm(CPA_R).


module CGamePerm(G : CGame, S : SchemePerm, A : CAdversaryPerm, O : PRIMITIVE) = {
   module Pi = PPub(O)
   proc main() : bool = {
     var b;
     O.init();
     b <@ G(S(Pi),A(Pi)).main();
     return b;
   }
}.
