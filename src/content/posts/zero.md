---
title: "ZERO: Adding Booleans and Runtime Type Errors to a Tiny Interpreter in Elm"
description: Add the zero? predicate to a tiny Elm interpreter and see how Boolean values introduce runtime type errors, type checks, and fallible evaluation with Result.
pubDatetime: 2026-08-17T07:40:00
tags:
  - interpreters
  - programming languages
  - elm
---

In [CONST](/posts/const) and [DIFF](/posts/diff), every expression evaluated to a number. ZERO breaks that assumption by adding the `zero?` predicate:

```txt
zero?(expression)
```

Instead of evaluating to another number, `zero?(expression)` evaluates to a Boolean.

Once expressions can produce either numbers or Booleans, an operation may receive a kind of value it doesn't know how to use.

What should this program mean?

```txt
zero?(zero?(0))
```

The inner `zero?` produces a Boolean, but the outer `zero?` expects a number.

This new kind of value also affects expressions we've already implemented:

```txt
-(zero?(0), 1)
```

Difference expects two numbers, but its first operand produces a Boolean.

Both programs are valid according to the grammar, but neither can evaluate successfully. For the first time in the series, parsing a program successfully won't guarantee that evaluation produces a value.

In this article, we'll add Boolean values to the interpreter, define which values our operations accept, and represent the runtime type errors that occur when those expectations are violated.

