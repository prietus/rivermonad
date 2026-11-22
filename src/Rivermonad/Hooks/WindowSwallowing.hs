-- | A program started from a terminal takes the terminal's place, as in
-- @XMonad.Hooks.WindowSwallowing@: run @mpv video.mkv@ or @imv photo.png@
-- in foot and the video or image appears where the terminal was; close it
-- and the terminal comes back in the same place.
--
-- > main = rivermonad $ swallowWindows (appId =? "foot") (pure True) myConfig
--
-- The first query picks the windows that may be swallowed (terminals),
-- the second the windows that may swallow them. A window swallows a
-- terminal when its process descends from the terminal's (river reports
-- the pid of every window). The terminal waits, hidden, on the
-- scratchpads' workspace; the pairing survives a restart of rivermonad.
--
-- Programs that hand their window to a process that already exists (a
-- browser already running, @foot --server@ clients) are not children of
-- the terminal, so they do not swallow it.
module Rivermonad.Hooks.WindowSwallowing
  ( swallowWindows
  , swallowManageHook
  , swallowEventHook
  ) where

import Control.Monad (filterM)
import qualified Data.Map.Strict as M
import Data.Maybe (listToMaybe)
import Data.Monoid (Endo (..))

import Rivermonad.Core
import Rivermonad.Operations (windows)
import qualified Rivermonad.StackSet as W
import qualified Rivermonad.Util.ExtensibleState as XS
import Rivermonad.Util.NamedScratchpad (scratchpadWorkspaceTag)
import Rivermonad.Util.Process (ancestorsOf)
import Rivermonad.Wayland.Protocol (Event (..), RiverWindowV1Event (..))

-- | Child window identifier -> the identifier of the terminal it swallowed.
-- Identifiers, unlike window ids, stay the same across a restart.
newtype Swallowed = Swallowed (M.Map String String) deriving (Show, Read)

instance ExtensionClass Swallowed where
  initialValue = Swallowed M.empty
  extensionType = PersistentExtension

-- | Add both hooks to a configuration.
swallowWindows :: Query Bool -> Query Bool -> XConfig -> XConfig
swallowWindows parentQ childQ conf = conf
  { -- after the rest of the manage hook (insertPosition and the like), so
    -- the window ends up exactly where the terminal was
    manageHook = swallowManageHook parentQ childQ <> manageHook conf
  , handleEventHook = \e -> (<>) <$> handleEventHook conf e <*> swallowEventHook e
  }

-- | When a new window matches the child query, look for a terminal among
-- the ancestors of its process and take its place.
swallowManageHook :: Query Bool -> Query Bool -> ManageHook
swallowManageHook parentQ childQ = do
  isChild <- childQ
  if not isChild then pure (Endo id) else do
    w <- ask
    liftX (findParent parentQ w) >>= \case
      Nothing -> pure (Endo id)
      Just p -> do
        infos <- liftX (gets windowInfo)
        case (M.lookup w infos, M.lookup p infos) of
          (Just ci, Just pi') | not (null (wiIdentifier ci)), not (null (wiIdentifier pi')) ->
            liftX (XS.modify (\(Swallowed m) -> Swallowed (M.insert (wiIdentifier ci) (wiIdentifier pi') m)))
          _ -> pure ()
        pure (Endo (swallow p w))

-- | When a window that swallowed a terminal closes, put the terminal back.
swallowEventHook :: Event -> X All
swallowEventHook = \case
  EvRiverWindowV1 c RiverWindowV1Closed -> do
    infos <- gets windowInfo
    Swallowed m <- XS.get
    case M.lookup c infos >>= \ci -> (,) (wiIdentifier ci) <$> M.lookup (wiIdentifier ci) m of
      Nothing -> pure ()
      Just (cid, pid') -> do
        XS.put (Swallowed (M.delete cid m))
        ws <- gets windowset
        let parent = listToMaybe [ p | (p, i) <- M.toList infos, wiIdentifier i == pid', W.member p ws ]
            focused = W.peek ws == Just c
            back p = (if focused then W.focusWindow p else id) . replace c p . W.delete' p
        mapM_ (windows . back) parent
    pure (All True)
  _ -> pure (All True)

-- | The window among the ancestors of @w@'s process (nearest first) that
-- matches the query.
findParent :: Query Bool -> Window -> X (Maybe Window)
findParent q w = do
  infos <- gets windowInfo
  ws <- gets windowset
  case M.lookup w infos >>= wiPid of
    Nothing -> pure Nothing
    Just pid -> do
      ancestors <- io (ancestorsOf pid)
      let byPid a = [ p | (p, i) <- M.toList infos, p /= w, wiPid i == Just a, W.member p ws ]
      listToMaybe <$> filterM (runQuery q) (concatMap byPid ancestors)

-- | The child @w@ takes the place of the terminal @p@, which goes to the
-- hidden scratchpad workspace.
swallow :: Window -> Window -> WindowSet -> WindowSet
swallow p w s0 =
  let s1 = replace p w (W.delete' w s0)
      s2 = case M.lookup p (W.floating s0) of
             Just rr -> W.float w rr s1
             Nothing -> s1
  in hide p (ensureWorkspace s2)

-- | Replace one window with another in whatever stack it is.
replace :: Window -> Window -> WindowSet -> WindowSet
replace old new = W.mapWorkspace $ \wsp -> wsp { W.stack = fmap sub (W.stack wsp) }
  where
    sub (W.Stack f u d) = W.Stack (r f) (map r u) (map r d)
    r x = if x == old then new else x

hide :: Window -> WindowSet -> WindowSet
hide p = W.mapWorkspace $ \wsp ->
  if W.tag wsp /= scratchpadWorkspaceTag then wsp
  else wsp { W.stack = Just (W.Stack p [] (W.integrate' (W.stack wsp))) }

ensureWorkspace :: WindowSet -> WindowSet
ensureWorkspace s
  | W.tagMember scratchpadWorkspaceTag s = s
  | otherwise = s { W.hidden = W.hidden s ++ [W.Workspace scratchpadWorkspaceTag (W.layout (W.workspace (W.current s))) Nothing] }
