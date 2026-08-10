---
title: "DIFF: Adding Recursive Expressions to a Tiny Interpreter in Elm"
description: Add recursive difference expressions to a tiny Elm interpreter and see how recursion shapes the grammar, AST, parser with lazy, and evaluator.
pubDatetime: 2026-08-10T09:00:00
tags:
  - interpreters
  - parser combinators
  - elm
---

In [CONST](/posts/const), we built a minimal interpreter that evaluates programs consisting of a single non-negative integer literal. It takes a program like `123` through the complete interpreter pipeline: `123 → Program (Const 123) → VNumber 123`.

DIFF extends that interpreter with difference expressions:

```txt
-(456, 123)
```

This expression subtracts the second operand from the first, producing:

```elm
VNumber 333
```

What matters here isn’t subtraction itself, but that each operand is also an expression. That means either operand can contain another difference expression:

```txt
-(2, -(4, 3))
```

Once an expression can contain other expressions, recursion appears across several layers of the interpreter.

In this article, we’ll extend the grammar, lexer, AST, parser, and evaluator to support difference expressions and see where that recursive structure appears.

You can find the [complete source code for DIFF on GitHub](https://github.com/tinyinterpreters/diff).

## Table of contents

## The DIFF language

DIFF supports everything CONST supports and adds difference expressions with this general form:

```txt
-(expression, expression)
```

A difference expression starts with `-`, followed by two expressions inside parentheses and separated by a comma.

DIFF uses this syntax instead of conventional infix subtraction:

```txt
456 - 123
```

The prefix-style syntax keeps the grammar simple. We don’t need to introduce operator precedence, associativity, or additional grouping rules yet, so we can stay focused on how recursive expressions affect the interpreter.

### What does a difference expression mean?

A difference expression evaluates both of its operands and subtracts the value of the second from the value of the first.

## Extending the grammar with recursive expressions

CONST has this grammar:

```txt
Program ::= Expr
Expr    ::= Const
Const   ::= Number
Number  ::= [0-9]+
```

To create DIFF, we extend the `Expr` rule and introduce a new rule for `Diff`:

```txt
Expr ::= Const
       | Diff

Diff ::= '-' '(' Expr ',' Expr ')'
```

The key detail is that both operands are defined as `Expr`. This allows either operand to be any valid expression, including another `Diff`.

If we defined them as numbers instead:

```txt
Diff ::= '-' '(' Number ',' Number ')'
```

we would only be able to write expressions like:

```txt
-(456, 123)
```

but not nested ones such as:

```txt
-(2, -(4, 3))
```

In the nested example, the second operand isn’t a number literal. It’s another difference expression, which is why using `Expr` is essential.

Right now, an operand can be a `Const` or another `Diff`. As we add more expression forms later, they’ll also be able to appear inside a difference expression without changing this rule.

The grammar is recursive because `Expr` can expand to `Diff`, while `Diff` refers back to `Expr` for both operands. This indirect recursion is what allows an expression to contain other expressions.

## Extending the lexer with symbols

The DIFF grammar introduces four new symbols:

```txt
-
(
,
)
```

Each symbol needs the same behavior: recognize a particular symbol and consume any trailing whitespace.

CONST already gave us a `lexeme` helper for adding whitespace handling to a parser. We can use it with [`P.symbol`](https://package.elm-lang.org/packages/elm/parser/latest/Parser#symbol) to define a reusable **symbol lexeme parser**:

```elm
symbol : String -> Parser ()
symbol =
    lexeme << P.symbol
```

For example:

```elm
symbol "-"
```

recognizes `-` and consumes the trailing whitespace. The same helper works for the opening parenthesis, comma, and closing parenthesis:

```elm
symbol "("
symbol ","
symbol ")"
```

Because each symbol consumes its own trailing whitespace, the parser can accept both compact expressions:

```txt
-(456,123)
```

and expressions spaced across multiple lines:

```txt
-(
    -(5, 3),
    -(0, 1)
)
```

More importantly, the parser code can focus on the meaningful structure of a difference expression instead of handling whitespace between every symbol.

## Representing recursive expressions in the AST

The grammar now defines two kinds of expressions:

```txt
Expr ::= Const
       | Diff
```

We represent the same alternatives in Elm:

```elm
type Expr
    = Const Number
    | Diff Expr Expr
```

A `Const` contains a number but no other expressions. A `Diff`, on the other hand, contains two expressions. Either operand can therefore be a constant or another difference expression.

For example:

```txt
-(2, -(4, 3))
```

becomes:

```elm
Program
    (Diff
        (Const 2)
        (Diff
            (Const 4)
            (Const 3)
        )
    )
```

The outer `Diff` contains a constant expression on the left and another difference expression on the right. That inner `Diff` contains two more constant expressions.

Because `Diff` contains `Expr` values, `Expr` is a recursive data type: it appears inside one of its own constructors. This recursive structure allows expressions to be nested to any depth.

### The compiler reveals what else must change

Before DIFF, the evaluator only needed to handle `Const`:

```elm
runExpr : Expr -> Value
runExpr expr =
    case expr of
        Const n ->
            VNumber n
```

Once we add `Diff` to the `Expr` type, that `case` expression is no longer exhaustive. Elm reports the missing possibility:

```txt
Missing possibilities include:

    Diff _ _
```

The compiler can’t decide what a difference expression should mean, but it can tell us that the evaluator still reflects the old AST.

We’ll define the new branch when we reach the evaluator. For now, the error shows an important benefit of modelling language features with custom types: when the language grows, Elm helps us find the code that must grow with it.

## Parsing recursive expressions

With the AST in place, we can now add a parser for difference expressions.

```txt
Expr ::= Const
       | Diff
```

The `expr` parser reflects these alternatives using [`P.oneOf`](https://package.elm-lang.org/packages/elm/parser/latest/Parser#oneOf):

```elm
expr : Parser Expr
expr =
    P.oneOf
        [ constExpr
        , diffExpr
        ]
```

It tries the expression parsers in order, starting with `constExpr` and then `diffExpr`, and uses the first one that succeeds.

The `Diff` grammar rule gives us the structure to follow:

```txt
Diff ::= '-' '(' Expr ',' Expr ')'
```

A direct translation into parser combinators looks like this:

```elm
diffExpr : Parser Expr
diffExpr =
    P.succeed Diff
        |. L.symbol "-"
        |. L.symbol "("
        |= expr
        |. L.symbol ","
        |= expr
        |. L.symbol ")"
```

We start with the AST constructor we want to produce:

```elm
P.succeed Diff
```

The [`|.`](https://package.elm-lang.org/packages/elm/parser/latest/Parser#(|.)) operators parse and discard the symbols that belong to the concrete syntax:

```elm
|. L.symbol "-"
|. L.symbol "("
|. L.symbol ","
|. L.symbol ")"
```

The [`|=`](https://package.elm-lang.org/packages/elm/parser/latest/Parser#(|=)) operators parse and keep the two operands:

```elm
|= expr
|= expr
```

We use `expr` for both operands because either one can be a `Const`, another `Diff`, or any expression form we add later.

This parser matches the grammar and produces the AST structure we want. However, Elm rejects the definition because `expr` and `diffExpr` depend on each other in a cycle.

## Why the direct recursive parser fails

The definition in the previous section creates a circular dependency: `expr` includes `diffExpr` as one of its alternatives, while `diffExpr` refers back to `expr` for both operands.

Together, they form a cycle. Elm detects this while constructing the parser values and reports the cyclic definition:

```txt
The `diffExpr` definition is causing a very tricky infinite loop.

44| diffExpr =
    ^^^^^^^^
The `diffExpr` value depends on itself through the following chain of
definitions:

    ┌─────┐
    │    diffExpr
    │     ↓
    │    expr
    └─────┘
```

The recursive grammar itself isn’t the problem. A difference expression needs to contain other expressions.

The problem is that `expr` and `diffExpr` are parser values that immediately depend on each other. To construct `expr`, Elm needs `diffExpr`. But to construct `diffExpr`, it needs `expr`.

Neither definition can be completed first.

What we need is a way to delay obtaining the `expr` parser until parsing reaches an operand. That’s what `P.lazy` allows us to do.

## Using `P.lazy` for recursive parsers

`elm/parser` provides [`P.lazy`](https://package.elm-lang.org/packages/elm/parser/latest/Parser#lazy) for recursive parser definitions. Instead of referring to `expr` directly, we provide a function that returns it:

```elm
diffExpr : Parser Expr
diffExpr =
    P.succeed Diff
        |. L.symbol "-"
        |. L.symbol "("
        |= P.lazy (\_ -> expr)
        |. L.symbol ","
        |= P.lazy (\_ -> expr)
        |. L.symbol ")"
```

The important change is:

```elm
P.lazy (\_ -> expr)
```

The `expr` parser is now obtained through a function. This allows Elm to construct `diffExpr` without first having to obtain `expr`.

When parsing reaches an operand, `P.lazy` obtains the `expr` parser from the function. The operand can then be parsed as either a constant or another difference expression.

We use `P.lazy` for both operands because either one can contain a nested expression.

The recursion eventually reaches `constExpr`, which parses a number without referring back to `expr`. That gives the recursive parser its base case.

With `expr` obtained lazily at each operand, the parser compiles and can handle expressions nested to any depth.

## Evaluating the recursive AST

Earlier, adding `Diff` to `Expr` caused Elm to point out that `runExpr` was missing a case. We can now define what that case means.

The parser gives us a recursive AST:

```elm
type Expr
    = Const Number
    | Diff Expr Expr
```

The evaluator follows that same structure:

```elm
runExpr : Expr -> Value
runExpr expr =
    case expr of
        Const n ->
            VNumber n

        Diff a b ->
            evalDiff (runExpr a) (runExpr b)


evalDiff : Value -> Value -> Value
evalDiff va vb =
    case ( va, vb ) of
        ( VNumber a, VNumber b ) ->
            VNumber <| a - b
```

`Const` is the base case. It contains no other expressions, so evaluating it simply wraps its number in `VNumber`.

A `Diff`, on the other hand, contains two expressions. We recursively evaluate both operands:

```elm
runExpr a
runExpr b
```

and pass their values to `evalDiff`, which extracts the two numbers and subtracts the second from the first.

The evaluator is recursive because the AST is recursive. We didn’t add recursion as a separate technique; it follows naturally from the shape of the data being evaluated.

For our running example:

```txt
-(2, -(4, 3))
```

the nested difference evaluates to `1`, allowing the outer expression to compute `2 - 1`.

The complete transformation is:

```txt
-(2, -(4, 3))

        ↓ parse

Program
    (Diff
        (Const 2)
        (Diff
            (Const 4)
            (Const 3)
        )
    )

        ↓ evaluate

VNumber 1
```

The `evalDiff` helper keeps two steps separate: `runExpr` evaluates the operand expressions, then `evalDiff` applies subtraction to the resulting values.

### Computing values that can’t be written as literals

DIFF’s grammar only supports non-negative integer literals:

```txt
Number ::= [0-9]+
```

This means the following isn’t a valid DIFF program:

```txt
-1
```

However, DIFF can still compute a negative value:

```txt
-(0, 1)
```

which evaluates to:

```elm
VNumber -1
```

The grammar describes which numeric literals can be written directly in source code. The `Value` type describes which values can result from evaluation.

That distinction appears in:

```txt
-(-(5, 3), -(0, 1))
```

The left operand evaluates to `2`, while the right operand evaluates to `-1`:

```txt
-(2, -1)
→ 3
```

So the complete program evaluates to:

```elm
VNumber 3
```

## Testing structure and meaning

The parser tests document which source programs DIFF accepts and which ASTs they produce.

These tests use the `testValue` helper we developed in [Testing an Elm Interpreter with elm-test](/posts/testing-an-elm-interpreter-with-elm-test).

We keep a constant expression to confirm that constant expressions inherited from CONST still work, then add examples of basic and nested difference expressions:

```elm
suite : Test
suite =
    describe "DIFF.Parser"
        [ describe "parse" <|
            List.map (testValue P.parse)
                [ ( "123"
                  , Just (Program (Const 123))
                  )

                , ( "-(456, 123)"
                  , Just
                        (Program
                            (Diff
                                (Const 456)
                                (Const 123)
                            )
                        )
                  )

                , ( "-(2, -(4, 3))"
                  , Just
                        (Program
                            (Diff
                                (Const 2)
                                (Diff
                                    (Const 4)
                                    (Const 3)
                                )
                            )
                        )
                  )

                , ( """
                    -(
                        -(5, 3),
                        -(0, 1)
                    )
                    """
                  , Just
                        (Program
                            (Diff
                                (Diff
                                    (Const 5)
                                    (Const 3)
                                )
                                (Diff
                                    (Const 0)
                                    (Const 1)
                                )
                            )
                        )
                  )
                ]
        ]
```

The interpreter tests document the meaning of those programs:

```elm
suite : Test
suite =
    describe "DIFF.Interpreter"
        [ describe "run" <|
            List.map (testValue I.run)
                [ ( "123"
                  , Just (VNumber 123)
                  )

                , ( "-(456, 123)"
                  , Just (VNumber 333)
                  )

                , ( "-(2, -(4, 3))"
                  , Just (VNumber 1)
                  )

                , ( """
                    -(
                        -(5, 3),
                        -(0, 1)
                    )
                    """
                  , Just (VNumber 3)
                  )
                ]
        ]
```

Elm’s compiler and these tests check different things.

When we added `Diff` to the AST, the compiler told us that `runExpr` needed another branch. It can ensure that the `case` expression handles every kind of `Expr`.

It can’t ensure that we gave `Diff` the correct meaning. Each of these implementations would still type-check:

```elm
VNumber <| a + b
```

```elm
VNumber <| b - a
```

```elm
VNumber 0
```

The interpreter tests verify that we gave the expressions their intended meaning:

```txt
-(456, 123)
→ 333

-(2, -(4, 3))
→ 1

-(-(5, 3), -(0, 1))
→ 3
```

Together, the compiler and tests give us different kinds of confidence: the compiler ensures that every kind of expression is handled, the parser tests verify that source programs produce the intended structure, and the interpreter tests verify that those programs have the intended meaning.

## What DIFF adds to the interpreter

Adding difference expressions changes each layer of the implementation we’ve been following:

- **Grammar:** `Expr` can now be either a `Const` or a `Diff`. The grammar is recursive because `Expr` can expand to `Diff`, whose operands are themselves expressions.
- **Lexer:** The new `symbol` helper recognizes `-`, `(`, `,`, and `)` while consuming trailing whitespace.
- **AST:** The `Diff Expr Expr` constructor gives us a recursive data structure that can represent nested expressions.
- **Parser:** `P.oneOf` chooses between expression forms, while `P.lazy` lets the recursive `expr` parser be obtained only when parsing reaches an operand.
- **Evaluator:** `runExpr` recursively evaluates both operands before applying subtraction.
- **Tests:** Parser tests verify the structure produced from source programs, while interpreter tests verify their meaning.

The new syntax is small, but the change is structural. A difference expression contains other expressions, so the same recursive shape appears in the grammar, AST, parser, and evaluator.

## Where we go next

Our next interpreter, ZERO, will introduce a second kind of value: Booleans.

Before we build ZERO, think through what introducing Booleans might require us to change. How might the grammar, lexer, AST, parser, evaluator, and tests need to evolve?

We’ll answer those questions when we build ZERO.
