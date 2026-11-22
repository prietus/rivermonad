-- | Remember the order in which workspaces were visited, as in
-- @XMonad.Hooks.WorkspaceHistory@.
--
-- > logHook = workspaceHistoryHook
-- > , ("M-S-<Tab>", recentWorkspacesMenu)  -- the workspaces, most recent first, in fuzzel
module Rivermonad.Hooks.WorkspaceHistory
  ( workspaceHistoryHook
  , workspaceHistory
  , recentWorkspacesMenu
  ) where

import Rivermonad.Core
import Rivermonad.Operations (windows)
import qualified Rivermonad.StackSet as W
import qualified Rivermonad.Util.ExtensibleState as XS
import Rivermonad.Util.Dmenu (menu)

newtype History = History [WorkspaceId] deriving (Show, Read)

instance ExtensionClass History where
  initialValue = History []
  extensionType = PersistentExtension

-- | Put this in the log hook.
workspaceHistoryHook :: X ()
workspaceHistoryHook = do
  cur <- gets (W.currentTag . windowset)
  XS.modify $ \(History h) -> History (cur : filter (/= cur) h)

-- | The workspaces visited, most recent (the current one) first.
workspaceHistory :: X [WorkspaceId]
workspaceHistory = do
  History h <- XS.get
  tags <- gets (map W.tag . W.workspaces . windowset)
  pure (filter (`elem` tags) h)

-- | Pick one of the workspaces visited before, most recent first.
recentWorkspacesMenu :: X ()
recentWorkspacesMenu = do
  h <- workspaceHistory
  menu (filter (`notElem` ["NSP", "hidden"]) (drop 1 h)) $ \t -> windows (W.greedyView t)
