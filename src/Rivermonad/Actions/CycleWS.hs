-- | Cycle through workspaces and screens, as in @XMonad.Actions.CycleWS@.
--
-- > , ("M-<Right>", nextWS), ("M-<Left>", prevWS)
-- > , ("M-S-<Right>", shiftToNext >> nextWS)
-- > , ("M-<Tab>", toggleWS)
-- > , ("M-o", nextScreen)
-- > , ("M-n", moveTo Next EmptyWS)
module Rivermonad.Actions.CycleWS
  ( -- * Workspaces
    nextWS, prevWS, shiftToNext, shiftToPrev, toggleWS
  , Direction1D (..), WSType (..)
  , moveTo, shiftTo, findWorkspace
    -- * Screens
  , nextScreen, prevScreen, shiftNextScreen, shiftPrevScreen
  , swapNextScreen, swapPrevScreen
  ) where

import Data.List (elemIndex, sortOn)
import Data.Maybe (fromMaybe, isJust, isNothing)

import Rivermonad.Core
import Rivermonad.Operations (windows)
import qualified Rivermonad.StackSet as W
import Rivermonad.Actions.Minimize (minimizedTag)
import Rivermonad.Util.NamedScratchpad (scratchpadWorkspaceTag)

data Direction1D = Next | Prev deriving (Show, Eq)

data WSType
  = AnyWS
  | EmptyWS
  | NonEmptyWS
  | HiddenWS            -- ^ not shown on any screen
  | HiddenNonEmptyWS
  | HiddenEmptyWS
  | WSIs (WindowSpace -> Bool)

nextWS, prevWS, shiftToNext, shiftToPrev :: X ()
nextWS = moveTo Next AnyWS
prevWS = moveTo Prev AnyWS
shiftToNext = shiftTo Next AnyWS
shiftToPrev = shiftTo Prev AnyWS

-- | Go back to the previously viewed workspace.
toggleWS :: X ()
toggleWS = do
  hs <- gets (W.hidden . windowset)
  case filter (regular . W.tag) hs of
    (w : _) -> windows (W.greedyView (W.tag w))
    [] -> pure ()

moveTo :: Direction1D -> WSType -> X ()
moveTo dir t = findWorkspace dir t 1 >>= mapM_ (windows . W.greedyView)

shiftTo :: Direction1D -> WSType -> X ()
shiftTo dir t = findWorkspace dir t 1 >>= mapM_ (windows . W.shift)

-- | The n-th workspace in the given direction matching the type, in the
-- order of the configuration (the scratchpad and minimised workspaces are
-- skipped).
findWorkspace :: Direction1D -> WSType -> Int -> X (Maybe WorkspaceId)
findWorkspace dir t n = do
  ws <- gets windowset
  tags <- asks (workspaces . config)
  let idx w = fromMaybe maxBound (elemIndex (W.tag w) tags)
      ordered = sortOn idx (filter (regular . W.tag) (W.workspaces ws))
      visibleTags = map (W.tag . W.workspace) (W.screens ws)
      ok w = case t of
        AnyWS -> True
        EmptyWS -> isNothing (W.stack w)
        NonEmptyWS -> isJust (W.stack w)
        HiddenWS -> W.tag w `notElem` visibleTags
        HiddenNonEmptyWS -> W.tag w `notElem` visibleTags && isJust (W.stack w)
        HiddenEmptyWS -> W.tag w `notElem` visibleTags && isNothing (W.stack w)
        WSIs p -> p w
      cur = W.currentTag ws
      (before, after) = break ((== cur) . W.tag) ordered
      cycleFrom = case dir of
        Next -> drop 1 after ++ before
        Prev -> reverse before ++ reverse (drop 1 after)
      candidates = filter ok cycleFrom
  pure $ if n < 1 || null candidates
    then Nothing
    else Just (W.tag (candidates !! ((n - 1) `mod` length candidates)))

------------------------------------------------------------------------------
-- Screens

screenBy :: Int -> X (Maybe WorkspaceId)
screenBy d = do
  ws <- gets windowset
  let scrs = sortOn W.screen (W.screens ws)
      n = length scrs
      S cur = W.screen (W.current ws)
      target = S ((cur + d) `mod` max 1 n)
  pure (W.lookupWorkspace target ws)

nextScreen, prevScreen, shiftNextScreen, shiftPrevScreen, swapNextScreen, swapPrevScreen :: X ()
nextScreen = screenBy 1 >>= mapM_ (windows . W.view)
prevScreen = screenBy (-1) >>= mapM_ (windows . W.view)
shiftNextScreen = screenBy 1 >>= mapM_ (windows . W.shift)
shiftPrevScreen = screenBy (-1) >>= mapM_ (windows . W.shift)
-- | Swap the current workspace with the one on the next screen.
swapNextScreen = screenBy 1 >>= mapM_ (windows . W.greedyView)
swapPrevScreen = screenBy (-1) >>= mapM_ (windows . W.greedyView)

-- | Not one of the window manager's own hidden workspaces.
regular :: WorkspaceId -> Bool
regular t = t /= scratchpadWorkspaceTag && t /= minimizedTag
