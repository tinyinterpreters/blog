---
title: "Multiple-Binding let Expressions - Syntax Before Semantics"
description: Extend a tiny Elm interpreter with multiple-binding let expressions, then explore the semantic choices that lead to parallel and sequential bindings.
pubDatetime: 2026-09-10T01:10:00
tags:
  - interpreters
  - programming languages
  - elm
---

Our [LET](https://github.com/tinyinterpreters/let) interpreter already allows a program to introduce many local bindings, but each `let` expression introduces exactly one:

```txt
let a = 5 in let b = 3 in -(a, b)
```

What if a single `let` expression could introduce several?

```txt
let
    a = 5
    b = 3
in
-(a, b)
```

At first, this looks like a straightforward extension. Change the grammar so `let` accepts several bindings, represent those bindings in the AST, and update the parser.

But multiple bindings introduce a question that a single binding never had to answer.

Consider:

```txt
let
    x = 20
    y = x
in
y
```

What does the `x` in `y = x` refer to?

Does it refer to the `x = 20` introduced by the same `let` expression, or to an `x` from the surrounding environment?

Both are reasonable meanings for a multiple-binding `let` expression.

So in this article, we'll add support for writing and parsing multiple bindings without deciding yet which meaning they should have.

You can find the code for this exploration on the [`multiple-bindings`](https://github.com/tinyinterpreters/let/tree/multiple-bindings) branch of LET.

## Table of contents

## Extending the grammar

LET currently describes a `let` expression with:

```txt
Let ::= 'let' Id '=' Expr 'in' Expr
```

We can allow multiple bindings by changing the rule to:

```txt
Let ::= 'let' (Id '=' Expr)+ 'in' Expr
```

Here, each `Id '=' Expr` is a binding, and `+` requires at least one. That rules out a `let` expression with no bindings.

## Updating the AST

The AST also needs to represent a collection of bindings:

```elm
module LET.AST exposing
    ( Binding(..)
    , -- ...
    )

type Expr
    = -- ...
    | Let (List Binding) Expr


type Binding
    = Binding Id Expr
```

Each binding now has its own representation. For example:

```txt
a = 5
```

becomes:

```elm
Binding "a" (Const 5)
```

and:

```txt
let
    a = 5
    b = 3
in
-(a, b)
```

can be represented as:

```elm
Let
    [ Binding "a" (Const 5)
    , Binding "b" (Const 3)
    ]
    (Diff (Var "a") (Var "b"))
```

There is one mismatch between the grammar and this representation. `List Binding` also allows us to construct:

```elm
Let [] body
```

An alternative would be:

```elm
type Expr
    = -- ...
    | Let (Binding, List Binding) Expr
```

This representation guarantees that a `Let` contains a first binding, followed by any additional bindings.

For this exploration, I'll keep `List Binding`. Source programs enter the interpreter through the parser, where the grammar already rules out the empty case.

The alternative is still interesting because it shows how the AST itself could preserve that invariant.

## Preserving the existing behaviour

Before changing the parser to accept multiple bindings, we can update the existing code to work with the new AST while preserving LET's current behaviour.

The `letExpr` parser still parses a single binding, but now wraps it in a list:

```elm
letExpr : Parser Expr
letExpr =
    P.succeed
        (\name bound body ->
            Let [ Binding name bound ] body
        )
        |. L.keyword "let"
        |= id
        |. L.symbol "="
        |= P.lazy (\_ -> expr)
        |. L.keyword "in"
        |= P.lazy (\_ -> expr)
```

The parser tests need the corresponding structural change, with each existing binding represented using `Binding`.

The evaluator can likewise preserve the existing single-binding semantics:

```elm
Let [ Binding name bound ] body ->
    runExpr bound env
        |> Result.andThen
            (\vBound ->
                runExpr body (Env.extend name vBound env)
            )

Let _ body ->
    Debug.todo "Define the semantics of multiple bindings"
```

The first branch handles the programs LET already supports. The second deliberately leaves multiple bindings undefined for now.

With these changes, all the existing tests continue to pass, so the AST is ready for multiple bindings while the current language still behaves exactly as before.

## Parsing multiple bindings

Now we can update the parser to match the new grammar.

First, we add a combinator for parsing one or more occurrences of another parser:

```elm
oneOrMore : Parser a -> Parser (List a)
oneOrMore p =
    P.succeed (::)
        |= p
        |= many p


many : Parser a -> Parser (List a)
many p =
    P.loop [] <|
        \rev ->
            P.oneOf
                [ P.map (\x -> P.Loop (x :: rev)) p
                , P.succeed (P.Done (List.reverse rev))
                ]
```

`oneOrMore` requires one successful parse with `p`, then uses `many` to collect any additional results.

Next, we give a single binding its own parser:

```elm
binding : Parser Binding
binding =
    P.succeed Binding
        |= id
        |. L.symbol "="
        |= P.lazy (\_ -> expr)
```

With that in place, `letExpr` becomes:

```elm
letExpr : Parser Expr
letExpr =
    P.succeed Let
        |. L.keyword "let"
        |= oneOrMore binding
        |. L.keyword "in"
        |= P.lazy (\_ -> expr)
```

This now follows the grammar closely:

```txt
Let ::= 'let' (Id '=' Expr)+ 'in' Expr
```

The parser collects the bindings into the `List Binding` expected by `Let`.

## Testing the new syntax

We can now add parser tests for multiple bindings:

```elm
--- Multiple bindings
, ( "let a = 5 b = 3 in -(a, b)"
  , Just
        (Program
            (Let
                [ Binding "a" (Const 5)
                , Binding "b" (Const 3)
                ]
                (Diff (Var "a") (Var "b"))
            )
        )
  )
, ( """
    let
        a = 5
        b = 3
        c =
            -(a, b)
    in
    c
    """
  , Just
        (Program
            (Let
                [ Binding "a" (Const 5)
                , Binding "b" (Const 3)
                , Binding "c" (Diff (Var "a") (Var "b"))
                ]
                (Var "c")
            )
        )
  )
```

These tests confirm that the parser collects each binding in source order and constructs the `List Binding` expected by `Let`.

## Deciding what multiple bindings mean

We can now write and parse multiple-binding `let` expressions, but the evaluator still doesn't know what to do with them.

That is deliberate.

In a binding such as:

```txt
x = e
```

we'll call `e` the **initializer expression**. It is the expression evaluated to obtain the value associated with `x`.

Giving meaning to multiple bindings involves several choices:

|Axis|Some possibilities|
|---|---|
|Earlier bindings visible?|yes / no|
|Self visible?|yes / no|
|Later bindings visible?|yes / no|
|How bindings become available|parallel / sequential / dependency-ordered|
|Initializer evaluation order|first-to-last / last-to-first / unspecified / concurrent|
|Evaluation strategy|eager / call-by-name / call-by-need|
|Cycles between bindings|impossible / allowed / rejected|
|Duplicate names|rejected / shadowing / first wins / last wins|

Here, **earlier** and **later** refer to the order in which bindings appear in the source.

These questions overlap, but they aren't identical.

For example, deciding whether an initializer can see an earlier binding is separate from deciding which initializer gets evaluated first. Likewise, allowing duplicate names is a different decision from deciding how bindings become available.

Bindings could become available in several ways:

- **parallel** — sibling bindings are not available while their initializers are evaluated
- **sequential** — bindings become available according to source order
- **dependency-ordered** — bindings become available in an order determined by which bindings depend on which others

Dependency-ordered bindings can therefore make a later binding available before an earlier one when the earlier binding depends on it.

For this exploration, we'll focus on one especially important question:

> Can an initializer see bindings that came before it in the same `let` expression?

## Two meanings we'll explore

Two conventional answers to that question are parallel binding and sequential binding, which we'll explore as **LETPAR** and **LETSEQ**.

These aren't arbitrary choices. The underlying parallel and sequential binding semantics both appear in real programming languages, although their syntax and terminology vary.

We'll keep most of our choices the same and vary how sibling bindings become available:

|Axis|LETPAR|LETSEQ|
|---|---|---|
|Earlier bindings visible?|no|yes|
|Self visible?|no|no|
|Later bindings visible?|no|no|
|How bindings become available|parallel|sequential|
|Initializer evaluation order|first-to-last|first-to-last|
|Evaluation strategy|eager|eager|
|Cycles between bindings|impossible|impossible|
|Duplicate names|later bindings shadow earlier ones|later bindings shadow earlier ones|

Here, **parallel** means that none of the sibling bindings becomes available while the initializer expressions are being evaluated. **Sequential** means that bindings become available in source order, so each initializer can see the bindings that came before it.

The initializer expressions themselves are still evaluated first-to-last in both variations. Parallel binding therefore does not mean concurrent evaluation.

Now reconsider the example from the introduction:

```txt
let
    x = 20
    y = x
in
y
```

Suppose the surrounding environment already associates `x` with `10`.

With LETPAR, `x = 20` is not available while the initializer for `y` is evaluated, so the `x` in `y = x` refers to the surrounding `x`:

```txt
LETPAR → 10
```

With LETSEQ, `x = 20` becomes available before the initializer for `y` is evaluated:

```txt
LETSEQ → 20
```

The syntax and AST are identical. What changes is the meaning we assign to the bindings.

## Where we go next

Next, we'll implement LETPAR and see how parallel binding semantics shape the evaluator.

Then we'll return to the same syntax and AST for LETSEQ and see how one change in meaning leads to a different evaluation strategy.
