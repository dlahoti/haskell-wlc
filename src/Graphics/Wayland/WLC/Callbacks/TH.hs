{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}

module Graphics.Wayland.WLC.Callbacks.TH
  ( WrapFun (..), mkWrapFun
  , CallbackType (..), mkCallback, mkCallback'
  ) where

import Graphics.Wayland.WLC.Internal.TH
import Graphics.Wayland.WLC.Types.Internal

import Language.Haskell.TH

import Foreign
import Foreign.C

import Control.Applicative ((<*>))
import Control.Monad (join, when)

import Data.Char (isUpper, toLower)

class WrapFun fn where
  wrapFun :: fn -> IO (FunPtr (Marshalled fn))

class CallbackType cbt where
  type Callback cbt
  setCallback' :: cbt -> FunPtr (Marshalled (Callback cbt)) -> IO ()

mkWrapFun :: String -> Type -> Q [Dec]
mkWrapFun name t = do
  let wrapName = mkName $ "wrap" ++ name
      fnName = mkName "fn"
      wrapper = UInfixE (VarE wrapName) (VarE '($)) $ beforeAfterFnt 'unmarshal 'id fnName t
  return
    [ ForeignD . ImportF CCall Safe "wrapper" wrapName $ AppT (AppT ArrowT $ AppT (ConT ''Marshalled) t) $ AppT (ConT ''IO) $ AppT (ConT ''FunPtr) $ AppT (ConT ''Marshalled) t
    , InstanceD [] (AppT (ConT ''WrapFun) t)
        [FunD 'wrapFun [Clause [VarP fnName] (NormalB wrapper) []]]
    ]

mkCallback :: String -> String -> Q Type -> Q [Dec]
mkCallback str cfn fnt' = do
  fnt <- fnt'
  let name = mkName str
      cName = mkName $ "on" ++ str
  alreadyWrapped <- isInstance ''WrapFun [fnt]
  wrapper <- if alreadyWrapped then return [] else mkWrapFun str fnt
  return $ wrapper ++
    [ ForeignD $ ImportF CCall Safe cfn cName
        $ AppT (AppT ArrowT $ AppT (ConT ''FunPtr) $ AppT (ConT ''Marshalled) fnt) $ AppT (ConT ''IO) $ TupleT 0
    , DataD [] name [] [NormalC name []] []
    , InstanceD [] (AppT (ConT ''CallbackType) (ConT name))
        [ TySynInstD ''Callback $ TySynEqn [ConT name] fnt
        , FunD 'setCallback' [Clause [WildP] (NormalB $ VarE cName) []]
        ]
    ]

mkCallback' :: String -> Q Type -> Q [Dec]
mkCallback' str = mkCallback str cstr where
  cstr = "wlc_set" ++ (replFn =<< str) ++ "_cb"
  replFn c
    | isUpper c = ['_', toLower c]
    | otherwise = [c]
