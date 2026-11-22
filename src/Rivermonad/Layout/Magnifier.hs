{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- | The focused window is drawn bigger than its place in the layout, over
-- its neighbours, as in @XMonad.Layout.Magnifier@. Handy with many small
-- windows (a Grid of terminals).
--
-- > layoutHook = Layout (magnifier Grid ||| tiled)
-- > , ("M-S-=", sendMessage MagnifyMore), ("M-S--", sendMessage MagnifyLess)
-- > , ("M-S-z", sendMessage Toggle)
--
-- It stays inside the screen and does nothing with a single window.
module Rivermonad.Layout.Magnifier
  ( magnifier
  , magnifiercz
  , magnifierOff
  , MagnifyMsg (..)
  , Magnifier
  ) where

import Data.List (partition)

import Rivermonad.Core
import Rivermonad.Layout.LayoutModifier
import qualified Rivermonad.StackSet as W

-- | Magnify by 1.5.
magnifier :: l a -> ModifiedLayout Magnifier l a
magnifier = magnifiercz 1.5

-- | Magnify by a factor of your own.
magnifiercz :: Rational -> l a -> ModifiedLayout Magnifier l a
magnifiercz k = ModifiedLayout (Magnifier k True)

-- | Like 'magnifier', but off until it gets 'Toggle' or 'ToggleOn'.
magnifierOff :: l a -> ModifiedLayout Magnifier l a
magnifierOff = ModifiedLayout (Magnifier 1.5 False)

data Magnifier a = Magnifier !Rational !Bool deriving (Show, Read)

data MagnifyMsg = MagnifyMore | MagnifyLess | ToggleOn | ToggleOff | Toggle
  deriving (Show, Eq)

instance Message MagnifyMsg

instance LayoutModifier Magnifier Window where
  pureModifier (Magnifier k on) area ms wrs = case ms of
    Just st | on, length wrs > 1 ->
      case partition ((== W.focus st) . fst) wrs of
        ([(w, r)], others) -> (others ++ [(w, inside area (grow k r))], Nothing)
        _ -> (wrs, Nothing)
    _ -> (wrs, Nothing)
  pureMess (Magnifier k on) m = fromMessage m >>= \case
    MagnifyMore -> Just (Magnifier (k + 0.1) on)
    MagnifyLess -> Just (Magnifier (max 1 (k - 0.1)) on)
    ToggleOn -> Just (Magnifier k True)
    ToggleOff -> Just (Magnifier k False)
    Toggle -> Just (Magnifier k (not on))
  modifierDescription (Magnifier _ on) = if on then "Magnifier" else ""

-- | Bigger by the factor, around the same centre.
grow :: Rational -> Rectangle -> Rectangle
grow k (Rectangle x y w h) = Rectangle (x - (w' - w) `div` 2) (y - (h' - h) `div` 2) w' h'
  where
    w' = round (k * fromIntegral w)
    h' = round (k * fromIntegral h)

-- | Moved (and if needed shrunk) to fit in the area.
inside :: Rectangle -> Rectangle -> Rectangle
inside (Rectangle ax ay aw ah) (Rectangle x y w h) = Rectangle x' y' w' h'
  where
    w' = min w aw
    h' = min h ah
    x' = max ax (min x (ax + aw - w'))
    y' = max ay (min y (ay + ah - h'))
