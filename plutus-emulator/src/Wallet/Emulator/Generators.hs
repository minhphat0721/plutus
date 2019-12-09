{-# LANGUAGE Rank2Types #-}
module Wallet.Emulator.Generators(
      runTrace
    , runTraceOn
    ) where

import           Hedgehog

import           Wallet.Emulator   as Emulator
import           Wallet.Generators (GeneratorModel, Mockchain (Mockchain), genMockchain')


-- | Run an emulator trace on a mockchain.
runTrace ::
    Mockchain
    -> Trace a
    -> (Either AssertionError a, EmulatorState)
runTrace (Mockchain ch _) = Emulator.runTraceTxPool ch

-- | Run an emulator trace on a mockchain generated by the model.
runTraceOn :: MonadGen m
    => GeneratorModel
    -> Trace a
    -> m (Either AssertionError a, EmulatorState)
runTraceOn gm t = flip runTrace t <$> genMockchain' gm
