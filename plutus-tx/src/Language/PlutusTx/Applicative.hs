{-# LANGUAGE NoImplicitPrelude #-}
{-# OPTIONS_GHC -fno-omit-interface-pragmas #-}
module Language.PlutusTx.Applicative where

import           Language.PlutusTx.Functor
import           Prelude                   (Maybe (..))

{-# ANN module "HLint: ignore" #-}

infixl 4 <*>, <*, *>

class Functor f => Applicative f where
    {-# MINIMAL pure, (<*>) #-}
    -- | Lift a value.
    pure :: a -> f a

    -- | Sequential application.
    (<*>) :: f (a -> b) -> f a -> f b

{-# INLINABLE liftA2 #-}
-- | Lift a binary function to actions.
liftA2 :: Applicative f => (a -> b -> c) -> f a -> f b -> f c
liftA2 f x = (<*>) (fmap f x)

{-# INLINABLE (*>) #-}
-- | Sequence actions, discarding the value of the first argument.
(*>) :: Applicative f => f a -> f b -> f b
a1 *> a2 = (id <$ a1) <*> a2

{-# INLINABLE (<*) #-}
-- | Sequence actions, discarding the value of the second argument.
(<*) :: Applicative f => f a -> f b -> f a
(<*) = liftA2 const

{-# INLINABLE sequence #-}
-- | Sequence a list of applicative actions.
sequence :: Applicative f => [f a] -> f [a]
sequence []    = pure []
sequence (h:t) = (:) <$> h <*> sequence t

instance Applicative Maybe where
    {-# INLINABLE pure #-}
    pure = Just
    {-# INLINABLE (<*>) #-}
    Just f <*> Just x = Just (f x)
    _ <*> _ = Nothing
