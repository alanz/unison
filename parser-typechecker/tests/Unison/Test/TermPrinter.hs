{-# Language OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Unison.Test.TermPrinter where

import EasyTest
import qualified Data.Text as Text
import Unison.ABT (annotation)
import Unison.Term
import Unison.TermPrinter
import qualified Unison.Type as Type
import Unison.Symbol (Symbol, symbol)
import Unison.Builtin
import Unison.Parser (Ann(..))
import qualified Unison.Util.Pretty as PP
import qualified Unison.PrettyPrintEnv as PPE

get_names :: PPE.PrettyPrintEnv
get_names = PPE.fromNames Unison.Builtin.names

-- Test the result of the pretty-printer.  Expect the pretty-printer to
-- produce output that differs cosmetically from the original code we parsed.
-- Check also that re-parsing the pretty-printed code gives us the same ABT.
-- (Skip that latter check if rtt is false.)
-- Note that this does not verify the position of the PrettyPrint Break elements.
tc_diff_rtt :: Bool -> String -> String -> Int -> Test ()
tc_diff_rtt rtt s expected width =
   let input_term = Unison.Builtin.tm s :: Unison.Term.AnnotatedTerm Symbol Ann
       prettied = pretty get_names (ac (-1) Normal) input_term
       actual = if width == 0
                then PP.renderUnbroken $ prettied
                else PP.render width   $ prettied
       actual_reparsed = Unison.Builtin.tm actual
   in scope s $ tests [(
       if actual == expected then ok
       else do note $ "expected: " ++ show expected
               note $ "actual  : "   ++ show actual
               note $ "show(input)  : "   ++ show input_term
               note $ "prettyprint  : "   ++ show prettied
               crash "actual != expected"
       ), (
       if (not rtt) || (input_term == actual_reparsed) then ok
       else do note $ "round trip test..."
               note $ "single parse: " ++ show input_term
               note $ "double parse: " ++ show actual_reparsed
               note $ "prettyprint  : "   ++ show prettied
               crash "single parse != double parse"
       )]

-- As above, but do the round-trip test unconditionally.
tc_diff :: String -> String -> Test ()
tc_diff s expected = tc_diff_rtt True s expected 0

-- As above, but expect not even cosmetic differences between the input string
-- and the pretty-printed version.
tc :: String -> Test ()
tc s = tc_diff s s

-- Use renderBroken to render the output to some maximum width.
tc_breaks_diff :: Int -> String -> String -> Test ()
tc_breaks_diff width s expected = tc_diff_rtt True s expected width

tc_breaks :: Int -> String -> Test ()
tc_breaks width s = tc_diff_rtt True s s width

tc_binding :: Int -> String -> Maybe String -> String -> String -> Test ()
tc_binding width v mtp tm expected =
   let base_term = Unison.Builtin.tm tm :: Unison.Term.AnnotatedTerm Symbol Ann
       input_type = (fmap Unison.Builtin.t mtp) :: Maybe (Type.AnnotatedType Symbol Ann)
       input_term (Just (tp)) = ann (annotation tp) base_term tp
       input_term Nothing     = base_term
       var_v = symbol $ Text.pack v
       prettied = prettyBinding get_names var_v (input_term input_type)
       actual = if width == 0
                then PP.renderUnbroken $ prettied
                else PP.render width   $ prettied
   in scope expected $ tests [(
       if actual == expected then ok
       else do note $ "expected: " ++ show expected
               note $ "actual  : "   ++ show actual
               note $ "show(input)  : "   ++ show (input_term input_type)
               note $ "prettyprint  : "   ++ show prettied
               crash "actual != expected"
       )]

test :: Test ()
test = scope "termprinter" . tests $
  [ tc "if true then +2 else -2"
  , tc "[2, 3, 4]"
  , tc "[2]"
  , tc "[]"
  , tc "and true false"
  , tc "or false false"
  , tc "g (and (or true false) (f x y))"
  , tc "if _something then _foo else _"
  , tc "3.14159"
  , tc "+0"
  , tc "\"some text\""
  , pending $ tc "\"they said \\\"hi\\\"\""  -- TODO lexer doesn't support strings with quotes in
  , tc "2 : Nat"
  , tc "x -> and x false"
  , tc "x y -> and x y"
  , tc "x y z -> and x y"
  , tc "x y y -> and x y"
  , tc "()"
  , tc "Pair"
  , tc "foo"
  , tc "Sequence.empty"
  , tc "None"
  , tc "Optional.None"
  , tc "handle foo in bar"
  , tc "Pair 1 1"
  -- let bindings have no unbroken form accepted by the parser.
  -- We could choose to render them broken anyway, but that would complicate
  -- PrettyPrint.renderUnbroken a great deal.
  , tc_diff_rtt False "let\n\
                      \  x = 1\n\
                      \  x\n"
                      "let; x = 1; x"
                      0
  , tc_breaks 50 "let\n\
                 \  x = 1\n\
                 \  x"
  , tc_breaks 50 "let\n\
                 \  x = 1\n\
                 \  y = 2\n\
                 \  f x y"
  , tc_breaks 50 "let\n\
                 \  x = 1\n\
                 \  x = 2\n\
                 \  f x x"
  , pending $ tc "case x of Pair t 0 -> foo t" -- TODO hitting UnknownDataConstructor when parsing pattern
  , pending $ tc "case x of Pair t 0 | pred t -> foo t" -- ditto
  , pending $ tc "case x of Pair t 0 | pred t -> foo t; Pair t 0 -> foo' t; Pair t u -> bar;" -- ditto
  , tc "case x of () -> foo"
  , tc "case x of _ -> foo"
  , tc "case x of y -> y"
  , tc "case x of 1 -> foo"
  , tc "case x of +1 -> foo"
  , tc "case x of -1 -> foo"
  , tc "case x of 3.14159 -> foo"
  , tc_diff_rtt False "case x of\n\
                      \  true -> foo\n\
                      \  false -> bar"
                      "case x of true -> foo; false -> bar" 0
  , tc_breaks 50 "case x of\n\
                 \  true -> foo\n\
                 \  false -> bar"
  , tc "case x of false -> foo"
  , tc "case x of y@() -> y"
  , tc "case x of a@(b@(c@())) -> c"
  , tc "case e of { a } -> z"
  , pending $ tc "case e of { () -> k } -> z" -- TODO doesn't parse since 'many leaf' expected before the "-> k"
                                              -- need an actual effect constructor to test this with
  , pending $ tc "if a then (if b then c else d) else e"
  , pending $ tc "(if b then c else d)"   -- TODO parser doesn't like bracketed ifs (`unexpected )`)
  , pending $ tc "handle foo in (handle bar in baz)"  -- similarly
  , pending $ tc_breaks 16 "case (if a \n\
                           \      then b\n\
                           \      else c) of\n\
                           \  112 -> x"        -- similarly
  , tc "handle Pair 1 1 in bar"
  , tc "handle x -> foo in bar"
  , tc_diff_rtt True "let\n\
                     \  x = (1 : Int)\n\
                     \  (x : Int)"
                     "let\n\
                     \  x : Int\n\
                     \  x = 1\n\
                     \  (x : Int)" 50
  , tc "case x of 12 -> (y : Int)"
  , tc "if a then (b : Int) else (c : Int)"
  , tc "case x of 12 -> if a then b else c"
  , tc "case x of 12 -> x -> f x"
  , tc_diff "case x of (12) -> x" $ "case x of 12 -> x"
  , tc_diff "case (x) of 12 -> x" $ "case x of 12 -> x"
  , tc_breaks 50 "case x of\n\
                 \  12 -> x"
  , tc_breaks 15 "case x of\n\
                 \  12 -> x\n\
                 \  13 -> y\n\
                 \  14 -> z"
  , tc_breaks 21 "case x of\n\
                 \  12 | p x -> x\n\
                 \  13 | q x -> y\n\
                 \  14 | r x y -> z"
  , tc_breaks 9 "case x of\n\
                \  112 ->\n\
                \    x\n\
                \  113 ->\n\
                \    y\n\
                \  114 ->\n\
                \    z"
  , pending $ tc_breaks 19 "case\n\
                           \  myFunction\n\
                           \    argument1\n\
                           \    argument2\n\
                           \of\n\
                           \  112 -> x"          -- TODO, 'unexpected semi' before 'of' - should the parser accept this?
  , tc "if c then x -> f x else x -> g x"
  , tc "(f x) : Int"
  , tc "(f x) : Pair Int Int"
  , tc_breaks 50 "let\n\
                 \  x = if a then b else c\n\
                 \  if x then y else z"
  , tc "f x y"
  , tc "f x y z"
  , tc "f (g x) y"
  , tc_diff "(f x) y" $ "f x y"
  , pending $ tc "1.0e-19"         -- TODO parser throws UnknownLexeme
  , pending $ tc "-1.0e19"         -- ditto
  , tc "0.0"
  , tc "-0.0"
  , pending $ tc_diff "+0.0" $ "0.0"  -- TODO parser throws "Prelude.read: no parse" - should it?  Note +0 works for UInt.
  , tc_breaks_diff 21 "case x of 12 -> if a then b else c" $
              "case x of\n\
              \  12 ->\n\
              \    if a\n\
              \    then b\n\
              \    else c"
  , tc_diff_rtt True "if foo\n\
            \then\n\
            \  use bar\n\
            \  and true true\n\
            \  12\n\
            \else\n\
            \  namespace baz where\n\
            \    f : Int -> Int\n\
            \    f x = x\n\
            \  13"
            "if foo\n\
            \then\n\
            \  and true true\n\
            \  12\n\
            \else\n\
            \  baz.f : Int -> Int\n\
            \  baz.f x = x\n\
            \  13" 50
  , tc_breaks 50 "if foo\n\
                 \then\n\
                 \  and true true\n\
                 \  12\n\
                 \else\n\
                 \  baz.f : Int -> Int\n\
                 \  baz.f x = x\n\
                 \  13"
  , pending $ tc_breaks 90 "handle foo in\n\
                 \  a = 5\n\
                 \  b =\n\
                 \    c = 3\n\
                 \    true\n\
                 \  false"  -- TODO comes back out with line breaks around foo
  , tc_breaks 50 "case x of\n\
                 \  true ->\n\
                 \    d = 1\n\
                 \    false\n\
                 \  false ->\n\
                 \    f x = x + 1\n\
                 \    true"
  , pending $ tc_breaks 50 "x -> e = 12\n\
                 \     x + 1"  -- TODO parser looks like lambda body should be a block, but we hit 'unexpected ='
  , tc "x + y"
  , tc "x ~ y"
  , tc_diff "x `foo` y" $ "foo x y"
  , tc "x + (y + z)"
  , tc "x + y + z"
  , tc "x + y * z" -- i.e. (x + y) * z !
  , tc "x \\ y == z ~ a"
  , tc "foo x (y + z)"
  , tc "foo (x + y) z"
  , tc "foo x y + z"
  , tc "foo p q + r + s"
  , tc "foo (p + q) r + s"
  , tc "foo (p + q + r) s"
  , tc "p + q + r + s"
  , tc_diff_rtt False "(foo.+) x y" "x foo.+ y" 0
  , tc "x + y + f a b c"
  , tc "x + y + foo a b"
  , tc "foo x y p + z"
  , tc "foo p q a + r + s"
  , tc "foo (p + q) r a + s"
  , tc "foo (x + y) (p - q)"
  , tc "x -> x + y"
  , tc "if p then x + y else a - b"
  , tc "(x + y) : Int"
  , tc "!foo"
  , tc "!(foo a b)"
  , tc "!f a"
  , tc_diff "f () a ()" $ "!(!f a)"
  , tc_diff "f a b ()" $ "!(f a b)"
  , tc_diff "!f ()" $ "!(!f)"
  , tc "!(!foo)"
  , tc "'bar"
  , tc "'(bar a b)"
  , tc "'('bar)"
  , tc "!('bar)"
  , tc "'(!foo)"
  , tc "x -> '(y -> 'z)"
  , tc "'(x -> '(y -> z))"
  , tc "(\"a\", 2)"
  , tc "(\"a\", 2, 2.0)"
  , tc_diff "(2)" $ "2"
  , pending $ tc_diff "Pair \"2\" (Pair 2 ())" $ "(\"2\", 2)"  -- TODO parser produced
                                                     --  Pair "2" (Pair 2 ()#0)
                                                     -- instead of
                                                     --  Pair#0 "2" (Pair#0 2 ()#0)
                                                     -- Maybe because in this context the
                                                     -- parser can't distinguish between a constructor
                                                     -- called 'Pair' and a function called 'Pair'.
  , pending $ tc "Pair 2 ()"  -- unary tuple; fails for same reason as above
  , tc "case x of (a, b) -> a"
  , tc "case x of () -> foo"
  , pending $ tc "case x of [a, b] -> a"  -- issue #266
  , pending $ tc "case x of [a] -> a"     -- ditto
  , pending $ tc "case x of [] -> a"      -- ditto
  , tc_binding 50 "foo" (Just "Int") "3" "foo : Int\n\
                                         \foo = 3"
  , tc_binding 50 "foo" Nothing "3" "foo = 3"
  , tc_binding 50 "foo" (Just "Int -> Int") "n -> 3" "foo : Int -> Int\n\
                                                     \foo n = 3"
  , tc_binding 50 "foo" Nothing "n -> 3" "foo n = 3"
  , tc_binding 50 "foo" Nothing "n m -> 3" "foo n m = 3"
  , tc_binding 9 "foo" Nothing "n m -> 3" "foo n m =\n\
                                          \  3"
  , tc_binding 50 "+" (Just "Int -> Int -> Int") "a b -> foo a b" "(+) : Int -> Int -> Int\n\
                                                                  \a + b = foo a b"
  , tc_binding 50 "+" (Just "Int -> Int -> Int -> Int") "a b c -> foo a b c" "(+) : Int -> Int -> Int -> Int\n\
                                                                             \(+) a b c = foo a b c"
  , tc_binding 50 "+" Nothing "a b -> foo a b" "a + b = foo a b"
  , tc_binding 50 "+" Nothing "a b c -> foo a b c" "(+) a b c = foo a b c"
  , tc_breaks 32 "let\n\
                 \  go acc a b =\n\
                 \    case Sequence.at 0 a of\n\
                 \      Optional.None -> 0\n\
                 \      Optional.Some hd1 -> 0\n\
                 \  go [] a b"
  , tc_breaks 50 "case x of\n\
                 \  (Optional.None, _) -> foo"
  , pending $ tc_breaks 50 "if true\n\
                 \then\n\
                 \  case x of\n\
                 \    12 -> x\n\
                 \else\n\
                 \  x"              -- TODO parser bug?  'unexpected else', parens around case doens't help, cf next test
  , pending $ tc_breaks 50 "if true\n\
                 \then x\n\
                 \else\n\
                 \  (case x of\n\
                 \    12 -> x)"     -- TODO parser bug, 'unexpected )'
  , tc_diff_rtt False "if true\n\
                      \then x\n\
                      \else case x of\n\
                      \  12 -> x"
                      "if true\n\
                      \then x\n\
                      \else\n\
                      \  (case x of\n\
                      \    12 -> x)" 50  -- TODO fix surplus parens around case.
                                         -- Are they only surplus due to layout cues?
                                         -- And no round trip, due to issue in test directly above.
  , pending $ tc_breaks 80 "x -> (if c then t else f)"  -- TODO 'unexpected )', surplus parens
  , tc_breaks 80 "'let\n\
                 \  foo = bar\n\
                 \  baz foo"
  , tc_breaks 80 "!let\n\
                 \  foo = bar\n\
                 \  baz foo"
  , tc_diff_rtt True "foo let\n\
                     \      a = 1\n\
                     \      b"
                     "foo\n\
                     \  let\n\
                     \    a = 1\n\
                     \    b" 80
  , pending $ tc_breaks 80 "if let\n\
                           \     a = b\n\
                           \     a\n\
                           \then foo\n\
                           \else bar"   -- TODO parser throws 'unexpected then'
  , tc_breaks 80 "Stream.fold-left 0 (+) t"
  , tc_breaks 80 "foo?"
  , tc_breaks 80 "(foo a b)?"
  ]
