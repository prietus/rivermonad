-- | Hide windows and bring them back, like minimising, or sway's
-- scratchpad; after @XMonad.Actions.Minimize@.
--
-- > , ("M-S-o", withFocused minimizeWindow)
-- > , ("M-o",   withLastMinimized maximizeWindowAndFocus)
-- > , ("M-C-o", restoreMenu)   -- pick one in fuzzel
--
-- Minimised windows wait on a workspace of their own, 'minimizedTag',
-- outside the configured ones: status bars and
-- "Rivermonad.Actions.CycleWS" skip it, and waymobar can count its
-- windows. A window comes back to the workspace you are on, tiled or
-- floating as it was; the most recently minimised first.
module Rivermonad.Actions.Minimize
  ( minimizeWindow
  , maximizeWindow
  , maximizeWindowAndFocus
  , withLastMinimized
  , withFirstMinimized
  , withMinimized
  , restoreMenu
  , minimizedTag
  ) where

import qualified Data.Map.Strict as M

import Rivermonad.Core
import Rivermonad.Operations (windows)
import qualified Rivermonad.StackSet as W
import Rivermonad.Util.Dmenu (menuMap)

-- | The workspace minimised windows wait on.
minimizedTag :: WorkspaceId
minimizedTag = "hidden"

minimizeWindow :: Window -> X ()
minimizeWindow w = windows $ \s ->
  let l = W.layout (W.workspace (W.current s))
      -- created on demand, at the end, so toggleWS never lands on it
      s' | W.tagMember minimizedTag s = s
         | otherwise = s { W.hidden = W.hidden s ++ [W.Workspace minimizedTag l Nothing] }
  in if W.member w s then W.shiftWin minimizedTag w s' else s

-- | Bring a minimised window to the current workspace.
maximizeWindow :: Window -> X ()
maximizeWindow w = windows $ \s ->
  if W.findTag w s == Just minimizedTag then W.shiftWin (W.currentTag s) w s else s

maximizeWindowAndFocus :: Window -> X ()
maximizeWindowAndFocus w = maximizeWindow w >> windows (\s -> if W.member w s then W.focusWindow w s else s)

-- | The minimised windows, the most recent first.
withMinimized :: ([Window] -> X a) -> X a
withMinimized f = do
  ws <- gets windowset
  f (concat [ W.integrate' (W.stack w) | w <- W.workspaces ws, W.tag w == minimizedTag ])

withLastMinimized :: (Window -> X ()) -> X ()
withLastMinimized f = withMinimized $ \case
  w : _ -> f w
  [] -> pure ()

withFirstMinimized :: (Window -> X ()) -> X ()
withFirstMinimized f = withMinimized $ \case
  [] -> pure ()
  ws -> f (last ws)

-- | Pick a minimised window by its title in fuzzel and bring it back.
restoreMenu :: X ()
restoreMenu = withMinimized $ \ws -> do
  infos <- gets windowInfo
  let name i = if null (wiTitle i) then wiAppId i else wiTitle i ++ " · " ++ wiAppId i
      entries = M.fromList (numbered [ (name i, w) | w <- ws, Just i <- [M.lookup w infos] ])
  menuMap entries maximizeWindowAndFocus
  where
    numbered = go M.empty
    go _ [] = []
    go seen ((n, w) : rest) =
      let k = M.findWithDefault (0 :: Int) n seen
      in (if k == 0 then n else n ++ " (" ++ show (k + 1) ++ ")", w) : go (M.insert n (k + 1) seen) rest
