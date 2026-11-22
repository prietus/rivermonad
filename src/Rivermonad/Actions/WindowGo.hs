-- | Focus a window if it exists, or start it, as in @XMonad.Actions.WindowGo@.
--
-- > , ("M-b", runOrRaise "firefox" (appId =? "firefox"))
-- > , ("M-e", raiseMaybe (spawn "foot -e nvim") (title =? "nvim"))
--
-- Focusing a window on another workspace goes to that workspace.
module Rivermonad.Actions.WindowGo
  ( raise
  , raiseNext
  , raiseMaybe
  , raiseNextMaybe
  , raiseAndDo
  , runOrRaise
  , runOrRaiseNext
  , runOrRaiseAndDo
  , ifWindow
  , ifWindows
  ) where

import Control.Monad (filterM)
import Data.Monoid (appEndo)

import Rivermonad.Core
import Rivermonad.Operations (spawn, windows)
import qualified Rivermonad.StackSet as W

-- | Every window the query matches, the focused one first, then the
-- current workspace's, then the rest in workspace order.
matching :: Query Bool -> X [Window]
matching q = do
  ws <- gets windowset
  let order = W.index ws ++ concatMap (W.integrate' . W.stack) (W.hidden ws ++ map W.workspace (W.visible ws))
  filterM (runQuery q) order

-- | Run the function on the matching windows (focused one and current
-- workspace first), or the action if none matches.
ifWindows :: Query Bool -> ([Window] -> X ()) -> X () -> X ()
ifWindows q f none = matching q >>= \case
  [] -> none
  ws -> f ws

-- | The first matching window, or the action.
withFirst :: Query Bool -> (Window -> X ()) -> X () -> X ()
withFirst q f none = matching q >>= \case
  [] -> none
  w : _ -> f w

-- | Apply a manage hook to the first matching window, or run the action.
--
-- > ifWindow (appId =? "mpv") doFloat (spawn "mpv")
ifWindow :: Query Bool -> ManageHook -> X () -> X ()
ifWindow q hook = withFirst q $ \w -> do
  f <- runQuery hook w
  windows (appEndo f)

-- | Focus the first matching window, or run the action.
raiseMaybe :: X () -> Query Bool -> X ()
raiseMaybe act q = withFirst q (windows . W.focusWindow) act

-- | Focus the first matching window; nothing if none.
raise :: Query Bool -> X ()
raise = raiseMaybe (pure ())

-- | Focus the matching window after the focused one, cycling through all
-- of them on each press; run the action if none matches.
raiseNextMaybe :: X () -> Query Bool -> X ()
raiseNextMaybe act q = do
  ws <- gets windowset
  let order = concatMap (W.integrate' . W.stack) (W.workspaces ws)
      cur = W.peek ws
  ms <- filterM (runQuery q) order
  let after = drop 1 (dropWhile ((/= cur) . Just) order)
  case (filter (`elem` ms) after, ms) of
    (w : _, _) -> windows (W.focusWindow w)
    ([], w : _) -> windows (W.focusWindow w)
    ([], []) -> act

raiseNext :: Query Bool -> X ()
raiseNext = raiseNextMaybe (pure ())

-- | Focus the first matching window, or start the command.
runOrRaise :: String -> Query Bool -> X ()
runOrRaise = raiseMaybe . spawn

runOrRaiseNext :: String -> Query Bool -> X ()
runOrRaiseNext = raiseNextMaybe . spawn

-- | Focus the first matching window (or start the command) and then apply
-- a manage hook to it, e.g. 'Rivermonad.ManageHook.doShift' to bring it
-- here. For a window that does not exist yet the hook is not applied: put
-- it in your manage hook.
raiseAndDo :: X () -> Query Bool -> (Window -> X ()) -> X ()
raiseAndDo act q f = withFirst q (\w -> windows (W.focusWindow w) >> f w) act

runOrRaiseAndDo :: String -> Query Bool -> (Window -> X ()) -> X ()
runOrRaiseAndDo = raiseAndDo . spawn
