{-# LANGUAGE ScopedTypeVariables #-}
-- | Process helpers for modules that match windows to the programs that
-- made them ("Rivermonad.Hooks.WindowSwallowing",
-- "Rivermonad.Actions.SpawnOn").
module Rivermonad.Util.Process
  ( ancestorsOf
  ) where

import Control.Exception (SomeException, evaluate, try)

-- | Parent, grandparent... of a process (nearest first, without init),
-- read from @/proc@. Empty if the process is gone.
ancestorsOf :: Int -> IO [Int]
ancestorsOf = go (64 :: Int)
  where
    go 0 _ = pure []
    go n pid = parentOf pid >>= \case
      Just pp | pp > 1 -> (pp :) <$> go (n - 1) pp
      _ -> pure []

parentOf :: Int -> IO (Maybe Int)
parentOf pid = do
  r <- try (readFile ("/proc/" ++ show pid ++ "/stat") >>= \s -> evaluate (length s) >> pure s)
  pure $ case r of
    Left (_ :: SomeException) -> Nothing
    -- "pid (comm) state ppid ...": the command may contain spaces and ')'
    Right s -> case words (reverse (takeWhile (/= ')') (reverse s))) of
      _state : ppid : _ | [(n, "")] <- reads ppid -> Just n
      _ -> Nothing
