-- | This module contains definitions which allow to test the 'applyBuiltinName' function.
-- See the "Success" and "SuccessFailure" module for actual tests implemented
-- in terms of functions defined here.

{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE GADTs      #-}
module Evaluation.Constant.Apply
    ( prop_applyBuiltinName
    , prop_applyBuiltinNameSuccess
    , prop_applyBuiltinNameSuccessFailure
    ) where

import           Language.PlutusCore
import           Language.PlutusCore.Constant
import           Evaluation.Constant.GenTypedBuiltinSized
import           Evaluation.Generator

import           GHC.Stack
import           Control.Monad.Reader
import           Control.Monad.Morph
import           Data.Text.Prettyprint.Doc
import           Hedgehog hiding (Size, Var, annotate)
import qualified Hedgehog.Gen as Gen

-- | The internal type used in properties defined in this module.
-- It is parameterized by an 'TheGenTypedBuiltinSized' which determines
-- how to generate sized builtins having a 'Size'. See for example
-- 'genTypedBuiltinSizedSum' and 'genTypedBuiltinSizedDiv'.
type ConstAppProperty = PropertyT (ReaderT TheGenTypedBuiltinSized IO)

evalMaybe :: (MonadTest m, Show e, HasCallStack) => e -> Maybe a -> m a
evalMaybe e = evalEither . maybe (Left e) Right

forAllPretty :: (Monad m, Pretty a) => Gen a -> PropertyT m a
forAllPretty = forAllWith prettyString

forAllTypedBuiltin :: Monad m => TypedBuiltin Size a -> Gen a -> PropertyT m a
forAllTypedBuiltin tb gen = do
    TypedBuiltinValue _ x <- forAllPretty $ TypedBuiltinValue tb <$> gen
    return x

-- | Generate a value of one of the builtin types.
-- See 'TypedBuiltin' for the list of such types.
genTypedBuiltin :: TypedBuiltin Size a -> ConstAppProperty a
genTypedBuiltin tb@(TypedBuiltinSized sizeEntry tbs) = do
    let size = flattenSizeEntry sizeEntry
    TheGenTypedBuiltinSized genTbs <- ask
    forAllTypedBuiltin tb $ genTbs size tbs
genTypedBuiltin TypedBuiltinBool                     = forAll Gen.bool

-- | Coerce a Haskell value to a PLC value checking all constraints
-- (e.g. an 'Integer' is in appropriate bounds) along the way and
-- fail in case constraints are not satisfied.
typedBuiltinAsValue :: TypedBuiltin Size a -> a -> ConstAppProperty (Value TyName Name ())
typedBuiltinAsValue builtin x = evalMaybe err $ makeConstant builtin x where
    sx = prettyString $ TypedBuiltinValue builtin x
    err = "prop_typedAddInteger: out of bounds: " ++ sx

-- | Generate a value of one of the builtin types (see 'TypedBuiltin' for
-- the list of such types) and return it along with the corresponding PLC value.
getTypedBuiltinAndItsValue :: TypedBuiltin Size a -> ConstAppProperty (a, Value TyName Name ())
getTypedBuiltinAndItsValue builtin = do
    x <- genTypedBuiltin builtin
    v <- typedBuiltinAsValue builtin x
    return (x, v)

getSchemedAndItsValue :: TypeScheme Size a -> ConstAppProperty (a, Value TyName Name ())
getSchemedAndItsValue (TypeSchemeBuiltin builtin) = getTypedBuiltinAndItsValue builtin
getSchemedAndItsValue (TypeSchemeArrow _ _)       = error "Not implemented."
getSchemedAndItsValue (TypeSchemeAllSize _)       = error "Not implemented."

-- | This a generic property-based testing procedure for 'applyBuiltinName'.
-- It generates Haskell values of builtin types (see 'TypedBuiltin' for the list of such types)
-- taking size-induced bounds (controlled by the 'GenTypedBuiltinSized' parameter) into account
-- for arguments and either taking those bounds into account for the final result or using the
-- default ones (as per the spec) or ignoring them completely depending on how you instantiate
-- the first parameter. An argument is generated as a Haskell value, then coerced to the
-- corresponding PLC value which gets appended to the spine of arguments 'applyBuiltinName' expects.
-- The generated Haskell value is passed to the semantics of the 'TypedBuiltinName'
-- (the second argument), i.e. to the third argument. Thus we collect arguments on the PLC side
-- and supply them to a function on the Haskell side. When all appropriate arguments are generated,
-- we check that the results of the two computations match. We also check along the way that each
-- underapplication on the PLC side is a stuck application.
prop_applyBuiltinName
    :: (forall b. TypedBuiltin Size b -> b -> ConstAppProperty ConstAppResult)
                             -- ^ How to get a 'ConstAppResult' having a Haskell value of
                             -- one of the builtin types. See 'TypedBuiltin' for the list of such types.
    -> TypedBuiltinName a    -- ^ A (typed) builtin name to apply.
    -> a                     -- ^ The semantics of the builtin name. E.g. the semantics of
                             -- 'AddInteger' (and hence 'typedAddInteger') is '(+)'.
    -> GenTypedBuiltinSized  -- ^ How to generate values of sized builtin types.
    -> Property
prop_applyBuiltinName getFinal (TypedBuiltinName name schema) op allTbs = result where
    result = property . hoist (flip runReaderT $ TheGenTypedBuiltinSized allTbs) $ do
        size <- forAll genSizeDef                   -- Generate a size.
        go (applyBuiltinName name) size schema op

    go
        :: ([Value TyName Name ()] -> ConstAppResult)
        -> Size -> TypeScheme Size a -> a -> ConstAppProperty ()
    go app _    (TypeSchemeBuiltin builtin) y = do  -- Computed the result.
        final <- getFinal builtin y                 -- Get a 'ConstAppResult' from a Haskell value.
        app [] === final                            -- Check that results of application of 'applyBuiltinName'
                                                    -- and 'op' to their PLC/Haskell arguments match.
    go app size (TypeSchemeArrow schA schB) f = do  -- Another argument is required.
        app [] === ConstAppStuck                    -- Check that 'applyBuiltinName' can't reduce yet.
        (x, v) <- getSchemedAndItsValue schA        -- Get a Haskell and the correspoding PLC values.
        go (app . (v :)) size schB (f x)            -- Apply to each of the values their respective consumers,
                                                    -- i.e. 'applyBuiltName' for the PLC value
                                                    -- and 'op' for the Haskell value.
    go app size (TypeSchemeAllSize schK)    f =
        go app size (schK size) f                   -- Instantiate a size variable with the size
                                                    -- generated above.

-- | A specialized version of 'prop_applyBuiltinName'. A final value of the computation on
-- the Haskell side must fit into the specified (by the 'GenTypedBuiltinSized' argument) bounds
-- and hence the result of the 'applyBuiltinName' computation must be a 'ConstAppSuccess'.
-- See 'genTypedBuiltinSizedSum' for how this is achieved for 'AddInteger' and 'SubtractInteger'.
-- See the "Success" module for tests defined in terms of this function.
prop_applyBuiltinNameSuccess :: TypedBuiltinName a -> a -> GenTypedBuiltinSized -> Property
prop_applyBuiltinNameSuccess =
    prop_applyBuiltinName $ \tbs -> fmap ConstAppSuccess . typedBuiltinAsValue tbs

-- | A specialized version of 'prop_applyBuiltinName'. A final value of the computation on
-- the Haskell side may or may not fit into the default bounds (as per the spec) and hence the
-- result of the 'applyBuiltinName' computation must be either a 'ConstAppSuccess' or 'ConstAppFailure'.
-- See the "SuccessFailure" module for tests defined in terms of this function.
prop_applyBuiltinNameSuccessFailure :: TypedBuiltinName a -> a -> Property
prop_applyBuiltinNameSuccessFailure tbn x =
    prop_applyBuiltinName (\tbs -> return . makeConstantApp tbs) tbn x genTypedBuiltinSizedDef
