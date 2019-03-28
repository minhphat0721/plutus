{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts   #-}
{-# LANGUAGE FlexibleInstances  #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Ledger.Types(
    -- * Basic types
    Value,
    Ada,
    Slot(..),
    SlotRange,
    lastSlot,
    TxIdOf(..),
    TxId,
    PubKey(..),
    Signature(..),
    signedBy,
    -- ** Addresses
    AddressOf(..),
    Address,
    pubKeyAddress,
    scriptAddress,
    -- ** Scripts
    Script,
    scriptSize,
    fromCompiledCode,
    compileScript,
    lifted,
    applyScript,
    evaluateScript,
    ValidatorScript(..),
    RedeemerScript(..),
    DataScript(..),
    -- * Transactions
    Tx(..),
    TxStripped(..),
    strip,
    preHash,
    hashTx,
    dataTxo,
    TxInOf(..),
    TxInType(..),
    TxIn,
    TxOutOf(..),
    TxOutType(..),
    TxOut,
    TxOutRefOf(..),
    TxOutRef,
    pubKeyTxIn,
    scriptTxIn,
    pubKeyTxOut,
    scriptTxOut,
    isPubKeyOut,
    isPayToScriptOut,
    txOutRefs,
    -- * Blockchain & UTxO model
    Block,
    Blockchain,
    ValidationData(..),
    transaction,
    out,
    value,
    unspentOutputsTx,
    spentOutputs,
    unspentOutputs,
    updateUtxo,
    txOutPubKey,
    pubKeyTxo,
    validValuesTx,
    -- * Scripts
    unitRedeemer,
    unitData,
    runScript,
    -- * Lenses
    inputs,
    outputs,
    outAddress,
    outValue,
    outType,
    inRef,
    inType,
    inScripts,
    inSignature,
    validRange
    ) where

import           Control.Monad                            (join)
import           Data.Map                                 (Map)
import qualified Data.Map                                 as Map
import           Data.Maybe                               (listToMaybe)

import           Ledger.Crypto
import           Ledger.Slot                              (Slot(..), SlotRange)
import           Ledger.Scripts
import           Ledger.Ada                               (Ada)
import           Ledger.Value                             (Value)
import           Ledger.Tx

-- | The slot number of the last slot of a blockchain. Assumes that each slot
--   has precisely one block. This is true in the
--   emulator but not necessarily on the real chain.
lastSlot :: Blockchain -> Slot
lastSlot = Slot . length

-- | A block on the blockchain. This is just a list of transactions which
-- successfully validate following on from the chain so far.
type Block = [Tx]
-- | A blockchain, which is just a list of blocks, starting with the newest.
type Blockchain = [Block]

-- | Lookup a transaction in a 'Blockchain' by its id.
transaction :: Blockchain -> TxId -> Maybe Tx
transaction bc txid = listToMaybe $ filter p  $ join bc where
    p = (txid ==) . hashTx

-- | Determine the unspent output that an input refers to
out :: Blockchain -> TxOutRef -> Maybe TxOut
out bc o = do
    t <- transaction bc (txOutRefId o)
    let i = txOutRefIdx o
    if length (txOutputs t) <= i
        then Nothing
        else Just $ txOutputs t !! i

-- | Determine the unspent value that a transaction output refers to.
value :: Blockchain -> TxOutRef -> Maybe Value
value bc o = txOutValue <$> out bc o

-- | Determine the data script that a transaction output refers to.
dataTxo :: Blockchain -> TxOutRef -> Maybe DataScript
dataTxo bc o = txOutData =<< out bc o

-- | Determine the public key that locks a transaction output, if there is one.
pubKeyTxo :: Blockchain -> TxOutRef -> Maybe PubKey
pubKeyTxo bc o = out bc o >>= txOutPubKey

-- | The unspent transaction outputs of the ledger as a whole.
unspentOutputs :: Blockchain -> Map TxOutRef TxOut
unspentOutputs = foldr updateUtxo Map.empty . join
