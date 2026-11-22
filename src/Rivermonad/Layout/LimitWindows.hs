{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- | Show at most a number of windows, as in @XMonad.Layout.LimitWindows@;
-- the rest wait hidden. The focused window is always among the ones
-- shown.
--
-- > layoutHook = Layout (limitWindows 3 tiled ||| Full)
-- > , ("M-[", decreaseLimit), ("M-]", increaseLimit)
module Rivermonad.Layout.LimitWindows
  ( limitWindows
  , increaseLimit
  , decreaseLimit
  , setLimit
  , LimitWindows
  , LimitChange (..)
  ) where

import Rivermonad.Core
import Rivermonad.Layout.LayoutModifier
import Rivermonad.Operations (sendMessage)
import qualified Rivermonad.StackSet as W

limitWindows :: Int -> l a -> ModifiedLayout LimitWindows l a
limitWindows n = ModifiedLayout (LimitWindows (max 1 n))

newtype LimitWindows a = LimitWindows Int deriving (Show, Read)

data LimitChange = LimitInc Int | LimitSet Int deriving (Show, Eq)

instance Message LimitChange

increaseLimit, decreaseLimit :: X ()
increaseLimit = sendMessage (LimitInc 1)
decreaseLimit = sendMessage (LimitInc (-1))

setLimit :: Int -> X ()
setLimit = sendMessage . LimitSet

instance LayoutModifier LimitWindows Window where
  modifyLayout (LimitWindows n) (W.Workspace i l ms) r =
    runLayout (W.Workspace i l (fmap limit ms)) r
    where
      limit (W.Stack f u d)
        | length u < n = W.Stack f u (take (n - 1 - length u) d)
        -- the focus is beyond the limit: the first n-1 and the focus
        | otherwise = W.Stack f (reverse (take (n - 1) (reverse u))) []
  pureMess (LimitWindows n) m = fromMessage m >>= \case
    LimitInc k -> Just (LimitWindows (max 1 (n + k)))
    LimitSet k -> Just (LimitWindows (max 1 k))
  modifierDescription _ = ""
