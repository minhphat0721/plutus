module ContractHome.Lenses
  ( _status
  , _contracts
  , _selectedContractIndex
  , _selectedContract
  ) where

import Prelude
import Contract.Types (ContractId)
import Contract.Types (State) as Contract
import ContractHome.Types (ContractStatus, State)
import Data.Array as Array
import Data.Lens (Lens', Traversal', set, wander)
import Data.Lens.Record (prop)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Symbol (SProxy(..))

_status :: Lens' State ContractStatus
_status = prop (SProxy :: SProxy "status")

_contracts :: Lens' State (Map ContractId Contract.State)
_contracts = prop (SProxy :: SProxy "contracts")

_selectedContractIndex :: Lens' State (Maybe ContractId)
_selectedContractIndex = prop (SProxy :: SProxy "selectedContractIndex")

-- This traversal focus on a specific contract indexed by another property of the state
_selectedContract :: Traversal' State Contract.State
_selectedContract =
  wander \f state -> case state.selectedContractIndex of
    Just ix
      | Just contract <- Map.lookup ix state.contracts ->
        let
          updateContract contract' = Map.insert ix contract' state.contracts
        in
          (\contract' -> set _contracts (updateContract contract') state) <$> f contract
    _ -> pure state
