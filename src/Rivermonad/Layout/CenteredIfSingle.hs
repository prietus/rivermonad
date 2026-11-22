{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- | A window alone on the workspace is not stretched across the whole
-- screen but centered, as in @XMonad.Layout.CenteredIfSingle@. On a wide
-- or 4K monitor this keeps a single editor or browser at a readable width.
--
-- > tiled = centeredIfSingle 0.6 1 (Tall 1 (3/100) (3/5))
--
-- The ratios are of the width and height of the area; @1@ keeps that
-- dimension as it was. With two or more windows the layout is unchanged.
module Rivermonad.Layout.CenteredIfSingle
  ( centeredIfSingle
  , CenteredIfSingle (..)
  ) where

import Rivermonad.Core
import Rivermonad.Layout.LayoutModifier

centeredIfSingle :: Double -> Double -> l a -> ModifiedLayout CenteredIfSingle l a
centeredIfSingle rx ry = ModifiedLayout (CenteredIfSingle rx ry)

data CenteredIfSingle a = CenteredIfSingle !Double !Double deriving (Show, Read)

instance LayoutModifier CenteredIfSingle a where
  pureModifier (CenteredIfSingle rx ry) area _ [(w, _)] = ([(w, centered rx ry area)], Nothing)
  pureModifier _ _ _ wrs = (wrs, Nothing)

-- | A rectangle of the given fractions of @r@, centered in it.
centered :: Double -> Double -> Rectangle -> Rectangle
centered rx ry (Rectangle x y w h) = Rectangle (x + (w - w') `div` 2) (y + (h - h') `div` 2) w' h'
  where
    w' = scale rx w
    h' = scale ry h
    scale k n = max 1 (min n (round (k * fromIntegral n)))
