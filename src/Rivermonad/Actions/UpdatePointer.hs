{-# LANGUAGE ScopedTypeVariables #-}
-- | The pointer follows the focus, as in @XMonad.Actions.UpdatePointer@:
-- when you change window with the keyboard the pointer jumps into the new
-- one, so focus-follows-mouse and the keyboard agree.
--
-- > logHook = updatePointer (0.5, 0.5) (0, 0)
--
-- Nothing happens if the pointer is already inside the window. Otherwise
-- the first pair says where in the window it goes (0 = left/top, 1 =
-- right/bottom). The second pair is how far, as a fraction of the window,
-- it may stay from that point: @(0, 0)@ puts it exactly there, @(1, 1)@
-- moves it only as much as needed to be inside the window.
-- Needs river 0.5 (river_window_manager_v1 version 3).
module Rivermonad.Actions.UpdatePointer
  ( updatePointer
  ) where

import Control.Monad (forM_, when)
import qualified Data.Map.Strict as M

import Rivermonad.Core
import Rivermonad.Operations (queue, windowGeometry)
import qualified Rivermonad.StackSet as W
import qualified Rivermonad.Util.ExtensibleState as XS
import Rivermonad.Wayland.Protocol (riverSeatV1PointerWarp)

newtype LastFocus = LastFocus (Maybe Window) deriving (Show)

instance ExtensionClass LastFocus where
  initialValue = LastFocus Nothing

updatePointer :: (Double, Double) -> (Double, Double) -> X ()
updatePointer (rx, ry) (bx, by) = do
  cur <- gets (W.peek . windowset)
  LastFocus prev <- XS.get
  when (cur /= prev) $ do
    XS.put (LastFocus cur)
    -- The new geometry is known after this manage sequence's layout: warp
    -- in the next one.
    forM_ cur $ \w -> queue (warpInto w)
  where
    warpInto w = do
      v <- asks (gWmVersion . globals)
      still <- gets ((== Just w) . W.peek . windowset)
      mr <- windowGeometry w
      case mr of
        Just (Rectangle x y wd ht) | v >= 3, still -> do
          ss <- gets (M.toList . seats)
          c <- asks conn
          forM_ ss $ \(seat, si) -> do
            let tx = fromIntegral x + rx * fromIntegral wd :: Double
                ty = fromIntegral y + ry * fromIntegral ht :: Double
                inside (px, py) = px >= x && px < x + wd && py >= y && py < y + ht
                clamp p t half = max (t - half) (min (t + half) (fromIntegral p))
            case siPointerPos si of
              Just pos | inside pos -> pure ()
              mpos -> do
                let (px, py) = maybe (round tx, round ty) id mpos
                    nx = clamp px tx (bx * fromIntegral wd / 2)
                    ny = clamp py ty (by * fromIntegral ht / 2)
                io (riverSeatV1PointerWarp c seat (round nx) (round ny))
        _ -> pure ()
