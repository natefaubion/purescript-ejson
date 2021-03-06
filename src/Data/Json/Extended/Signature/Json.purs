module Data.Json.Extended.Signature.Json where

import Prelude

import Control.Alt ((<|>))
import Data.Argonaut.Core as JS
import Data.Argonaut.Decode (class DecodeJson, decodeJson, (.?))
import Data.Argonaut.Encode (encodeJson)
import Data.Bifunctor (lmap)
import Data.Either as E
import Data.HugeInt as HI
import Data.HugeNum as HN
import Data.Int as Int
import Data.Json.Extended.Signature.Core (EJsonF(..), EJsonMap(..))
import Data.Maybe as M
import Data.StrMap as SM
import Data.Traversable as TR
import Matryoshka (Algebra, CoalgebraM)

encodeJsonEJsonF ∷ Algebra EJsonF JS.Json
encodeJsonEJsonF = case _ of
  Null → JS.jsonNull
  Boolean b → encodeJson b
  Integer i → encodeJson $ HN.toNumber $ HI.toHugeNum i -- TODO: bug in HI.toInt
  Decimal a → encodeJson $ HN.toNumber a
  String str → encodeJson str
  Array xs → encodeJson xs
  Map (EJsonMap xs) → JS.jsonSingletonObject "$obj" $ encodeJson xs

decodeJsonEJsonF ∷ CoalgebraM (E.Either String) EJsonF JS.Json
decodeJsonEJsonF =
  JS.foldJson
    (\_ → E.Right Null)
    (E.Right <<< Boolean)
    (E.Right <<< decodeNumber)
    (E.Right <<< String)
    decodeArray
    decodeObject
  where
  decodeNumber ∷ Number → EJsonF JS.Json
  decodeNumber a = case Int.fromNumber a of
    M.Just i → Integer $ HI.fromInt i
    M.Nothing → Decimal $ HN.fromNumber a

  decodeArray ∷ JS.JArray → E.Either String (EJsonF JS.Json)
  decodeArray arr = E.Right $ Array arr

  decodeObject
    ∷ JS.JObject
    → E.Either String (EJsonF JS.Json)
  decodeObject obj =
    unwrapBranch "$obj" strMapObject obj
    <|> unwrapBranch "$obj" arrTpls obj
    <|> unwrapNull obj
    <|> strMapObject obj

  arrTpls
    ∷ Array JS.Json
    → E.Either String (EJsonF JS.Json)
  arrTpls arr = do
    map Map $ map EJsonMap $ TR.traverse decodeJson arr

  strMapObject
    ∷ SM.StrMap JS.Json
    → E.Either String (EJsonF JS.Json)
  strMapObject =
    pure
    <<< Map
    <<< EJsonMap
    <<< map (lmap encodeJson)
    <<< SM.toUnfoldable

  unwrapBranch
    ∷ ∀ t
    . TR.Traversable t
    ⇒ DecodeJson (t JS.Json)
    ⇒ String
    → (t JS.Json → E.Either String (EJsonF JS.Json))
    → JS.JObject
    → E.Either String (EJsonF JS.Json)
  unwrapBranch key trCodec obj =
    getOnlyKey key obj
      >>= decodeJson
      >>= trCodec

  unwrapNull
    ∷ JS.JObject
    → E.Either String (EJsonF JS.Json)
  unwrapNull =
    getOnlyKey "$na" >=>
      JS.foldJsonNull
        (E.Left "Expected null")
        (\_ → pure Null)

  unwrapLeaf
    ∷ ∀ b
    . String
    → (JS.Json → E.Either String b)
    → (b → EJsonF JS.Json)
    → JS.JObject
    → E.Either String (EJsonF JS.Json)
  unwrapLeaf key decode codec =
    getOnlyKey key
      >=> decode
      >>> map codec

  getOnlyKey
    ∷ String
    → JS.JObject
    → E.Either String JS.Json
  getOnlyKey key obj = case SM.keys obj of
    [_] →
      obj .? key
    keys →
      E.Left $ "Expected '" <> key <> "' to be the only key, but found: " <> show keys
