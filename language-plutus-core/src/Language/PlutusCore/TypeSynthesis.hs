{-# LANGUAGE MonadComprehensions #-}
{-# LANGUAGE OverloadedStrings   #-}

module Language.PlutusCore.TypeSynthesis ( typecheckProgram
                                         , typecheckTerm
                                         , kindCheck
                                         , tyReduce
                                         , runTypeCheckM
                                         , TypeCheckM
                                         , BuiltinTable (..)
                                         , TypeError (..)
                                         , TypeCheckCfg (..)
                                         ) where

import           Control.Monad.Except
import           Control.Monad.Reader
import           Control.Monad.State.Class
import           Control.Monad.Trans.State      hiding (get, modify)
import qualified Data.IntMap                    as IM
import qualified Data.Map                       as M
import           Language.PlutusCore.Clone
import           Language.PlutusCore.Error
import           Language.PlutusCore.Lexer.Type
import           Language.PlutusCore.Name
import           Language.PlutusCore.Normalize
import           Language.PlutusCore.Quote
import           Language.PlutusCore.Type
import           Lens.Micro
import           PlutusPrelude

-- | A builtin table contains the kinds of builtin types and the types of
-- builtin names.
data BuiltinTable = BuiltinTable (M.Map TypeBuiltin (Kind ())) (M.Map BuiltinName (NormalizedType TyNameWithKind ()))

type TypeSt = IM.IntMap (Type TyNameWithKind ())

data TypeConfig = TypeConfig { _reduce   :: Bool -- ^ Whether we reduce type annotations
                             , _builtins :: BuiltinTable -- ^ Builtin types
                             }

data TypeCheckSt = TypeCheckSt { _uniqueLookup :: TypeSt
                               , _gas          :: Natural
                               }

data TypeCheckCfg = TypeCheckCfg { _cfgGas       :: Natural -- ^ Gas to be provided to the typechecker
                                 , _cfgNormalize :: Bool -- ^ Whether we should reduce type annotations
                                 }

uniqueLookup :: Lens' TypeCheckSt TypeSt
uniqueLookup f s = fmap (\x -> s { _uniqueLookup = x }) (f (_uniqueLookup s))

gas :: Lens' TypeCheckSt Natural
gas f s = fmap (\x -> s { _gas = x }) (f (_gas s))

-- | The type checking monad contains the 'BuiltinTable' and it lets us throw
-- 'TypeError's.
type TypeCheckM a = StateT TypeCheckSt (ReaderT TypeConfig (ExceptT (TypeError a) Quote))

isType :: Kind a -> Bool
isType Type{} = True
isType _      = False

-- | Create a new 'Type' for an integer operation.
intop :: (MonadQuote m) => m (NormalizedType TyNameWithKind ())
intop = do
    nam <- newTyName (Size ())
    let ity = TyApp () (TyBuiltin () TyInteger) (TyVar () nam)
        fty = TyFun () ity (TyFun () ity ity)
    pure $ NormalizedType $ TyForall () nam (Size ()) fty

-- | Create a new 'Type' for an integer relation
intRel :: (MonadQuote m)  => m (NormalizedType TyNameWithKind ())
intRel = NormalizedType <$> builtinRel TyInteger

bsRel :: (MonadQuote m) => m (NormalizedType TyNameWithKind ())
bsRel = NormalizedType <$> builtinRel TyByteString

-- | Create a dummy 'TyName'
newTyName :: (MonadQuote m) => Kind () -> m (TyNameWithKind ())
newTyName k = do
    u <- nameUnique . unTyName <$> liftQuote (freshTyName () "a")
    pure $ TyNameWithKind (TyName (Name ((), k) "a" u))

boolean :: MonadQuote m => m (Type TyNameWithKind ())
boolean = do
    nam <- newTyName (Type ())
    let var = TyVar () nam
    pure $ TyForall () nam (Type ()) (TyFun () var (TyFun () var var))

builtinRel :: (MonadQuote m) => TypeBuiltin -> m (Type TyNameWithKind ())
builtinRel bi = do
    nam <- newTyName (Size ())
    b <- boolean
    let ity = TyApp () (TyBuiltin () bi) (TyVar () nam)
        fty = TyFun () ity (TyFun () ity b)
    pure $ TyForall () nam (Size ()) fty

txHash :: NormalizedType TyNameWithKind ()
txHash = NormalizedType $ TyApp () (TyBuiltin () TyByteString) (TyInt () 256)

defaultTable :: (MonadQuote m) => m BuiltinTable
defaultTable = do

    let tyTable = M.fromList [ (TyByteString, KindArrow () (Size ()) (Type ()))
                             , (TySize, Size ())
                             , (TyInteger, KindArrow () (Size ()) (Type ()))
                             ]
        intTypes = [ AddInteger, SubtractInteger, MultiplyInteger, DivideInteger, RemainderInteger ]
        intRelTypes = [ LessThanInteger, LessThanEqInteger, GreaterThanInteger, GreaterThanEqInteger, EqInteger ]

    is <- repeatM (length intTypes) intop
    irs <- repeatM (length intRelTypes) intRel
    bsRelType <- bsRel

    let f = M.fromList .* zip
        termTable = f intTypes is <> f intRelTypes irs <> f [TxHash, EqByteString] [txHash, bsRelType]

    pure $ BuiltinTable tyTable termTable

-- | Type-check a program, returning a normalized type.
typecheckProgram :: (MonadError (Error a) m, MonadQuote m)
                 => TypeCheckCfg
                 -> Program TyNameWithKind NameWithType a
                 -> m (NormalizedType TyNameWithKind ())
typecheckProgram cfg (Program _ _ t) = typecheckTerm cfg t

-- | Type-check a term, returning a normalized type.
typecheckTerm :: (MonadError (Error a) m, MonadQuote m)
              => TypeCheckCfg
              -> Term TyNameWithKind NameWithType a
              -> m (NormalizedType TyNameWithKind ())
typecheckTerm cfg t = convertErrors asError $ runTypeCheckM cfg (typeOf t)

-- | Kind-check a PLC type.
kindCheck :: (MonadError (Error a) m, MonadQuote m)
          => TypeCheckCfg
          -> Type TyNameWithKind a
          -> m (Kind ())
kindCheck cfg t = convertErrors asError $ runTypeCheckM cfg (kindOf t)

-- | Run the type checker with a default context.
runTypeCheckM :: TypeCheckCfg
              -> TypeCheckM a b
              -> ExceptT (TypeError a) Quote b
runTypeCheckM (TypeCheckCfg i n) tc = do
    table <- defaultTable
    runReaderT (evalStateT tc (TypeCheckSt mempty i)) (TypeConfig n table)

typeCheckStep :: TypeCheckM a ()
typeCheckStep = do
    (TypeCheckSt _ i) <- get
    if i == 0
        then throwError OutOfGas
        else modify (over gas (subtract 1))

-- | Extract kind information from a type.
kindOf :: Type TyNameWithKind a -> TypeCheckM a (Kind ())
kindOf TyInt{} = pure (Size ())
kindOf (TyFun x ty' ty'') = do
    k <- kindOf ty'
    k' <- kindOf ty''
    if isType k && isType k'
        then pure (Type ())
        else
            if isType k
                then throwError (KindMismatch x (void ty'') k' (Type ()))
                else throwError (KindMismatch x (void ty') k (Type ()))
kindOf (TyForall x _ _ ty) = do
    k <- kindOf ty
    if isType k
        then pure (Type ())
        else throwError (KindMismatch x (void ty) (Type ()) k)
kindOf (TyLam _ _ k ty) =
    [ KindArrow () (void k) k' | k' <- kindOf ty ]
kindOf (TyVar _ (TyNameWithKind (TyName (Name (_, k) _ _)))) = pure (void k)
kindOf (TyBuiltin _ b) = do
    (TypeConfig _ (BuiltinTable tyst _)) <- ask
    case M.lookup b tyst of
        Just k -> pure k
        _      -> throwError InternalError
kindOf (TyFix x _ ty) = do
    k <- kindOf ty
    if isType k
        then pure (Type ())
        else throwError (KindMismatch x (void ty) (Type ()) k)
kindOf (TyApp x ty ty') = do
    k <- kindOf ty
    case k of
        KindArrow _ k' k'' -> do
            k''' <- kindOf ty'
            typeCheckStep
            if k' == k'''
                then pure k''
                else throwError (KindMismatch x (void ty') k'' k''')
        _ -> throwError (KindMismatch x (void ty') (KindArrow () (Type ()) (Type ())) k)

intApp :: Type a () -> Natural -> Type a ()
intApp ty n = TyApp () ty (TyInt () n)

integerType :: Natural -> NormalizedType a ()
integerType = NormalizedType . intApp (TyBuiltin () TyInteger)

bsType :: Natural -> NormalizedType a ()
bsType = NormalizedType . intApp (TyBuiltin () TyByteString)

sizeType :: Natural -> NormalizedType a ()
sizeType = NormalizedType . intApp (TyBuiltin () TySize)

dummyUnique :: Unique
dummyUnique = Unique 0

dummyTyName :: TyNameWithKind ()
dummyTyName = TyNameWithKind (TyName (Name ((), Type ()) "*" dummyUnique))

dummyKind :: Kind ()
dummyKind = Type ()

dummyType :: Type TyNameWithKind ()
dummyType = TyVar () dummyTyName

-- | Extract type of a term. The resulting type is normalized.
typeOf :: Term TyNameWithKind NameWithType a -> TypeCheckM a (NormalizedType TyNameWithKind ())
typeOf (Var _ (NameWithType (Name (_, ty) _ _))) = do
    (TypeConfig norm _) <- ask
    maybeRed norm (void ty)
typeOf (LamAbs _ _ ty t)                         = do
    (TypeConfig norm _) <- ask
    (NormalizedType ty') <- maybeRed norm (void ty)
    NormalizedType <$> (TyFun () ty' <$> (getNormalizedType <$> typeOf t))
typeOf (Error x ty)                              = do
    k <- kindOf ty
    case k of
        Type{} -> pure (void $ NormalizedType ty)
        _      -> throwError (KindMismatch x (void ty) (Type ()) k)
typeOf (TyAbs _ n k t)                           = NormalizedType <$> (TyForall () (void n) (void k) <$> (getNormalizedType <$> typeOf t))
typeOf (Constant _ (BuiltinName _ n)) = do
    (TypeConfig _ (BuiltinTable _ st)) <- ask
    case M.lookup n st of
        Just k -> pure k
        _      -> throwError InternalError
typeOf (Constant _ (BuiltinInt _ n _))           = pure (integerType n)
typeOf (Constant _ (BuiltinBS _ n _))            = pure (bsType n)
typeOf (Constant _ (BuiltinSize _ n))            = pure (sizeType n)
typeOf (Apply x fun arg) = do
    nFunTy@(NormalizedType funTy) <- typeOf fun
    case funTy of
        TyFun _ inTy outTy -> do
            nArgTy@(NormalizedType argTy) <- typeOf arg
            typeCheckStep
            if inTy == argTy
                then pure $ NormalizedType outTy -- subpart of a normalized type, so normalized
                else throwError (TypeMismatch x (void arg) inTy nArgTy)
        _ -> throwError (TypeMismatch x (void fun) (TyFun () dummyType dummyType) nFunTy)
typeOf (TyInst x body ty) = do
    nBodyTy@(NormalizedType bodyTy) <- typeOf body
    case bodyTy of
        TyForall _ n k absTy -> do
            k' <- kindOf ty
            typeCheckStep
            if k == k'
                then tyReduceBinder n (void $ NormalizedType ty) absTy
                else throwError (KindMismatch x (void ty) k k')
        _ -> throwError (TypeMismatch x (void body) (TyForall () dummyTyName dummyKind dummyType) nBodyTy)
typeOf (Unwrap x body) = do
    nBodyTy@(NormalizedType bodyTy) <- typeOf body
    case bodyTy of
        TyFix _ n fixTy ->
            tyReduceBinder n nBodyTy fixTy
        _             -> throwError (TypeMismatch x (void body) (TyFix () dummyTyName dummyType) nBodyTy)
typeOf (Wrap x n ty body) = do
    nBodyTy <- typeOf body
    tyEnvAssign (extractUnique n) (TyFix () (void n) (void ty))
    typeCheckStep
    red <- tyReduce (void ty) <* tyEnvDelete (extractUnique n)
    if red == nBodyTy
        then pure $ NormalizedType (TyFix () (void n) (void ty))
        else throwError (TypeMismatch x (void body) (getNormalizedType red) nBodyTy)

tyReduceBinder :: TyNameWithKind () -> NormalizedType TyNameWithKind () -> Type TyNameWithKind () -> TypeCheckM a (NormalizedType TyNameWithKind ())
tyReduceBinder n ty ty' = do
    let u = extractUnique n
    tyEnvAssign u (getNormalizedType ty)
    tyReduce ty' <* tyEnvDelete u

extractUnique :: TyNameWithKind a -> Unique
extractUnique = nameUnique . unTyName . unTyNameWithKind

-- This works because names are globally unique
tyEnvDelete :: MonadState TypeCheckSt m
            => Unique
            -> m ()
tyEnvDelete (Unique i) = modify (over uniqueLookup (IM.delete i))

tyEnvAssign :: MonadState TypeCheckSt m
            => Unique
            -> Type TyNameWithKind ()
            -> m ()
tyEnvAssign (Unique i) ty = modify (over uniqueLookup (IM.insert i ty))

-- this will reduce a type, or simply wrap it in a 'NormalizedType' constructor
-- if we are working with normalized type annotations
maybeRed :: Bool -> Type TyNameWithKind () -> TypeCheckM a (NormalizedType TyNameWithKind ())
maybeRed True  = tyReduce
maybeRed False = pure . NormalizedType

-- This performs rewrites with the appropriate environment. It is necessary in
-- the cases when we are not allowed to perform type reductions.
rewriteCtx :: Type TyNameWithKind () -> TypeCheckM a (Type TyNameWithKind ())
rewriteCtx (TyApp x ty ty')     = TyApp x <$> rewriteCtx ty <*> rewriteCtx ty'
rewriteCtx (TyFun x ty ty')     = TyFun x <$> rewriteCtx ty <*> rewriteCtx ty'
rewriteCtx (TyFix x tn ty')     = TyFix x tn <$> rewriteCtx ty'
rewriteCtx (TyLam x tn k ty)    = TyLam x tn k <$> rewriteCtx ty
rewriteCtx (TyForall x tn k ty) = TyForall x tn k <$> rewriteCtx ty
rewriteCtx ty@TyInt{}           = pure ty
rewriteCtx ty@TyBuiltin{}       = pure ty
rewriteCtx ty@(TyVar _ (TyNameWithKind (TyName (Name _ _ u)))) = do
    (TypeCheckSt st _) <- get
    case IM.lookup (unUnique u) st of

        -- we must use recursive lookups because we can have an assignment
        -- a -> b and an assignment b -> c which is locally valid but in
        -- a smaller scope than a -> b.
        Just ty'@TyVar{} -> rewriteCtx ty'
        Just ty'         -> cloneType ty'
        Nothing          -> pure ty

-- | Reduce any redexes inside a type.
tyReduce :: Type TyNameWithKind () -> TypeCheckM a (NormalizedType TyNameWithKind ())
tyReduce (TyForall x tn k ty) = NormalizedType <$> (TyForall x tn k <$> (getNormalizedType <$> tyReduce ty))
tyReduce (TyFix x tn ty) = NormalizedType <$> (TyFix x tn <$> (getNormalizedType <$> tyReduce ty))

-- The guards here are necessary for spec compliance.
--
-- In particular, \\( (\mathtt{fun} S _) )\\ is a valid type reduction frame if and only if
-- \\(S\\) is a type value.
--
-- This is detailed in Fig. 6. of the spec.
tyReduce (TyFun x ty ty') | isTypeValue ty                                   = NormalizedType <$> (TyFun x <$> (getNormalizedType <$> tyReduce ty) <*> (getNormalizedType <$> tyReduce ty'))
                          | otherwise                                        = NormalizedType <$> (TyFun x <$> (getNormalizedType <$> tyReduce ty) <*> rewriteCtx ty')
tyReduce (TyLam x tn k ty)                                                   = NormalizedType <$> (TyLam x tn k <$> (getNormalizedType <$> tyReduce ty))
tyReduce (TyApp x ty ty') = do

    let modTy = if isTypeValue ty -- FIXME: does this recurse right?
        then fmap getNormalizedType . tyReduce
        else rewriteCtx

    arg <- modTy ty'
    fun <- getNormalizedType <$> tyReduce ty
    case fun of
        (TyLam _ (TyNameWithKind (TyName (Name _ _ u))) _ ty'') -> do
            tyEnvAssign u (void arg)
            tyReduce ty'' <* tyEnvDelete u
        _ -> pure $ NormalizedType $ TyApp x fun arg

tyReduce x                                                                   = NormalizedType <$> rewriteCtx x
