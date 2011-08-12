{-# LANGUAGE NoImplicitPrelude #-}
module FOL.Language.Common
    ( Real
    , Name (..)
    , name2str
    , module Prelude
    )
    where

import Prelude hiding (Real)

type Real = Double

data Name = Name String deriving (Eq, Show)

name2str :: Name -> String
name2str (Name n) = n
