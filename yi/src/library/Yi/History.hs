{-# LANGUAGE ScopedTypeVariables, DeriveDataTypeable, TemplateHaskell, FlexibleInstances,
  CPP, StandaloneDeriving, DeriveGeneric #-}
{-# LANGUAGE Rank2Types #-}

-- Copyright (c) 2005,2007,2008 Jean-Philippe Bernardy

-- "command history" implementation

module Yi.History where

import Control.Lens
import Data.Binary
#if __GLASGOW_HASKELL__ < 708
import Data.DeriveTH
#else
import GHC.Generics (Generic)
#endif
import Data.List
import Data.Default
import Data.Typeable
import qualified Data.Map as M
import Yi.Buffer
import Yi.Dynamic
import Yi.Editor

type Histories = M.Map String History


data History = History {_historyCurrent :: Int,
                        _historyContents :: [String],
                        _historyPrefix :: String}

    deriving (Show, Typeable)
instance Default History where
    def = History (-1) [] ""
#if __GLASGOW_HASKELL__ < 708
$(derive makeBinary ''History)
#else
deriving instance Generic History
instance Binary History
#endif

instance YiVariable (M.Map String History)

dynKeyA :: (Default v, Ord k) => k -> Lens' (M.Map k v) v
dynKeyA key = lens (M.findWithDefault def key) (flip (M.insert key))

miniBuffer :: String
miniBuffer = "minibuffer"

historyUp :: EditorM ()
historyUp = historyMove miniBuffer 1

historyDown :: EditorM ()
historyDown = historyMove miniBuffer (-1)

historyStart :: EditorM ()
historyStart = historyStartGen miniBuffer

-- | Start an input session with History
historyStartGen :: String -> EditorM ()
historyStartGen ident = do
  (History _cur cont pref) <- use (dynA . dynKeyA ident)
  assign (dynA . dynKeyA ident) (History 0 (nub ("":cont)) pref)

historyFinish :: EditorM ()
historyFinish = historyFinishGen miniBuffer (withBuffer0 elemsB)

-- | Finish the current input session with history.
historyFinishGen :: String -> EditorM String -> EditorM ()
historyFinishGen ident getCurValue = do
  (History _cur cont pref) <- use (dynA . dynKeyA ident)
  curValue <- getCurValue
  let cont' = dropWhile (curValue==) . dropWhile null $ cont
  length curValue `seq` -- force the new value, otherwise we'll hold on to the buffer from which it's computed
    cont'         `seq` -- force checking the top of the history, otherwise we'll build up thunks
    assign (dynA . dynKeyA ident) $ History (-1) (curValue:cont') pref

historyFind :: [String] -> Int -> Int -> Int -> String -> Int
historyFind cont len cur delta pref =
  case (next < 0, next >= len) of
    (True,_) -> next
    (_,True) -> next
    (_,_) -> if pref `isPrefixOf` (cont !! next)
      then next
      else historyFind cont len cur deltaLarger pref
  where
    next = cur + delta
    deltaLarger = delta + signum delta

historyMove :: String -> Int -> EditorM ()
historyMove ident delta = (withBuffer0 . replaceBufferContent) =<< historyMoveGen ident delta (withBuffer0 elemsB)

historyMoveGen :: String -> Int -> EditorM String -> EditorM String
historyMoveGen ident delta getCurValue = do
  (History cur cont pref) <- use (dynA . dynKeyA ident)

  curValue <- getCurValue
  let len = length cont
      next = historyFind cont len cur delta pref
      nextValue = cont !! next
  case (next < 0, next >= len) of
    (True, _) -> do printMsg $ "end of " ++ ident ++ " history, no next item."
                    return curValue
    (_, True) -> do printMsg $ "beginning of " ++ ident ++ " history, no previous item."
                    return curValue
    (_,_) -> do
         assign (dynA . dynKeyA ident) (History next (take cur cont ++ [curValue] ++ drop (cur+1) cont) pref)
         return nextValue

historyPrefixSet :: String -> EditorM ()
historyPrefixSet = historyPrefixSet' miniBuffer

historyPrefixSet' :: String -> String -> EditorM ()
historyPrefixSet' ident pref = do
  (History cur cont _pref) <- use (dynA . dynKeyA ident)
  assign (dynA . dynKeyA ident) (History cur cont pref)
  return ()
