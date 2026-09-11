---
title: "LETSEQ: Sequential Binding Semantics for let Expressions"
description: Define LETSEQ precisely, implement sequential binding semantics in Elm, test the interesting edge cases, and compare similar forms in Racket and Clojure.
pubDatetime: 2026-09-10T09:00:00
tags:
  - interpreters
  - programming languages
  - elm
---

In [LETPAR: Parallel Binding Semantics for `let` Expressions](/posts/letpar), every initializer expression was evaluated in the environment that existed before the `let` expression.

LETSEQ makes a different choice: each binding becomes available before the next initializer expression is evaluated.

Consider:

```txt
let
    x = 20
    y = x
in
y
```

Our initial environment already contains `x = 10`.

After `x = 20` is evaluated, that binding becomes available before `y = x` is evaluated. So `y` sees `x = 20`, not the incoming `x = 10`.

The complete expression therefore evaluates to:

```elm
VNumber 20
```

In this article, we'll define LETSEQ precisely, implement it in the evaluator, test the interesting cases, and look at programming languages with comparable sequential-binding semantics.

You can find the complete implementation on the [`letseq`](https://github.com/tinyinterpreters/let/tree/letseq) branch of LET.

## Table of contents

## The meaning of LETSEQ

Let's make the semantics precise. For:

```txt
let
    x1 = e1
    x2 = e2
    ...
    xn = en
in
body
```

evaluated in an incoming environment `env`:

1. Evaluate `e1` through `en` to values, from first to last.
2. Evaluate each initializer expression in the environment produced by all the bindings before it, starting with `env` for `e1`.
3. If an initializer fails, return that error without evaluating the remaining initializers.
4. After each initializer succeeds, add its resulting binding to the environment. If a name occurs more than once, a later binding shadows an earlier one.
5. Evaluate `body` in the resulting environment, where all the new bindings are visible.

Because visibility only flows from earlier bindings to later ones, cycles between sibling bindings cannot arise.

With LETSEQ, source order determines both the order in which initializer expressions are evaluated and which sibling bindings each initializer can see.

## LETSEQ as nested `let` expressions

There is another useful way to understand LETSEQ: a multiple-binding LETSEQ expression is equivalent to nested single-binding `let` expressions.

This:

```txt
let
    x = 20
    y = -(x, 1)
in
y
```

has the same meaning as:

```txt
let
    x = 20
in
let
    y = -(x, 1)
in
y
```

More generally:

```txt
let
    x1 = e1
    x2 = e2
    ...
    xn = en
in
body
```

is equivalent to:

```txt
let
    x1 = e1
in
let
    x2 = e2
in
...
let
    xn = en
in
body
```

Each binding becomes available to the initializer expressions that follow it and, eventually, to the body.

## Implementing LETSEQ

The implementation is slightly simpler than LETPAR:

```elm
runExpr : Expr -> Env -> Result RuntimeError Value
runExpr expr env =
    case expr of
        -- ...

        Let bindings body ->
            evalBindings bindings env
                |> Result.andThen
                    (\bodyEnv ->
                        runExpr body bodyEnv
                    )


evalBindings : List Binding -> Env -> Result RuntimeError Env
evalBindings bindings bodyEnv =
    case bindings of
        [] ->
            Ok bodyEnv

        (Binding name bound) :: restOfBindings ->
            runExpr bound bodyEnv
                |> Result.andThen
                    (\vBound ->
                        evalBindings
                            restOfBindings
                            (Env.extend name vBound bodyEnv)
                    )
```

LETPAR needed separate environments for the initializer expressions and the body. LETSEQ needs only one.

Each initializer is evaluated in `bodyEnv`. If it succeeds, its resulting binding is added to that environment before evaluation continues with the remaining bindings.

As a result, `bodyEnv` grows from one binding to the next. Each initializer sees the bindings that came before it. When there are no bindings left, `evalBindings` returns the fully extended `bodyEnv`, which is then used to evaluate the body.

## Testing LETSEQ

The interpreter tests exercise the semantics we defined:

```elm
--- LETSEQ semantics
, ( "let x = 20 y = x in y", SucceedsWith (VNumber 20) )
, ( "let x = 20 y = -(x, 1) in y", SucceedsWith (VNumber 19) )
, ( "let a = 5 b = -(a, 1) c = -(b, 1) in c"
  , SucceedsWith (VNumber 3)
  )
, ( "let a = b b = 1 in a"
  , RuntimeError <| I.IdentifierNotFound "b"
  )
, ( "let x = 1 x = x in x", SucceedsWith (VNumber 1) )
, ( "let x = 1 x = 2 in x", SucceedsWith (VNumber 2) )
```

Tests 1–3 check that earlier sibling bindings are visible to initializer expressions. Each successful binding extends the environment used by the initializers that follow it.

Test 4 checks the other direction: later sibling bindings are not visible, so the forward reference to `b` fails.

Tests 5 and 6 cover duplicate names. Test 5 is the more interesting case: the second initializer sees the earlier `x = 1`, so the later binding also gets the value `1`. Test 6 confirms that a later binding shadows an earlier one with the same name.

## Sequential bindings in other programming languages

LETSEQ's sequential binding semantics also appear in real programming languages.

Racket's [`let*`](https://docs.racket-lang.org/guide/let.html?version=9.3#(part._.Sequential_.Binding__let_)) allows each binding to be used by the bindings that follow it. This matches LETSEQ's visibility rule, and `let*` can likewise be understood as a sequence of nested single-binding `let` expressions.

Clojure's [`let`](https://clojure.org/reference/special_forms#let) also uses sequential bindings. Each binding can see the bindings that came before it in the binding vector.

The names differ, but both share LETSEQ's central idea: each binding becomes available before the next initializer expression is evaluated.
