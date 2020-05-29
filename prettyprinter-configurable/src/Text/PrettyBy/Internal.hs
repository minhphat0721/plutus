{-# LANGUAGE ConstraintKinds            #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DefaultSignatures          #-}
{-# LANGUAGE DerivingStrategies         #-}
{-# LANGUAGE DerivingVia                #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE TypeApplications           #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}
{-# LANGUAGE UndecidableInstances       #-}

module Text.PrettyBy.Internal
    ( PrettyBy (..)
    , IgnorePrettyConfig (..)
    , AttachPrettyConfig (..)
    , PrettyAny (..)
    , withAttachPrettyConfig
    , defaultPrettyFunctorBy
    , defaultPrettyBifunctorBy
    , HasPrettyDefaults
    , AttachDefaultPrettyConfig (..)
    , DefaultPrettyBy (..)
    , NonDefaultPrettyBy (..)
    , PrettyDefaultBy
    , PrettyCommon (..)
    , ThrowOnStuck
    , HasPrettyDefaultsStuckError
    , NonStuckHasPrettyDefaults
    , DispatchPrettyDefaultBy (..)
    ) where

import           Text.Pretty

import           Data.Bifunctor
import           Data.Coerce
import           Data.Functor.Const
import           Data.Functor.Identity
import           Data.Int
import           Data.List.NonEmpty    (NonEmpty (..))
import           Data.Maybe
import qualified Data.Text             as Strict
import qualified Data.Text.Lazy        as Lazy
import           Data.Void
import           Data.Word
import           GHC.Natural
import           GHC.TypeLits

-- **********
-- ** Core **
-- **********

-- | A class for pretty-printing values in a configurable manner.
--
-- Here's a basic example:
--
-- >>> data Case = UpperCase | LowerCase
-- >>> data D = D
-- >>> instance PrettyBy Case D where prettyBy UpperCase D = "D"; prettyBy LowerCase D = "d"
-- >>> prettyBy UpperCase D
-- D
-- >>> prettyBy LowerCase D
-- d
--
-- The library provides instances for common types like 'Integer' or 'Bool', so you can't define
-- your own @PrettyBy SomeConfig Integer@ instance. And for the same reason you should not define
-- instances like @PrettyBy SomeAnotherConfig a@ for universally quantified @a@, because such an
-- instance would overlap with the existing ones. This is the reason why the library does not
-- provide this kind of config: TODO: rephrase
--
-- >>> data ViaShow = ViaShow
-- >>> instance Show a => PrettyBy ViaShow a where prettyBy ViaShow = pretty . show
--
-- With such an instance @prettyBy ViaShow (1 :: Int)@ throws an error about overlapping instances:
--
-- > • Overlapping instances for PrettyBy ViaShow Int
-- >     arising from a use of ‘prettyBy’
-- >   Matching instances:
-- >     instance PrettyDefaultBy config Int => PrettyBy config Int
-- >     instance [safe] Show a => PrettyBy ViaShow a
--
-- There's a @newtype@ provided specifically for the purpose of defining a 'PrettyBy' instance for
-- any 'a': 'PrettyAny'. Read its docs for details on when you might want to use it.
--
-- The 'PrettyBy' instance for common types is defined in a way that allows to override default
-- pretty-printing behaviour, read the docs of 'HasPrettyDefaults' for details.
class PrettyBy config a where

    -- | Pretty-print a value of type @a@ the way a @config@ specifies it.
    -- The default implementation of 'prettyBy' is in terms of 'pretty'.
    prettyBy :: config -> a -> Doc ann
    default prettyBy :: Pretty a => config -> a -> Doc ann
    prettyBy _ = pretty

    -- | 'prettyListBy' is used to define the default 'PrettyBy' instance for @[a]@ and @NonEmpty a@.
    -- In normal circumstances only the 'prettyBy' function is used.
    -- The default implementation of 'prettyListBy' is in terms of 'prettyList'.
    prettyListBy :: config -> [a] -> Doc ann
    default prettyListBy :: config -> [a] -> Doc ann
    prettyListBy = defaultPrettyFunctorBy

-- Interop with 'Pretty'.

-- | A newtype wrapper around @a@ whose point is to provide a @PrettyBy config@ instance
-- for anything that has a 'Pretty' instance.
newtype IgnorePrettyConfig a = IgnorePrettyConfig
    { unIgnorePrettyConfig :: a
    } deriving newtype (Pretty)

-- |
-- >>> data C = C
-- >>> data D = D
-- >>> instance Pretty D where pretty D = "D"
-- >>> prettyBy C $ IgnorePrettyConfig D
-- D
instance Pretty a => PrettyBy config (IgnorePrettyConfig a)

-- | A config together with some value. The point is to provide a 'Pretty' instance
-- for anything that has a @PrettyBy config@ instance.
data AttachPrettyConfig config a = AttachPrettyConfig !config !a

-- |
-- >>> data C = C
-- >>> data D = D
-- >>> instance PrettyBy C D where prettyBy C D = "D"
-- >>> pretty $ AttachPrettyConfig C D
-- D
instance PrettyBy config a => Pretty (AttachPrettyConfig config a) where
    pretty (AttachPrettyConfig config x) = prettyBy config x

withAttachPrettyConfig
    :: config -> ((forall a. a -> AttachPrettyConfig config a) -> r) -> r
withAttachPrettyConfig config k = k $ AttachPrettyConfig config

-- TODO: Fix the docs.
-- -- | This class is used in order to provide default implementations of 'PrettyM' for
-- -- particular @config@s. Whenever a @Config@ is a sum type of @Subconfig1@, @Subconfig2@, etc,
-- -- we can define a single 'DefaultPrettyM' instance and then derive @PrettyM Config a@ for each
-- -- @a@ provided the @a@ implements the @PrettyM Subconfig1@, @PrettyM Subconfig2@, etc instances.
-- --
-- -- Example:
-- --
-- -- > data Config = Subconfig1 Subconfig1 | Subconfig2 Subconfig2
-- -- >
-- -- > instance (PrettyM Subconfig1 a, PrettyM Subconfig2 a) => DefaultPrettyM Config a where
-- -- >     defaultPrettyM (Subconfig1 subconfig1) = prettyBy subconfig1
-- -- >     defaultPrettyM (Subconfig2 subconfig2) = prettyBy subconfig2
-- --
-- -- Now having in scope  @PrettyM Subconfig1 A@ and @PrettyM Subconfig2 A@
-- -- and the same instances for @B@ we can write
-- --
-- -- > instance PrettyM Config A
-- -- > instance PrettyM Config B
-- --
-- -- and the instances will be derived for us.
newtype PrettyAny a = PrettyAny
    { unPrettyAny :: a
    }

-- | Default configurable pretty-printing for a 'Functor' in terms of 'Pretty'
-- (attaches the config to each value in the functor).
defaultPrettyFunctorBy
    :: (Functor f, Pretty (f (AttachPrettyConfig config a)))
    => config -> f a -> Doc ann
defaultPrettyFunctorBy config a =
    pretty $ AttachPrettyConfig config <$> a

-- | Default configurable pretty-printing for a 'Bifunctor' in terms of 'Pretty'
-- (attaches the config to each value in the bifunctor).
defaultPrettyBifunctorBy
    :: (Bifunctor f, Pretty (f (AttachPrettyConfig config a) (AttachPrettyConfig config b)))
    => config -> f a b -> Doc ann
defaultPrettyBifunctorBy config a =
    withAttachPrettyConfig config $ \attach -> pretty $ bimap attach attach a

-- | Determines whether a pretty-printing config allows default pretty-printing for types that
-- support it. I.e. it's possible to create a new config and get access to pretty-printing for
-- all types supporting default pretty-printing just by providing the right type instance. E.g.
--
-- >>> data Def = Def
-- >>> type instance HasPrettyDefaults Def = 'True
-- >>> prettyBy Def (['a', 'b', 'c'], (1 :: Int), Just True)
-- (abc, 1, True)
--
-- The set of types supporting default pretty-printing is determined by the @prettyprinter@
-- library: whatever __there__ has a 'Pretty' instance also supports default pretty-printing
-- in this library and the behavior of @pretty x@ and @prettyBy <config_with_defaults> x@ must
-- be identical when @x@ is one of such types.
--
-- It is possible to override default pretty-printing. For this you need to specify that
-- 'HasPrettyDefaults' is @'False@ for your config and then define a @NonDefaultPrettyBy config@
-- instance for each of the types supporting default pretty-printing that you want to pretty-print
-- values of. Note that once 'HasPrettyDefaults' is specified to be @'False@,
-- __all defaults are lost__ for your config, so you can't override default pretty-printing for one
-- type and keep the defaults for all others. I.e. if you have
--
-- >>> data NonDef = NonDef
-- >>> type instance HasPrettyDefaults NonDef = 'False
--
-- then you have no defaults available and an attempt to pretty-print a value of a type supporting
-- default pretty-printing
--
-- > prettyBy NonDef True
--
-- results in a type error:
--
-- > • No instance for (NonDefaultPrettyBy NonDef Bool)
-- >      arising from a use of ‘prettyBy’
--
-- As the error suggests you need to provide a 'NonDefaultPrettyBy' instance explicitly:
--
-- >>> instance NonDefaultPrettyBy NonDef Bool where nonDefaultPrettyBy _ b = if b then "t" else "f"
-- >>> prettyBy NonDef True
-- t
--
-- It is also possible not to provide any implementation for 'nonDefaultPrettyBy', in which case
-- it defaults to being the default pretty-printing for the given type. This can be useful to
-- recover default pretty-printing for types pretty-printing of which you don't want to override:
--
-- >>> instance NonDefaultPrettyBy NonDef Int
-- >>> prettyBy NonDef (123 :: Int)
-- 123
--
-- We could give the user more fine-grained control of what defaults to override instead of
-- requiring to explicitly provide all the instances whenever there's a need to override any
-- default behavior, but that would complicate the library even more, so we opted for not doing
-- that at the moment.
--
-- Note that you can always override default behavior by wrapping a type in @newtype@ and
-- providing a @PrettyBy <config_name>@ instance for that @newtype@.
--
-- Also note that if you want to extend the set of types supporting default pretty-printing
-- it's not enough to provide a 'Pretty' instance for your type (such logic is hardly expressible
-- in present day Haskell). Read docs of 'DefaultPrettyBy' for how to extend the set of types
-- supporting default pretty-printing.
type family HasPrettyDefaults config :: Bool

-- | @prettyBy ()@ works like @pretty@ for types supporting default pretty-printing.
type instance HasPrettyDefaults () = 'True

-- ###################################################
-- ## The 'DefaultPrettyBy' class and its instances ##
-- ###################################################

-- | Same as 'AttachPrettyConfig', but for providing a 'Pretty' instance for anything that has
-- a 'DefaultPrettyBy' instance. Needed for the default implementation of 'defaultPrettyListBy'.
data AttachDefaultPrettyConfig config a = AttachDefaultPrettyConfig !config !a

instance DefaultPrettyBy config a => Pretty (AttachDefaultPrettyConfig config a) where
    pretty (AttachDefaultPrettyConfig config x) = defaultPrettyBy config x

class DefaultPrettyBy config a where
    defaultPrettyBy :: config -> a -> Doc ann
    default defaultPrettyBy :: Pretty a => config -> a -> Doc ann
    defaultPrettyBy _ = pretty

    defaultPrettyListBy :: config -> [a] -> Doc ann
    default defaultPrettyListBy :: config -> [a] -> Doc ann
    defaultPrettyListBy config = pretty . map (AttachDefaultPrettyConfig config)

instance PrettyBy config Strict.Text => DefaultPrettyBy config Char where
    defaultPrettyListBy config = prettyBy config . Strict.pack

instance PrettyBy config a => DefaultPrettyBy config (Maybe a) where
    defaultPrettyBy = defaultPrettyFunctorBy
    defaultPrettyListBy config = prettyListBy config . catMaybes

instance PrettyBy config a => DefaultPrettyBy config [a] where
    defaultPrettyBy = prettyListBy

instance PrettyBy config a => DefaultPrettyBy config (NonEmpty a) where
    defaultPrettyBy config (x :| xs) = prettyListBy config (x : xs)

instance DefaultPrettyBy config Void
instance DefaultPrettyBy config ()
instance DefaultPrettyBy config Bool
instance DefaultPrettyBy config Natural
instance DefaultPrettyBy config Integer
instance DefaultPrettyBy config Int
instance DefaultPrettyBy config Int8
instance DefaultPrettyBy config Int16
instance DefaultPrettyBy config Int32
instance DefaultPrettyBy config Int64
instance DefaultPrettyBy config Word
instance DefaultPrettyBy config Word8
instance DefaultPrettyBy config Word16
instance DefaultPrettyBy config Word32
instance DefaultPrettyBy config Word64
instance DefaultPrettyBy config Float
instance DefaultPrettyBy config Double
instance DefaultPrettyBy config Strict.Text
instance DefaultPrettyBy config Lazy.Text

instance PrettyBy config a => DefaultPrettyBy config (Identity a) where
    defaultPrettyBy = defaultPrettyFunctorBy

instance (PrettyBy config a, PrettyBy config b) => DefaultPrettyBy config (a, b) where
    defaultPrettyBy = defaultPrettyBifunctorBy

instance (PrettyBy config a, PrettyBy config b, PrettyBy config c) =>
            DefaultPrettyBy config (a, b, c) where
    defaultPrettyBy config (x, y, z) =
        withAttachPrettyConfig config $ \attach -> pretty (attach x, attach y, attach z)

instance PrettyBy config a => DefaultPrettyBy config (Const a b) where
    defaultPrettyBy config a =
       withAttachPrettyConfig config $ \attach -> pretty $ first attach a

-- ###########################################################
-- ## The 'NonDefaultPrettyBy' class and its none instances ##
-- ###########################################################

-- | A class for overriding default pretty-printing behavior for types having it.
class NonDefaultPrettyBy config a where

    -- | Pretty-print a value of a type supporting default pretty-printing in a possibly
    -- non-default way. The "possibly" is due to 'nonDefaultPrettyBy' having a default
    -- implementation in terms of 'defaultPrettyBy'. See docs for 'HasPrettyDefaults' for details.
    nonDefaultPrettyBy :: config -> a -> Doc ann
    default nonDefaultPrettyBy :: DefaultPrettyBy config a => config -> a -> Doc ann
    nonDefaultPrettyBy = defaultPrettyBy

    -- | 'nonDefaultPrettyListBy' to 'prettyListBy' is what 'nonDefaultPrettyBy' to 'prettyBy'.
    -- Analogously, the default implementation is in terms 'defaultPrettyListBy'.
    nonDefaultPrettyListBy :: config -> [a] -> Doc ann
    default nonDefaultPrettyListBy :: DefaultPrettyBy config a => config -> [a] -> Doc ann
    nonDefaultPrettyListBy = defaultPrettyListBy

-- ####################################################################
-- ## Dispatching between 'DefaultPrettyBy' and 'NonDefaultPrettyBy' ##
-- ####################################################################

-- | 'DispatchPrettyDefaultBy' is a class for dispatching on @HasPrettyDefaults config@:
-- if it's @'True@, then 'dispatchPrettyDefaultBy' is instantiated as 'defaultPrettyBy',
-- otherwise as 'nonDefaultPrettyBy' (and similarly for 'dispatchPrettyDefaultListBy').
-- I.e. depending on whether a config allows to pretty-print values using default
-- pretty-printing, either the default or non-default pretty-printing strategy is used.
class HasPrettyDefaults config ~ b => DispatchPrettyDefaultBy (b :: Bool) config a where
    dispatchPrettyDefaultBy     :: config -> a   -> Doc ann
    dispatchPrettyDefaultListBy :: config -> [a] -> Doc ann

instance (HasPrettyDefaults config ~ 'True, DefaultPrettyBy config a) =>
            DispatchPrettyDefaultBy 'True config a where
    dispatchPrettyDefaultBy     = defaultPrettyBy
    dispatchPrettyDefaultListBy = defaultPrettyListBy

instance (HasPrettyDefaults config ~ 'False, NonDefaultPrettyBy config a) =>
            DispatchPrettyDefaultBy 'False config a where
    dispatchPrettyDefaultBy     = nonDefaultPrettyBy
    dispatchPrettyDefaultListBy = nonDefaultPrettyListBy

{- Note [Definition of PrettyDefaultBy]
A class alias throws "this makes type inference for inner bindings fragile" warnings
in user code, so we opt for a type alias in the definition of 'PrettyDefaultBy'.

I also tried the following representation

    class PrettyDefaultBy config a where
        type HasPrettyDefaults config :: Bool
        prettyDefaultsBy :: config -> a -> Doc ann
        prettyDefaultsListBy :: config -> [a] -> Doc ann

with both the methods having default implementations in terms of methods of the
'DispatchPrettyDefaultBy' class, so that 'PrettyDefaultBy' does not unwind to a creepy
type in errors, but then the user has to write things like

    instance DefaultPrettyBy () a => PrettyDefaultBy () a where
        type HasPrettyDefaults () = 'True

which is wordy and leaks 'DefaultPrettyBy' to the user, which is something that the user
does not see otherwise.

Instead, we fix the problem of 'PrettyDefaultBy' unwinding to a creepy type by using a custom
type error, 'HasPrettyDefaultsStuckError', which is thrown whenever @HasPrettyDefaults config@
is stuck. This way the user's code either type checks or gives a nice error and so the whole
'DispatchPrettyDefaultBy' thing does not leak to the user.

See https://kcsongor.github.io/report-stuck-families for how detection of a stuck type family
application is implemented.
-}

type family ThrowOnStuck err (b :: Bool) :: Bool where
    ThrowOnStuck _   'True  = 'True
    ThrowOnStuck _   'False = 'False
    ThrowOnStuck err _      = err

-- We have to use a type family here rather than a type alias, because otherwise it evaluates too early.
type family HasPrettyDefaultsStuckError config :: Bool where
    HasPrettyDefaultsStuckError config = TypeError
        (     'Text "No ’HasPrettyDefaults’ is specified for " ':<>: 'ShowType config
        ':$$: 'Text "Either you're trying to derive an instance, in which case you have to use"
        ':$$: 'Text "  standalone deriving and need to explicitly put a ‘PrettyDefaultBy config’"
        ':$$: 'Text "  constraint in the instance context for each type in your data type"
        ':$$: 'Text "  that supports default pretty-printing"
        ':$$: 'Text "Or you're trying to pretty-print a value of a type supporting default"
        ':$$: 'Text "  pretty-printing using a config, for which ‘HasPrettyDefaults’ is not specified."
        ':$$: 'Text "  If the config is a bound type variable, then you need to add"
        ':$$: 'Text "    ‘HasPrettyDefaults <config_variable_name> ~ 'True’"
        ':$$: 'Text "  to the context."
        ':$$: 'Text "  If the config is a data type, then you need to add"
        ':$$: 'Text "    ‘type instance HasPrettyDefaults <config_name> = 'True’"
        ':$$: 'Text "  at the top level."
        )

-- | A version of 'HasPrettyDefaults' that is never stuck: it either immediately evaluates
-- to a 'Bool' or fails with a 'TypeError'.
type NonStuckHasPrettyDefaults config =
    ThrowOnStuck (HasPrettyDefaultsStuckError config) (HasPrettyDefaults config)

-- See Note [Definition of PrettyDefaultBy].
-- | @PrettyDefaultBy config a@ is what we implement @PrettyBy config a@ in terms of,
-- when @a@ supports default pretty-printing.
-- Thus @PrettyDefaultBy config a@ and @PrettyBy config a@ are interchangeable constraints
-- for such types, but the latter throws an annoying \"this makes type inference for inner
-- bindings fragile\" warning, unlike the former.
type PrettyDefaultBy config = DispatchPrettyDefaultBy (NonStuckHasPrettyDefaults config) config

-- | A newtype wrapper defined for its 'PrettyBy' instance that allows to via-derive a 'PrettyBy'
-- instance for a type supporting default pretty-printing.
newtype PrettyCommon a = PrettyCommon
    { unPrettyCommon :: a
    }

coerceDispatchPrettyDefaults :: Coercible a b => (config -> a -> Doc ann) -> config -> b -> Doc ann
coerceDispatchPrettyDefaults = coerce

instance PrettyDefaultBy config a => PrettyBy config (PrettyCommon a) where
    prettyBy     = coerceDispatchPrettyDefaults @a   dispatchPrettyDefaultBy
    prettyListBy = coerceDispatchPrettyDefaults @[a] dispatchPrettyDefaultListBy

-- #######################################################################
-- ## 'PrettyBy' instances for types supporting default pretty-printing ##
-- #######################################################################

-- |
-- >>> prettyBy () ([] :: [Void])
-- []
deriving via PrettyCommon Void
    instance PrettyDefaultBy config Void => PrettyBy config Void

-- |
-- >>> prettyBy () ()
-- ()
--
-- The argument is not used:
--
-- >>> prettyBy () (error "Strict?" :: ())
-- ()
deriving via PrettyCommon ()
    instance PrettyDefaultBy config () => PrettyBy config ()

-- |
-- >>> prettyBy () True
-- True
deriving via PrettyCommon Bool
    instance PrettyDefaultBy config Bool => PrettyBy config Bool

-- |
-- >>> prettyBy () (123 :: Natural)
-- 123
deriving via PrettyCommon Natural
    instance PrettyDefaultBy config Natural => PrettyBy config Natural

-- |
-- >>> prettyBy () (2^(123 :: Int) :: Integer)
-- 10633823966279326983230456482242756608
deriving via PrettyCommon Integer
    instance PrettyDefaultBy config Integer => PrettyBy config Integer

-- |
-- >>> prettyBy () (123 :: Int)
-- 123
deriving via PrettyCommon Int
    instance PrettyDefaultBy config Int => PrettyBy config Int
deriving via PrettyCommon Int8
    instance PrettyDefaultBy config Int8 => PrettyBy config Int8
deriving via PrettyCommon Int16
    instance PrettyDefaultBy config Int16 => PrettyBy config Int16
deriving via PrettyCommon Int32
    instance PrettyDefaultBy config Int32 => PrettyBy config Int32
deriving via PrettyCommon Int64
    instance PrettyDefaultBy config Int64 => PrettyBy config Int64
deriving via PrettyCommon Word
    instance PrettyDefaultBy config Word => PrettyBy config Word
deriving via PrettyCommon Word8
    instance PrettyDefaultBy config Word8 => PrettyBy config Word8
deriving via PrettyCommon Word16
    instance PrettyDefaultBy config Word16 => PrettyBy config Word16
deriving via PrettyCommon Word32
    instance PrettyDefaultBy config Word32 => PrettyBy config Word32
deriving via PrettyCommon Word64
    instance PrettyDefaultBy config Word64 => PrettyBy config Word64

-- |
-- >>> prettyBy () (pi :: Float)
-- 3.1415927
deriving via PrettyCommon Float
    instance PrettyDefaultBy config Float => PrettyBy config Float

-- |
-- >>> prettyBy () (pi :: Double)
-- 3.141592653589793
deriving via PrettyCommon Double
    instance PrettyDefaultBy config Double => PrettyBy config Double

-- | Automatically converts all newlines to @line@.
--
-- >>> prettyBy () ("hello\nworld" :: Strict.Text)
-- hello
-- world
deriving via PrettyCommon Strict.Text
    instance PrettyDefaultBy config Strict.Text => PrettyBy config Strict.Text

-- | An instance for lazy @Text@. Identitical to the strict one.
deriving via PrettyCommon Lazy.Text
    instance PrettyDefaultBy config Lazy.Text => PrettyBy config Lazy.Text

-- |
-- >>> prettyBy () (Identity True)
-- True
deriving via PrettyCommon (Identity a)
    instance PrettyDefaultBy config (Identity a) => PrettyBy config (Identity a)

-- |
-- >>> prettyBy () (False, "abc")
-- (False, abc)
deriving via PrettyCommon (a, b)
    instance PrettyDefaultBy config (a, b) => PrettyBy config (a, b)

-- |
-- >>> prettyBy () ('a', "bcd", True)
-- (a, bcd, True)
deriving via PrettyCommon (a, b, c)
    instance PrettyDefaultBy config (a, b, c) => PrettyBy config (a, b, c)

-- | Non-polykinded, because @Pretty (Const a b)@ is not polykinded either.
--
-- >>> prettyBy () (Const 1 :: Const Integer Bool)
-- 1
deriving via PrettyCommon (Const a b)
    instance PrettyDefaultBy config (Const a b) => PrettyBy config (Const a b)

-- | 'prettyBy' for @[a]@ is defined in terms of 'prettyListBy' by default.
--
-- >>> prettyBy () [True, False]
-- [True, False]
-- >>> prettyBy () "abc"
-- abc
-- >>> prettyBy () [Just False, Nothing, Just True]
-- [False, True]
deriving via PrettyCommon [a]
    instance PrettyDefaultBy config [a] => PrettyBy config [a]

-- | 'prettyBy' for @NonEmpty a@ is defined in terms of 'prettyListBy' by default.
--
-- >>> prettyBy () (True :| [False])
-- [True, False]
-- >>> prettyBy () ('a' :| "bc")
-- abc
-- >>> prettyBy () (Just False :| [Nothing, Just True])
-- [False, True]
deriving via PrettyCommon (NonEmpty a)
    instance PrettyDefaultBy config (NonEmpty a) => PrettyBy config (NonEmpty a)

-- | By default a 'String' (i.e. @[Char]@) is converted to a @Text@ first and then pretty-printed.
-- So make sure that if you have any non-default pretty-printing for @Char@ or @Text@,
-- they're in sync.
--
-- >>> prettyBy () 'a'
-- a
-- >>> prettyBy () "abc"
-- abc
deriving via PrettyCommon Char
    instance PrettyDefaultBy config Char => PrettyBy config Char

-- | By default a @[Maybe a]@ is converted to @[a]@ first and only then pretty-printed.
--
-- >>> braces $ prettyBy () (Just True)
-- {True}
-- >>> braces $ prettyBy () (Nothing :: Maybe Bool)
-- {}
-- >>> prettyBy () [Just False, Nothing, Just True]
-- [False, True]
-- >>> prettyBy () [Nothing, Just 'a', Just 'b', Nothing, Just 'c']
-- abc
deriving via PrettyCommon (Maybe a)
    instance PrettyDefaultBy config (Maybe a) => PrettyBy config (Maybe a)

-- $setup
--
-- (Definitions for the doctests)
--
-- >>> :set -XDataKinds
-- >>> :set -XFlexibleInstances
-- >>> :set -XMultiParamTypeClasses
-- >>> :set -XOverloadedStrings
-- >>> :set -XTypeFamilies
