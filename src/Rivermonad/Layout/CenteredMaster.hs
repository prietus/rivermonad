{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- | The master window floats over the others in the middle of the screen,
-- as in @XMonad.Layout.CenteredMaster@; the rest are tiled behind it by
-- the inner layout.
--
-- > layoutHook = Layout (centerMaster Grid ||| tiled)
--
-- With a single window it fills the area like any other layout.
module Rivermonad.Layout.CenteredMaster
  ( centerMaster
  , centerMasterWith
  , topRightMaster
  , CenteredMaster (..)
  ) where

import Rivermonad.Core
import Rivermonad.Layout.LayoutModifier
import Rivermonad.StackSet (Workspace (..))
import qualified Rivermonad.StackSet as W

-- | The master in the middle, 70% of the width and height.
centerMaster :: l a -> ModifiedLayout CenteredMaster l a
centerMaster = centerMasterWith 0.7 0.7

-- | The master in the middle, at the given fractions of the area.
centerMasterWith :: Double -> Double -> l a -> ModifiedLayout CenteredMaster l a
centerMasterWith rx ry = ModifiedLayout (CenteredMaster 0.5 0.5 rx ry)

-- | The master in the top-right corner, half the width and height.
topRightMaster :: l a -> ModifiedLayout CenteredMaster l a
topRightMaster = ModifiedLayout (CenteredMaster 1 0 0.5 0.5)

-- | Where (0 = left/top, 1 = right/bottom) and how big (fractions of the
-- area) the master is.
data CenteredMaster a = CenteredMaster !Double !Double !Double !Double
  deriving (Show, Read)

instance LayoutModifier CenteredMaster Window where
  modifyLayout (CenteredMaster px py rx ry) (Workspace i l ms) r =
    case W.integrate' ms of
      m : _ : _ -> do
        -- the others, tiled by the inner layout over the whole area (the
        -- focus stays where it was)
        (wrs, l') <- runLayout (Workspace i l (ms >>= W.filter (/= m))) r
        -- the master last, so it is stacked above them
        pure (wrs ++ [(m, piece px py rx ry r)], l')
      _ -> runLayout (Workspace i l ms) r

  modifierDescription _ = "Centered"

piece :: Double -> Double -> Double -> Double -> Rectangle -> Rectangle
piece px py rx ry (Rectangle x y w h) = Rectangle (x + round (px * fromIntegral (w - w'))) (y + round (py * fromIntegral (h - h'))) w' h'
  where
    w' = max 1 (round (rx * fromIntegral w))
    h' = max 1 (round (ry * fromIntegral h))
