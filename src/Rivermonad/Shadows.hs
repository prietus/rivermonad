-- | Drop shadows: river decorations below windows, drawn by rivermonad into
-- wl_shm buffers (see @rivermonad_shadow_fd@ in cbits/rivermonad.c).
-- Enabled with 'shadows' in the 'XConfig'.
module Rivermonad.Shadows
  ( syncShadows
  , drawShadows
  , dropShadow
  , handleShadowEvent
  , shadowWanted
  , shadowRgb
  ) where

import Control.Monad (forM_, unless, when)
import qualified Data.Map.Strict as M
import Data.Char (digitToInt, isHexDigit)
import qualified Data.Set as S
import Foreign.C.Types (CDouble (..), CInt (..))
import System.Posix.IO (closeFd)
import System.Posix.Types (Fd (..))

import Rivermonad.Core
import qualified Rivermonad.StackSet as W
import Rivermonad.Wayland.Protocol

foreign import ccall safe "rivermonad_shadow_fd"
  c_shadow_fd :: CInt -> CInt -> CInt -> CInt -> CInt -> CDouble -> CDouble -> CDouble -> CDouble -> IO CInt

-- | Manage sequence: give a decoration to every window that should have a
-- shadow (floating ones, or all with 'shadowTiled'; never fullscreen ones)
-- and remove the others.
syncShadows :: X ()
syncShadows = do
  mcfg <- asks (shadows . config)
  g <- asks globals
  cur <- gets shadowMap
  case (mcfg, gCompositor g, gShm g) of
    -- on river-fx the compositor draws the shadows (see sendFx)
    _ | Just _ <- gFx g, gFxVersion g >= 2 -> mapM_ dropShadow (M.keys cur)
    (Just sc, Just comp, Just _) -> do
      ws <- gets windowset
      infos <- gets windowInfo
      fs <- gets fullscreen
      let wanted = S.fromList
            [ w | w <- W.allWindows ws, M.member w infos
                , shadowTiled sc || M.member w (W.floating ws)
                , not (S.member w fs) ]
      forM_ (M.keys cur) $ \w -> unless (S.member w wanted) (dropShadow w)
      c <- asks conn
      forM_ (S.toList wanted) $ \w -> unless (M.member w cur) $ do
        sh <- io $ do
          surf <- wlCompositorCreateSurface c comp
          -- an empty input region: clicks go through the shadow
          region <- wlCompositorCreateRegion c comp
          wlSurfaceSetInputRegion c surf region
          wlRegionDestroy c region
          deco <- riverWindowV1GetDecorationBelow c w surf
          pure (Shadow surf deco Nothing Nothing)
        modify $ \s -> s { shadowMap = M.insert w sh (shadowMap s) }
    _ -> mapM_ dropShadow (M.keys cur)

-- | Whether a window should have a shadow now: floating ones, or all with
-- 'shadowTiled'; never fullscreen ones.
shadowWanted :: ShadowConfig -> Window -> X Bool
shadowWanted sc w = do
  ws <- gets windowset
  fs <- gets fullscreen
  pure ((shadowTiled sc || M.member w (W.floating ws)) && not (S.member w fs))

-- | The colour of the shadows, components 0..1.
shadowRgb :: ShadowConfig -> (Double, Double, Double)
shadowRgb = rgb . shadowColor

-- | Render sequence: (re)draw the shadows whose window changed size, in
-- sync with the frame that shows the new size.
drawShadows :: X ()
drawShadows = do
  mcfg <- asks (shadows . config)
  mshm <- asks (gShm . globals)
  bwDefault <- asks (borderWidth . config)
  case (mcfg, mshm) of
    (Just sc, Just shm) -> do
      m <- gets shadowMap
      infos <- gets windowInfo
      overrides <- gets borderWidths
      c <- asks conn
      let r = max 0 (shadowRadius sc)
          (dx, dy) = shadowOffset sc
          (cr, cg, cb) = rgb (shadowColor sc)
      forM_ (M.toList m) $ \(w, sh) -> forM_ (M.lookup w infos >>= wiDims) $ \(cw, ch) -> do
        let bw = M.findWithDefault bwDefault w overrides
            box = (cw + 2 * bw, ch + 2 * bw)
        when (shDrawn sh /= Just box) $ do
          let (bxw, bxh) = box
              bufW = bxw + 2 * r
              bufH = bxh + 2 * r
          fd <- io $ c_shadow_fd (fi bxw) (fi bxh) (fi r) (fi dx) (fi dy)
                       (realToFrac cr) (realToFrac cg) (realToFrac cb)
                       (realToFrac (max 0 (min 1 (shadowOpacity sc))))
          when (fd >= 0) $ do
            buf <- io $ do
              pool <- wlShmCreatePool c shm (Fd fd) (fi (bufW * bufH * 4))
              b <- wlShmPoolCreateBuffer c pool 0 (fi bufW) (fi bufH) (fi (bufW * 4)) wlShmFormatArgb8888
              wlShmPoolDestroy c pool
              closeFd (Fd fd)
              let surf = shSurface sh
              wlSurfaceAttach c surf b 0 0
              wlSurfaceDamageBuffer c surf 0 0 (fi bufW) (fi bufH)
              -- relative to the window content's top-left corner
              riverDecorationV1SetOffset c (shDecoration sh) (fi (dx - r - bw)) (fi (dy - r - bw))
              riverDecorationV1SyncNextCommit c (shDecoration sh)
              wlSurfaceCommit c surf
              pure b
            -- the old buffer may still be on screen: free it once released
            forM_ (shBuffer sh) $ \old ->
              modify $ \s -> s { retiredBuffers = S.insert old (retiredBuffers s) }
            modify $ \s -> s { shadowMap = M.insert w sh { shDrawn = Just box, shBuffer = Just buf } (shadowMap s) }
    _ -> pure ()
  where
    fi :: (Integral a, Num b) => a -> b
    fi = fromIntegral

-- | Remove a window's shadow (window closed, tiled, fullscreen...).
dropShadow :: Window -> X ()
dropShadow w = do
  m <- gets (M.lookup w . shadowMap)
  forM_ m $ \sh -> do
    c <- asks conn
    io $ do
      riverDecorationV1Destroy c (shDecoration sh)
      wlSurfaceDestroy c (shSurface sh)
      forM_ (shBuffer sh) (wlBufferDestroy c)
    modify $ \s -> s { shadowMap = M.delete w (shadowMap s) }

-- | Buffer releases (and other events of our own surfaces); False if not ours.
handleShadowEvent :: Event -> X Bool
handleShadowEvent ev = case ev of
  EvWlBuffer b WlBufferRelease -> do
    retired <- gets (S.member b . retiredBuffers)
    when retired $ do
      c <- asks conn
      io (wlBufferDestroy c b)
      modify $ \s -> s { retiredBuffers = S.delete b (retiredBuffers s) }
    pure True
  EvWlSurface {} -> pure True
  EvWlShm {} -> pure True
  _ -> pure False

-- | "#rrggbb" to components in [0, 1] (black if it doesn't parse).
rgb :: String -> (Double, Double, Double)
rgb ('#' : h) | length h >= 6, all isHexDigit (take 6 h) =
  let byte i = fromIntegral (digitToInt (h !! i) * 16 + digitToInt (h !! (i + 1))) / 255
  in (byte 0, byte 2, byte 4)
rgb _ = (0, 0, 0)
