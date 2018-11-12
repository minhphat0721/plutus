{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DerivingStrategies         #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures             #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE TupleSections              #-}
{-# LANGUAGE ViewPatterns               #-}
{-# OPTIONS_GHC -Wno-unused-foralls #-}
module Language.Plutus.CoreToPLC.Plugin (PlcCode, getSerializedCode, getAst, plugin, plc) where

import           Language.Plutus.CoreToPLC.Compiler.Builtins
import           Language.Plutus.CoreToPLC.Compiler.Error
import           Language.Plutus.CoreToPLC.Compiler.Expr
import           Language.Plutus.CoreToPLC.Compiler.Types
import           Language.Plutus.CoreToPLC.Compiler.Utils
import           Language.Plutus.CoreToPLC.PIRTypes
import           Language.Plutus.CoreToPLC.PLCTypes
import           Language.Plutus.CoreToPLC.Utils
import           Language.Plutus.Lift

import qualified GhcPlugins                                  as GHC
import qualified Panic                                       as GHC

import qualified Language.PlutusCore                         as PLC
import           Language.PlutusCore.Quote

import qualified Language.PlutusIR                           as PIR
import qualified Language.PlutusIR.Compiler                  as PIR
import qualified Language.PlutusIR.Optimizer.DeadCode        as PIR

import           Language.Haskell.TH.Syntax                  as TH

import           Codec.Serialise                             (DeserialiseFailure, Serialise, deserialiseOrFail,
                                                              serialise)
import           Control.Exception
import           Control.Monad
import           Control.Monad.Except
import           Control.Monad.Reader
import qualified Data.ByteString.Lazy                        as BSL
import qualified Data.Map                                    as Map
import           Data.Maybe                                  (catMaybes)
import qualified Data.Text.Prettyprint.Doc                   as PP
import           GHC.TypeLits

{- Note [Constructing the final program]
Our final type is a simple newtype wrapper. However, constructing *anything* in Core
is a pain - we have to go off and find the right constructor, ensure we've applied it
correctly etc. But since it *is* just a wrapper... we can just put in a coercion!

Very nice and easy, but we need to make sure we don't stop being a simple newtype
without revisiting this.

We also obviously don't want to break anyone by changing the internals, so the type
should be abstract.
-}

-- See Note [Constructing the final program]
-- | A PLC program.
newtype PlcCode = PlcCode { unPlc :: [Word] }
  --  The encoding generated by deriving Serialise is the same as getSerializedCode except that it is surrounded by TkListBegin and TkBreak Tokens
  deriving newtype Serialise

-- Note that we do *not* have a TypeablePlc instance, since we don't know what the type is. We could in principle store it after the plugin
-- typechecks the code, but we don't currently.
instance LiftPlc PlcCode where
    lift (getAst -> (PLC.Program () _ body)) = PLC.rename body

getSerializedCode :: PlcCode -> BSL.ByteString
getSerializedCode = BSL.pack . fmap fromIntegral . unPlc

{- Note [Deserializing the AST]
The types suggest that we can fail to deserialize the AST that we embedded in the program.
However, we just did it ourselves, so this should be impossible, and we signal this with an
exception.
-}
newtype ImpossibleDeserialisationFailure = ImpossibleDeserialisationFailure DeserialiseFailure
instance Show ImpossibleDeserialisationFailure where
    show (ImpossibleDeserialisationFailure e) = "Failed to deserialise our own program! This is a bug, please report it. Caused by: " ++ show e
instance Exception ImpossibleDeserialisationFailure

getAst :: PlcCode -> PLC.Program PLC.TyName PLC.Name ()
getAst wrapper = case deserialiseOrFail $ getSerializedCode wrapper of
    Left e  -> throw $ ImpossibleDeserialisationFailure e
    Right p -> p

-- | Marks the given expression for conversion to PLC.
plc :: forall (loc::Symbol) a . a -> PlcCode
-- this constructor is only really there to get rid of the unused warning
plc _ = PlcCode mustBeReplaced

data PluginOptions = PluginOptions {
    poDoTypecheck    :: Bool
    , poDeferErrors  :: Bool
    , poStripContext :: Bool
    }

plugin :: GHC.Plugin
plugin = GHC.defaultPlugin { GHC.installCoreToDos = install }

install :: [GHC.CommandLineOption] -> [GHC.CoreToDo] -> GHC.CoreM [GHC.CoreToDo]
install args todo =
    let
        opts = PluginOptions {
            poDoTypecheck = notElem "dont-typecheck" args
            , poDeferErrors = elem "defer-errors" args
            , poStripContext = elem "strip-context" args
            }
    in
        pure (GHC.CoreDoPluginPass "Core to PLC" (pluginPass opts) : todo)

pluginPass :: PluginOptions -> GHC.ModGuts -> GHC.CoreM GHC.ModGuts
pluginPass opts guts = qqMarkerName >>= \case
    -- nothing to do
    Nothing -> pure guts
    Just name -> GHC.bindsOnlyPass (mapM $ convertMarkedExprsBind opts name) guts

{- Note [Hooking in the plugin]
Working out what to process and where to put it is tricky. We are going to turn the result in
to a 'PlcCode', not the Haskell expression we started with!

Currently we look for calls to the 'plc :: a -> PlcCode' function, and we replace the whole application with the
generated code object, which will still be well-typed.

However, if we do this with a polymorphic expression as the argument to 'plc', we have problems
where GHC gives unconstrained type variables the type `Any` rather than leaving them abstracted as we require (see
note [System FC and system FW]). I don't currently know how to resolve this.
-}

qqMarkerName :: GHC.CoreM (Maybe GHC.Name)
qqMarkerName = GHC.thNameToGhcName 'plc

qqMarkerType :: GHC.Type -> Maybe GHC.Type
qqMarkerType vtype = do
    (_, ty) <- GHC.splitForAllTy_maybe vtype
    (_, ty') <- GHC.splitForAllTy_maybe ty
    (_, o) <- GHC.splitFunTy_maybe ty'
    pure o

-- | Make a 'BuiltinNameInfo' mapping the given set of TH names to their
-- 'GHC.TyThing's for later reference.
makePrimitiveNameInfo :: [TH.Name] -> GHC.CoreM BuiltinNameInfo
makePrimitiveNameInfo names = do
    mapped <- forM names $ \name -> do
        ghcNameMaybe <- GHC.thNameToGhcName name
        case ghcNameMaybe of
            Just n -> do
                thing <- GHC.lookupThing n
                pure $ Just (name, thing)
            Nothing -> pure Nothing
    pure $ Map.fromList (catMaybes mapped)

-- | Converts all the marked expressions in the given binder into PLC literals.
convertMarkedExprsBind :: PluginOptions -> GHC.Name -> GHC.CoreBind -> GHC.CoreM GHC.CoreBind
convertMarkedExprsBind opts markerName = \case
    GHC.NonRec b e -> GHC.NonRec b <$> convertMarkedExprs opts markerName e
    GHC.Rec bs -> GHC.Rec <$> mapM (\(b, e) -> (,) b <$> convertMarkedExprs opts markerName e) bs

-- | Converts all the marked expressions in the given expression into PLC literals.
convertMarkedExprs :: PluginOptions -> GHC.Name -> GHC.CoreExpr -> GHC.CoreM GHC.CoreExpr
convertMarkedExprs opts markerName =
    let
        conv = convertMarkedExprs opts markerName
        convB = convertMarkedExprsBind opts markerName
    in \case
      -- the ignored argument is the type for the polymorphic 'plc'
      e@(GHC.App(GHC.App (GHC.App (GHC.Var fid) (GHC.Type (GHC.isStrLitTy -> Just fs_locStr))) (GHC.Type _)) inner) | markerName == GHC.idName fid ->
          let
              vtype = GHC.varType fid
              locStr = show fs_locStr
          in case qqMarkerType vtype of
              Just t -> convertExpr opts locStr inner t
              Nothing -> do
                  GHC.errorMsg $ "plc Plugin: found invalid marker, could not decode type:" GHC.$+$ GHC.ppr vtype
                  pure e
      e@(GHC.Var fid) | markerName == GHC.idName fid -> do
            GHC.errorMsg "plc Plugin: found invalid marker, not applied correctly"
            pure e
      GHC.App e a -> GHC.App <$> conv e <*> conv a
      GHC.Lam b e -> GHC.Lam b <$> conv e
      GHC.Let bnd e -> GHC.Let <$> convB bnd <*> conv e
      GHC.Case e b t alts -> do
            e' <- conv e
            let expAlt (a, bs, rhs) = (,,) a bs <$> conv rhs
            alts' <- mapM expAlt alts
            pure $ GHC.Case e' b t alts'
      GHC.Cast e c -> flip GHC.Cast c <$> conv e
      GHC.Tick t e -> GHC.Tick t <$> conv e
      e@(GHC.Coercion _) -> pure e
      e@(GHC.Lit _) -> pure e
      e@(GHC.Var _) -> pure e
      e@(GHC.Type _) -> pure e

-- | Actually invokes the Core to PLC compiler to convert an expression into a PLC literal.
convertExpr :: PluginOptions -> String -> GHC.CoreExpr -> GHC.Type -> GHC.CoreM GHC.CoreExpr
convertExpr opts locStr origE resType = do
    flags <- GHC.getDynFlags
    -- We need to do this out here, since it has to run in CoreM
    nameInfo <- makePrimitiveNameInfo builtinNames
    let result = withContextM (sdToTxt $ "Converting expr at" GHC.<+> GHC.text locStr) $ do
              (pirP::PIRProgram) <- PIR.Program () . PIR.removeDeadBindings <$> convExprWithDefs origE
              (plcP::PLCProgram) <- convertErrors (NoContext . PIRError) $ void <$> (flip runReaderT PIR.NoProvenance $ PIR.compileProgram pirP)
              when (poDoTypecheck opts) $ convertErrors (NoContext . PLCError) $ do
                  annotated <- PLC.annotateProgram plcP
                  void $ PLC.typecheckProgram (PLC.TypeCheckCfg 1000 $ PLC.TypeConfig True mempty) annotated
              pure (pirP, plcP)
        context = ConvertingContext {
            ccOpts=ConversionOptions { coCheckValueRestriction=poDoTypecheck opts },
            ccFlags=flags,
            ccBuiltinNameInfo=nameInfo,
            ccScopes=initialScopeStack
            }
        initialState = ConvertingState mempty mempty
    case runConverting context initialState result of
        Left s ->
            let shown = show $ if poStripContext opts then PP.pretty (stripContext s) else PP.pretty s in
            if poDeferErrors opts
            -- TODO: is this the right way to do either of these things?
            then pure $ GHC.mkRuntimeErrorApp GHC.rUNTIME_ERROR_ID resType shown -- this will blow up at runtime
            else liftIO $ GHC.throwGhcExceptionIO (GHC.ProgramError shown) -- this will actually terminate compilation
        -- TODO: get the PIR into the PlcCode somehow (need serialization)
        Right (_, plcP) -> do
            -- this is useful as debug printing until we store the PIR properly
            {-
            let pirPrinted = show $ PIR.prettyDef pirP
            GHC.debugTraceMsg $
                "Successfully converted GHC core expression:" GHC.$+$
                GHC.ppr origE GHC.$+$
                "Resulting PIR term is:" GHC.$+$
                GHC.text pirPrinted
            -}
            let serialized = serialise plcP
            -- The GHC api only exposes a way to make literals for Words, not Word8s, so we need to convert them
            let (word8s :: [Word]) = fromIntegral <$> BSL.unpack serialized
            -- The flags here are so GHC can check whether the word is in range for the current platform.
            -- This will never actually be a problem for us, since they're really Word8s, but GHC
            -- doesn't know that.
            let (wordExprs :: [GHC.CoreExpr]) = fmap (GHC.mkWordExprWord flags) word8s
            let listExpr = GHC.mkListExpr GHC.wordTy wordExprs
            -- See Note [Constructing the final program]
            pure $ GHC.Cast listExpr $ GHC.mkRepReflCo resType
