-- | One window on several workspaces at once, as in
-- @XMonad.Actions.CopyWindow@: a video in picture-in-picture, a chat or a
-- music player that follows you.
--
-- > , ("M-v",   windows copyToAll)    -- the focused window on every workspace
-- > , ("M-S-v", killAllOtherCopies)   -- back to only this workspace
-- > , ("M-S-c", kill1)                -- remove it from here (closes the last copy)
-- >   ++ [ ("M-C-" ++ show n, windows (copy t)) | (n, t) <- zip [1 :: Int ..] myWorkspaces ]
--
-- A copy is the same window: it is shown on whichever of its workspaces
-- is on screen (on one monitor at a time). Copies are not kept across a
-- restart of rivermonad; the window stays on one workspace.
module Rivermonad.Actions.CopyWindow
  ( copy
  , copyWindow
  , copyToAll
  , killAllOtherCopies
  , kill1
  , wsContainingCopies
  ) where

import Rivermonad.Core
import Rivermonad.Operations (killWindow, windows)
import qualified Rivermonad.StackSet as W

-- | Copy the focused window to a workspace.
copy :: WorkspaceId -> WindowSet -> WindowSet
copy n s = maybe s (\w -> copyWindow w n s) (W.peek s)

-- | Copy a window to a workspace (nothing if it is already there).
copyWindow :: Window -> WorkspaceId -> WindowSet -> WindowSet
copyWindow w n s
  | not (W.member w s) || not (W.tagMember n s) = s
  | otherwise = W.mapWorkspace add s
  where
    add wsp
      | W.tag wsp /= n || w `elem` W.integrate' (W.stack wsp) = wsp
      | otherwise = wsp { W.stack = Just (case W.stack wsp of
          Nothing -> W.Stack w [] []
          Just (W.Stack f u d) -> W.Stack f u (d ++ [w])) }

-- | Copy the focused window to every workspace (but not to the hidden
-- ones of the scratchpads and minimised windows).
copyToAll :: WindowSet -> WindowSet
copyToAll s = foldr copy s [ W.tag w | w <- W.workspaces s, W.tag w `notElem` ["NSP", "hidden"] ]

-- | Keep the focused window only on the current workspace.
killAllOtherCopies :: X ()
killAllOtherCopies = windows $ \s -> case W.peek s of
  Nothing -> s
  Just w -> W.mapWorkspace (\wsp ->
    if W.tag wsp == W.currentTag s then wsp
    else wsp { W.stack = W.stack wsp >>= W.filter (/= w) }) s

-- | Remove the focused window from the current workspace; if it is not
-- on any other one, close it.
kill1 :: X ()
kill1 = do
  s <- gets windowset
  case W.peek s of
    Nothing -> pure ()
    Just w
      | null (filter (/= W.currentTag s) (wsContainingCopies w s)) -> killWindow w
      | otherwise -> windows (W.modify Nothing (W.filter (/= w)))

-- | The workspaces a window is on.
wsContainingCopies :: Window -> WindowSet -> [WorkspaceId]
wsContainingCopies w s = [ W.tag wsp | wsp <- W.workspaces s, w `elem` W.integrate' (W.stack wsp) ]
