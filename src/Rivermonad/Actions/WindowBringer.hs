-- | Pick a window by name in a menu (fuzzel) and go to it or bring it
-- here, as in @XMonad.Actions.WindowBringer@.
--
-- > , ("M-g", gotoMenu)    -- go to the window (and its workspace)
-- > , ("M-S-g", bringMenu) -- bring the window to this workspace
--
-- Each entry is the window's title, its app id and its workspace:
-- @"README.md - nvim · foot [code]"@. Windows hidden on the scratchpad
-- workspaces are listed too, so 'bringMenu' also brings them back.
module Rivermonad.Actions.WindowBringer
  ( gotoMenu
  , gotoMenuArgs
  , bringMenu
  , bringMenuArgs
  , actionMenu
  , actionMenuArgs
  , windowMap
  , windowMap'
  , decorateName
  , bringWindow
  ) where

import qualified Data.Map.Strict as M

import Rivermonad.Core
import Rivermonad.Operations (windows)
import qualified Rivermonad.StackSet as W
import Rivermonad.Util.Dmenu (defaultMenuCommand, menuMapArgs)

-- | Go to the window picked: its workspace becomes the current one.
gotoMenu :: X ()
gotoMenu = uncurry gotoMenuArgs defaultMenuCommand

gotoMenuArgs :: String -> [String] -> X ()
gotoMenuArgs cmd args = actionMenuArgs cmd args (windows . W.focusWindow)

-- | Bring the window picked to the current workspace and focus it.
bringMenu :: X ()
bringMenu = uncurry bringMenuArgs defaultMenuCommand

bringMenuArgs :: String -> [String] -> X ()
bringMenuArgs cmd args = actionMenuArgs cmd args $ \w ->
  windows (\s -> W.focusWindow w (bringWindow w s))

-- | Move a window to the current workspace.
bringWindow :: Window -> WindowSet -> WindowSet
bringWindow w s = W.shiftWin (W.currentTag s) w s

-- | Any action on the window picked.
actionMenu :: (Window -> X ()) -> X ()
actionMenu = uncurry actionMenuArgs defaultMenuCommand

actionMenuArgs :: String -> [String] -> (Window -> X ()) -> X ()
actionMenuArgs cmd args act = do
  m <- windowMap
  menuMapArgs cmd args m act

-- | Every window by its 'decorateName'.
windowMap :: X (M.Map String Window)
windowMap = windowMap' decorateName

-- | Every window by a name of your own; names that repeat get a number.
windowMap' :: (WindowSpace -> WindowInfo -> String) -> X (M.Map String Window)
windowMap' name = do
  ws <- gets windowset
  infos <- gets windowInfo
  let named = [ (name wsp i, w)
              | wsp <- W.workspaces ws, w <- W.integrate' (W.stack wsp)
              , Just i <- [M.lookup w infos] ]
  pure (M.fromList (numbered named))
  where
    numbered = go M.empty
    go _ [] = []
    go seen ((n, w) : rest) =
      let k = M.findWithDefault (0 :: Int) n seen
          n' = if k == 0 then n else n ++ " (" ++ show (k + 1) ++ ")"
      in (n', w) : go (M.insert n (k + 1) seen) rest

-- | @"title · app_id [workspace]"@.
decorateName :: WindowSpace -> WindowInfo -> String
decorateName wsp i =
  title ++ app ++ " [" ++ W.tag wsp ++ "]"
  where
    title = if null (wiTitle i) then wiAppId i else wiTitle i
    app = if null (wiAppId i) || null (wiTitle i) then "" else " · " ++ wiAppId i
