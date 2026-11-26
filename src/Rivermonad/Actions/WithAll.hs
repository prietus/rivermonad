-- | Actions on every window of the current workspace, as in
-- @XMonad.Actions.WithAll@.
--
-- > , ("M-S-t", sinkAll)   -- every floating window back into the layout
-- > , ("M-C-c", killAll)   -- close them all
--
-- 'sinkAll' is the plural of the default @M-t@, which only tiles the
-- focused window.
module Rivermonad.Actions.WithAll
  ( sinkAll
  , killAll
  , withAll
  , withAll'
  ) where

import Rivermonad.Core
import Rivermonad.Operations (killWindow, windows)
import qualified Rivermonad.StackSet as W

-- | Put every floating window of the current workspace back into tiling.
sinkAll :: X ()
sinkAll = withAll' W.sink

-- | Close every window of the current workspace.
killAll :: X ()
killAll = withAll killWindow

-- | Run an action on every window of the current workspace.
withAll :: (Window -> X ()) -> X ()
withAll f = withWindowSet (mapM_ f . W.index)

-- | Apply a pure change for every window of the current workspace, in one
-- step (one layout pass).
withAll' :: (Window -> WindowSet -> WindowSet) -> X ()
withAll' f = windows (\ws -> foldr f ws (W.index ws))
