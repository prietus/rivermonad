-- | Windows in the order you last used them, across workspaces, as in
-- @XMonad.Actions.MostRecentlyUsed@.
--
-- > logHook = mostRecentlyUsedHook
-- > , ("M1-<Tab>", focusPreviousWindow)  -- back to the previous window, wherever it is
-- > , ("M-S-w",    mruMenu)              -- every window, most recent first, in fuzzel
--
-- xmonad's version cycles while Alt is held; river does not tell the
-- window manager when a modifier is released, so here the same key swaps
-- between the last two windows and the menu reaches the rest.
module Rivermonad.Actions.MostRecentlyUsed
  ( mostRecentlyUsedHook
  , mostRecentlyUsed
  , focusPreviousWindow
  , mruMenu
  ) where

import qualified Data.Map.Strict as M

import Rivermonad.Actions.WindowBringer (decorateName)
import Rivermonad.Core
import Rivermonad.Operations (windows)
import qualified Rivermonad.StackSet as W
import qualified Rivermonad.Util.ExtensibleState as XS
import Rivermonad.Util.Dmenu (menuArgs)

newtype MRU = MRU [Window]

instance ExtensionClass MRU where
  initialValue = MRU []

-- | Put this in the log hook.
mostRecentlyUsedHook :: X ()
mostRecentlyUsedHook = do
  ws <- gets windowset
  case W.peek ws of
    Nothing -> pure ()
    Just f -> XS.modify $ \(MRU l) ->
      MRU (f : filter (\w -> w /= f && W.member w ws) l)

-- | The windows that still exist, most recently used first.
mostRecentlyUsed :: X [Window]
mostRecentlyUsed = do
  MRU l <- XS.get
  ws <- gets windowset
  pure (filter (`W.member` ws) l)

-- | Focus the window used before the current one (going to its workspace).
focusPreviousWindow :: X ()
focusPreviousWindow = mostRecentlyUsed >>= \case
  _ : p : _ -> windows (W.focusWindow p)
  _ -> pure ()

-- | Pick a window in fuzzel, the most recently used first (fuzzel keeps
-- the order of its input).
mruMenu :: X ()
mruMenu = do
  ws <- mostRecentlyUsed
  s <- gets windowset
  infos <- gets windowInfo
  let wsOf w = [ wsp | wsp <- W.workspaces s, w `elem` W.integrate' (W.stack wsp) ]
      entries = [ (decorateName wsp i, w) | w <- drop 1 ws, wsp : _ <- [wsOf w], Just i <- [M.lookup w infos] ]
      m = M.fromList entries
  menuArgs "fuzzel" ["--dmenu", "--no-sort"] (map fst entries) $ \c ->
    maybe (pure ()) (windows . W.focusWindow) (M.lookup c m)
