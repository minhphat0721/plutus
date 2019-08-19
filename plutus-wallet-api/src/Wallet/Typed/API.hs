{-# LANGUAGE ConstraintKinds     #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE DerivingStrategies  #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}
{-# OPTIONS_GHC -fno-omit-interface-pragmas #-}
{-# OPTIONS_GHC -fno-ignore-interface-pragmas #-}
module Wallet.Typed.API where

import qualified Language.PlutusTx    as PlutusTx
import qualified Ledger               as L
import           Ledger.AddressMap
import           Ledger.Tx
import qualified Ledger.Typed.Tx      as Typed
import           Ledger.Value
import           Wallet.API           (SlotRange, WalletAPI, WalletAPIError)
import qualified Wallet.API           as WAPI

import           Control.Lens
import           Control.Monad.Except

import           Data.Either
import qualified Data.Map             as Map
import           Data.Maybe
import qualified Data.Set             as Set
import qualified Data.Text            as T

signTxAndSubmit
    :: forall ins outs m .
    (Monad m, WalletAPI m, MonadError WalletAPIError m)
    => Typed.TypedTx ins outs
    -> m (Typed.TypedTx ins outs)
signTxAndSubmit tx = do
    _ <- WAPI.signTxAndSubmit $ Typed.toUntypedTx tx
    pure tx

makeScriptPayment
    :: forall a m .
    (Monad m, WalletAPI m, MonadError WalletAPIError m)
    => Typed.ScriptInstance a
    -> SlotRange
    -> Value
    -> PlutusTx.CompiledCode (Typed.DataType a)
    -> m (Typed.TypedTx '[] '[a])
makeScriptPayment ct range v ds = do
    (i, ownChange) <- WAPI.createPaymentWithChange v
    (ins, change) <- either (WAPI.throwOtherError . T.pack . show) pure $ do
        ins <- traverse Typed.typePubKeyTxIn (Set.toList i)
        change <- traverse Typed.typePubKeyTxOut ownChange
        pure (ins, change)
    let out = Typed.makeTypedScriptTxOut @a ct ds v
        tyTx = Typed.addTypedTxOut @'[] @a out (Typed.baseTx { Typed.tyTxValidRange = range, Typed.tyTxPubKeyTxIns = ins, Typed.tyTxPubKeyTxOuts = maybeToList change })
    pure tyTx

payToScript
    :: forall a m .
    (WalletAPI m, MonadError WalletAPIError m)
    => Typed.ScriptInstance a
    -> SlotRange
    -> Value
    -> PlutusTx.CompiledCode (Typed.DataType a)
    -> m (Typed.TypedTx '[] '[a])
payToScript ct range v ds = makeScriptPayment ct range v ds >>= signTxAndSubmit

payToScript_
    :: forall a m .
    (WalletAPI m, MonadError WalletAPIError m)
    => Typed.ScriptInstance a
    -> SlotRange
    -> Value
    -> PlutusTx.CompiledCode (Typed.DataType a)
    -> m ()
payToScript_ ct range v ds = void $ payToScript ct range v ds

spendScriptOutputs
    :: forall a outs m
    . (Monad m, WalletAPI m, PlutusTx.Typeable (Typed.DataType a))
    => Typed.ScriptInstance a
    -> PlutusTx.CompiledCode (Typed.RedeemerFunctionType outs a)
    -> m [(Typed.TypedScriptTxIn outs a, Value)]
spendScriptOutputs ct red = do
    am <- WAPI.watchedAddresses
    let
        addr = Typed.scriptAddress ct
        utxo :: Map.Map TxOutRef TxOut
        utxo = fromMaybe Map.empty $ am ^. at addr
        refs :: [(TxOutRef, TxOut)]
        refs = Map.toList utxo
        typeRef :: (TxOutRef, TxOut) -> Either Typed.ConnectionError (Typed.TypedScriptTxOutRef a, Value)
        typeRef (ref, out) = do
            tyRef <- Typed.typeScriptTxOutRef @a (\refq -> Map.lookup refq utxo) ct ref
            pure (tyRef, view outValue out)
        typedRefs :: [(Typed.TypedScriptTxOutRef a, Value)]
        typedRefs = rights $ typeRef <$> refs
        typedIns :: [(Typed.TypedScriptTxIn outs a, Value)]
        typedIns = (\(ref, v) -> (Typed.makeTypedScriptTxIn @a @outs ct red ref, v)) <$> typedRefs

    pure typedIns

-- | Given the pay to script address of the 'ValidatorScript', collect from it
--   all the outputs that match a predicate, using the 'RedeemerScript'.
collectFromScriptFilter ::
    forall a
    . (PlutusTx.Typeable (Typed.DataType a))
    => (TxOutRef -> TxOut -> Bool)
    -> AddressMap
    -> Typed.ScriptInstance a
    -> PlutusTx.CompiledCode (Typed.RedeemerType a)
    -> Typed.TypedTxSomeIns '[]
collectFromScriptFilter flt am si@(Typed.Validator vls) red =
    let adr     = L.scriptAddress $ L.ValidatorScript $ L.fromCompiledCode vls
        utxo :: Map.Map TxOutRef TxOut
        utxo    = fromMaybe Map.empty $ am ^. at adr
        ourUtxo :: [(TxOutRef, TxOut)]
        ourUtxo = Map.toList $ Map.filterWithKey flt utxo
        refs :: [TxOutRef]
        refs = fst <$> ourUtxo
        -- We just throw away any outputs at this script address that don't typecheck.
        -- TODO: we should log this, it would make debugging much easier
        typedRefs :: [Typed.TypedScriptTxOutRef a]
        typedRefs = rights $ Typed.typeScriptTxOutRef @a (\ref -> Map.lookup ref utxo) si <$> refs
        typedIns :: [Typed.TypedScriptTxIn '[] a]
        typedIns = Typed.makeTypedScriptTxIn @a @'[] si red <$> typedRefs
    -- We need to add many txins and we've done as much checking as we care to, so we switch to TypedTxSomeIns
    in Typed.addManyTypedTxIns typedIns Typed.baseTx
