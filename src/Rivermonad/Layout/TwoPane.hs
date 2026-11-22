{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- | Two windows side by side, as in @XMonad.Layout.TwoPane@: the master on
-- the left and the focused window on the right (or the next one, when the
-- master has the focus). The rest wait hidden; moving the focus brings
-- them to the right pane.
--
-- > layoutHook = Layout (TwoPane (3/100) (1/2) ||| tiled)
module Rivermonad.Layout.TwoPane
  ( TwoPane (..)
  ) where

import Rivermonad.Core
import Rivermonad.Layout
import qualified Rivermonad.StackSet as W

-- | Step for Shrink/Expand, and the master's share of the width.
data TwoPane a = TwoPane !Rational !Rational
  deriving (Show, Read)

instance LayoutClass TwoPane a where
  pureLayout (TwoPane _ split) r s = case reverse (W.up s) of
    master : _ -> [(master, left), (W.focus s, right)]
    [] -> case W.down s of
      next : _ -> [(W.focus s, left), (next, right)]
      [] -> [(W.focus s, r)]
    where (left, right) = splitHorizontallyBy split r
  pureMessage (TwoPane d split) m = fmap resize (fromMessage m)
    where
      resize Shrink = TwoPane d (max 0.05 (split - d))
      resize Expand = TwoPane d (min 0.95 (split + d))
  description _ = "TwoPane"
