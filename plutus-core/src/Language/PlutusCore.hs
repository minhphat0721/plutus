-- Why is it needed here, but not in 'Universe.hs'?
{-# LANGUAGE ExplicitNamespaces #-}
{-# LANGUAGE TypeApplications   #-}


module Language.PlutusCore
    (
      -- * Parser
    parseProgram
    , parseTerm
    , parseType
    , parseScoped
    -- * Universe
    , Some (..)
    , TypeIn (..)
    , ValueOf (..)
    , someValue
    , Includes (..)
    , IncludesAll
    , Closed (..)
    , EverywhereAll
    , knownUniOf
    , GShow (..)
    , show
    , GEq (..)
    , deriveGEq
    , (:~:) (..)
    , Lift
    , type (<:)
    , DefaultUni (..)
    , DefaultFun (..)
    -- * AST
    , Term (..)
    , termSubterms
    , termSubtypes
    , Type (..)
    , typeSubtypes
    , Kind (..)
    , ParseError (..)
    , Version (..)
    , Program (..)
    , Name (..)
    , TyName (..)
    , Unique (..)
    , UniqueMap (..)
    , Normalized (..)
    , defaultVersion
    , allKeywords
    , toTerm
    , termAnn
    , typeAnn
    -- * Lexer
    , AlexPosn (..)
    -- * Formatting
    , format
    , formatDoc
    -- * Processing
    , HasUniques
    , Rename (..)
    -- * Type checking
    , module TypeCheck
    , fileType
    , fileTypeCfg
    , printType
    , normalizeTypesIn
    , normalizeTypesInProgram
    , AsTypeError (..)
    , TypeError
    , parseTypecheck
    -- for testing
    , typecheckPipeline
    -- * Errors
    , Error (..)
    , AsError (..)
    , AsNormCheckError (..)
    , UniqueError (..)
    -- * Base functors
    , TermF (..)
    , TypeF (..)
    -- * Quotation and term construction
    , Quote
    , runQuote
    , QuoteT
    , runQuoteT
    , MonadQuote
    , liftQuote
    -- * Name generation
    , freshUnique
    , freshName
    , freshTyName
    -- * Evaluation
    , EvaluationResult (..)
    -- * Combining programs
    , applyProgram
    -- * Benchmarking
    , termSize
    , typeSize
    , kindSize
    , programSize
    , serialisedSize
    ) where

import           PlutusPrelude

import           Language.PlutusCore.Builtins
import           Language.PlutusCore.CBOR                  ()
import qualified Language.PlutusCore.Check.Uniques         as Uniques
import           Language.PlutusCore.Core
import           Language.PlutusCore.Error
import           Language.PlutusCore.Evaluation.Machine.Ck
import           Language.PlutusCore.Lexer
import           Language.PlutusCore.Lexer.Type
import           Language.PlutusCore.Name
import           Language.PlutusCore.Normalize
import           Language.PlutusCore.Parser
import           Language.PlutusCore.Pretty
import           Language.PlutusCore.Quote
import           Language.PlutusCore.Rename
import           Language.PlutusCore.Size
import           Language.PlutusCore.TypeCheck             as TypeCheck
import           Language.PlutusCore.Universe

import           Control.Monad.Except
import qualified Data.ByteString.Lazy                      as BSL
import qualified Data.Text                                 as T

nullAlexPosn :: AlexPosn
nullAlexPosn = AlexPn 0 0 0

-- | Given a file at @fibonacci.plc@, @fileType "fibonacci.plc"@ will display
-- its type or an error message.
fileType :: FilePath -> IO T.Text
fileType = fmap (either prettyErr id . printType) . BSL.readFile
    where
        prettyErr :: Error DefaultUni DefaultFun AlexPosn -> T.Text
        prettyErr = displayPlcDef

-- | Given a file, display
-- its type or an error message, optionally dumping annotations and debug
-- information.
fileTypeCfg :: PrettyConfigPlc -> FilePath -> IO T.Text
fileTypeCfg cfg = fmap (either prettyErr id . printType) . BSL.readFile
    where
        prettyErr :: Error DefaultUni DefaultFun AlexPosn -> T.Text
        prettyErr = displayBy cfg

-- | Print the type of a program contained in a 'ByteString'
printType
    :: (AsParseError e AlexPosn,
        AsUniqueError e AlexPosn,
        AsTypeError e (Term TyName Name DefaultUni DefaultFun ()) DefaultUni DefaultFun AlexPosn,
        MonadError e m)
    => BSL.ByteString
    -> m T.Text
printType bs = runQuoteT $ displayPlcDef <$> do
    scoped <- parseScoped bs
    config <- getDefTypeCheckConfig nullAlexPosn
    inferTypeOfProgram config scoped

-- | Parse and rewrite so that names are globally unique, not just unique within
-- their scope.
parseScoped
    :: (AsParseError e AlexPosn,
        AsUniqueError e AlexPosn,
        MonadError e m,
        MonadQuote m)
    => BSL.ByteString
    -> m (Program TyName Name DefaultUni DefaultFun AlexPosn)
-- don't require there to be no free variables at this point, we might be parsing an open term
parseScoped = through (Uniques.checkProgram (const True)) <=< rename <=< parseProgram

-- | Parse a program and typecheck it.
parseTypecheck
    :: (AsParseError e AlexPosn,
        AsUniqueError e AlexPosn,
        AsTypeError e (Term TyName Name DefaultUni DefaultFun ()) DefaultUni DefaultFun AlexPosn,
        MonadError e m,
        MonadQuote m)
    => TypeCheckConfig DefaultUni DefaultFun
    -> BSL.ByteString
    -> m (Normalized (Type TyName DefaultUni ()))
parseTypecheck cfg = typecheckPipeline cfg <=< parseScoped

-- | Typecheck a program.
typecheckPipeline
    :: (AsTypeError e (Term TyName Name DefaultUni DefaultFun ()) DefaultUni DefaultFun a,
        MonadError e m,
        MonadQuote m)
    => TypeCheckConfig DefaultUni DefaultFun
    -> Program TyName Name DefaultUni DefaultFun a
    -> m (Normalized (Type TyName DefaultUni ()))
typecheckPipeline = inferTypeOfProgram

parseProgramDef
    :: (AsParseError e AlexPosn, MonadError e m, MonadQuote m)
    => BSL.ByteString -> m (Program TyName Name DefaultUni DefaultFun AlexPosn)
parseProgramDef = parseProgram

formatDoc :: (AsParseError e AlexPosn, MonadError e m) => PrettyConfigPlc -> BSL.ByteString -> m (Doc a)
-- don't use parseScoped since we don't bother running sanity checks when we format
formatDoc cfg = runQuoteT . fmap (prettyBy cfg) . (rename <=< parseProgramDef)

format
    :: (AsParseError e AlexPosn, MonadError e m)
    => PrettyConfigPlc -> BSL.ByteString -> m T.Text
-- don't use parseScoped since we don't bother running sanity checks when we format
format cfg = runQuoteT . fmap (displayBy cfg) . (rename <=< parseProgramDef)

-- | Take one PLC program and apply it to another.
applyProgram
    :: Program tyname name uni fun ()
    -> Program tyname name uni fun ()
    -> Program tyname name uni fun ()
applyProgram (Program _ _ t1) (Program _ _ t2) = Program () (defaultVersion ()) (Apply () t1 t2)
