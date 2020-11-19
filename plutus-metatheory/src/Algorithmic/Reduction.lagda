\begin{code}
module Algorithmic.Reduction where
\end{code}

## Imports

\begin{code}
open import Relation.Binary.PropositionalEquality hiding ([_]) renaming (subst to substEq)
open import Data.Empty
open import Data.Product renaming (_,_ to _,,_)
open import Data.Sum
open import Function hiding (_∋_)
open import Data.Integer using (_<?_;_+_;_-_;∣_∣;_≤?_;_≟_) renaming (_*_ to _**_)
open import Relation.Nullary
open import Relation.Nullary.Decidable
open import Data.Unit hiding (_≤_; _≤?_; _≟_)
open import Data.List hiding ([_]; take; drop)
open import Data.Bool using (Bool;true;false)
open import Data.Nat using (zero)
open import Data.Unit using (tt)


open import Type
import Type.RenamingSubstitution as T
open import Algorithmic
open import Algorithmic.RenamingSubstitution
open import Type.BetaNBE
open import Type.BetaNBE.Stability
open import Type.BetaNBE.RenamingSubstitution
open import Type.BetaNormal
open import Type.BetaNormal.Equality
open import Builtin
open import Builtin.Constant.Type
open import Builtin.Constant.Term Ctx⋆ Kind * _⊢Nf⋆_ con
open import Builtin.Signature
  Ctx⋆ Kind ∅ _,⋆_ * _∋⋆_ Z S _⊢Nf⋆_ (ne ∘ `) con
open import Utils
open import Data.Maybe using (just;from-just)
open import Data.String using (String)
\end{code}

## Values

\begin{code}

_<C+_ : ∀{Φ Φ'} → Ctx Φ → Ctx+ Φ' → Set
Γ <C+ (Γ' ,, A) = Γ ≤C' Γ'

_<C_ : ∀{Φ Φ'} → Ctx Φ → Ctx Φ' → Set
Γ <C Γ' = (Σ (_ ⊢Nf⋆ *) λ A → (Γ , A) ≤C Γ') ⊎ (Σ Kind λ K → (Γ ,⋆ K) ≤C Γ') 

<C2type : ∀{Φ Φ'}{Γ : Ctx Φ}{Γ' : Ctx Φ'} → Γ ≤C Γ' → Φ' ⊢Nf⋆ * → Φ ⊢Nf⋆ *
<C2type base      C = C
<C2type (skip⋆ p) C = <C2type p (Π C)
<C2type (skip {A = A} p)  C = <C2type p (A ⇒ C)

<C'2type : ∀{Φ Φ'}{Γ : Ctx Φ}{Γ' : Ctx Φ'} → Γ ≤C' Γ' → Φ' ⊢Nf⋆ * → Φ ⊢Nf⋆ *
<C'2type base      C = C
<C'2type (skip⋆ p) C = Π (<C'2type p C)
<C'2type (skip {A = A} p)  C = A ⇒ <C'2type p C

Ctx2type : ∀{Φ}(Γ : Ctx Φ) → Φ ⊢Nf⋆ * → ∅ ⊢Nf⋆ *
Ctx2type ∅        C = C
Ctx2type (Γ ,⋆ J) C = Ctx2type Γ (Π C)
Ctx2type (Γ , x)  C = Ctx2type Γ (x ⇒ C)

VTel : ∀ Δ → (σ : ∀ {K} → Δ ∋⋆ K → ∅ ⊢Nf⋆ K)(As : List (Δ ⊢Nf⋆ *))
  → Tel ∅ Δ σ As → Set

ITel : Builtin → ∀{Φ} → Ctx Φ → SubNf Φ ∅ → Set
data Value : {A : ∅ ⊢Nf⋆ *} → ∅ ⊢ A → Set where

  V-ƛ : {A B : ∅ ⊢Nf⋆ *}
    → (M : ∅ , A ⊢ B)
      ---------------------------
    → Value (ƛ M)

  V-Λ : ∀ {K}{B : ∅ ,⋆ K ⊢Nf⋆ *}
    → (M : ∅ ,⋆ K ⊢ B)
      ----------------
    → Value (Λ M)

  V-wrap : ∀{K}
   → {A : ∅ ⊢Nf⋆ (K ⇒ *) ⇒ K ⇒ *}
   → {B : ∅ ⊢Nf⋆ K}
   → {M : ∅ ⊢  _}
   → Value M
   → Value (wrap A B M)

  V-con : ∀{tcn : TyCon}
    → (cn : TermCon (con tcn))
    → Value (con cn)

  V-pbuiltin : (b : Builtin)
    → let Ψ ,, As ,, C = SIG b in
      (σ : SubNf Ψ ∅)
    → (A : Ψ ⊢Nf⋆ *)
    → (As' : List (Ψ ⊢Nf⋆ *))
    → (p : (A ∷ As') ≤L' As)
    → (ts : Tel ∅ Ψ σ As')
    → Value (pbuiltin b Ψ σ As' (inj₂ (refl ,, skip p)) ts)

  V-pbuiltin⋆ : (b : Builtin)
    → let Ψ ,, As ,, C = SIG b in
      ∀ Ψ' {K} → 
      (σ : SubNf Ψ' ∅)
    → (p : (Ψ' ,⋆ K) ≤C⋆' Ψ)
    → Value (pbuiltin b Ψ' σ [] (inj₁ (skip p ,, refl)) [])

  -- It is not necessary to index by the builtin, I could instead index
  -- by a context which is extracted from the builtin in the base case,
  -- but is it helpful to have it on the top level?

  V-I⇒ : ∀(b : Builtin){Φ Φ'}{Γ : Ctx Φ}{Δ : Ctx Φ'}{A : Φ' ⊢Nf⋆ *}{C : Φ ⊢Nf⋆ *}
    → let Ψ ,, Γ' ,, C' = ISIG b in
      (p : Ψ ≡ Φ)
    → (q : substEq Ctx p Γ' ≡ Γ)
    → (r : substEq (_⊢Nf⋆ *) p C' ≡ C)
    → (σ : SubNf Φ' ∅)
    → (p : (Δ , A) ≤C' Γ)
    → ITel b Δ σ
    → (t : ∅ ⊢ substNf σ (<C'2type (skip p) C))
    → Value t

  V-IΠ : ∀(b : Builtin){Φ Φ'}{Γ : Ctx Φ}{Δ : Ctx Φ'}{K}{C : Φ ⊢Nf⋆ *}
    → let Ψ ,, Γ' ,, C' = ISIG b in
      (p : Ψ ≡ Φ)
    → (q : substEq Ctx p Γ' ≡ Γ)
    → (r : substEq (_⊢Nf⋆ *) p C' ≡ C)
    → (σ : SubNf Φ' ∅) -- could try one at a time
      (p : (Δ ,⋆ K) ≤C' Γ)
    → ITel b Δ σ
    → (t : ∅ ⊢ substNf σ (<C'2type (skip⋆ p) C))
    → Value t

ITel b ∅       σ = ⊤
ITel b (Γ ,⋆ J) σ = ITel b Γ (σ ∘ S) × ∅ ⊢Nf⋆ J
ITel b (Γ , A) σ = ITel b Γ σ × Σ (∅ ⊢ substNf σ A) Value

deval : {A : ∅ ⊢Nf⋆ *}{u : ∅ ⊢ A} → Value u → ∅ ⊢ A
deval {u = u} _ = u
tval : {A : ∅ ⊢Nf⋆ *}{u : ∅ ⊢ A} → Value u → ∅ ⊢Nf⋆ *
tval {A = A} _ = A
\end{code}

\begin{code}
voidVal : Value (con unit)
voidVal = V-con unit
\end{code}

\begin{code}
data Error :  ∀ {Φ Γ} {A : Φ ⊢Nf⋆ *} → Γ ⊢ A → Set where
  -- an actual error term
  E-error : ∀{Φ Γ }{A : Φ ⊢Nf⋆ *} → Error {Γ = Γ} (error {Φ} A)
\end{code}

\begin{code}
VTel Δ σ []       []        = ⊤
VTel Δ σ (A ∷ As) (t ∷ tel) = Value t × VTel Δ σ As tel

convVal :  ∀ {A A' : ∅ ⊢Nf⋆ *}(q : A ≡ A')
  → ∀{t : ∅ ⊢ A} → Value t → Value (conv⊢ refl q t)
convVal refl v = v
\end{code}

\begin{code}
VERIFYSIG : ∀{Φ}{Γ : Ctx Φ} → Maybe Bool → Γ ⊢ con bool
VERIFYSIG (just false) = con (bool false)
VERIFYSIG (just true)  = con (bool true)
VERIFYSIG nothing      = error (con bool)

IBUILTIN : (b : Builtin)
    → let Φ ,, Γ ,, C = ISIG b in
      (σ : SubNf Φ ∅)
    → (tel : ITel b Γ σ)
      -----------------------------
    → ∅ ⊢ substNf σ C
IBUILTIN addInteger σ ((tt ,, .(con (integer i)) ,, V-con (integer i)) ,, .(con (integer i₁)) ,, V-con (integer i₁)) = con (integer (i + i₁))
IBUILTIN subtractInteger σ tel = error _
IBUILTIN multiplyInteger σ tel = error _
IBUILTIN divideInteger σ tel = error _
IBUILTIN quotientInteger σ tel = error _
IBUILTIN remainderInteger σ tel = error _
IBUILTIN modInteger σ tel = error _
IBUILTIN lessThanInteger σ tel = error _
IBUILTIN lessThanEqualsInteger σ tel = error _
IBUILTIN greaterThanInteger σ tel = error _
IBUILTIN greaterThanEqualsInteger σ tel = error _
IBUILTIN equalsInteger σ tel = error _
IBUILTIN concatenate σ tel = error _
IBUILTIN takeByteString σ tel = error _
IBUILTIN dropByteString σ tel = error _
IBUILTIN sha2-256 σ tel = error _
IBUILTIN sha3-256 σ tel = error _
IBUILTIN verifySignature σ tel = error _
IBUILTIN equalsByteString σ tel = error _
IBUILTIN ifThenElse σ tel = error _

IBUILTIN' : (b : Builtin)
    → let Φ ,, Γ ,, C = ISIG b in
      ∀{Φ'}{Γ' : Ctx Φ'}
    → (p : Φ ≡ Φ')
    → (q : substEq Ctx p Γ ≡ Γ')
      (σ : SubNf Φ' ∅)
    → (tel : ITel b Γ' σ)
    → (C' : Φ' ⊢Nf⋆ *)
    → (r : substEq (_⊢Nf⋆ *) p C ≡ C')
      -----------------------------
    → ∅ ⊢ substNf σ C'
    
IBUILTIN' b refl refl σ tel _ refl = IBUILTIN b σ tel

BUILTIN :
    (bn : Builtin)
    → let Δ ,, As ,, C = SIG bn in
      (σ : ∀ {K} → Δ ∋⋆ K → ∅ ⊢Nf⋆ K)
    → (tel : Tel ∅ Δ σ As)
    → (vtel : VTel Δ σ As tel)
      -----------------------------
    → ∅ ⊢ substNf σ C
BUILTIN addInteger _ (_ ∷ _ ∷ []) (V-con (integer i) ,, V-con (integer j) ,, tt) =
  con (integer (i + j))
BUILTIN subtractInteger _ (_ ∷ _ ∷ []) (V-con (integer i) ,, V-con (integer j) ,, tt) =
  con (integer (i - j))
BUILTIN multiplyInteger _ (_ ∷ _ ∷ []) (V-con (integer i) ,, V-con (integer j) ,, tt) =
  con (integer (i ** j))
BUILTIN divideInteger _ (_ ∷ _ ∷ []) (V-con (integer i) ,, V-con (integer j) ,, tt) =
  decIf (∣ j ∣ Data.Nat.≟ zero) (error _) (con (integer (div i j)))
BUILTIN quotientInteger _ (_ ∷ _ ∷ []) (V-con (integer i) ,, V-con (integer j) ,, tt) =
  decIf (∣ j ∣ Data.Nat.≟ zero) (error _) (con (integer (quot i j)))
BUILTIN remainderInteger _ (_ ∷ _ ∷ []) (V-con (integer i) ,, V-con (integer j) ,, tt) =
  decIf (∣ j ∣ Data.Nat.≟ zero) (error _) (con (integer (rem i j)))
BUILTIN modInteger _ (_ ∷ _ ∷ []) (V-con (integer i) ,, V-con (integer j) ,, tt) =
  decIf (∣ j ∣ Data.Nat.≟ zero) (error _) (con (integer (mod i j)))
BUILTIN lessThanInteger _ (_ ∷ _ ∷ []) (V-con (integer i) ,, V-con (integer j) ,, tt) =
  decIf (i <? j) (con (bool true)) (con (bool false))
BUILTIN lessThanEqualsInteger _ (_ ∷ _ ∷ []) (V-con (integer i) ,, V-con (integer j) ,, tt)
  = decIf (i ≤? j) (con (bool true)) (con (bool false))
BUILTIN greaterThanInteger _ (_ ∷ _ ∷ []) (V-con (integer i) ,, V-con (integer j) ,, tt) =
  decIf (i Builtin.Constant.Type.>? j) (con (bool true)) (con (bool false))
BUILTIN greaterThanEqualsInteger _ (_ ∷ _ ∷ []) (V-con (integer i) ,, V-con (integer j) ,, tt) =
  decIf (i Builtin.Constant.Type.≥? j) (con (bool true)) (con (bool false))
BUILTIN equalsInteger _ (_ ∷ _ ∷ []) (V-con (integer i) ,, V-con (integer j) ,, tt) =
  decIf (i ≟ j) (con (bool true)) (con (bool false))
BUILTIN concatenate _ (_ ∷ _ ∷ []) (V-con (bytestring b) ,, V-con (bytestring b') ,, tt) =
  con (bytestring (append b b'))
BUILTIN takeByteString _ (_ ∷ _ ∷ []) (V-con (integer i) ,, V-con (bytestring b) ,, tt) =
  con (bytestring (take i b))
BUILTIN dropByteString _ (_ ∷ _ ∷ []) (V-con (integer i) ,, V-con (bytestring b) ,, tt) =
  con (bytestring (drop i b))
BUILTIN sha2-256 _ (_ ∷ []) (V-con (bytestring b) ,, tt) =
  con (bytestring (SHA2-256 b))
BUILTIN sha3-256 _ (_ ∷ []) (V-con (bytestring b) ,, tt) =
  con (bytestring (SHA3-256 b))
BUILTIN verifySignature _ (_ ∷ _ ∷ _ ∷ []) (V-con (bytestring k) ,, V-con (bytestring d) ,, V-con (bytestring c) ,, tt) = VERIFYSIG (verifySig k d c)
BUILTIN equalsByteString _ (_ ∷ _ ∷ []) (V-con (bytestring b) ,, V-con (bytestring b') ,, tt) = con (bool (equals b b'))
BUILTIN ifThenElse _ (f ∷ (_ ∷ (_ ∷ _))) (_ ,, _ ,, V-con (bool false) ,, _) = f
BUILTIN ifThenElse _ (_ ∷ (t ∷ (_ ∷ _))) (_ ,, _ ,, V-con (bool true) ,, _) = t
\end{code}

## Intrinsically Type Preserving Reduction

\begin{code}
data Any {Δ}{σ : ∀ {K} → Δ ∋⋆ K → ∅ ⊢Nf⋆ K}(P : {A : ∅ ⊢Nf⋆ *} → ∅ ⊢ A → Set) : ∀{As} → (ts : Tel ∅ Δ σ As) → Set where
  here : ∀ {A}{As}{t}{ts} → P t → Any P {As = A ∷ As} (t ∷ ts)
  there : ∀ {A}{As}{t}{ts} → Value t → Any P ts → Any P {As = A ∷ As} (t ∷ ts)

data _—→T_ {Δ}{σ : ∀ {J} → Δ ∋⋆ J → ∅ ⊢Nf⋆ J} : {As : List (Δ ⊢Nf⋆ *)}
  → Tel ∅ Δ σ As → Tel ∅ Δ σ As → Set
  
infix 2 _—→_

data _—→_ : {A : ∅ ⊢Nf⋆ *} → (∅ ⊢ A) → (∅ ⊢ A) → Set where

  ξ-·₁ : {A B : ∅ ⊢Nf⋆ *} {L L′ : ∅ ⊢ A ⇒ B} {M : ∅ ⊢ A}
    → L —→ L′
      -----------------
    → L · M —→ L′ · M

  ξ-·₂ : {A B : ∅ ⊢Nf⋆ *}{V : ∅ ⊢ A ⇒ B} {M M′ : ∅ ⊢ A}
    → Value V
    → M —→ M′
      --------------
    → V · M —→ V · M′

  ξ-·⋆ : ∀ {K}{B : ∅ ,⋆ K ⊢Nf⋆ *}{L L' : ∅ ⊢ Π B}{A}
    → L —→ L'
      -----------------
    → L ·⋆ A —→ L' ·⋆ A

  β-ƛ : {A B : ∅ ⊢Nf⋆ *}{N : ∅ , A ⊢ B} {V : ∅ ⊢ A}
    → Value V
      -------------------
    → (ƛ N) · V —→ N [ V ]

  β-Λ : ∀ {K}{B : ∅ ,⋆ K ⊢Nf⋆ *}{N : ∅ ,⋆ K ⊢ B}{A}
      -------------------
    → (Λ N) ·⋆ A —→ N [ A ]⋆

  β-wrap : ∀{K}
    → {A : ∅ ⊢Nf⋆ (K ⇒ *) ⇒ K ⇒ *}
    → {B : ∅ ⊢Nf⋆ K}
    → {M : ∅ ⊢ _}
    → Value M
    → unwrap (wrap A B M) —→ M

  ξ-unwrap : ∀{K}
    → {A : ∅ ⊢Nf⋆ (K ⇒ *) ⇒ K ⇒ *}
    → {B : ∅ ⊢Nf⋆ K}
    → {M M' : ∅ ⊢ μ A B}
    → M —→ M'
    → unwrap M —→ unwrap M'
    
  ξ-wrap : ∀{K}
    → {A : ∅ ⊢Nf⋆ (K ⇒ *) ⇒ K ⇒ *}
    → {B : ∅ ⊢Nf⋆ K}
    → {M M' : ∅ ⊢ nf (embNf A · ƛ (μ (embNf (weakenNf A)) (` Z)) · embNf B)}
    → M —→ M'
    → wrap A B M —→ wrap A B M'

  β-builtin :
      (bn : Builtin)
    → let Δ ,, As ,, C = SIG bn in
      (σ : ∀ {K} → Δ ∋⋆ K → ∅ ⊢Nf⋆ K)
    → (tel : Tel ∅ Δ σ As)
    → (vtel : VTel Δ σ As tel)
      -----------------------------
    → builtin bn σ tel —→ BUILTIN bn σ tel vtel
    
  ξ-builtin : (bn : Builtin)
    → let Δ ,, As ,, C = SIG bn in
      (σ : ∀ {K} → Δ ∋⋆ K → ∅ ⊢Nf⋆ K)
    → {ts ts' : Tel ∅ Δ σ As}
    → ts —→T ts'
    → builtin bn σ ts —→ builtin bn σ ts'

  tick-pbuiltin : {b : Builtin}
      → let Ψ ,, As ,, C = SIG b in
        (σ : SubNf Ψ ∅)
      → {ts : Tel ∅ Ψ σ []}
      → pbuiltin b Ψ σ []  (inj₁ (base ,, refl)) ts
        —→ pbuiltin b Ψ σ [] (inj₂ (refl ,, []≤L' _)) ts

  β-pbuiltin : 
      (bn : Builtin)
    → let Δ ,, As ,, C = SIG bn in
      (σ : SubNf Δ ∅)
    → (ts : Tel ∅ Δ σ As)
    → (vts : VTel Δ σ As ts)
      -----------------------------
    → pbuiltin bn _ σ _ (inj₂ (refl ,, base)) ts —→ BUILTIN bn σ ts vts
    
  ξ-pbuiltin : (bn : Builtin)
    → let Δ ,, As ,, C = SIG bn in
      (σ : SubNf Δ ∅)
    → {ts ts' : Tel ∅ Δ σ As}
    → ts —→T ts'
    → pbuiltin bn _ σ _ (inj₂ (refl ,, base)) ts —→ pbuiltin bn _ σ _ (inj₂ (refl ,, base)) ts'

  sat⋆ : (b : Builtin)
    → let Δ ,, As ,, C = SIG b in
      ∀ Ψ K
    → (σ : SubNf Ψ ∅)
    → (A : ∅ ⊢Nf⋆ K)
    → (p : (Ψ ,⋆ K) ≤C⋆' Δ)
    → pbuiltin b Ψ σ [] (inj₁ (skip p ,, refl)) [] ·⋆ A
      —→ conv⊢ refl
               (substNf-cons-[]Nf
                 (abstractTy Δ (Ψ ,⋆ _) p (abstractTm Δ As [] ([]≤L' As) C)))
               (pbuiltin b (Ψ ,⋆ K) (substNf-cons σ A) [] (inj₁ (p ,, refl)) [])

  sat : (b : Builtin)
    → let Δ ,, As ,, C = SIG b in
      (σ : SubNf Δ ∅)
    → (As' : List (Δ ⊢Nf⋆ *))
    → (ts : Tel ∅ Δ σ As')
    → ∀ A
    → ∀ t
    → (p : (A ∷ As') ≤L' As)
    → Value t
    → pbuiltin b Δ σ As' (inj₂ (refl ,, skip p)) ts · t
      —→ pbuiltin b Δ σ (A ∷ As') (inj₂ (refl ,, p)) (t ∷ ts)


  E-·₂ : {A B : ∅ ⊢Nf⋆ *} {L : ∅ ⊢ A ⇒ B}
    → Value L
    → L · error A —→ error B
  E-·₁ : {A B : ∅ ⊢Nf⋆ *}{M : ∅ ⊢ A}
    → error (A ⇒ B) · M —→ error B
  E-·⋆ : ∀{K}{B : ∅ ,⋆ K ⊢Nf⋆ *}{A : ∅ ⊢Nf⋆ K}
    → error (Π B) ·⋆ A —→ error (B [ A ]Nf)
  E-unwrap : ∀{K}
    → {A : ∅ ⊢Nf⋆ (K ⇒ *) ⇒ K ⇒ *}
    → {B : ∅ ⊢Nf⋆ K}
    → unwrap (error (μ A B))
        —→ error (nf (embNf A · ƛ (μ (embNf (weakenNf A)) (` Z)) · embNf B))
  E-wrap : ∀{K}
    → {A : ∅ ⊢Nf⋆ (K ⇒ *) ⇒ K ⇒ *}
    → {B : ∅ ⊢Nf⋆ K}
    → wrap A B (error _) —→ error (μ A B) 
  E-builtin : (bn : Builtin)
    → let Δ ,, As ,, C = SIG bn in
      (σ : ∀ {K} → Δ ∋⋆ K → ∅ ⊢Nf⋆ K)
    → (ts : Tel ∅ Δ σ As)
    → Any Error ts
    → builtin bn σ ts —→ error (substNf σ C)

  E-pbuiltin : (b :  Builtin)
    → let Ψ ,, As ,, C = SIG b in
      (σ : SubNf Ψ ∅)
    → (ts : Tel ∅ Ψ σ As)
    → Any Error ts
    → pbuiltin b Ψ σ As (inj₂ (refl ,, base)) ts —→ error (abstractArg As As (inj₂ (refl ,, base)) C σ)

  β-sbuiltin :
      (b : Builtin)
    → let Φ ,, Γ ,, C = ISIG b in
      ∀{Φ'}{Γ' : Ctx Φ'}{A : Φ' ⊢Nf⋆ *}
    → (σ : SubNf Φ' ∅)
    → (p : Φ ≡ Φ')
    → (q : substEq Ctx p Γ ≡  Γ' , A)
    → (C' : Φ' ⊢Nf⋆ *)
    → (r : substEq (_⊢Nf⋆ *) p C ≡ C')
    → (t : ∅ ⊢ substNf σ A ⇒ substNf σ C')
    → (u : ∅ ⊢ substNf σ A)
    → (tel : ITel b Γ' σ)
    → (v : Value u)
      -----------------------------
    → t · u —→ IBUILTIN' b p q σ (tel ,, u ,, v) C' r

  β-sbuiltin⋆ :
      (b : Builtin)
    → let Φ ,, Γ ,, C = ISIG b in
      ∀{Φ'}{Γ' : Ctx Φ'}{K}{A : ∅ ⊢Nf⋆ K}
    → (σ : SubNf Φ' ∅)
    → (p : Φ ≡ Φ' ,⋆ K)
    → (q : substEq Ctx p Γ ≡  (Γ' ,⋆ K))
    → (C' : Φ' ,⋆ K ⊢Nf⋆ *)
    → (r : substEq (_⊢Nf⋆ *) p C ≡ C')
    → (t : ∅ ⊢ substNf σ (Π C'))
    → (tel : ITel b Γ' σ)
      -----------------------------
    → t ·⋆ A —→ conv⊢ refl (substNf-cons-[]Nf C') (IBUILTIN' b p q (substNf-cons σ A) (tel ,, A) C' r) 


data _—→T_ {Δ}{σ} where
  here  : ∀{A}{As}{t t'}{ts : Tel ∅ Δ σ As}
    → t —→ t' → (_∷_ {A = A} t ts) —→T (t' ∷ ts)
  there : ∀{A As}{t}{ts ts' : Tel ∅ Δ σ As}
    → Value t → ts —→T ts' → (_∷_ {A = A} t ts) —→T (t ∷ ts')

\end{code}

\begin{code}
data _—↠_ : {A A' : ∅ ⊢Nf⋆ *} → ∅ ⊢ A → ∅ ⊢ A' → Set
  where

  refl—↠ : ∀{A}{M : ∅ ⊢ A}
      --------
    → M —↠ M

  trans—↠ : {A : ∅ ⊢Nf⋆ *}{M  M' M'' : ∅ ⊢ A}
    → M —→ M'
    → M' —↠ M''
      ---------
    → M —↠ M''


\end{code}

\begin{code}
data Progress {A : ∅ ⊢Nf⋆ *} (M : ∅ ⊢ A) : Set where
  step : ∀{N : ∅ ⊢ A}
    → M —→ N
      -------------
    → Progress M
  done :
      Value M
      ----------
    → Progress M

  error :
      Error M
      -------
    → Progress M
\end{code}

\begin{code}
data TelProgress
  {Δ}
  {σ : SubNf Δ ∅}
  {As : List (Δ ⊢Nf⋆ *)}
  (ts : Tel ∅ Δ σ As)
  : Set where
  done : VTel Δ σ As ts → TelProgress ts
  step : {ts' : Tel ∅ Δ σ As}
    → ts —→T ts'
    → TelProgress ts
    
  error : Any Error ts → TelProgress ts
\end{code}

\begin{code}
progress-·V :  {A B : ∅ ⊢Nf⋆ *}
  → {t : ∅ ⊢ A ⇒ B} → Value t
  → {u : ∅ ⊢ A} → Progress u
  → Progress (t · u)
progress-·V v       (step q)        = step (ξ-·₂ v q)
progress-·V v       (error E-error) = step (E-·₂ v)
progress-·V (V-ƛ t) (done w)        = step (β-ƛ w)
progress-·V (V-pbuiltin b σ A As' p ts) (done v) =
  step (sat b σ As' ts A (deval v) p v)
progress-·V (V-I⇒ b p q r σ base vs t) (done v) = step (β-sbuiltin b σ p q _ r t (deval v) vs v)
-- ^ we're done, call BUILTIN
progress-·V (V-I⇒ b p' q r σ (skip⋆ p) vs t) (done v) = done (V-IΠ b p' q r σ p (vs ,, deval v ,, v) (t · deval v))
progress-·V (V-I⇒ b p' q r σ (skip p)  vs t) (done v) = done (V-I⇒ b p' q r σ p (vs ,, deval v ,, v) (t · deval v))

progress-· :  {A B : ∅ ⊢Nf⋆ *}
  → {t : ∅ ⊢ A ⇒ B} → Progress t
  → {u : ∅ ⊢ A} → Progress u
  → Progress (t · u)
progress-· (step p)  q = step (ξ-·₁ p)
progress-· (done v)  q = progress-·V v q
progress-· (error E-error) q = step E-·₁

val-lem : ∀{A A'}{t : ∅ ⊢ A}(p : A ≡ A') → Value (conv⊢ refl p t) → Value t
val-lem refl v = v

Πlem : ∀{K K'}{Φ Φ'}{Δ : Ctx Φ'}{Γ : Ctx Φ}(p : ((Δ ,⋆ K) ,⋆ K') ≤C' Γ)
  (A : ∅ ⊢Nf⋆ K)(C : Φ ⊢Nf⋆ *)(σ : SubNf Φ' ∅)
  → (Π
       (eval
        (T.subst (T.exts (T.exts (λ x → embNf (σ x))))
         (embNf (<C'2type p C)))
        (exte (exte (idEnv ∅))))
       [ A ]Nf)
      ≡ substNf (substNf-cons σ A) (Π (<C'2type p C))
Πlem p A C σ = sym (substNf-cons-[]Nf (Π (<C'2type p C)))


⇒lem : ∀{K}{A : ∅ ⊢Nf⋆ K}{Φ Φ'}{Δ : Ctx Φ'}{Γ : Ctx Φ}{B : Φ' ,⋆ K ⊢Nf⋆ *}
       (p : ((Δ ,⋆ K) , B) ≤C' Γ)(σ : SubNf Φ' ∅)(C : Φ ⊢Nf⋆ *)
  → ((eval (T.subst (T.exts (λ x → embNf (σ x))) (embNf B))
        (exte (idEnv ∅))
        ⇒
        eval (T.subst (T.exts (λ x → embNf (σ x))) (embNf (<C'2type p C)))
        (exte (idEnv ∅)))
       [ A ]Nf)
      ≡ substNf (substNf-cons σ A) (B ⇒ <C'2type p C)
⇒lem {B = B} p σ C = sym (substNf-cons-[]Nf (B ⇒ <C'2type p C)) 
progress-·⋆ : ∀{K B}{t : ∅ ⊢ Π B} → Progress t → (A : ∅ ⊢Nf⋆ K)
  → Progress (t ·⋆ A)
progress-·⋆ (step p)        A = step (ξ-·⋆ p)
progress-·⋆ (done (V-Λ t))  A = step β-Λ
progress-·⋆ (error E-error) A = step E-·⋆
progress-·⋆ (done (V-pbuiltin⋆ b Ψ σ p)) A = step (sat⋆ b Ψ _ σ A p)
progress-·⋆ (done (V-IΠ b {C = C} p' q r σ (skip⋆ p) vs t)) A = done (val-lem (Πlem p A C σ) (V-IΠ b {C = C} p' q r (substNf-cons σ A) p (vs ,, A) (conv⊢ refl (Πlem p A C σ) (t ·⋆ A))) )
progress-·⋆ (done (V-IΠ b {C = C} p' q r σ (skip p) vs t))  A = done (val-lem (⇒lem p σ C) (V-I⇒ b p' q r (substNf-cons σ A) p (vs ,, A) (conv⊢ refl (⇒lem p σ C) (t ·⋆ A) )))
progress-·⋆ (done (V-IΠ b p q r σ base vs t)) A = step (β-sbuiltin⋆ b σ p q _ r t vs)
-- ^ it's the last one, call BUILTIN

progress-unwrap : ∀{K}{A}{B : ∅ ⊢Nf⋆ K}{t : ∅ ⊢ μ A B}
  → Progress t → Progress (unwrap t)
progress-unwrap (step q) = step (ξ-unwrap q)
progress-unwrap (done (V-wrap v)) = step (β-wrap v)
progress-unwrap {A = A} (error E-error) =
  step (E-unwrap {A = A})
-- this shouldn't be possible the only type V-I can take is either μ or ⇒

progress-builtin : ∀ bn
  (σ : SubNf (proj₁ (SIG bn)) ∅)
  (tel : Tel ∅ (proj₁ (SIG bn)) σ (proj₁ (proj₂ (SIG bn))))
  → TelProgress tel
  → Progress (builtin bn σ tel)
progress-builtin bn σ tel (done vtel)                       =
  step (β-builtin bn σ tel vtel)
progress-builtin bn σ tel (step p) = step (ξ-builtin bn σ p)
progress-builtin bn σ tel (error p) = step (E-builtin bn σ tel p)

progress-pbuiltin : ∀ bn
  (σ : SubNf (proj₁ (SIG bn)) ∅)
  (tel : Tel ∅ (proj₁ (SIG bn)) σ (proj₁ (proj₂ (SIG bn))))
  → TelProgress tel
  → Progress (pbuiltin bn _ σ _ (inj₂ (refl ,, base)) tel)
progress-pbuiltin bn σ tel (done vs) = step (β-pbuiltin bn σ tel vs)
progress-pbuiltin bn σ tel (step p)  = step (ξ-pbuiltin bn σ p)
progress-pbuiltin bn σ tel (error e) = step (E-pbuiltin bn σ tel e)

progress : {A : ∅ ⊢Nf⋆ *} → (M : ∅ ⊢ A) → Progress M

progressTelCons : ∀{Δ}
  → {σ : ∀ {K} → Δ ∋⋆ K → ∅ ⊢Nf⋆ K}
  → {A : Δ ⊢Nf⋆ *}
  → {t : ∅ ⊢ substNf σ A}
  → Progress t
  → {As : List (Δ ⊢Nf⋆ *)}
  → {tel : Tel  ∅ Δ σ As}
  → TelProgress tel
  → TelProgress {As = A ∷ As} (t ∷ tel)
progressTelCons (step p)  q           = step (here p)
progressTelCons (error p) q           = error (here p)
progressTelCons (done v)  (done vtel) = done (v ,, vtel)
progressTelCons (done v)  (step p)    = step (there v p)
progressTelCons (done v)  (error p)   = error (there v p)


progressTel : ∀{Δ}
  → {σ : SubNf Δ ∅}
  → {As : List (Δ ⊢Nf⋆ *)}
  → (tel : Tel ∅ Δ σ As)
  → TelProgress tel
progressTel {As = []}     []        = done tt
progressTel {As = A ∷ As} (t ∷ tel) =
  progressTelCons (progress t) (progressTel tel)

progress-wrap : ∀{K}
   → {A : ∅ ⊢Nf⋆ (K ⇒ *) ⇒ K ⇒ *}
   → {B : ∅ ⊢Nf⋆ K}
   → {M : ∅ ⊢ nf (embNf A · ƛ (μ (embNf (weakenNf A)) (` Z)) · embNf B)}
   → Progress M → Progress (wrap A B M)
progress-wrap (step p)        = step (ξ-wrap p)
progress-wrap (done v)        = done (V-wrap v)
progress-wrap (error E-error) = step E-wrap
progress (ƛ M)                = done (V-ƛ M)
progress (M · N)              = progress-· (progress M) (progress N)
progress (Λ M)                = done (V-Λ M)
progress (M ·⋆ A)             = progress-·⋆ (progress M) A
progress (wrap A B M) = progress-wrap (progress M)
progress (unwrap M)          = progress-unwrap (progress M)
progress (con c)              = done (V-con c)
progress (builtin bn σ ts)     = progress-builtin bn σ ts (progressTel ts)
progress (pbuiltin b .(proj₁ (SIG b)) σ .[] (inj₁ (base ,, refl)) ts) =
  step (tick-pbuiltin σ)
progress (pbuiltin b Ψ' σ As' (inj₁ (skip q ,, refl)) []) =
  done (V-pbuiltin⋆ b Ψ' σ q)
progress (pbuiltin b Ψ' σ _ (inj₂ (refl ,, base)) ts) =
  progress-pbuiltin b σ ts (progressTel ts)
progress (pbuiltin b Ψ' σ As' (inj₂ (refl ,, skip r)) ts) =
  done (V-pbuiltin b σ _ _ r ts)
  
-- these are a bit annoying, it would be nice to be able to look at
-- the signature instead and the decide what to do
progress (ibuiltin addInteger) = done (V-I⇒ addInteger {Γ = proj₁ (proj₂ (ISIG addInteger))}{Δ = ∅}{C = proj₂ (proj₂ (ISIG addInteger))} refl refl refl (λ()) (≤Cto≤C' (skip base)) tt (ibuiltin addInteger))
progress (ibuiltin subtractInteger) = done (V-I⇒ subtractInteger {Γ = proj₁ (proj₂ (ISIG subtractInteger))}{Δ = ∅}{C = proj₂ (proj₂ (ISIG subtractInteger))} refl refl refl (λ()) (≤Cto≤C' (skip base)) tt (ibuiltin subtractInteger))
progress (ibuiltin multiplyInteger) = done (V-I⇒ multiplyInteger {Γ = proj₁ (proj₂ (ISIG multiplyInteger))}{Δ = ∅}{C = proj₂ (proj₂ (ISIG multiplyInteger))} refl refl refl (λ()) (≤Cto≤C' (skip base)) tt (ibuiltin multiplyInteger))
progress (ibuiltin divideInteger) = done (V-I⇒ divideInteger {Γ = proj₁ (proj₂ (ISIG divideInteger))}{Δ = ∅}{C = proj₂ (proj₂ (ISIG divideInteger))} refl refl refl (λ()) (≤Cto≤C' (skip base)) tt (ibuiltin divideInteger))
progress (ibuiltin quotientInteger) = done (V-I⇒ quotientInteger {Γ = proj₁ (proj₂ (ISIG quotientInteger))}{Δ = ∅}{C = proj₂ (proj₂ (ISIG quotientInteger))} refl refl refl (λ()) (≤Cto≤C' (skip base)) tt (ibuiltin quotientInteger))
progress (ibuiltin remainderInteger) = done (V-I⇒ remainderInteger {Γ = proj₁ (proj₂ (ISIG remainderInteger))}{Δ = ∅}{C = proj₂ (proj₂ (ISIG remainderInteger))} refl refl refl (λ()) (≤Cto≤C' (skip base)) tt (ibuiltin remainderInteger))
progress (ibuiltin modInteger) = done (V-I⇒ modInteger {Γ = proj₁ (proj₂ (ISIG modInteger))}{Δ = ∅}{C = proj₂ (proj₂ (ISIG modInteger))} refl refl refl (λ()) (≤Cto≤C' (skip base)) tt (ibuiltin modInteger))
progress (ibuiltin lessThanInteger) = done (V-I⇒ lessThanInteger {Γ = proj₁ (proj₂ (ISIG lessThanInteger))}{Δ = ∅}{C = proj₂ (proj₂ (ISIG lessThanInteger))} refl refl refl (λ()) (≤Cto≤C' (skip base)) tt (ibuiltin lessThanInteger))
progress (ibuiltin lessThanEqualsInteger) = done (V-I⇒ lessThanEqualsInteger {Γ = proj₁ (proj₂ (ISIG lessThanEqualsInteger))}{Δ = ∅}{C = proj₂ (proj₂ (ISIG lessThanEqualsInteger))} refl refl refl (λ()) (≤Cto≤C' (skip base)) tt (ibuiltin lessThanEqualsInteger))
progress (ibuiltin greaterThanInteger) = done (V-I⇒ greaterThanInteger {Γ = proj₁ (proj₂ (ISIG greaterThanInteger))}{Δ = ∅}{C = proj₂ (proj₂ (ISIG greaterThanInteger))} refl refl refl (λ()) (≤Cto≤C' (skip base)) tt (ibuiltin greaterThanInteger))
progress (ibuiltin greaterThanEqualsInteger) = done (V-I⇒ greaterThanEqualsInteger {Γ = proj₁ (proj₂ (ISIG greaterThanEqualsInteger))}{Δ = ∅}{C = proj₂ (proj₂ (ISIG greaterThanEqualsInteger))} refl refl refl (λ()) (≤Cto≤C' (skip base)) tt (ibuiltin greaterThanEqualsInteger))
progress (ibuiltin equalsInteger) = done (V-I⇒ equalsInteger {Γ = proj₁ (proj₂ (ISIG equalsInteger))}{Δ = ∅}{C = proj₂ (proj₂ (ISIG equalsInteger))} refl refl refl (λ()) (≤Cto≤C' (skip base)) tt (ibuiltin equalsInteger))
progress (ibuiltin concatenate) = done (V-I⇒ concatenate {Γ = proj₁ (proj₂ (ISIG concatenate))}{Δ = ∅}{C = proj₂ (proj₂ (ISIG concatenate))} refl refl refl (λ()) (≤Cto≤C' (skip base)) tt (ibuiltin concatenate))
progress (ibuiltin takeByteString) = done (V-I⇒ takeByteString {Γ = proj₁ (proj₂ (ISIG takeByteString))}{Δ = ∅}{C = proj₂ (proj₂ (ISIG takeByteString))} refl refl refl (λ()) (≤Cto≤C' (skip base)) tt (ibuiltin takeByteString))
progress (ibuiltin dropByteString) = done (V-I⇒ dropByteString {Γ = proj₁ (proj₂ (ISIG dropByteString))}{Δ = ∅}{C = proj₂ (proj₂ (ISIG dropByteString))} refl refl refl (λ()) (≤Cto≤C' (skip base)) tt (ibuiltin dropByteString))
progress (ibuiltin sha2-256) = done (V-I⇒ sha2-256 {Γ = proj₁ (proj₂ (ISIG sha2-256))}{Δ = ∅}{C = proj₂ (proj₂ (ISIG sha2-256))} refl refl refl (λ()) base tt (ibuiltin sha2-256))
progress (ibuiltin sha3-256) = done (V-I⇒ sha3-256 {Γ = proj₁ (proj₂ (ISIG sha3-256))}{Δ = ∅}{C = proj₂ (proj₂ (ISIG sha3-256))} refl refl refl (λ()) base tt (ibuiltin sha3-256))
progress (ibuiltin verifySignature) = done (V-I⇒ verifySignature {Γ = proj₁ (proj₂ (ISIG verifySignature))}{Δ = ∅}{C = proj₂ (proj₂ (ISIG verifySignature))} refl refl refl (λ()) (≤Cto≤C' (skip (skip base))) tt (ibuiltin verifySignature))
progress (ibuiltin equalsByteString) = done (V-I⇒ equalsByteString {Γ = proj₁ (proj₂ (ISIG equalsByteString))}{Δ = ∅}{C = proj₂ (proj₂ (ISIG equalsByteString))} refl refl refl (λ()) (≤Cto≤C' (skip base)) tt (ibuiltin equalsByteString))
progress (ibuiltin ifThenElse) = done (V-IΠ ifThenElse {Γ = proj₁ (proj₂ (ISIG ifThenElse))}{C = proj₂ (proj₂ (ISIG ifThenElse))} refl refl refl (λ()) (≤Cto≤C' (skip (skip (skip base)))) tt (ibuiltin ifThenElse))
progress (error A)            = error E-error
{-
--

open import Data.Empty

-- progress is disjoint:


-- a value cannot make progress
val-red : ∀{∅ ∅}{σ : ∅ ⊢Nf⋆ *}{t : ∅ ⊢ σ} → Value t → ¬ (Σ (∅ ⊢ σ) (t —→_))
val-red (V-wrap p) (.(wrap _ _ _) ,, ξ-wrap q) = val-red p (_ ,, q)

valT-redT : ∀ {∅ ∅ Δ}{σ : ∀ {K} → Δ ∋⋆ K → ∅ ⊢Nf⋆ K}{As : List (Δ ⊢Nf⋆ *)}
  → {ts : Tel ∅ Δ σ As} → VTel ∅ Δ σ As ts → ¬ Σ (Tel ∅ Δ σ As) (ts —→T_)
valT-redT (v ,, vs) (.(_ ∷ _) ,, here p)    = val-red v (_ ,, p)
valT-redT (v ,, vs) (.(_ ∷ _) ,, there w p) = valT-redT vs (_ ,, p)

-- a value cannot be an error
val-err : ∀{∅ ∅}{σ : ∅ ⊢Nf⋆ *}{t : ∅ ⊢ σ} → Value t → ¬ (Error t)
val-err () E-error

valT-errT : ∀ {∅ ∅ Δ}{σ : ∀ {K} → Δ ∋⋆ K → ∅ ⊢Nf⋆ K}{As : List (Δ ⊢Nf⋆ *)}
  → {ts : Tel ∅ Δ σ As} → VTel ∅ Δ σ As ts → ¬ (Any Error ts)
valT-errT (v ,, vs) (here p)    = val-err v p
valT-errT (v ,, vs) (there w p) = valT-errT vs p

-- an error cannot make progress
red-err : ∀{∅ ∅}{σ : ∅ ⊢Nf⋆ *}{t : ∅ ⊢ σ} → Σ (∅ ⊢ σ) (t —→_) → ¬ (Error t)
red-err () E-error

redT-errT : ∀ {∅ ∅ Δ}{σ : ∀ {K} → Δ ∋⋆ K → ∅ ⊢Nf⋆ K}{As : List (Δ ⊢Nf⋆ *)}
  → {ts : Tel ∅ Δ σ As} → Σ (Tel ∅ Δ σ As) (ts —→T_) → ¬ (Any Error ts)
redT-errT (.(_ ∷ _) ,, here p)    (here q)    = red-err (_ ,, p) q
redT-errT (.(_ ∷ _) ,, there v p) (here q)    = val-err v q
redT-errT (.(_ ∷ _) ,, here p)    (there w q) = val-red w (_ ,, p)
redT-errT (.(_ ∷ _) ,, there v p) (there w q) = redT-errT (_ ,, p) q

-- values are unique for a term
valUniq : ∀ {∅ ∅} {A : ∅ ⊢Nf⋆ *}(t : ∅ ⊢ A) → (v v' : Value t) → v ≡ v'
valUniq .(ƛ _)         (V-ƛ _)    (V-ƛ _)     = refl
valUniq .(Λ _)         (V-Λ _)    (V-Λ _)     = refl
valUniq .(wrap _ _ _) (V-wrap v) (V-wrap v') = cong V-wrap (valUniq _ v v')
valUniq .(con cn)      (V-con cn) (V-con .cn) = refl
valUniq _ (V-pbuiltin⋆ _ _ _ _) (V-pbuiltin⋆ _ _ _ _) = refl
valUniq _ (V-pbuiltin _ _ _ _ _ _ ) (V-pbuiltin _ _ _ _ _ _ ) = refl


-- telescopes of values are unique for that telescope
vTelUniq : ∀ {∅} ∅ Δ → (σ : ∀ {K} → Δ ∋⋆ K → ∅ ⊢Nf⋆ K)(As : List (Δ ⊢Nf⋆ *))
  → (tel : Tel ∅ Δ σ As)
  → (vtel vtel' : VTel ∅ Δ σ As tel)
  → vtel ≡ vtel'
vTelUniq ∅ Δ σ [] [] vtel vtel' = refl
vTelUniq ∅ Δ σ (A ∷ As) (t ∷ tel) (v ,, vtel) (v' ,, vtel') =
  cong₂ _,,_ (valUniq t v v') (vTelUniq ∅ Δ σ As tel vtel vtel') 

-- exclusive or
_xor_ : Set → Set → Set
A xor B = (A ⊎ B) × ¬ (A × B)

infixr 2 _xor_

-- a term cannot make progress and be a value

notboth : {σ : ∅ ⊢Nf⋆ *}{t : ∅ ⊢ σ} → ¬ (Value t × Σ (∅ ⊢ σ) (t —→_))
notboth (v ,, p) = val-red v p

-- term cannot make progress and be error

notboth' : {σ : ∅ ⊢Nf⋆ *}{t : ∅ ⊢ σ} → ¬ (Σ (∅ ⊢ σ) (t —→_) × Error t)
notboth' (p ,, e) = red-err p e

-- armed with this, we can upgrade progress to an xor

progress-xor : {σ : ∅ ⊢Nf⋆ *}(t : ∅ ⊢ σ)
  → Value t xor (Σ (∅ ⊢ σ) (t —→_)) xor Error t
progress-xor t with progress _ t
progress-xor t | step p  = (inj₂ ((inj₁ (_ ,, p)) ,, λ{(p ,, e) → red-err p e})) ,, λ { (v ,, inj₁ p ,, q) → val-red v p ; (v ,, inj₂ e ,, q) → val-err v e}
progress-xor t | done v  = (inj₁ v) ,, (λ { (v' ,, inj₁ p ,, q) → val-red v p ; (v' ,, inj₂ e ,, q) → val-err v e})
progress-xor t | error e = (inj₂ ((inj₂ e) ,, (λ { (p ,, e) → red-err p e}))) ,, λ { (v ,, q) → val-err v e }
-- the reduction rules are deterministic
det : ∀{∅ ∅}{σ : ∅ ⊢Nf⋆ *}{t t' t'' : ∅ ⊢ σ}
  → (p : t —→ t')(q : t —→ t'') → t' ≡ t''
detT : ∀{∅}{∅}{Δ}{σ : ∀ {K} → Δ ∋⋆ K → ∅ ⊢Nf⋆ K}{As}{ts ts' ts'' : Tel ∅ Δ σ As}
    → (p : ts —→T ts')(q : ts —→T ts'') → ts' ≡ ts''

det (ξ-·₁ p) (ξ-·₁ q) = cong (_· _) (det p q)
det (ξ-·₁ p) (ξ-·₂ w q) = ⊥-elim (val-red w (_ ,, p))
det (ξ-·₂ v p) (ξ-·₁ q) = ⊥-elim (val-red v (_ ,, q))
det (ξ-·₂ v p) (ξ-·₂ w q) = cong (_ ·_) (det p q)
det (ξ-·₂ v p) (β-ƛ w) = ⊥-elim (val-red w (_ ,, p))
det (ξ-·⋆ p) (ξ-·⋆ q) = cong (_·⋆ _) (det p q)
det (β-ƛ v) (ξ-·₂ w q) = ⊥-elim (val-red v (_ ,, q))
det (β-ƛ v) (β-ƛ w) = refl
det β-Λ β-Λ = refl
det (β-wrap p) (β-wrap q) = refl
det (β-wrap p) (ξ-unwrap q) = ⊥-elim (val-red (V-wrap p) (_ ,, q))
det (ξ-unwrap p) (β-wrap q) = ⊥-elim (val-red (V-wrap q) (_ ,, p))
det (ξ-unwrap p) (ξ-unwrap q) = cong unwrap (det p q)
det (ξ-wrap p) (ξ-wrap q) = cong (wrap _ _) (det p q)
det (β-builtin bn σ ts vs) (β-builtin .bn .σ .ts ws) =
  cong (BUILTIN bn σ ts) (vTelUniq _ _ σ _ ts vs ws)
det (β-builtin bn σ ts vs) (ξ-builtin .bn .σ p) =
  ⊥-elim (valT-redT vs (_ ,, p))
det (ξ-builtin bn σ p) (β-builtin .bn .σ ts vs) =
  ⊥-elim (valT-redT vs (_ ,, p))
det (ξ-builtin bn σ p) (ξ-builtin .bn .σ p') = cong (builtin bn σ) (detT p p')
det (β-builtin _ _ _ vs) (E-builtin _ _ _ p) = ⊥-elim (valT-errT vs p)
det (ξ-builtin _ _ p) (E-builtin _ _ _ q) = ⊥-elim (redT-errT (_ ,, p) q)
det (E-builtin _ _ _ _) (E-builtin _ _ _ _) = refl
det (E-builtin bn σ ts p) (β-builtin .bn .σ .ts vs) = ⊥-elim (valT-errT vs p)
det (E-builtin bn σ ts p) (ξ-builtin .bn .σ q) = ⊥-elim (redT-errT (_ ,, q) p)
det E-·₁ (ξ-·₁ ())
det (E-·₂ v) (ξ-·₁ p) = ⊥-elim (val-red v (_ ,, p))
det (E-·₂ v) (E-·₂ w) = refl
det (E-·₂ ()) E-·₁
det (ξ-·₁ p) (E-·₂ v) = ⊥-elim (val-red v (_ ,, p))
det E-·₁ (E-·₂ ())
det E-·₁ E-·₁ = refl
det E-·⋆ E-·⋆ = refl
det E-unwrap E-unwrap = refl
det E-wrap E-wrap = refl
det (ξ-·₂ x p) (sat b σ As' ts A _ p₁ v) = ⊥-elim (val-red v (_ ,, p))
det (tick-pbuiltin σ) (tick-pbuiltin .σ) = refl
det (β-pbuiltin bn σ ts vts) (β-pbuiltin .bn .σ .ts vts') =
  cong (BUILTIN bn σ ts) (vTelUniq _ _ σ _ ts vts vts')
det (β-pbuiltin bn σ ts vts) (ξ-pbuiltin .bn .σ p) =
  ⊥-elim (valT-redT vts (_ ,, p))
det (β-pbuiltin bn σ ts vts) (E-pbuiltin .bn .σ .ts e) =
  ⊥-elim (valT-errT vts e)
det (ξ-pbuiltin bn σ p) (β-pbuiltin .bn .σ _ vts) =
  ⊥-elim (valT-redT vts (_ ,, p))
det (ξ-pbuiltin bn σ p) (ξ-pbuiltin .bn .σ q) =
  cong (pbuiltin bn _ σ _ _) (detT p q)
det (ξ-pbuiltin bn σ p) (E-pbuiltin .bn .σ _ e) = ⊥-elim (redT-errT (_ ,, p) e)
det (sat⋆ b Ψ K σ A p) (sat⋆ .b .Ψ .K .σ .A .p) = refl
det (sat b σ As' ts A t p _) (sat .b .σ .As' .ts .A .t .p _) = refl
det (E-pbuiltin b σ ts e) (β-pbuiltin .b .σ .ts vts) = ⊥-elim (valT-errT vts e)
det (E-pbuiltin b σ ts e) (ξ-pbuiltin .b .σ p) =
  ⊥-elim (redT-errT (_ ,, p) e)
det (E-pbuiltin b σ ts e) (E-pbuiltin .b .σ .ts e') = refl
det (sat _ _ _ _ _ _ _ v) (ξ-·₂ _ q) = ⊥-elim (val-red v (_ ,, q))

detT (here p)    (there w q) = ⊥-elim (val-red w (_ ,, p))
detT (there v p) (here q)    = ⊥-elim (val-red v (_ ,, q))
detT (there v p) (there w q) = cong (_ ∷_) (detT p q)
detT (here p) (here q) = cong (_∷ _) (det p q)
-- -}
