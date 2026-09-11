---
title: "LETPAR: Parallel Binding Semantics for let Expressions"
description: Define LETPAR precisely, implement parallel binding semantics in Elm, test the interesting edge cases, and compare similar forms in Racket and OCaml.
pubDatetime: 2026-09-09T09:00:00
tags:
  - interpreters
  - programming languages
  - elm
---

In [Multiple-Binding `let` Expressions: Syntax Before Semantics](/posts/multiple-binding-let-expressions), we added support for multiple bindings but deliberately stopped before deciding what they should mean.

Now we'll implement one of the meanings we identified there: **LETPAR**, with parallel binding semantics.

For LETPAR, every initializer expression is evaluated in the environment that existed before the `let` expression.

Consider:

```txt
let
    x = 20
    y = x
in
y
```

Our initial environment already contains `x = 10`.

Because `y = x` is evaluated in that incoming environment, it sees `x = 10`, not the sibling binding `x = 20`.

So the expression evaluates to:

```elm
VNumber 10
```

In this article, we'll define LETPAR precisely, implement it in the evaluator, test the interesting cases, and look at programming languages with comparable parallel-binding semantics.

You can find the complete implementation on the [`letpar`](https://github.com/tinyinterpreters/let/tree/letpar) branch of LET.

## Table of contents

## The meaning of LETPAR

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
2. Evaluate every initializer expression in `env`.
3. None of the bindings introduced by the `let` expression is visible to any initializer.
4. If an initializer fails, return that error without evaluating the remaining initializers.
5. Add each resulting binding to the body environment from first to last. If a name occurs more than once, a later binding shadows an earlier one.
6. Evaluate `body` in the resulting environment, where all the new bindings are visible.

Because sibling bindings are never visible to initializer expressions, cycles between them cannot arise.

Here, **parallel** describes how the bindings relate to one another, not how their initializer expressions must be executed. Our interpreter evaluates them from first to last, although an implementation could potentially evaluate them concurrently as an optimization, provided it preserves the observable behavior of that evaluation order.

## Implementing LETPAR

The evaluator change is small:

```elm
runExpr : Expr -> Env -> Result RuntimeError Value
runExpr expr env =
    case expr of
        -- ...

        Let bindings body ->
            evalBindings bindings env env
                |> Result.andThen
                    (\bodyEnv ->
                        runExpr body bodyEnv
                    )


evalBindings : List Binding -> Env -> Env -> Result RuntimeError Env
evalBindings bindings bodyEnv initializerEnv =
    case bindings of
        [] ->
            Ok bodyEnv

        (Binding name bound) :: restOfBindings ->
            runExpr bound initializerEnv
                |> Result.andThen
                    (\vBound ->
                        evalBindings
                            restOfBindings
                            (Env.extend name vBound bodyEnv)
                            initializerEnv
                    )
```

The key is that `evalBindings` carries two environments:

- `initializerEnv` is the environment in which every initializer expression is evaluated.
- `bodyEnv` is the environment being built for the body.

They start out identical, but only `bodyEnv` changes.

Each initializer is evaluated in `initializerEnv`. If it succeeds, its resulting binding is added to `bodyEnv`, and evaluation continues with the remaining bindings while `initializerEnv` stays unchanged.

When there are no bindings left, `evalBindings` returns `bodyEnv`, and the `Let` branch evaluates the body in that environment.

## Testing LETPAR

The interpreter tests exercise the semantics we defined:

```elm
--- LETPAR semantics
, ( "let x = 20 y = x in y", SucceedsWith (VNumber 10) )
, ( "let x = 20 y = -(x, 1) in y", SucceedsWith (VNumber 9) )
, ( "let a = 5 b = -(a, 1) c = -(b, 1) in c"
  , RuntimeError <| I.IdentifierNotFound "a"
  )
, ( "let a = b b = 1 in a"
  , RuntimeError <| I.IdentifierNotFound "b"
  )
, ( "let x = 1 x = x in x", SucceedsWith (VNumber 10) )
, ( "let x = 1 x = 2 in x", SucceedsWith (VNumber 2) )
```

Tests 1–3 check that earlier sibling bindings are not visible to initializer expressions. Tests 1 and 2 therefore use the `x = 10` from the incoming environment, while test 3 fails because `a` is not present there.

Test 4 checks the other direction: later sibling bindings are not visible either, so the forward reference to `b` fails.

Tests 5 and 6 cover duplicate names. Test 5 is the more interesting case: the second initializer sees the incoming `x = 10`, not the earlier sibling binding. Test 6 confirms that once the bindings have been added to the body environment, a later binding shadows an earlier one with the same name.

## Parallel bindings in other programming languages

LETPAR's parallel binding semantics also appear in real programming languages.

Racket's [`let`](https://docs.racket-lang.org/guide/let.html?version=9.3#(part._.Parallel_.Binding__let)) is particularly close. Its documentation explicitly describes `let` as **parallel binding**: none of the new identifiers is visible in any initializer, but all are available in the body. Racket also evaluates the initializer expressions from left to right. Unlike LETPAR, however, it requires the bound identifiers to be distinct.

OCaml's [`let ... and ... in ...`](https://ocaml.org/manual/5.5/expr.html#sss:expr-localdef) provides a similar form. The right-hand expressions are evaluated before their bindings are added to the environment used for the body, although their evaluation order is unspecified.

So while the details vary, both share LETPAR's central idea: sibling bindings are not visible while their initializer expressions are evaluated.
