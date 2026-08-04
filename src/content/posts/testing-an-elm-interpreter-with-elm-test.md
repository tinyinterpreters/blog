---
title: "Testing an Elm Interpreter with elm-test"
description: Learn how to test an Elm interpreter with elm-test at the lexer, parser, and interpreter boundaries, then extract a reusable testValue helper.
pubDatetime: 2026-08-04T07:50:00
tags:
  - interpreters
  - testing
  - elm
---

In [CONST: The Structure of a Tiny Interpreter in Elm](/posts/const), we built a tiny interpreter whose programs contain a single non-negative integer literal.

A CONST program can be as simple as:

```txt
123
```

The parser turns that source text into an AST:

```elm
Program (Const 123)
```

The interpreter evaluates the AST to produce a value:

```elm
VNumber 123
```

We can describe that behaviour by testing CONST at three boundaries:

- the lexer
- the parser
- the interpreter

Together, those tests form an executable description of the language. Lexer tests show which pieces of syntax are recognized. Parser tests show which source texts form complete programs and which ASTs they produce. Interpreter tests show what those programs mean.

We’ll also develop a small testing helper. Rather than designing the abstraction upfront, we’ll let it emerge from the repeated shape of the tests.

## Table of contents

## Test the CONST lexer

CONST’s lexer exposes a parser called `digits`:

```elm
digits : Parser Int
```

It recognizes one or more digits, converts them to an `Int`, and consumes any spaces that follow the number.

Before extracting any helpers, we can test it with individual cases:

```elm
module Test.CONST.Lexer exposing (suite)

import CONST.Lexer as L
import Expect
import Parser as P
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "CONST.Lexer"
        [ describe "digits"
            [ test "\"123\"" <|
                \_ ->
                    P.run L.digits "123"
                        |> Expect.equal (Ok 123)
            , test "\"123 \"" <|
                \_ ->
                    P.run L.digits "123 "
                        |> Expect.equal (Ok 123)
            , test "\"123  \"" <|
                \_ ->
                    P.run L.digits "123  "
                        |> Expect.equal (Ok 123)
            , test "\" 123\"" <|
                \_ ->
                    P.run L.digits " 123"
                        |> Expect.err
            , test "\"123abc\"" <|
                \_ ->
                    P.run L.digits "123abc"
                        |> Expect.equal (Ok 123)
            , test "\"onetwothree\"" <|
                \_ ->
                    P.run L.digits "onetwothree"
                        |> Expect.err
            ]
        ]
```

These tests reveal three important parts of `digits` behaviour.

First, it accepts a number with or without trailing spaces. That’s because `digits` is a lexeme parser: it parses the number and then consumes any spaces following it.

Second, it rejects leading spaces:

```txt
" 123"
```

`digits` begins parsing at its current position, so it expects a digit immediately. Leading spaces are handled by the program parser instead.

Finally, it accepts the number at the beginning of this input:

```txt
"123abc"
```

The lexer successfully recognizes `123` and leaves `abc` unparsed. It does not require the entire input to form a complete CONST program. That responsibility also belongs to the program parser.

Together, these cases show that `digits` recognizes a number at its current position and consumes trailing spaces, but it neither skips leading spaces nor requires the end of the input.

### Why are quotation marks needed around the input?

The test descriptions contain quotation marks:

```elm
test "\"123 \"" <|
```

rather than using the input directly:

```elm
test "123 " <|
```

Trailing whitespace in test descriptions is trimmed. Without quotation marks, the inputs `"123"`, `"123 "`, and `"123  "` would all produce the same description `123`, and `elm-test` would report duplicate test names. Wrapping the inputs in quotation marks keeps the spaces before the end of each description, making the descriptions unique.

## Extract a local `testDigits` helper

The explicit tests are easy to understand, but they repeat the same process:

1. provide some source text
2. run `L.digits`
3. expect either a value or an error

The information that changes between tests is the input and expected result:

```elm
( "123", Just 123 )
( "123 ", Just 123 )
( " 123", Nothing )
```

`Just 123` means that we expect the parser to succeed with `123`. `Nothing` means that we expect it to return an error.

We can move the repeated mechanics into a local helper:

