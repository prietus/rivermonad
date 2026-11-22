-- | Programs open on the workspace they were started from, as in
-- @XMonad.Actions.SpawnOn@, even if you have moved to another one while
-- they load (a browser, an IDE).
--
-- > manageHook = manageSpawn <> myManageHook
-- > , ("M-b", spawnHere "firefox")
-- > , ("M-S-m", spawnOn "web" "thunderbird")
--
-- The window is recognised by its process: the one started or any of its
-- children. Programs that hand the window to a process already running
-- (a second Firefox, @footclient@) are not recognised and open where they
-- normally would.
module Rivermonad.Actions.SpawnOn
  ( spawnOn
  , spawnHere
  , spawnAndDo
  , manageSpawn
  ) where

import Data.List (find)
import qualified Data.Map.Strict as M
import Data.Monoid (Endo (..))

import Rivermonad.Core
import Rivermonad.ManageHook (doShift)
import Rivermonad.Operations (spawnPID)
import qualified Rivermonad.StackSet as W
import qualified Rivermonad.Util.ExtensibleState as XS
import Rivermonad.Util.Process (ancestorsOf)

-- | Started processes and what to do with their first window, newest first.
newtype Spawned = Spawned [(Int, ManageHook)]

instance ExtensionClass Spawned where
  initialValue = Spawned []

-- | Start a command; its windows open on the given workspace.
spawnOn :: WorkspaceId -> String -> X ()
spawnOn ws = spawnAndDo (doShift ws)

-- | Start a command; its windows open on the current workspace.
spawnHere :: String -> X ()
spawnHere cmd = gets (W.currentTag . windowset) >>= \t -> spawnOn t cmd

-- | Start a command and apply a manage hook to its first window.
spawnAndDo :: ManageHook -> String -> X ()
spawnAndDo mh cmd = spawnPID cmd >>= \case
  Nothing -> pure ()
  -- keep the last 20, in case some never open a window
  Just pid -> XS.modify (\(Spawned l) -> Spawned (take 20 ((fromIntegral pid, mh) : l)))

-- | Put this in your manage hook.
manageSpawn :: ManageHook
manageSpawn = do
  w <- ask
  mpid <- liftX (gets (\s -> M.lookup w (windowInfo s) >>= wiPid))
  case mpid of
    Nothing -> pure (Endo id)
    Just pid -> do
      Spawned l <- liftX XS.get
      family <- liftX (io ((pid :) <$> ancestorsOf pid))
      case find ((`elem` family) . fst) l of
        Nothing -> pure (Endo id)
        Just (p, mh) -> do
          liftX (XS.put (Spawned (filter ((/= p) . fst) l)))
          mh
