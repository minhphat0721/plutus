{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# OPTIONS_GHC -fno-warn-incomplete-uni-patterns -fno-warn-unused-do-bind #-}
{-# OPTIONS -fplugin=Language.Plutus.CoreToPLC.Plugin -fplugin-opt Language.Plutus.CoreToPLC.Plugin:dont-typecheck #-}
module Spec.Marlowe(tests) where

import           Data.Bifunctor                                      (Bifunctor (..))
import           Data.Either                                         (isRight)
import           Control.Monad                                        (void)
import           Data.Foldable                                       (traverse_)
import qualified Data.Map                                            as Map
import           Hedgehog                                            (Property, forAll, property)
import qualified Hedgehog
import qualified Hedgehog.Gen        as Gen
import qualified Hedgehog.Range      as Range
import           Test.Tasty
import           Test.Tasty.Hedgehog                                 (testProperty, HedgehogTestLimit(..))

import           Wallet.API                                          (PubKey (..))
import           Wallet.Emulator                                     hiding (Value)
import qualified Wallet.Generators                                   as Gen
import           Wallet.UTXO.Runtime                           (OracleValue (..), Signed (..))

import qualified Language.Plutus.Runtime                             as Runtime
import           Language.Plutus.TH
                          (plutus)
import           Language.Marlowe.Compiler
import qualified Wallet.UTXO                                         as UTXO
import qualified Debug.Trace as Debug

newtype MarloweScenario = MarloweScenario { mlInitialBalances :: Map.Map PubKey UTXO.Value }

tests :: TestTree
tests = localOption (HedgehogTestLimit $ Just 3) $ testGroup "Marlowe" [
        testProperty "Commit/Pay works" simplePayment,
        testProperty "Oracle Commit/Pay works" oraclePayment,
        testProperty "can't commit after timeout" cantCommitAfterStartTimeout,
        testProperty "redeem after commit expired" redeemAfterCommitExpired
        ]

-- | Funds available to wallets `Wallet 2` and `Wallet 3`
startingBalance :: UTXO.Value
startingBalance = 1000

-- | Run a trace with the given scenario and check that the emulator finished
--   successfully with an empty transaction pool.
checkMarloweTrace :: MarloweScenario -> Trace EmulatedWalletApi () -> Property
checkMarloweTrace MarloweScenario{mlInitialBalances} t = property $ do
    let model = Gen.generatorModel { Gen.gmInitialBalance = mlInitialBalances }
    (result, st) <- forAll $ Gen.runTraceOn model t
    Hedgehog.assert (isRight result)
    Hedgehog.assert ([] == emTxPool st)



simplePayment :: Property
simplePayment = checkMarloweTrace (MarloweScenario {
    mlInitialBalances = Map.fromList [ (PubKey 1, 1000), (PubKey 2, 777) ] }) $ do
    -- Init a contract
    let alice = Wallet 1
        bob = Wallet 2
        update = processPending >>= void . walletsNotifyBlock [alice, bob]
    update
    let contract = CommitCash (IdentCC 1) (PubKey 2) (Value 100) 128 256
            (Pay (IdentPay 1) (PubKey 2) (PubKey 1) (Committed (IdentCC 1)) 256 Null)
            Null
    [tx] <- walletAction alice (createContract contract 12)
    let txOut = head . filter (isPayToScriptOut . fst) . txOutRefs $ tx
    update
    assertIsValidated tx
    [tx] <- walletAction bob $ commit (PubKey 2) txOut [] [] 100 256
    let txOut = head . filter (isPayToScriptOut . fst) . txOutRefs $ tx
    update
    assertIsValidated tx
    [tx] <- walletAction alice (receivePayment txOut 100)
    let txOut@(txo, _) = head . filter (isPayToScriptOut . fst) . txOutRefs $ tx
    update
    assertIsValidated tx

    let (PayToScript (DataScript script)) = txOutType txo

    [tx] <- walletAction alice (endContract txOut)
    update
    assertIsValidated tx
    assertOwnFundsEq alice 1100
    assertOwnFundsEq bob 677
    return ()

cantCommitAfterStartTimeout :: Property
cantCommitAfterStartTimeout = checkMarloweTrace (MarloweScenario {
    mlInitialBalances = Map.fromList [ (PubKey 1, 1000), (PubKey 2, 777) ] }) $ do
    -- Init a contract
    let alice = Wallet 1
        bob = Wallet 2
        update = processPending >>= void . walletsNotifyBlock [alice, bob]
    update
    [tx] <- walletAction alice (createContract (CommitCash (IdentCC 1) (PubKey 2) (Value 100) 128 256 Null Null) 12)
    let txOut = head . filter (isPayToScriptOut . fst) . txOutRefs $ tx
    update
    assertIsValidated tx

    addBlocks 200

    [tx] <- walletAction bob $ commit (PubKey 2) txOut [] [] 100 256
    update
    -- assertIsValidated tx

    assertOwnFundsEq alice 988
    assertOwnFundsEq bob 777
    return ()

redeemAfterCommitExpired :: Property
redeemAfterCommitExpired = checkMarloweTrace (MarloweScenario {
    mlInitialBalances = Map.fromList [ (PubKey 1, 1000), (PubKey 2, 777) ] }) $ do
    -- Init a contract
    let alice = Wallet 1
        bob = Wallet 2
        update = processPending >>= void . walletsNotifyBlock [alice, bob]
        identCC = (IdentCC 1)
    update
    [tx] <- walletAction alice (createContract (CommitCash identCC (PubKey 2) (Value 100) 128 256 Null Null) 12)
    let txOut = head . filter (isPayToScriptOut . fst) . txOutRefs $ tx
    update
    assertIsValidated tx

    [tx] <- walletAction bob $ commit (PubKey 2) txOut [] [] 100 256
    let txOut = head . filter (isPayToScriptOut . fst) . txOutRefs $ tx
    update
    assertIsValidated tx

    addBlocks 300

    [tx] <- walletAction bob (redeem txOut identCC 100)
    update
    assertIsValidated tx

    assertOwnFundsEq alice 988
    assertOwnFundsEq bob 777
    return ()

oraclePayment :: Property
oraclePayment = checkMarloweTrace (MarloweScenario {
    mlInitialBalances = Map.fromList [ (PubKey 1, 1000), (PubKey 2, 777) ] }) $ do
    -- Init a contract
    let alice = Wallet 1
        bob = Wallet 2
        oracle = PubKey 42
        update = processPending >>= void . walletsNotifyBlock [alice, bob]
    update

    let contract = CommitCash (IdentCC 1) (PubKey 2) (ValueFromOracle oracle (Value 0)) 128 256
            (Pay (IdentPay 1) (PubKey 2) (PubKey 1) (Committed (IdentCC 1)) 256 Null)
            Null

    let oracleValue = OracleValue (Signed (oracle, (Runtime.Height 2, 100)))

    [tx] <- walletAction alice (createContract contract 12)
    let txOut = head . filter (isPayToScriptOut . fst) . txOutRefs $ tx
    update
    assertIsValidated tx
    [tx] <- walletAction bob $ commit (PubKey 2) txOut [oracleValue] [] 100 256
    let txOut = head . filter (isPayToScriptOut . fst) . txOutRefs $ tx
    update
    assertIsValidated tx
    [tx] <- walletAction alice (receivePayment txOut 100)
    let txOut@(txo, _) = head . filter (isPayToScriptOut . fst) . txOutRefs $ tx
    update
    assertIsValidated tx

    let (PayToScript (DataScript _)) = txOutType txo

    [tx] <- walletAction alice (endContract txOut)
    update
    assertIsValidated tx
    assertOwnFundsEq alice 1100
    assertOwnFundsEq bob 677
    return ()