```elm
testDigits : ( String, Maybe Int ) -> Test
testDigits ( input, expectedOutput ) =
    test ("\"" ++ input ++ "\"") <|
        \_ ->
            case P.run L.digits input of
                Ok n ->
                    if expectedOutput == Just n then
                        Expect.pass

                    else
                        Expect.fail <|
                            Debug.toString
                                { expected = expectedOutput
                                , actual = n
                                }

                Err e ->
                    if expectedOutput == Nothing then
                        Expect.pass

                    else
                        Expect.fail (Debug.toString e)
```

`Debug.toString` lets the helper display arbitrary Elm values and parser errors when a test fails, so we don’t need separate formatting functions just for our tests. Uses of the `Debug` module must be removed from optimized production code, but it can remain in test code.

For now, we’ll keep `testDigits` in the lexer test module. We’ve only seen this repeated shape in one suite, so there is no reason to make it a shared abstraction yet.

The suite can now emphasize the examples:

```elm
suite : Test
suite =
    describe "CONST.Lexer"
        [ describe "digits" <|
            List.map testDigits
                [ ( "123", Just 123 )
                , ( "123 ", Just 123 )
                , ( "123  ", Just 123 )
                , ( "123abc", Just 123 )
                , ( " 123", Nothing )
                , ( "onetwothree", Nothing )
                ]
        ]
```

The helper hides the repeated testing mechanics while keeping the accepted and rejected inputs visible in one compact list.

## Test the CONST parser

The parser has a different responsibility:

```elm
parse : String -> Result Error AST.Program
```

It must parse the entire source text as a complete CONST program and produce its AST.

Its tests describe source text in terms of ASTs:

```elm
suite : Test
suite =
    describe "CONST.Parser"
        [ describe "parse" <|
            List.map testParse
                [ ( "123", Just (Program (Const 123)) )
                , ( "123 ", Just (Program (Const 123)) )
                , ( "123  ", Just (Program (Const 123)) )
                , ( " 123", Just (Program (Const 123)) )
                , ( "  123", Just (Program (Const 123)) )
                , ( "123abc", Nothing )
                , ( "onetwothree", Nothing )
                ]
        ]
```

Comparing these cases with the lexer tests shows where the parser takes on additional responsibility.

The lexer rejected:

```txt
" 123"
```

but the complete-program parser accepts it and produces:

```elm
Program (Const 123)
```

Unlike `digits`, the program parser consumes leading spaces before parsing the expression.

The parser also rejects:

```txt
"123abc"
```

Although `digits` recognizes the initial `123`, the program parser requires the end of the input. The leftover `abc` therefore causes the parse to fail.

The parser helper has almost exactly the same shape as `testDigits`:

```elm
testParse : ( String, Maybe AST.Program ) -> Test
testParse ( input, expectedOutput ) =
    test ("\"" ++ input ++ "\"") <|
        \_ ->
            case P.parse input of
                Ok program ->
                    if expectedOutput == Just program then
                        Expect.pass

                    else
                        Expect.fail <|
                            Debug.toString
                                { expected = expectedOutput
                                , actual = program
                                }

                Err e ->
                    if expectedOutput == Nothing then
                        Expect.pass

                    else
                        Expect.fail (Debug.toString e)
```

`testDigits` and `testParse` differ in the function being tested and the types carried by its `Result`, but their testing logic is otherwise the same.

Now we have enough repetition to justify a shared abstraction.

## Extract a shared `testValue` helper

We can move that common testing shape into `Test.Lib`:

```elm
module Test.Lib exposing (testValue)

import Expect
import Test exposing (Test, test)


testValue : (String -> Result e a) -> ( String, Maybe a ) -> Test
testValue f ( input, expectedOutput ) =
    test ("\"" ++ input ++ "\"") <|
        \_ ->
            case f input of
                Ok value ->
                    if expectedOutput == Just value then
                        Expect.pass

                    else
                        Expect.fail <|
                            Debug.toString
                                { expected = expectedOutput
                                , actual = value
                                }

                Err e ->
                    if expectedOutput == Nothing then
                        Expect.pass

                    else
                        Expect.fail (Debug.toString e)
```

Its first argument is the function we want to test:

