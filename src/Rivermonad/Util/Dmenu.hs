-- | Menus through an external dmenu-style program (fuzzel by default), as
-- in @XMonad.Util.Dmenu@.
--
-- The menu runs in the background, so the window manager keeps working
-- while it is open (in xmonad the menu blocks it). Because of that the
-- choice is handed to a continuation instead of being returned:
--
-- > , ("M-s", menu ["suspend", "reboot"] $ \case
-- >     "suspend" -> spawn "systemctl suspend"
-- >     "reboot"  -> spawn "systemctl reboot"
-- >     _         -> pure ())
--
-- Nothing happens if the menu is cancelled (Esc) or the program fails.
module Rivermonad.Util.Dmenu
  ( menu
  , menuArgs
  , menuMap
  , menuMapArgs
  , dmenu
  , defaultMenuCommand
  ) where

import Control.Concurrent (forkIO)
import Control.Concurrent.Chan (writeChan)
import qualified Control.Exception as E
import Control.Monad (void)
import qualified Data.Map.Strict as M
import System.Exit (ExitCode (..))
import System.Process (proc, readCreateProcessWithExitCode)

import Rivermonad.Core

-- | The program and arguments 'menu' uses: @fuzzel --dmenu@.
defaultMenuCommand :: (String, [String])
defaultMenuCommand = ("fuzzel", ["--dmenu"])

-- | Show the options in fuzzel and run the continuation with the one
-- picked (or the text typed, if it matches none).
menu :: [String] -> (String -> X ()) -> X ()
menu = uncurry menuArgs defaultMenuCommand

-- | Alias of 'menu', for xmonad configs.
dmenu :: [String] -> (String -> X ()) -> X ()
dmenu = menu

-- | Any dmenu-style program: it gets the options on stdin, one per line,
-- and prints the choice on stdout.
--
-- > menuArgs "fuzzel" ["--dmenu", "--prompt", "power › "] options act
menuArgs :: String -> [String] -> [String] -> (String -> X ()) -> X ()
menuArgs cmd args opts k = do
  ch <- asks inputs
  void $ io $ forkIO $ do
    r <- E.try @E.SomeException (readCreateProcessWithExitCode (proc cmd args) (unlines opts))
    case r of
      Right (ExitSuccess, out, _)
        | choice <- takeWhile (/= '\n') out, not (null choice) -> writeChan ch (InRun (k choice))
      _ -> pure ()

-- | Like 'menu', but the options are the keys of a map and the
-- continuation gets the value of the one picked.
menuMap :: M.Map String a -> (a -> X ()) -> X ()
menuMap = uncurry menuMapArgs defaultMenuCommand

menuMapArgs :: String -> [String] -> M.Map String a -> (a -> X ()) -> X ()
menuMapArgs cmd args m k =
  menuArgs cmd args (M.keys m) (\c -> maybe (pure ()) k (M.lookup c m))
