-- | Move the focus, or the focused window, to the neighbour in a
-- direction on screen, as in @XMonad.Actions.Navigation2D@: left goes to
-- the window that is to the left, whatever the layout and the order of
-- the stack.
--
-- > , ("M-<Left>",    windowGo L)
-- > , ("M-S-<Left>",  windowSwap L)
--
-- Tiled and floating windows on every visible screen are candidates, so
-- the focus also crosses to the next monitor.
module Rivermonad.Actions.Navigation2D
  ( Direction2D (..)
  , windowGo
  , windowSwap
  , neighbour
  ) where

import Control.Monad (forM)
import qualified Data.Set as S
import Data.List (sortOn)
import Data.Maybe (catMaybes, listToMaybe)

import Rivermonad.Core
import Rivermonad.Operations (windowGeometry, windows)
import qualified Rivermonad.StackSet as W

data Direction2D = U | D | L | R
  deriving (Show, Read, Eq)

-- | Focus the nearest window in that direction.
windowGo :: Direction2D -> X ()
windowGo d = neighbour d >>= mapM_ (windows . W.focusWindow)

-- | Swap the focused window with the nearest one in that direction (both
-- keep their place in their own stack); the focus stays on the window.
windowSwap :: Direction2D -> X ()
windowSwap d = do
  cur <- gets (W.peek . windowset)
  next <- neighbour d
  case (cur, next) of
    (Just a, Just b) -> windows (W.focusWindow a . swapWindows a b)
    _ -> pure ()

-- | The nearest window on screen in that direction from the focused one.
neighbour :: Direction2D -> X (Maybe Window)
neighbour d = do
  ws <- gets windowset
  shown <- gets shownWindows
  case W.peek ws of
    Nothing -> pure Nothing
    Just f -> do
      mfr <- windowGeometry f
      case mfr of
        Nothing -> pure Nothing
        Just fr -> do
          let others = [ w | scr <- W.screens ws, w <- W.integrate' (W.stack (W.workspace scr))
                           , w /= f, S.member w shown ]
          rs <- catMaybes <$> forM others (\w -> fmap ((,) w) <$> windowGeometry w)
          pure (fst <$> listToMaybe (sortOn (score d fr . snd) (filter (ahead d fr . snd) rs)))

-- | Its centre lies beyond the focused window's centre in that direction.
ahead :: Direction2D -> Rectangle -> Rectangle -> Bool
ahead d a b = case d of
  L -> cx b < cx a
  R -> cx b > cx a
  U -> cy b < cy a
  D -> cy b > cy a

-- | Windows that overlap the focused one across the direction come first
-- (the one beside it, not the one in a corner), then the nearest.
score :: Direction2D -> Rectangle -> Rectangle -> (Bool, Int, Int)
score d a b = (not overlapping, along, across)
  where
    horizontal = d == L || d == R
    overlapping
      | horizontal = rect_y b < rect_y a + rect_height a && rect_y a < rect_y b + rect_height b
      | otherwise = rect_x b < rect_x a + rect_width a && rect_x a < rect_x b + rect_width b
    along = if horizontal then abs (cx b - cx a) else abs (cy b - cy a)
    across = if horizontal then abs (cy b - cy a) else abs (cx b - cx a)

cx, cy :: Rectangle -> Int
cx r = rect_x r + rect_width r `div` 2
cy r = rect_y r + rect_height r `div` 2

-- | Exchange two windows wherever they are.
swapWindows :: Window -> Window -> WindowSet -> WindowSet
swapWindows a b = W.mapWorkspace $ \wsp -> wsp { W.stack = fmap sw (W.stack wsp) }
  where
    sw (W.Stack f u dn) = W.Stack (r f) (map r u) (map r dn)
    r x | x == a = b
        | x == b = a
        | otherwise = x
