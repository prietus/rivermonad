{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- | Maximise one window over the others without changing layout, as in
-- @XMonad.Layout.Maximize@; the same key brings it back.
--
-- > layoutHook = Layout (maximize (tiled ||| Mirror tiled))
-- > , ("M-<Backspace>", withFocused (sendMessage . maximizeRestore))
--
-- Unlike full screen, the bar and the gaps stay, and the other windows
-- keep their places behind it.
module Rivermonad.Layout.Maximize
  ( maximize
  , maximizeRestore
  , MaximizeRestore
  , Maximize
  ) where

import Data.List (partition)

import Rivermonad.Core
import Rivermonad.Layout.LayoutModifier

maximize :: l a -> ModifiedLayout Maximize l a
maximize = ModifiedLayout (Maximize Nothing)

newtype Maximize a = Maximize (Maybe a)

-- Window ids change when rivermonad restarts, so the maximised window is
-- not saved: after a restart nothing is maximised.
instance Show (Maximize a) where
  show _ = "Maximize"

instance Read (Maximize a) where
  readsPrec _ s = [ (Maximize Nothing, rest) | ("Maximize", rest) <- lex s ]

newtype MaximizeRestore = MaximizeRestore Window deriving (Show, Eq)

instance Message MaximizeRestore

-- | The message that maximises a window, or restores it if it already is.
maximizeRestore :: Window -> MaximizeRestore
maximizeRestore = MaximizeRestore

instance LayoutModifier Maximize Window where
  pureModifier (Maximize (Just m)) area _ wrs = case partition ((== m) . fst) wrs of
    ([(w, _)], others) -> (others ++ [(w, area)], Nothing)
    -- the window is gone (or not shown): forget it
    _ -> (wrs, Just (Maximize Nothing))
  pureModifier _ _ _ wrs = (wrs, Nothing)
  pureMess (Maximize cur) m = fromMessage m >>= \(MaximizeRestore w) ->
    Just (Maximize (if cur == Just w then Nothing else Just w))
  modifierDescription _ = ""
