-- | Key sequences and modes, as in @XMonad.Actions.Submap@: after the
-- first key, a few more keys do something without holding Super.
--
-- > , ("M-r", submapP myConf          -- M-r, then h/l/j/k resize, once
-- >     [ ("h", sendMessage Shrink), ("l", sendMessage Expand) ])
-- > , ("M-S-r", modeP myConf         -- the same, until Esc or Enter
-- >     [ ("h", sendMessage Shrink), ("l", sendMessage Expand) ])
--
-- While a submap is active its keys go to it, not to the focused window;
-- Escape leaves it. Other keys are not caught (river only reports the keys
-- bound), so they still reach the window and the submap stays active
-- until one of its keys or Escape is pressed.
module Rivermonad.Actions.Submap
  ( submap
  , submapP
  , mode
  , modeP
  , exitSubmap
  ) where

import Control.Monad (forM, forM_)
import qualified Data.Map.Strict as M

import Rivermonad.Core
import Rivermonad.Keysym (KeyMask, KeySym, xK_Escape, xK_Return)
import Rivermonad.Wayland.Wire (ObjectId)
import qualified Rivermonad.Util.ExtensibleState as XS
import Rivermonad.Util.EZConfig (mkKeymap)
import Rivermonad.Wayland.Protocol (riverXkbBindingV1Destroy, riverXkbBindingV1Enable, riverXkbBindingsV1GetXkbBinding)

-- | The bindings of the active submap.
newtype Active = Active [ObjectId]

instance ExtensionClass Active where
  initialValue = Active []

-- | Run one of these keys' actions, then go back to the normal keys.
submap :: M.Map (KeyMask, KeySym) (X ()) -> X ()
submap keymap = activate (M.map (\a -> exitSubmap >> a) keymap)

-- | 'submap' with EZConfig-style keys ("h", "S-l", "<Left>").
submapP :: XConfig -> [(String, X ())] -> X ()
submapP conf = submap . mkKeymap conf

-- | The keys stay active after each action, until Escape or Enter.
mode :: M.Map (KeyMask, KeySym) (X ()) -> X ()
mode keymap = activate (M.insert (0, xK_Return) exitSubmap keymap)

modeP :: XConfig -> [(String, X ())] -> X ()
modeP conf = mode . mkKeymap conf

-- | Leave the active submap or mode.
exitSubmap :: X ()
exitSubmap = do
  Active bs <- XS.get
  c <- asks conn
  io (mapM_ (riverXkbBindingV1Destroy c) bs)
  modify $ \s -> s { keyActions = foldr M.delete (keyActions s) bs }
  XS.put (Active [])

activate :: M.Map (KeyMask, KeySym) (X ()) -> X ()
activate keymap = do
  exitSubmap
  c <- asks conn
  xkb <- asks (gXkb . globals)
  ss <- gets (M.keys . seats)
  let withEsc = M.insert (0, xK_Escape) exitSubmap keymap
  bound <- fmap concat $ forM ss $ \seat ->
    forM (M.toList withEsc) $ \((m, k), act) -> do
      b <- io (riverXkbBindingsV1GetXkbBinding c xkb seat k m)
      pure (b, act)
  -- key actions run inside a manage sequence, where enabling is allowed
  io (forM_ bound (riverXkbBindingV1Enable c . fst))
  modify $ \s -> s { keyActions = M.union (M.fromList bound) (keyActions s) }
  XS.put (Active (map fst bound))