```elm
String -> Result e a
```

The type variable `e` allows the function to return any kind of error, while `a` allows it to produce different kinds of successful values that can be compared with `==`.

Its second argument describes one example:

```elm
( String, Maybe a )
```

The `String` is the source text. `Just` contains the expected successful result, while `Nothing` means that we expect an error.

We can now use the same helper for the lexer:

```elm
List.map (testValue (P.run L.digits))
    [ ( "123", Just 123 )
    , ( "123 ", Just 123 )
    , ( " 123", Nothing )
    , ( "123abc", Just 123 )
    ]
```

and for the parser:

```elm
List.map (testValue P.parse)
    [ ( "123", Just (Program (Const 123)) )
    , ( " 123", Just (Program (Const 123)) )
    , ( "123abc", Nothing )
    ]
```

The shared helper handles the repeated testing mechanics, while each suite still shows the function being tested, the source input, and the expected result.

There’s one limitation.

`Nothing` means only that we expect some error. It doesn't check which error occurred.

That’s enough for CONST because its interpreter currently reports only syntax errors, and our immediate concern is whether an input succeeds or fails. Once an interpreter can fail in meaningfully different ways, such as with either a syntax error or a runtime error, checking only for `Nothing` could allow a test to pass even when the program failed for the wrong reason.

We don’t need to solve that problem before we encounter it.

## Test the CONST interpreter

The interpreter’s `run` function is the main public entry point:

```elm
run : String -> Result Error Value
```

It accepts source text, parses it, evaluates the resulting AST, and returns either an error or a value.

Testing `run` gives us the most complete outside view of CONST. Each test starts with source text and checks the final result. It doesn’t need to know how the parser or evaluator works internally:

```elm
module Test.CONST.Interpreter exposing (suite)

import CONST.Interpreter as I exposing (Value(..))
import Test exposing (Test, describe)
import Test.Lib exposing (testValue)


suite : Test
suite =
    describe "CONST.Interpreter"
        [ describe "run" <|
            List.map (testValue I.run)
                [ ( "123", Just (VNumber 123) )
                , ( "123 ", Just (VNumber 123) )
                , ( "123  ", Just (VNumber 123) )
                , ( " 123", Just (VNumber 123) )
                , ( "  123", Just (VNumber 123) )
                , ( "123abc", Nothing )
                , ( "onetwothree", Nothing )
                ]
        ]
```

The suite shows that CONST accepts a non-negative integer literal with leading or trailing spaces:

```txt
"123 " → VNumber 123
" 123" → VNumber 123
```

`VNumber 123` represents the program’s numeric result, `123`.

Inputs that do not form complete CONST programs are rejected:

```txt
"123abc"
"onetwothree"
```

Together, these examples describe which source programs CONST accepts, which it rejects, and what value an accepted program produces.

## Reuse the testing structure as the language grows

The lexer, parser, and interpreter test modules mirror their corresponding source modules:

```txt
.
└── tests/
    └── Test/
        ├── CONST/
        │   ├── Interpreter.elm
        │   ├── Lexer.elm
        │   └── Parser.elm
        └── Lib.elm
```

Each mirrored module tests one interpreter boundary, while `Test.Lib` contains testing support shared between them.

We can reuse this structure in each later interpreter as it adds more syntax, AST forms, and evaluation rules.

The existing examples should remain too. When a later interpreter adds a new kind of expression, it should still confirm that programs supported by earlier interpreters behave as expected.

The examples will grow, and the helpers may evolve when the language needs more precise tests. We’ll continue asking the same basic questions: What source text are we testing? What result should it produce? Which inputs should produce an error?

## What we learned

Testing the lexer, parser, and interpreter lets us describe CONST at several levels, from recognizing pieces of syntax to evaluating complete programs.

Using the same source inputs at different boundaries makes their responsibilities easier to see. Each suite answers a different question about the language.

The shared `testValue` helper emerged only after the lexer and parser tests revealed the same repeated shape. It hides the testing mechanics while leaving the source inputs and expected results visible.

That’s the approach we’ll carry into the rest of the series: describe the language with concrete examples, run those examples as tests, and extract abstractions only when the repetition justifies them.
