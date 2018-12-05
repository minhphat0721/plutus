{-# LANGUAGE AutoDeriveTypeable    #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DerivingStrategies    #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeOperators         #-}

module PSGenerator
    ( generate
    , k
    ) where

import           Control.Applicative                       ((<|>))
import           Control.Lens                              (set, (&))
import           Control.Monad.Reader.Class                (MonadReader)
import qualified Data.ByteString                           as BS
import           Data.FileEmbed                            (embedFile)
import           Data.Monoid                               ()
import           Data.Proxy                                (Proxy (Proxy))
import qualified Data.Set                                  as Set ()
import qualified Data.Text                                 as T ()
import qualified Data.Text.Encoding                        as T ()
import qualified Data.Text.IO                              as T ()
import           Language.PureScript.Bridge                (BridgeData, BridgePart, Language (Haskell), PSType, SumType,
                                                            TypeInfo (TypeInfo), buildBridge, mkSumType,
                                                            psTypeParameters, typeModule, typeName, writePSTypes, (^==))
import           Language.PureScript.Bridge.PSTypes        (psArray, psInt, psString)
import           Language.PureScript.Bridge.TypeParameters (A)
import           Ledger.Index                              (ValidationError)
import           Ledger.Types                              (Address, Height, PubKey, Signature, Tx, TxId, TxIn,
                                                            TxInType, TxOut, TxOutRef, TxOutType, Value)
import           Playground.API                            (CompilationError, Evaluation, EvaluationResult, Expression,
                                                            Fn, FunctionSchema, SimpleArgumentSchema, SourceCode)
import qualified Playground.API                            as API
import           Servant.PureScript                        (HasBridge, Settings, apiModuleName, defaultBridge,
                                                            defaultSettings, languageBridge, writeAPIModuleWithSettings,
                                                            _generateSubscriberAPI)
import           System.FilePath                           ((</>))
import           Wallet.API                                (WalletAPIError)
import           Wallet.Emulator.Types                     (EmulatorEvent, Wallet)
import           Wallet.Graph                              (FlowGraph, FlowLink, TxRef, UtxOwner)

integerBridge :: BridgePart
integerBridge = do
    typeName ^== "Integer"
    pure psInt

scientificBridge :: BridgePart
scientificBridge = do
    typeName ^== "Scientific"
    typeModule ^== "Data.Scientific"
    pure psInt

insOrdHashMapBridge :: BridgePart
insOrdHashMapBridge = do
    typeName ^== "InsOrdHashMap"
    psMap

mapBridge :: BridgePart
mapBridge = do
    typeName ^== "Map"
    typeModule ^== "Data.Map" <|> typeModule ^== "Data.Map.Internal"
    psMap

psMap :: MonadReader BridgeData m => m PSType
psMap = TypeInfo "purescript-maps" "Data.Map" "Map" <$> psTypeParameters

aesonBridge :: BridgePart
aesonBridge = do
    typeName ^== "Value"
    typeModule ^== "Data.Aeson.Types.Internal"
    pure psJson

psJson :: PSType
psJson = TypeInfo "" "Data.RawJson" "RawJson" []

setBridge :: BridgePart
setBridge = do
    typeName ^== "Set"
    typeModule ^== "Data.Set" <|> typeModule ^== "Data.Set.Internal"
    psArray

digestBridge :: BridgePart
digestBridge = do
    typeName ^== "Digest"
    typeModule ^== "Crypto.Hash.Types"
    pure psString

sha256Bridge :: BridgePart
sha256Bridge = do
    typeName ^== "SHA256"
    typeModule ^== "Crypto.Hash.Types" <|> typeModule ^== "Crypto.Hash" <|>
        typeModule ^== "Crypto.Hash.SHA256"
    pure psString

redeemerBridge :: BridgePart
redeemerBridge = do
    typeName ^== "Redeemer"
    typeModule ^== "Ledger.Types"
    pure psString

validatorBridge :: BridgePart
validatorBridge = do
    typeName ^== "Validator"
    typeModule ^== "Ledger.Types"
    pure psString

dataScriptBridge :: BridgePart
dataScriptBridge = do
    typeName ^== "DataScript"
    typeModule ^== "Ledger.Types"
    pure psString

validatorScriptBridge :: BridgePart
validatorScriptBridge = do
    typeName ^== "ValidatorScript"
    typeModule ^== "Ledger.Types"
    pure psString

redeemerScriptBridge :: BridgePart
redeemerScriptBridge = do
    typeName ^== "RedeemerScript"
    typeModule ^== "Ledger.Types"
    pure psString

myBridge :: BridgePart
myBridge =
    defaultBridge <|> integerBridge <|> scientificBridge <|> insOrdHashMapBridge <|>
    aesonBridge <|>
    setBridge <|>
    mapBridge <|>
    digestBridge <|>
    sha256Bridge <|>
    redeemerBridge <|>
    validatorBridge <|>
    validatorScriptBridge <|>
    redeemerScriptBridge <|>
    dataScriptBridge

data MyBridge

myBridgeProxy :: Proxy MyBridge
myBridgeProxy = Proxy

instance HasBridge MyBridge where
    languageBridge _ = buildBridge myBridge

myTypes :: [SumType 'Haskell]
myTypes =
    [ mkSumType (Proxy @SimpleArgumentSchema)
    , mkSumType (Proxy @(FunctionSchema A))
    , mkSumType (Proxy @Fn)
    , mkSumType (Proxy @SourceCode)
    , mkSumType (Proxy @Wallet)
    , mkSumType (Proxy @CompilationError)
    , mkSumType (Proxy @Expression)
    , mkSumType (Proxy @Evaluation)
    , mkSumType (Proxy @EvaluationResult)
    , mkSumType (Proxy @EmulatorEvent)
    , mkSumType (Proxy @ValidationError)
    , mkSumType (Proxy @Height)
    , mkSumType (Proxy @WalletAPIError)
    , mkSumType (Proxy @Tx)
    , mkSumType (Proxy @(TxIn A))
    , mkSumType (Proxy @(TxOutRef A))
    , mkSumType (Proxy @TxOutType)
    , mkSumType (Proxy @(TxOut A))
    , mkSumType (Proxy @(TxId A))
    , mkSumType (Proxy @TxInType)
    , mkSumType (Proxy @Signature)
    , mkSumType (Proxy @Value)
    , mkSumType (Proxy @PubKey)
    , mkSumType (Proxy @(Address A))
    , mkSumType (Proxy @FlowLink)
    , mkSumType (Proxy @TxRef)
    , mkSumType (Proxy @UtxOwner)
    , mkSumType (Proxy @FlowGraph)
    ]

mySettings :: Settings
mySettings =
    (defaultSettings & set apiModuleName "Playground.Server")
        {_generateSubscriberAPI = False}

multilineString :: BS.ByteString -> BS.ByteString -> BS.ByteString
multilineString name value =
    "\n\n" <> name <> " :: String\n" <> name <> " = \"\"\"" <> value <> "\"\"\""

psModule :: BS.ByteString -> BS.ByteString -> BS.ByteString
psModule name body = "module " <> name <> " where" <> body

writeUsecases :: FilePath -> IO ()
writeUsecases outputDir = do
    let usecases =
            multilineString "vesting" $(embedFile "./usecases/Vesting.hs") <>
            multilineString "game" $(embedFile "./usecases/Game.hs") <>
            multilineString
                "crowdfunding"
                $(embedFile "./usecases/CrowdFunding.hs") <>
            multilineString "messages" $(embedFile "./usecases/Messages.hs")
        usecasesModule = psModule "Playground.Usecases" usecases
    BS.writeFile (outputDir </> "Playground" </> "Usecases.purs") usecasesModule
    putStrLn outputDir

generate :: FilePath -> IO ()
generate outputDir = do
    writeAPIModuleWithSettings
        mySettings
        outputDir
        myBridgeProxy
        (Proxy @API.API)
    writePSTypes outputDir (buildBridge myBridge) myTypes
    writeUsecases outputDir

k :: IO ()
k =
    generate
        "/Users/kris/Work/Clients/IOHK/plutus/plutus-playground/plutus-playground-client/src"
