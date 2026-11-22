{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- | Switch transformations on and off on top of any layout, as in
-- @XMonad.Layout.MultiToggle@ (with the transformers of
-- @MultiToggle.Instances@ and @Reflect@ built in).
--
-- > layoutHook = Layout (mkToggle [FULL, MIRROR, NOBORDERS, REFLECTX] (tiled ||| Grid))
-- > , ("M-x", sendMessage (Toggle MIRROR))
-- > , ("M-S-x", sendMessage (Toggle REFLECTX))
--
-- Each toggle is independent and they combine (mirrored and reflected,
-- say); the layout underneath keeps its own state.
module Rivermonad.Layout.MultiToggle
  ( mkToggle
  , Transformer (..)
  , Toggle (..)
  , MultiToggle
  ) where

import qualified Data.Map.Strict as M

import Rivermonad.Core
import Rivermonad.Layout (mirrorRect)
import Rivermonad.Layout.LayoutModifier
import qualified Rivermonad.StackSet as W

data Transformer
  = FULL       -- ^ only the focused window, over the whole area
  | MIRROR     -- ^ rows instead of columns
  | NOBORDERS  -- ^ no borders on tiled windows
  | REFLECTX   -- ^ left and right swapped (master on the right)
  | REFLECTY   -- ^ top and bottom swapped
  deriving (Show, Read, Eq, Ord)

newtype Toggle = Toggle Transformer deriving (Show, Eq)

instance Message Toggle

-- | The transformers that may be toggled; all start off.
mkToggle :: [Transformer] -> l a -> ModifiedLayout MultiToggle l a
mkToggle ts = ModifiedLayout (MultiToggle ts [])

-- | Allowed transformers, and the ones on.
data MultiToggle a = MultiToggle [Transformer] [Transformer] deriving (Show, Read)

instance LayoutModifier MultiToggle Window where
  modifyLayout (MultiToggle _ on) wsp@(W.Workspace _ _ ms) r
    | FULL `elem` on = pure (maybe [] (\st -> [(W.focus st, r)]) ms, Nothing)
    | otherwise = do
        let mirrored = MIRROR `elem` on
        (wrs, l') <- runLayout wsp (if mirrored then mirrorRect r else r)
        let fix = (if REFLECTX `elem` on then reflectX r else id)
                . (if REFLECTY `elem` on then reflectY r else id)
                . (if mirrored then mirrorRect else id)
        pure ([ (w, fix wr) | (w, wr) <- wrs ], l')

  redoLayout (MultiToggle _ on) _ _ wrs = do
    if NOBORDERS `elem` on
      then modify $ \s -> s { borderWidths = foldr (\(w, _) -> M.insert w 0) (borderWidths s) wrs }
      else pure ()
    pure (wrs, Nothing)

  pureMess (MultiToggle allowed on) m = fromMessage m >>= \(Toggle t) ->
    if t `notElem` allowed then Nothing
    else Just (MultiToggle allowed (if t `elem` on then filter (/= t) on else t : on))

  modifierDescription (MultiToggle _ on)
    | FULL `elem` on = "Full"
    | otherwise = unwords [ name t | t <- [MIRROR, REFLECTX, REFLECTY], t `elem` on ]
    where
      name MIRROR = "Mirror"
      name REFLECTX = "ReflectX"
      name REFLECTY = "ReflectY"
      name t = show t

reflectX, reflectY :: Rectangle -> Rectangle -> Rectangle
reflectX (Rectangle ax _ aw _) (Rectangle x y w h) = Rectangle (ax + aw - (x - ax) - w) y w h
reflectY (Rectangle _ ay _ ah) (Rectangle x y w h) = Rectangle x (ay + ah - (y - ay) - h) w h
