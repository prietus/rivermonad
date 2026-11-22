{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- | Each new window splits the focused one in two, along its longer side,
-- as in @XMonad.Layout.BinarySpacePartition@ (bspwm's model). The splits
-- form a tree you can rotate, swap and resize.
--
-- > layoutHook = Layout (emptyBSP ||| tiled)
-- > , ("M-r",   sendMessage Rotate)   -- the focused split: side by side <-> stacked
-- > , ("M-S-r", sendMessage Swap)     -- swap the two halves
-- > , ("M-h",   sendMessage Shrink)   -- the focused half smaller / bigger
-- > , ("M-l",   sendMessage Expand)
--
-- The tree is kept across restarts as long as the windows are the same.
module Rivermonad.Layout.BinarySpacePartition
  ( emptyBSP
  , BinarySpacePartition
  , BSPMsg (..)
  ) where

import Data.Maybe (fromMaybe)
import Data.Word (Word32)

import Rivermonad.Core
import Rivermonad.Layout (Resize (..))
import qualified Rivermonad.StackSet as W
import Rivermonad.Wayland.Wire (ObjectId (..))

data Split = SideBySide | Stacked deriving (Show, Read, Eq)

-- | Windows by their numeric id (window ids are not 'Read').
data Tree = Leaf !Word32 | Node !Split !Rational Tree Tree deriving (Show, Read, Eq)

newtype BinarySpacePartition a = BSP (Maybe Tree) deriving (Show, Read)

emptyBSP :: BinarySpacePartition a
emptyBSP = BSP Nothing

data BSPMsg = Rotate | Swap deriving (Show, Eq)

instance Message BSPMsg

instance LayoutClass BinarySpacePartition Window where
  doLayout (BSP mt) r s = pure (place r t', if Just t' == mt then Nothing else Just (BSP (Just t')))
    where
      ws = map unObjectId (W.integrate s)
      foc = unObjectId (W.focus s)
      kept = mt >>= prune (`elem` ws)
      t' = foldl (insertNear r foc) kept [ w | w <- ws, maybe True (notElem w . leaves) kept ]
         `orElse` Leaf foc
      orElse m d = fromMaybe d m

  handleMessage (BSP Nothing) _ = pure Nothing
  handleMessage (BSP (Just t)) m = do
    foc <- gets (fmap unObjectId . W.peek . windowset)
    pure $ case foc of
      Nothing -> Nothing
      Just f -> BSP . Just <$> case (fromMessage m, fromMessage m) of
        (Just Rotate, _) -> onParent f (\_ sp k a b -> Node (other sp) k a b) t
        (Just Swap, _) -> onParent f (\_ sp k a b -> Node sp (1 - k) b a) t
        (_, Just Shrink) -> onParent f (\left sp k a b -> Node sp (resize left (-0.05) k) a b) t
        (_, Just Expand) -> onParent f (\left sp k a b -> Node sp (resize left 0.05 k) a b) t
        _ -> Nothing
    where
      other SideBySide = Stacked
      other Stacked = SideBySide
      resize left d k = max 0.1 (min 0.9 (if left then k + d else k - d))

  description _ = "BSP"

leaves :: Tree -> [Word32]
leaves (Leaf w) = [w]
leaves (Node _ _ a b) = leaves a ++ leaves b

-- | Drop the windows that are gone; a split left with one side becomes
-- that side.
prune :: (Word32 -> Bool) -> Tree -> Maybe Tree
prune keep (Leaf w) = if keep w then Just (Leaf w) else Nothing
prune keep (Node sp k a b) = case (prune keep a, prune keep b) of
  (Just a', Just b') -> Just (Node sp k a' b')
  (Just a', Nothing) -> Just a'
  (Nothing, Just b') -> Just b'
  (Nothing, Nothing) -> Nothing

-- | Add a window by splitting the focused one (or the last one) along its
-- longer side; the new window takes the right or bottom half.
insertNear :: Rectangle -> Word32 -> Maybe Tree -> Word32 -> Maybe Tree
insertNear _ _ Nothing w = Just (Leaf w)
insertNear r foc (Just t) w = Just (go r t)
  where
    target = if foc `elem` leaves t then foc else last (leaves t)
    go rect (Leaf x)
      | x == target = Node (if rect_width rect >= rect_height rect then SideBySide else Stacked) 0.5 (Leaf x) (Leaf w)
      | otherwise = Leaf x
    go rect (Node sp k a b) = let (ra, rb) = split sp k rect in Node sp k (go ra a) (go rb b)

-- | Change the split that directly contains a window; the function gets
-- whether the window is on its first (left/top) side.
onParent :: Word32 -> (Bool -> Split -> Rational -> Tree -> Tree -> Tree) -> Tree -> Maybe Tree
onParent _ _ (Leaf _) = Nothing
onParent w f (Node sp k a b)
  | a == Leaf w = Just (f True sp k a b)
  | b == Leaf w = Just (f False sp k a b)
  | w `elem` leaves a = (\a' -> Node sp k a' b) <$> onParent w f a
  | w `elem` leaves b = Node sp k a <$> onParent w f b
  | otherwise = Nothing

place :: Rectangle -> Tree -> [(Window, Rectangle)]
place r (Leaf w) = [(ObjectId w, r)]
place r (Node sp k a b) = let (ra, rb) = split sp k r in place ra a ++ place rb b

split :: Split -> Rational -> Rectangle -> (Rectangle, Rectangle)
split SideBySide k (Rectangle x y w h) = (Rectangle x y w1 h, Rectangle (x + w1) y (w - w1) h)
  where w1 = round (k * fromIntegral w)
split Stacked k (Rectangle x y w h) = (Rectangle x y w h1, Rectangle x (y + h1) w (h - h1))
  where h1 = round (k * fromIntegral h)
