{-# LANGUAGE DeriveFunctor       #-}
{-# LANGUAGE DeriveFoldable      #-}
{-# LANGUAGE DeriveTraversable   #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE OverloadedStrings   #-}

module Unison.Util.Pretty (
   Pretty,
   bulleted,
   -- breakable
   column2,
   commas,
   dashed,
   flatMap,
   group,
   hang',
   hang,
   indent,
   indentAfterNewline,
   indentN,
   indentNAfterNewline,
   leftPad,
   lines,
   linesSpaced,
   lit,
   map,
   minWidth,
   newline,
   numbered,
   orElse,
   parenthesize,
   parenthesizeCommas,
   parenthesizeIf,
   preferredWidth,
   render,
   renderUnbroken,
   rightPad,
   sep,
   sepSpaced,
   softbreak,
   spaceIfBreak,
   spaced,
   spacedMap,
   text,
   toANSI,
   toPlain,
   wrap,
   wrapWords,
   black, red, green, yellow, blue, purple, cyan, white, hiBlack, hiRed, hiGreen, hiYellow, hiBlue, hiPurple, hiCyan, hiWhite, bold
  ) where

import           Data.Foldable                  ( toList )
import           Data.List                      ( foldl' , scanl', intersperse )
import           Data.Sequence                  ( Seq )
import           Data.String                    ( IsString , fromString )
import           Data.Text                      ( Text )
import           Prelude                 hiding ( lines , map )
import qualified Unison.Util.ColorText         as CT
import           Unison.Util.Monoid             ( intercalateMap )
import qualified Data.ListLike                 as LL
import qualified Data.Sequence                 as Seq
import qualified Data.Text                     as Text

type Width = Int

data Pretty s = Pretty { delta :: Delta, minDelta :: Delta, out :: F s (Pretty s) }
  deriving Show
data F s r
  = Empty | Group r | Lit s | Wrap (Seq r) | OrElse r r | Append (Seq r)
  deriving (Show, Foldable, Traversable, Functor)

map :: LL.ListLike s2 Char => (s -> s2) -> Pretty s -> Pretty s2
map f p = case out p of
  Append ps -> foldMap (map f) ps
  Empty -> mempty
  Group p -> group (map f p)
  Lit s -> lit' (foldMap chDelta $ LL.toList s2) s2 where s2 = f s
  OrElse p1 p2 -> orElse (map f p1) (map f p2)
  Wrap p -> wrap_ (map f <$> p)

flatMap :: (s -> Pretty s2) -> Pretty s -> Pretty s2
flatMap f p = case out p of
  Append ps -> foldMap (flatMap f) ps
  Empty -> mempty
  Group p -> group (flatMap f p)
  Lit s -> f s
  OrElse p1 p2 -> orElse (flatMap f p1) (flatMap f p2)
  Wrap p -> wrap_ (flatMap f <$> p)

lit :: (IsString s, LL.ListLike s Char) => s -> Pretty s
lit s = lit' (foldMap chDelta $ LL.toList s) s

lit' :: Delta -> s -> Pretty s
lit' d s = Pretty d d (Lit s)

orElse :: Pretty s -> Pretty s -> Pretty s
orElse p1 p2 = Pretty (delta p1) (minDelta p2) (OrElse p1 p2)

wrap :: IsString s => [Pretty s] -> Pretty s
wrap [] = mempty
wrap (p:ps) = wrap_ . Seq.fromList $ p : fmap (softbreak <>) ps

wrap_ :: Seq (Pretty s) -> Pretty s
wrap_ ps = Pretty (foldMap delta ps) (foldMap minDelta ps) (Wrap ps)

wrapWords :: IsString s => String -> Pretty s
wrapWords = wrap . fmap fromString . words

group :: Pretty s -> Pretty s
group p = Pretty (delta p) (minDelta p) (Group p)

toANSI :: Width -> Pretty CT.ColorText -> String
toANSI avail p = CT.toANSI (render avail p)

toPlain :: Width -> Pretty CT.ColorText -> String
toPlain avail p = CT.toPlain (render avail p)

renderUnbroken :: (Monoid s, IsString s) => Pretty s -> s
renderUnbroken = render maxBound

render :: (Monoid s, IsString s) => Width -> Pretty s -> s
render avail p =
  if preferredWidth p <= avail || minWidth p > avail then flow p
  else render avail (break1 p)
  where
    break1 p = case out p of
      Append ps -> foldMap break1 ps
      Empty -> mempty
      Group p -> p
      Lit _ -> p
      OrElse _ p -> break1 p
      Wrap ps -> go mempty ps where
        go _ Seq.Empty = mempty
        go start ps = let
          ws = drop 1 . scanl' (<>) start $ delta <$> (toList ps)
          n = length $ takeWhile (\(Delta _ w) -> w <= avail) ws
          rem = Seq.drop n ps
          s2 = Seq.take n ps <> (break1 <$> Seq.take 1 rem)
          hd = flows' s2
          in hd <> go (start <> delta hd) (Seq.drop 1 rem)

    flows' ps = lit' (foldMap delta ps) (foldMap flow ps)
    flow p = case out p of
      Append ps -> foldMap flow ps
      Empty -> mempty
      Group p -> flow p
      Lit s -> s
      OrElse p _ -> flow p
      Wrap ps -> foldMap flow ps

newline :: IsString s => Pretty s
newline = lit' (chDelta '\n') (fromString "\n")

spaceIfBreak :: IsString s => Pretty s
spaceIfBreak = "" `orElse` " "

softbreak :: IsString s => Pretty s
softbreak = " " `orElse` newline

spaced :: (Foldable f, IsString s) => f (Pretty s) -> Pretty s
spaced = intercalateMap softbreak id

spacedMap :: (Foldable f, IsString s) => (a -> Pretty s) -> f a -> Pretty s
spacedMap f as = spaced . fmap f $ toList as

commas :: (Foldable f, IsString s) => f (Pretty s) -> Pretty s
commas = intercalateMap ("," <> softbreak) id

parenthesizeCommas :: (Foldable f, IsString s) => f (Pretty s) -> Pretty s
parenthesizeCommas fs = parenthesize $
  spaceIfBreak <>
  intercalateMap ("," <> softbreak <> spaceIfBreak <> spaceIfBreak) id fs

sepSpaced :: (Foldable f, IsString s) => Pretty s -> f (Pretty s) -> Pretty s
sepSpaced between = sep (between <> softbreak)

sep :: (Foldable f, IsString s) => Pretty s -> f (Pretty s) -> Pretty s
sep between = intercalateMap between id

parenthesize :: IsString s => Pretty s -> Pretty s
parenthesize p = group $ "(" <> p <> ")"

parenthesizeIf :: IsString s => Bool -> Pretty s -> Pretty s
parenthesizeIf False s = s
parenthesizeIf True s = parenthesize s

lines :: (Foldable f, IsString s) => f (Pretty s) -> Pretty s
lines = intercalateMap newline id

linesSpaced :: (Foldable f, IsString s) => f (Pretty s) -> Pretty s
linesSpaced ps = lines (intersperse " " $ toList ps)

bulleted :: (Foldable f, LL.ListLike s Char, IsString s) => f (Pretty s) -> Pretty s
bulleted = intercalateMap newline (\b -> "* " <> indentAfterNewline "  " b)

dashed :: (Foldable f, LL.ListLike s Char, IsString s) => f (Pretty s) -> Pretty s
dashed = intercalateMap newline (\b -> "- " <> indentAfterNewline "  " b)

numbered :: (Foldable f, LL.ListLike s Char, IsString s) => (Int -> Pretty s) -> f (Pretty s) -> Pretty s
numbered num ps = column2 (fmap num [1..] `zip` toList ps)

leftPad, rightPad :: IsString s => Int -> Pretty s -> Pretty s
leftPad n p =
  let rem = n - preferredWidth p
  in if rem > 0 then fromString (replicate rem ' ') <> p
     else p
rightPad n p =
  let rem = n - preferredWidth p
  in if rem > 0 then p <> fromString (replicate rem ' ')
     else p

column2 :: (LL.ListLike s Char, IsString s) => [(Pretty s, Pretty s)] -> Pretty s
column2 rows = lines (group <$> alignedRows) where
  maxWidth = foldl' max 0 (preferredWidth . fst <$> rows) + 1
  alignedRows = [ rightPad maxWidth col0 <> indentNAfterNewline maxWidth col1
                | (col0, col1) <- rows ]

text :: IsString s => Text -> Pretty s
text t = fromString (Text.unpack t)

hang' :: (LL.ListLike s Char, IsString s) => Pretty s -> Pretty s -> Pretty s -> Pretty s
hang' from by p =
  (from <> " " <> p) `orElse`
  (from <> "\n" <> indent by (group p))

hang :: (LL.ListLike s Char, IsString s) => Pretty s -> Pretty s -> Pretty s
hang from p = hang' from "  " p

indent :: (LL.ListLike s Char, IsString s) => Pretty s -> Pretty s -> Pretty s
indent by p = by <> indentAfterNewline by p

indentN :: (LL.ListLike s Char, IsString s) => Width -> Pretty s -> Pretty s
indentN by = indent (fromString $ replicate by ' ')

indentNAfterNewline :: (LL.ListLike s Char, IsString s) => Width -> Pretty s -> Pretty s
indentNAfterNewline by = indentAfterNewline (fromString $ replicate by ' ')

indentAfterNewline :: (LL.ListLike s Char, IsString s) => Pretty s -> Pretty s -> Pretty s
indentAfterNewline by p = flatMap f p where
  f s = case LL.break (== '\n') s of
    (hd, s) -> if LL.null s then lit hd
               else lit hd <> "\n" <> by <> f (LL.drop 1 s)

instance IsString s => IsString (Pretty s) where
  fromString s = lit' (foldMap chDelta s) (fromString s)

instance Semigroup (Pretty s) where (<>) = mappend
instance Monoid (Pretty s) where
  mempty = Pretty mempty mempty Empty
  mappend p1 p2 = Pretty (delta p1 <> delta p2) (minDelta p1 <> minDelta p2) .
    Append $ case (out p1, out p2) of
      (Append ps1, Append ps2) -> ps1 <> ps2
      (Append ps1, _) -> ps1 <> pure p2
      (_, Append ps2) -> pure p1 <> ps2
      (_,_) -> pure p1 <> pure p2

-- Delta lines columns
data Delta = Delta !Int !Int deriving (Eq,Ord,Show)

instance Semigroup Delta where (<>) = mappend
instance Monoid Delta where
  mempty = Delta 0 0
  mappend (Delta l c) (Delta 0 c2) = Delta l (c + c2)
  mappend (Delta l _) (Delta l2 c2) = Delta (l + l2) c2

chDelta :: Char -> Delta
chDelta '\n' = Delta 1 0
chDelta _ = Delta 0 1

preferredWidth :: Pretty s -> Width
preferredWidth p = case delta p of Delta _ w -> w

minWidth :: Pretty s -> Width
minWidth p = case minDelta p of Delta _ w -> w

black, red, green, yellow, blue, purple, cyan, white, hiBlack, hiRed, hiGreen,
  hiYellow, hiBlue, hiPurple, hiCyan, hiWhite, bold :: Pretty CT.ColorText -> Pretty CT.ColorText
black = map CT.black
red = map CT.red
green = map CT.green
yellow = map CT.yellow
blue = map CT.yellow
purple = map CT.purple
cyan = map CT.cyan
white = map CT.white
hiBlack = map CT.hiBlack
hiRed = map CT.hiRed
hiGreen = map CT.hiGreen
hiYellow = map CT.hiYellow
hiBlue = map CT.hiBlue
hiPurple = map CT.hiPurple
hiCyan = map CT.hiCyan
hiWhite = map CT.hiWhite
bold = map CT.bold

--ex :: Pretty String
--ex = indentN 2 $ numbered (fromString . show) stuff
--  where
--    stuff = replicate 10 (commas $ replicate 10 "hi")
--
--ex2 :: Pretty String
--ex2 = indentN 2 $ lines (replicate 10 "hi")
--
--ex3 :: Pretty String
--ex3 = indentN 2 $ numbered (fromString . show) stuff
--  where
--    stuff = replicate 10 (group $ sepSpaced "**" (replicate 5 . group . commas $ replicate 5 "hi"))
--
--ex4 :: Pretty String
--ex4 = "x =" <> hang (spaced $ replicate 7 "sdlfkj")
--
--ex5 :: Pretty String
--ex5 = indentN 2 $ wrapWords "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Cras pretium metus dolor, id maximus mi commodo ac. Nullam accumsan ex non leo rutrum vulputate. Suspendisse potenti. Vivamus ultricies finibus neque, ut lacinia sem ornare sed. Morbi feugiat non sem sit amet tincidunt. Nam porttitor auctor orci, a vulputate metus. In non quam et magna elementum posuere. Nam laoreet nisl nec est iaculis, et ornare sem volutpat. Integer eget laoreet tortor. Fusce finibus pellentesque libero ac elementum."
--
--ex6 :: Pretty String
--ex6 = indentN 2 $ wrapWords "ab cde ef gh"
