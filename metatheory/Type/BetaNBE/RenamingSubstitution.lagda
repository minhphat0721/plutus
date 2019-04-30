\begin{code}
module Type.BetaNBE.RenamingSubstitution where

open import Type
open import Type.Equality
open import Type.RenamingSubstitution
open import Type.BetaNormal
open import Type.BetaNBE
open import Type.BetaNBE.Soundness
open import Type.BetaNBE.Completeness
open import Type.BetaNBE.Stability

open import Relation.Binary.PropositionalEquality hiding (subst; [_])
open import Function
\end{code}

reify ∘ reflect preserves the neutral term

\begin{code}
reify-reflect : ∀{K Φ}(n : Φ ⊢NeN⋆ K) → reify (reflect n) ≡ ne n
reify-reflect {*}     n = refl
reify-reflect {K ⇒ J} n = refl
\end{code}

eval is closed under propositional equality for terms

\begin{code}
evalCRSubst : ∀{Φ Ψ K}{η η' : Env Φ Ψ}
  → EnvCR η η'
  → {t t' : Φ ⊢⋆ K}
  → t ≡ t'
  → CR K (eval t η) (eval t' η')
evalCRSubst p {t = t} refl = idext p t
\end{code}

\begin{code}
rename-nf : ∀{ϕ ψ K}(σ : Ren ϕ ψ)(A : ϕ ⊢⋆ K) →
  renameNf σ (nf A) ≡ nf (rename σ A)
rename-nf σ A = trans
  (rename-reify (idext idCR A) σ)
  (reifyCR
    (transCR
      (renameVal-eval A idCR σ)
      (transCR
        (idext (renameVal-reflect σ ∘ `) A)
        (symCR (rename-eval A idCR σ))  )))
\end{code}

\begin{code}
SubNf : Ctx⋆ → Ctx⋆ → Set
SubNf φ Ψ = ∀ {J} → φ ∋⋆ J → Ψ ⊢Nf⋆ J
\end{code}

Substitution for normal forms:
1. embed back into syntax;
2. perform substitution;
3. renormalize.

\begin{code}
substNf : ∀ {Φ Ψ}
  → SubNf Φ Ψ
    -------------------------
  → (∀ {J} → Φ ⊢Nf⋆ J → Ψ ⊢Nf⋆ J)
substNf ρ n = nf (subst (embNf ∘ ρ) (embNf n))
\end{code}

First monad law for substNf

\begin{code}
substNf-id : ∀ {Φ J}
  → (n : Φ ⊢Nf⋆ J)
  → substNf (ne ∘ `) n ≡ n
substNf-id n = trans (cong nf (subst-id (embNf n))) (stability n)
\end{code}

This version of the first monad law might be η compatible as it doesn't rely
on subst-id

\begin{code}
substNf-id' : ∀ {Φ J}
  → (n : Φ ⊢Nf⋆ J)
  → substNf (nf ∘ `) n ≡ n
substNf-id' n = trans
  (reifyCR
    (transCR
      (subst-eval (embNf n) idCR (embNf ∘ nf ∘ `))
      (idext
        (λ α → evalCRSubst idCR (cong embNf (stability (ne (` α)))))
        (embNf n))))
  (stability n)
\end{code}

Second monad law for substNf
This is often holds definitionally for substitution (e.g. subst) but not here.

\begin{code}
substNf-∋ : ∀ {Φ Ψ J}
  → (ρ : SubNf Φ Ψ)
  → (α : Φ ∋⋆ J)
  → substNf ρ (ne (` α)) ≡ ρ α
substNf-∋ ρ α = stability (ρ α) 
\end{code}



Two lemmas that aim to remove a superfluous additional normalisation
via stability

\begin{code}
substNf-nf : ∀ {Φ Ψ}
  → (σ : ∀ {J} → Φ ∋⋆ J → Ψ ⊢Nf⋆ J)
  → ∀ {J}
  → (t : Φ ⊢⋆ J)
    -------------------------------------------
  → nf (subst (embNf ∘ σ) t) ≡ substNf σ (nf t)
substNf-nf σ t = trans
  (reifyCR (subst-eval t idCR (embNf ∘ σ)))
  (trans
    (sym
      (reifyCR (fund (λ x → idext idCR (embNf (σ x))) (sym≡β (soundness t)))))
    (sym (reifyCR (subst-eval (embNf (nf t)) idCR (embNf ∘ σ)))))
\end{code}

Third Monad Law for substNf

\begin{code}
substNf-comp : ∀{Φ Ψ Θ}
  (g : SubNf Φ Ψ)
  (f : SubNf Ψ Θ)
  → ∀{J}(A : Φ ⊢Nf⋆ J)
    -----------------------------------------------
  → substNf (substNf f ∘ g) A ≡ substNf f (substNf g A)
substNf-comp g f A = trans
  (trans
    (trans
      (reifyCR
        (subst-eval
          (embNf A)
          idCR
          (embNf ∘ nf ∘ subst (embNf ∘ f) ∘ embNf ∘ g)))
      (trans (reifyCR
               (idext
                 (λ x → fund
                   idCR
                   (sym≡β (soundness (subst (embNf ∘ f) (embNf (g x))))))
                 (embNf A)))
             (sym
               (reifyCR
                 (subst-eval
                   (embNf A)
                   idCR
                   (subst (embNf ∘ f) ∘ embNf ∘ g))))))
  (cong nf (subst-comp (embNf A)))) (substNf-nf f (subst (embNf ∘ g) (embNf A)))
\end{code}

extending a normal substitution

\begin{code}
extsNf : ∀ {Φ Ψ}
  → SubNf Φ Ψ
    -------------------------------
  → ∀ {K} → SubNf (Φ ,⋆ K) (Ψ ,⋆ K)
extsNf σ Z      =  ne (` Z)
extsNf σ (S α)  =  weakenNf (σ α)
\end{code}

cons for normal substitutions

\begin{code}
substNf-cons : ∀{Φ Ψ}
  → (∀{K} → Φ ∋⋆ K → Ψ ⊢Nf⋆ K)
  → ∀{J}(A : Ψ ⊢Nf⋆ J)
  → (∀{K} → Φ ,⋆ J ∋⋆ K → Ψ ⊢Nf⋆ K)
substNf-cons σ A Z     = A
substNf-cons σ A (S x) = σ x
\end{code}

Substitution of one variable

\begin{code}
_[_]Nf : ∀ {Φ J K}
        → Φ ,⋆ K ⊢Nf⋆ J
        → Φ ⊢Nf⋆ K 
          ------
        → Φ ⊢Nf⋆ J
A [ B ]Nf = substNf (substNf-cons (ne ∘ `) B) A
\end{code}

Congruence lemma for subst
\begin{code}
substNf-cong : ∀ {Φ Ψ}
  → {f g : ∀{K} → Φ ∋⋆ K → Ψ ⊢Nf⋆ K}
  → (∀ {J}(x : Φ ∋⋆ J) → f x ≡ g x)
  → ∀{K}(A : Φ ⊢Nf⋆ K)
    -------------------------------
  → substNf f A ≡ substNf g A
substNf-cong p A =
 reifyCR (evalCRSubst idCR (subst-cong (cong embNf ∘ p) (embNf A)))
\end{code}

Pushing renaming through normal substitution

\begin{code}
renameNf-substNf : ∀{Φ Ψ Θ}
  → {g : ∀{K} → Φ ∋⋆ K → Ψ ⊢Nf⋆ K}
  → {f : Ren Ψ Θ}
  → ∀{J}(A : Φ ⊢Nf⋆ J)
   -----------------------------------------------------
  → substNf (renameNf f ∘ g) A ≡ renameNf f (substNf g A)
renameNf-substNf {g = g}{f} A = trans
  (reifyCR
    (transCR
      (transCR
        (subst-eval (embNf A) idCR (embNf ∘ renameNf f ∘ g))
        (transCR
          (idext
            (λ α → transCR
              (evalCRSubst idCR (rename-embNf f (g α)))
              (transCR
                (rename-eval (embNf (g α)) idCR f)
                (idext (symCR ∘ renameVal-reflect f ∘ `) (embNf (g α)))))
            (embNf A))
          (symCR (subst-eval (embNf A) (renCR f ∘ idCR) (embNf ∘ g)))))
      (symCR (renameVal-eval (subst (embNf ∘ g) (embNf A)) idCR f))))
  (sym (rename-reify (idext idCR (subst (embNf ∘ g) (embNf A))) f))
\end{code}

Pushing a substitution through a renaming

\begin{code}
substNf-renameNf : ∀{Φ Ψ Θ}
  → {g : Ren Φ Ψ}
  → {f : ∀{K} → Ψ ∋⋆ K → Θ ⊢Nf⋆ K}
  → ∀{J}(A : Φ ⊢Nf⋆ J)
    --------------------------------------
  → substNf (f ∘ g) A ≡ substNf f (renameNf g A)
substNf-renameNf {g = g}{f} A = reifyCR
  (transCR
    (subst-eval (embNf A) idCR (embNf ∘ f ∘ g))
    (transCR
      (transCR
        (symCR (rename-eval (embNf A) (λ α → idext idCR (embNf (f α))) g))
        (symCR
          (evalCRSubst (λ α → idext idCR (embNf (f α))) (rename-embNf g A))))
      (symCR (subst-eval (embNf (renameNf g A)) idCR (embNf ∘ f)))))
\end{code}

Pushing renaming through a one variable normal substitution

\begin{code}
rename[]Nf : ∀ {Φ Θ J K}
        → (ρ : Ren Φ Θ)
        → (t : Φ ,⋆ K ⊢Nf⋆ J)
        → (u : Φ ⊢Nf⋆ K )
          --------------------------------------------------------------
        → renameNf ρ (t [ u ]Nf) ≡ renameNf (ext ρ) t [ renameNf ρ u ]Nf
rename[]Nf ρ t u = trans
  (sym (renameNf-substNf {g = substNf-cons (ne ∘ `) u}{f = ρ} t))
  (trans
    (substNf-cong
      {f = renameNf ρ ∘ substNf-cons (ne ∘ `) u}
      {g = substNf-cons (ne ∘ `) (renameNf ρ u) ∘ ext ρ}
      (λ { Z → refl ; (S α) → refl})
      t)
    (substNf-renameNf {g = ext ρ}{f = substNf-cons (ne ∘ `) (renameNf ρ u)} t))
\end{code}

Pushing a normal substitution through a one place normal substitution

\begin{code}
subst[]Nf : ∀{Φ Ψ K J}
  → (ρ : ∀{K} → Φ ∋⋆ K → Ψ ⊢Nf⋆ K)
  → (A : Φ ⊢Nf⋆ K)
  → (B : Φ ,⋆ K ⊢Nf⋆ J)
    --------------------------------------------------------------
  → substNf ρ (B [ A ]Nf) ≡ substNf (extsNf ρ) B [ substNf ρ A ]Nf
subst[]Nf ρ A B = trans
  (sym (substNf-comp (substNf-cons (ne ∘ `) A) ρ B))
  (trans
    (substNf-cong
      {f = substNf ρ ∘ substNf-cons (ne ∘ `) A}
      {g = substNf (substNf-cons (ne ∘ `) (substNf ρ A)) ∘ extsNf ρ}
      (λ { Z     → sym (substNf-∋ (substNf-cons (ne ∘ `) (substNf ρ A)) Z) 
         ; (S α) → trans
              (trans (substNf-∋ ρ α) (sym (substNf-id (ρ α))))
              (substNf-renameNf
                {g = S}
                {f = substNf-cons (ne ∘ `) (substNf ρ A)}
                (ρ α))})
      B)
    (substNf-comp  (extsNf ρ) (substNf-cons (ne ∘ `) (substNf ρ A)) B))
\end{code}

Extending a normal environment and then embedding is the same as
embedding and then extending.

\begin{code}
substNf-lemma : ∀{Φ Ψ K J}
  (ρ : ∀{K} → Φ ∋⋆ K → Ψ ⊢Nf⋆ K)
  → (t : Φ ,⋆ K ⊢⋆ J)
  → subst (exts (embNf ∘ ρ)) t ≡ subst (embNf ∘ extsNf ρ) t
substNf-lemma ρ t =
  subst-cong (λ { Z → refl ; (S x) → sym (rename-embNf S (ρ x))}) t
\end{code}

Repair a mismatch between two different ways of extending an environment

\begin{code}
substNf-lemma' : ∀{Φ K J}
  → (B : Φ ,⋆ K ⊢⋆ J)
  → nf B ≡ reify (eval B ((renameVal S ∘ idEnv _) ,,⋆ fresh))
substNf-lemma' B = reifyCR
  (idext (λ { Z     → reflectCR refl
            ; (S x) → symCR (renameVal-reflect S (` x))}) B)
\end{code}

combining the above lemmas

note: there are several mismatches here, one due to two different ways
of extending a normal substitution and another due to two different
ways of extending an environment

\begin{code}
subst[]Nf' : ∀{Φ Ψ K J}
  → (ρ : ∀{K} → Φ ∋⋆ K → Ψ ⊢Nf⋆ K)
  → (A : Φ ⊢Nf⋆ K)
  → (B : Φ ,⋆ K ⊢Nf⋆ J)
  → substNf ρ (B [ A ]Nf)
    ≡
    (reify (eval (subst (exts (embNf ∘ ρ)) (embNf B))
                 ((renameVal S ∘ idEnv _) ,,⋆ fresh)))
    [ substNf ρ A ]Nf
subst[]Nf' ρ A B =
  trans (subst[]Nf ρ A B)
        (trans (cong (λ t → nf t [ substNf ρ A ]Nf)
                     (sym (substNf-lemma ρ (embNf B))))
               (cong (λ n → n [ substNf ρ A ]Nf)
                     (substNf-lemma' (subst (exts (embNf ∘ ρ)) (embNf B)))))
\end{code}