You can find the [complete source code for ZERO on GitHub](https://github.com/tinyinterpreters/zero).

## Table of contents

## What should `zero?` mean?

Before changing the grammar or writing any Elm code, we should decide what the new expression means.

We might begin with this description:

> If `expression` evaluates to `0`, then `zero?(expression)` evaluates to `true`. Otherwise, it evaluates to `false`.

That seems clear while numbers are the only values in the language. Once expressions can also produce Booleans, however, the word “otherwise” becomes ambiguous.

Consider the example from the introduction:

```txt
zero?(zero?(0))
```

The inner expression evaluates to `true`. The word “otherwise” could be read as saying that the outer expression should therefore evaluate to `false`, simply because `true` isn't zero.

But `zero?` is supposed to test numbers, not silently treat every non-numeric value as “not zero.”

We need a more precise rule:

> To evaluate `zero?(expression)`, first evaluate `expression`. If the result is the number `0`, produce `true`. If the result is any other number, produce `false`. If the result isn't a number, evaluation fails with a type error.

This defines `zero?` for every value our language can currently produce and makes the order of evaluation explicit: we must evaluate the operand before we can test its value.

The implementation should follow the meaning we've chosen, not define that meaning by accident.

## Extending the ZERO language

The behaviour we defined requires a new kind of expression:

```txt
Expr ::= Const
       | Diff
       | Zero

Zero ::= 'zero?' '(' Expr ')'
```

Like the difference expressions we added in DIFF, a `Zero` expression contains another expression. This allows `zero?` to test a numeric literal:

```txt
zero?(0)
```

or a value computed by a compound expression:

```txt
zero?(-(1, 1))
```

Although the grammar permits any expression as the operand of `zero?`, evaluating that expression must still produce a numeric value.

The grammar therefore accepts:

```txt
zero?(zero?(0))
```

because the inner `zero?(0)` is an expression. Whether the value produced by that expression is suitable for the outer `zero?` is a question for the evaluator, not the parser.

## Representing `zero?` in the AST

We represent the new expression by adding a `Zero` constructor to `Expr`:

```elm
type Expr
    = Const Number
    | Diff Expr Expr
    | Zero Expr
```

Like `Diff`, the `Zero` constructor contains another expression.

For example:

```txt
zero?(-(1, 1))
```

is represented as:

```elm
Program
    (Zero
        (Diff
            (Const 1)
            (Const 1)
        )
    )
```

The AST keeps the meaningful structure of the program: a `Zero` expression whose operand is a `Diff` expression. The concrete syntax used to write that structure—`zero?`, `-`, parentheses, and the comma—is no longer needed.

## Parsing the new expression

Before we can parse `zero?`, we add and export a `keyword` lexeme parser in `ZERO.Lexer`:

```elm
keyword : String -> Parser ()
keyword =
    lexeme << P.keyword
```

Like the existing lexeme helpers, it consumes trailing whitespace after parsing a keyword.

We use `keyword` to recognize `zero?` as a complete word-like token. Unlike `symbol`, `Parser.keyword` checks that the matched text isn't immediately followed by a letter, number, or underscore. The parentheses are punctuation, so we'll continue to parse them with `symbol`.

With that helper in place, we can add `zeroExpr` as another alternative in the expression parser:

```elm
expr : Parser Expr
expr =
    P.oneOf
        [ constExpr
        , diffExpr
        , zeroExpr
        ]
```

Then we define `zeroExpr`:

```elm
zeroExpr : Parser Expr
zeroExpr =
    P.succeed Zero
        |. L.keyword "zero?"
        |. L.symbol "("
        |= P.lazy (\_ -> expr)
        |. L.symbol ")"
```

The operand is another expression, so we use `P.lazy` just as we did for the operands of a difference expression. If you want a closer look at why recursive Elm parsers need this, see [Why Recursive Elm Parsers Need `Parser.lazy`](/posts/why-recursive-elm-parsers-need-parser-lazy).

This allows `zero?` to contain constants, difference expressions, or another `zero?` expression.

## The value representation is no longer enough

Until now, every expression evaluated to a number, so our interpreter needed only one kind of value:

```elm
type Value
    = VNumber Number
```

The `zero?` predicate changes that. It evaluates to a Boolean, so we need to extend `Value`:

```elm
type Value
    = VNumber Number
    | VBool Bool
```

ZERO now has two kinds of values: numbers and Booleans.

The distinction between Elm’s `Bool` type and the `VBool` constructor is important. `VBool` marks the result as a Boolean belonging to the language we're interpreting, while the enclosed Elm `Bool` stores whether that value is `True` or `False`.

For example:

```elm
VBool True
```

represents the Boolean value `true` in ZERO.

ZERO can now produce Boolean values, but it still has no Boolean literals. A user can't write:

```txt
true
```

as a program. For now, Booleans can only be produced by evaluating a `zero?` expression.

A `Value` is no longer guaranteed to contain a number, so any operation that requires numeric operands must check the values it receives.

## Representing runtime errors

Because `Value` can now contain either a number or a Boolean, evaluating a valid AST doesn't always produce a value. The programs from the introduction show how either `zero?` or difference can receive a kind of value it can't use.

For now, the only runtime error is a type error:

```elm
type RuntimeError
    = TypeError
        { expected : List Type
        , actual : List Type
        }
```

A type error records the kinds of values an operation expected and the kinds it actually received.

We represent those kinds with another custom type:

```elm
type Type
    = TNumber
    | TBool
```

The lists allow each operation to describe the types of all its operands. `zero?` expects one number:

```elm
TypeError
    { expected = [ TNumber ]
    , actual = [ TBool ]
    }
```

while difference expects two:

```elm
TypeError
    { expected = [ TNumber, TNumber ]
    , actual = [ TBool, TNumber ]
    }
```

We can determine the type of a value with a small helper:

```elm
typeOf : Value -> Type
typeOf value =
    case value of
        VNumber _ ->
            TNumber

        VBool _ ->
            TBool
```

Despite its name, `Type` isn't part of a static type checker. It simply classifies a value that has already been produced during evaluation so that we can describe a runtime error.

Elm checks the code implementing our interpreter, not whether a ZERO expression uses values correctly. From Elm’s perspective, the nested `Zero` expressions are valid `Expr` values. Enforcing ZERO’s rule that `zero?` accepts only numbers is the evaluator’s responsibility.

The interpreter’s public error type must also distinguish errors found while parsing from errors found while evaluating:

```elm
type Error
    = SyntaxError P.Error
    | RuntimeError RuntimeError
```

The name appears twice because the first `RuntimeError` is a constructor of `Error`, while the second is the type of the value it contains.

Malformed source text produces a `SyntaxError`. A syntactically valid program that supplies the wrong kind of value to an operation produces a `RuntimeError`.

We can now describe runtime failure, but the evaluator still needs to return it. That requires changing evaluation from a function that always produces a value into one that may produce either a value or an error.

## Evaluation can now fail

In DIFF, `runExpr` always produced a value:

```elm
runExpr : Expr -> Value
```

In ZERO, evaluation may instead fail with a runtime error:

```elm
runExpr : Expr -> Result RuntimeError Value
```

A successful evaluation returns `Ok value`, while a runtime failure returns `Err runtimeError`.

The same change applies to `runProgram`:

```elm
runProgram : AST.Program -> Result RuntimeError Value
runProgram (Program expr) =
    runExpr expr
```

Constants can't produce runtime errors, but their branch must still return the same `Result` type as every other expression:

```elm
Const n ->
    Ok <| VNumber n
```

The public `run` function returns the broader `Error` type, which can represent both syntax and runtime errors:

```elm
run : String -> Result Error Value
run input =
    case P.parse input of
        Ok program ->
            runProgram program
                |> Result.mapError RuntimeError

        Err err ->
            Err <| SyntaxError err
```

When parsing fails, we wrap the parser error in `SyntaxError`.

When evaluation fails, `runProgram` returns a `RuntimeError`. `Result.mapError RuntimeError` wraps that value in the `RuntimeError` constructor of the public `Error` type.

Changing the return type is only the beginning. Existing evaluator branches still assume that recursively evaluating an operand produces a `Value` directly. They now need to handle the possibility that evaluating an operand may fail.

## Updating difference evaluation

To evaluate a difference expression, we now need to:

1. Evaluate the left operand.
2. If that succeeds, evaluate the right operand.
3. If both succeed, check that both values are numbers.
4. Subtract the numbers or return a type error.

We use `Result.andThen` to continue only after a successful evaluation. If the preceding result is an `Err`, it's returned unchanged without running the next step:

```elm
Diff a b ->
    runExpr a
        |> Result.andThen
            (\va ->
                runExpr b
                    |> Result.andThen
                        (\vb ->
                            evalDiff va vb
                        )
            )
```

This evaluates the operands from left to right. If evaluating `a` fails, `b` isn't evaluated. If `a` succeeds but evaluating `b` fails, that error is returned instead.

When both evaluations succeed, `evalDiff` receives the resulting values:

```elm
evalDiff : Value -> Value -> Result RuntimeError Value
evalDiff va vb =
    case ( va, vb ) of
        ( VNumber a, VNumber b ) ->
            Ok <| VNumber <| a - b

        _ ->
            Err <|
                TypeError
                    { expected = [ TNumber, TNumber ]
                    , actual = [ typeOf va, typeOf vb ]
                    }
```

`evalDiff`'s job is to check the values it receives and apply the operation when they're suitable.

If either value isn't a number, `evalDiff` returns a type error describing what difference expected and what it actually received.

For example:

```txt
-(zero?(0), 1)
```

produces:

```elm
TypeError
    { expected = [ TNumber, TNumber ]
    , actual = [ TBool, TNumber ]
    }
```

## Evaluating `zero?`

We can now translate the behaviour we defined earlier into evaluator code:

> First evaluate the operand. If it produces the number `0`, return `true`. If it produces any other number, return `false`. If it produces a non-numeric value, return a type error.

Before continuing, try implementing the `Zero` branch using the pattern from `Diff`.

The branch first evaluates its operand and then passes the resulting value to `evalZero`:

```elm
Zero a ->
    runExpr a
        |> Result.andThen
            (\va ->
                evalZero va
            )
```

If evaluating `a` produces a runtime error, `Result.andThen` propagates it. Otherwise, `evalZero` receives the value:

```elm
evalZero : Value -> Result RuntimeError Value
evalZero va =
    case va of
        VNumber a ->
            Ok <| VBool <| a == 0

        _ ->
            Err <|
                TypeError
                    { expected = [ TNumber ]
                    , actual = [ typeOf va ]
                    }
```

When the value is a number, `a == 0` produces an Elm `Bool`. Wrapping it with `VBool` represents the result as a Boolean belonging to ZERO.

If the value isn't a number, `evalZero` returns a type error describing what `zero?` expected and what it received.

## Testing exact failure modes

A test that checks only whether a program fails is no longer precise enough.

In [Testing an Elm Interpreter with elm-test](/posts/testing-an-elm-interpreter-with-elm-test), `Nothing` was enough to mean that we expected some error. At the time, the interpreter could only fail while parsing. ZERO introduces another possibility: parsing can succeed and evaluation can fail.

Consider:

```txt
zero?(zero?(0))
```

We expect this program to fail with a runtime type error. However, a generic failure test would also pass if a parser bug caused the program to produce a syntax error instead.

The program would fail either way, but only one result describes the intended behaviour of ZERO.

We therefore need our tests to distinguish successful values, syntax errors, and runtime errors:

```elm
type Expected a
    = SucceedsWith a
    | SyntaxError
    | RuntimeError I.RuntimeError
```

The test cases can now describe the expected outcome of each program directly:

```elm
suite : Test
suite =
    describe "ZERO.Interpreter"
        [ describe "run" <|
            List.map (testRun I.run)
                [ ( "123"
                  , SucceedsWith (VNumber 123)
                  )
                , ( "zero?(0)"
                  , SucceedsWith (VBool True)
                  )
                , ( "123abc"
                  , SyntaxError
                  )
                , ( "zero?(zero?(0))"
                  , RuntimeError <|
                        I.TypeError
                            { expected = [ I.TNumber ]
                            , actual = [ I.TBool ]
                            }
                  )
                ]
        ]
```

For syntax errors, we currently care only that parsing failed. We don't compare the particular parser error.

Runtime errors require more precision. The final case verifies that parsing succeeds and evaluation fails because `zero?` expected a number but received a Boolean.

The `testRun` helper compares the actual result with the corresponding `Expected` constructor. It compares successful values and runtime errors exactly, while any parser error satisfies `SyntaxError`.

## Where we go next

Our interpreter can now produce Boolean values, but no expression can use one successfully. A Boolean can be the final result of a program, but it can't yet influence which expression is evaluated next.

Our next interpreter, IF, will add conditional expressions. That introduces a new question about evaluation:

> After evaluating the condition, should we evaluate both branches and then choose a result, or evaluate only the selected branch?

Before we build IF, think through what using Boolean values to choose between expressions might require us to change. How might the grammar, AST, parser, evaluator, and tests need to evolve?

We’ll answer those questions when we build IF.
