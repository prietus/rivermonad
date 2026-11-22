-- | Run a manage hook again when a window changes its title or app id
-- after it opened, as in @XMonad.Hooks.OnPropertyChange@. Some programs
-- (Spotify, Electron apps, web apps) open with a generic name and set the
-- real one later, too late for the manage hook.
--
-- > main = rivermonad $ onTitleChange (title =? "Spotify" --> doShift "9") myConfig
--
-- The hook runs on every change, so keep it idempotent: shifting to a
-- workspace or floating is fine, toggling is not.
module Rivermonad.Hooks.OnPropertyChange
  ( onTitleChange
  , onAppIdChange
  , onClassChange
  ) where

import qualified Data.Map.Strict as M
import Data.Monoid (appEndo)

import Rivermonad.Core
import Rivermonad.Operations (queue, windows)
import Rivermonad.Wayland.Protocol (Event (..), RiverWindowV1Event (..))

onTitleChange :: ManageHook -> XConfig -> XConfig
onTitleChange = onChange $ \case
  RiverWindowV1Title _ -> True
  _ -> False

onAppIdChange :: ManageHook -> XConfig -> XConfig
onAppIdChange = onChange $ \case
  RiverWindowV1AppId _ -> True
  _ -> False

-- | Alias of 'onAppIdChange', for xmonad configs.
onClassChange :: ManageHook -> XConfig -> XConfig
onClassChange = onAppIdChange

onChange :: (RiverWindowV1Event -> Bool) -> ManageHook -> XConfig -> XConfig
onChange which mh conf = conf
  { handleEventHook = \e -> (<>) <$> handleEventHook conf e <*> hook e }
  where
    hook = \case
      EvRiverWindowV1 w e | which e -> do
        -- only windows that already went through the manage hook
        managed <- gets (maybe False wiManaged . M.lookup w . windowInfo)
        -- the new value is stored after this hook: run in the next manage
        -- sequence
        if managed then queue (stillThere w (runQuery mh w >>= windows . appEndo)) else pure ()
        pure (All True)
      _ -> pure (All True)
    stillThere w act = gets (M.member w . windowInfo) >>= \ok -> if ok then act else pure ()
