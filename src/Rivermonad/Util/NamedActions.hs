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
-- palette. The keys are added like 'additionalKeysP' does.
module Rivermonad.Util.NamedActions
  ( addDescrKeysP
  , showKeysMenu
  ) where

import qualified Data.Map.Strict as M

import Rivermonad.Core
import Rivermonad.Util.Dmenu (menuArgs)
import Rivermonad.Util.EZConfig (additionalKeysP)

-- | Add described keys, and a key that shows them all.
addDescrKeysP :: String -> XConfig -> [(String, String, X ())] -> XConfig
addDescrKeysP helpKey conf ks =
  additionalKeysP conf ((helpKey, showKeysMenu ks) : [ (k, a) | (k, _, a) <- ks ])

-- | The cheat sheet: pick an entry to run it.
showKeysMenu :: [(String, String, X ())] -> X ()
showKeysMenu ks = menuArgs "fuzzel" ["--dmenu", "--no-sort", "--prompt", "keys › ", "--width", "60"] (map fst entries) $ \c ->
  maybe (pure ()) id (M.lookup c (M.fromList entries))
  where
    width = maximum (0 : [ length (pretty k) | (k, _, _) <- ks ])
    entries = [ (pretty k ++ replicate (width - length (pretty k) + 3) ' ' ++ d, a) | (k, d, a) <- ks ]

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
