-- | When the focused window closes, the focus goes back to the window you
-- were using before it, as in @XMonad.Hooks.RefocusLast@, instead of to
-- its neighbour in the stack. Close a dialog or a terminal you opened for
-- a moment and you are back where you were.
--
-- > main = rivermonad $ refocusLast myConfig
--
-- Each workspace remembers its own previous window. 'toggleFocus' swaps
-- between the two most recent windows of the workspace (an Alt-Tab).
module Rivermonad.Hooks.RefocusLast
  ( refocusLast
  , refocusLastLogHook
  , refocusLastEventHook
  , toggleFocus
  ) where

import qualified Data.Map.Strict as M

import Rivermonad.Core
import Rivermonad.Operations (queue, windows)
import qualified Rivermonad.StackSet as W
import qualified Rivermonad.Util.ExtensibleState as XS
import Rivermonad.Wayland.Protocol (Event (..), RiverWindowV1Event (..))

-- | Per workspace: (focused now, focused before).
newtype Recent = Recent (M.Map WorkspaceId (Window, Maybe Window))

instance ExtensionClass Recent where
  initialValue = Recent M.empty

-- | Add the log hook and the event hook to a configuration.
refocusLast :: XConfig -> XConfig
refocusLast conf = conf
  { logHook = refocusLastLogHook >> logHook conf
  , handleEventHook = \e -> (<>) <$> refocusLastEventHook e <*> handleEventHook conf e
  }

-- | Remember the focus of the current workspace.
refocusLastLogHook :: X ()
refocusLastLogHook = do
  ws <- gets windowset
  case W.peek ws of
    Nothing -> pure ()
    Just f -> XS.modify $ \(Recent m) -> Recent $ case M.lookup (W.currentTag ws) m of
      Just (cur, prev) | cur == f -> M.insert (W.currentTag ws) (cur, prev) m
                       | otherwise -> M.insert (W.currentTag ws) (f, Just cur) m
      Nothing -> M.insert (W.currentTag ws) (f, Nothing) m

-- | When the focused window of a workspace closes, focus its previous one.
refocusLastEventHook :: Event -> X All
refocusLastEventHook = \case
  EvRiverWindowV1 w RiverWindowV1Closed -> do
    Recent m <- XS.get
    case [ (t, p) | (t, (cur, Just p)) <- M.toList m, cur == w, p /= w ] of
      (t, p) : _ -> do
        -- after the window is gone: in the next manage sequence
        queue $ do
          s <- gets windowset
          if p `elem` maybe [] (W.integrate' . W.stack) (lookupWs t s)
            then do
              XS.modify (\(Recent m') -> Recent (M.insert t (p, Nothing) m'))
              windows (\s' -> if W.currentTag s' == t then W.focusWindow p s' else onTag t p s')
            else pure ()
      [] -> pure ()
    pure (All True)
  _ -> pure (All True)
  where
    lookupWs t s = case [ w | w <- W.workspaces s, W.tag w == t ] of
      w : _ -> Just w
      [] -> Nothing
    -- focus p inside its (not current) workspace's stack, without going there
    onTag t p = W.mapWorkspace $ \wsp ->
      if W.tag wsp /= t then wsp else wsp { W.stack = W.stack wsp >>= focusIn p }
    focusIn p st = let l = W.integrate st; (before, after) = break (== p) l
                   in case after of
                        x : rest -> Just (W.Stack x (reverse before) rest)
                        [] -> Just st

-- | Focus the window used before the current one on this workspace.
toggleFocus :: X ()
toggleFocus = do
  ws <- gets windowset
  Recent m <- XS.get
  case M.lookup (W.currentTag ws) m of
    Just (_, Just p) | p `elem` W.index ws -> windows (W.focusWindow p)
    _ -> pure ()
