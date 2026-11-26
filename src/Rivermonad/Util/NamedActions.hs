-- | Key bindings with a description, and a cheat sheet of them in fuzzel,
-- after @XMonad.Util.NamedActions@.
--
-- > main = rivermonad $ addDescrKeysP "M-<F1>" myConfig
-- >   [ ("M-b", "Firefox (focus or start)", runOrRaise "firefox" (appId =? "firefox"))
-- >   , ("M-g", "Go to a window",           gotoMenu)
-- >   ]
--
-- @M-<F1>@ opens the list ("M-b    Firefox (focus or start)"); typing
-- filters it and Enter runs the chosen action, so it doubles as a command
-- palette. The keys are added like 'additionalKeysP' does. After your keys
-- the list goes on with the default ones you have not replaced, so it is a
-- cheat sheet of everything; the default cheat sheet key, @M-S-\/@ (see
-- "Rivermonad.Config"), shows this same list.
--
-- Every action can also be run from scripts over IPC, by its key or its
-- description (they are added to 'ipcActions'):
--
-- > rivermonad --ipc '{"Action":{"Run":"M-g"}}'
-- > rivermonad --ipc '"Actions"'      # the names
module Rivermonad.Util.NamedActions
  ( addDescrKeysP
  , showKeysMenu
  ) where

import qualified Data.Map.Strict as M
import Data.Maybe (mapMaybe)

import Rivermonad.Config (defaultKeysRows, helpKeys, keysMenu)
import Rivermonad.Core
import Rivermonad.Util.EZConfig (mkKeymap, readKey)

-- | Add described keys, and a key that shows them all, followed by the
-- default keys they have not replaced. The default cheat sheet key
-- (@mod-shift-\/@) shows the same list.
addDescrKeysP :: String -> XConfig -> [(String, String, X ())] -> XConfig
addDescrKeysP helpKey conf ks = conf
  { keys = \cc -> M.unions
      [ mkKeymap cc [ (k, a) | (k, _, a) <- ks ]
      , mkKeymap cc [(helpKey, help)]
      , M.fromList [ (k, help) | k <- helpKeys cc ]
      , keys conf cc ]
  , ipcActions = ipcActions conf ++ concat [ [(k, a), (d, a)] | (k, d, a) <- ks ]
                                 ++ [(helpKey, help)] }
  where
    help = asks config >>= \cc ->
      let mine = mapMaybe (readKey cc) (helpKey : [ k | (k, _, _) <- ks ])
      in keysMenu ([ (pretty k, d, a) | (k, d, a) <- ks ] ++ defaultKeysRows cc (mine ++ helpKeys cc))

-- | The cheat sheet of just these keys: pick an entry to run it.
showKeysMenu :: [(String, String, X ())] -> X ()
showKeysMenu ks = keysMenu [ (pretty k, d, a) | (k, d, a) <- ks ]

-- | "M-S-<Return>" -> "Super+Shift+Return".
pretty :: String -> String
pretty = go
  where
    go ('M' : '-' : r) = "Super+" ++ go r
    go ('S' : '-' : r) = "Shift+" ++ go r
    go ('C' : '-' : r) = "Ctrl+" ++ go r
    go ('M' : '1' : '-' : r) = "Alt+" ++ go r
    go ('<' : r) = takeWhile (/= '>') r ++ go (drop 1 (dropWhile (/= '>') r))
    go (c : r) = c : go r
    go [] = []
