---
title: "FUN: First-Class Functions, Currying, and a Surprise"
description: Extend LET with first-class functions, then use currying and partial application to uncover an unexpected consequence of how function calls are evaluated.
pubDatetime: 2026-09-21T02:30:00
tags:
  - first-class functions
  - currying
  - elm
---

Let's have some FUN. 🤓

FUN extends [LET](/posts/let/) with first-class functions. That means our functions can be created as values, bound to names, passed as arguments, and returned as results.

If you're used to functional programming, all of that probably feels ordinary. We're implementing these interpreters in Elm, after all. Functions are values in Elm too, where they enjoy first-class citizenship. FUN gives us a chance to see the small set of interpreter rules that make those familiar capabilities possible.

## Table of contents

## What do we need to do to add functions?

At a high level, adding functions requires two things.

First, we need a way to **create a function**, using a function expression:

```txt
fun (parameter) body
```

For example:

```txt
fun (x) -(x, 1)
```

Here, `x` is the **parameter**, also called the **formal parameter**, and `-(x, 1)` is the **body**.

Second, we need a way to **call a function**, using a call expression:

```txt
(function argument)
```

For example:

```txt
(decrement 333)
```

The first part is the **function position** and the second is the **argument position**. The function position can contain any expression that produces a function, while the argument position can contain any expression that produces the value we want to pass to it.

That means the function position doesn't have to be a name such as `decrement` and the argument position doesn't have to contain a constant such as `333`:

```txt
(fun (x) -(x, 1) -(456, 123))
```

The expression supplied in the argument position is the **argument**, also called the **actual parameter**.

We'll start with functions that take one argument. This keeps the language small while giving us the essential machinery for creating and calling functions.

Now that we know how we'll create and call them, we can decide what each expression should mean.

## What should a function expression mean?

Consider:

```txt
fun (x) -(x, 1)
```

What should happen when we evaluate this expression?

We can't evaluate the body yet because we don't have a value for `x`.

Instead, evaluating a function expression should produce a **function value** that remembers the parameter and body. The body will be evaluated later, when the function is called.

So our rule is:

> To evaluate `fun (parameter) body`, produce a function value containing the parameter and body. Do not evaluate the body.

## What should a function call mean?

Consider:

```txt
(decrement -(456, 123))
```

To evaluate this call, we first evaluate the function position, `decrement`, to get a function value. Then we evaluate the argument position, `-(456, 123)`, which produces `VNumber 333`.

Suppose the function value has `x` as its parameter and `-(x, 1)` as its body. We extend the current environment with `x ↦ VNumber 333` and evaluate the body in that extended environment. The complete call therefore produces `VNumber 332`.

More generally:

> To evaluate `(function argument)`, evaluate the function position and argument position in the current environment. If the function position produces a function value, extend the current environment by binding its parameter to the argument value, then evaluate its body in that extended environment.

Notice that the argument is evaluated before the function body. FUN therefore uses **call-by-value**, matching Elm's eager evaluation of function arguments.

## Extending the grammar

We can now extend the grammar with function expressions and call expressions:

```txt
Expr ::= ...
       | Fun
       | Call
Fun  ::= 'fun' '(' Id ')' Expr
Call ::= '(' Expr Expr ')'
```

A `Fun` contains an identifier for its parameter followed by an expression for its body. A `Call` contains two expressions: one in the function position and one in the argument position.

The only new reserved word is `fun`.

## Representing functions and calls in the AST

The AST changes exactly as the grammar suggests:

```elm
type Expr
    = -- ...
    | Fun Id Expr
    | Call Expr Expr
```

`Fun` stores the parameter and body, while `Call` stores the expressions in the function and argument positions.

That’s enough structure to represent both creating a function and calling one.

## Parsing functions and calls

The parsers follow directly from the grammar:

```elm
expr : Parser Expr
expr =
    P.oneOf
        [ -- ...
        , funExpr
        , callExpr
        ]

funExpr : Parser Expr
funExpr =
    P.succeed Fun
        |. L.keyword "fun"
        |. L.symbol "("
        |= id
        |. L.symbol ")"
        |= P.lazy (\_ -> expr)


callExpr : Parser Expr
callExpr =
    P.succeed Call
        |. L.symbol "("
        |= P.lazy (\_ -> expr)
        |= P.lazy (\_ -> expr)
        |. L.symbol ")"
```

And `fun` joins the list of reserved words:

```elm
keywords =
    [ "else"
    , "fun"
    , "if"
    , "in"
    , "let"
    , "then"
    ]
```

If you're joining the series for the first time, we've already explored the parser machinery behind this code in more depth. [Why Recursive Elm Parsers Need `Parser.lazy`](/posts/why-recursive-elm-parsers-need-parser-lazy/) explains why recursive parser values need to be delayed, while [Simplifying Whitespace with Lexeme Parsers in Elm](/posts/lexeme-parsers-in-elm/) explains the lexeme-parser convention behind helpers such as `symbol` and `keyword`.

## Representing functions as values

So far, our interpreter's values have represented results such as numbers and Booleans. FUN adds a new kind of value:

```elm
type Value
    = -- ...
    | VFun Id Expr
```

This gives us an important distinction:

- `Fun Id Expr` represents a function expression in the AST.
- `VFun Id Expr` represents the value produced when that expression is evaluated.

The evaluator rule follows directly from the semantics we established earlier:

```elm
Fun param body ->
    Ok <| VFun param body
```

So evaluating:

```
fun (x) -(x, 1)
```

produces:

```
VFun "x" (Diff (Var "x") (Const 1))
```

Because functions are now part of the value domain, we also add a corresponding runtime type:

```elm
type Type
    = -- ...
    | TFun
```

We'll use `TFun` when reporting an error if something that isn't a function appears in the function position of a call.

## Calling a function

**Calling a function**, also known as **applying a function** or **function application**, follows the rule we established earlier in the section "[What should a function call mean?](#what-should-a-function-call-mean)"

```elm
Call f arg ->
    runExpr f env
        |> Result.andThen
            (\vF ->
                runExpr arg env
                    |> Result.andThen
                        (\vArg ->
                            evalCall vF vArg env
                        )
            )
```

We evaluate the function position and the argument position in the current environment, then pass both resulting values to `evalCall`:

```elm
evalCall : Value -> Value -> Env -> Result RuntimeError Value
evalCall vF vArg env =
    case vF of
        VFun param body ->
            runExpr body (Env.extend param vArg env)

        _ ->
            Err <|
                TypeError
                    { expected = [ TFun ]
                    , actual = [ typeOf vF ]
                    }
```

If the function position produced a `VFun`, we extend the environment by binding its parameter to the argument value and evaluate its body in that extended environment. If it produced any other kind of value, we report a type error.

And that's it. FUN now has functions. 🎉

## Passing functions as arguments

Because functions are values, we can pass them as arguments to other functions.

For example, `applytwice` takes a function `f` and applies it twice:

```txt
let
    applytwice =
        fun (f) (f (f 5))
in
let
    double =
        fun (x) -(x, -(0, x))
in
(applytwice double)
```

`double` turns `5` into `10`, then applying it again turns `10` into `20`, so the program evaluates to:

```elm
VNumber 20
```

## Returning functions as results

Because functions are values, they can also be returned as results from other functions.

For example, `select` returns one of two functions depending on its argument:

```txt
let
    select =
        fun (n)
            if zero?(n) then
                fun (x) x
            else
                fun (x) -(x, 1)
in
((select 1) 8)
```

`select 1` returns:

```txt
fun (x) -(x, 1)
```

We then call that returned function with `8`, so the complete program evaluates to:

```elm
VNumber 7
```

## First-class and higher-order functions

We can now see what it means for functions to be **first-class values** in FUN. We can create them as values, bind them to names, pass them as arguments, and return them as results.

Functions that take other functions as arguments or return functions as results are called **higher-order functions**. `applytwice` is higher-order because it takes a function as an argument, while `select` is higher-order because it returns a function as its result.

These capabilities emerge from a small change to the interpreter: functions are now part of its value domain.

## Currying and partial application

When a Trinidadian thinks about [currying](https://www.youtube.com/watch?v=Ag85OTsaTWw), their mouth starts to water. Unfortunately, I'm talking about something else in this instance.

FUN's functions take one argument, but that doesn't stop us from expressing functions that conceptually take more than one. We've just seen that a function can return another function, so we can use that ability to define `add` like this:

```txt
let
    add =
        fun (a)
            fun (b)
                -(a, -(0, b))
in
((add 3) 5)
```

`add` takes `a` and returns a function that takes `b`. That inner function then adds the two values. Representing a function of multiple arguments as a sequence of functions that each take one argument is called **currying**.

Currying also lets us supply those arguments one at a time. `(add 3)` applies `add` to `3` and produces a function waiting for `b`. Supplying some, but not all, of a function's arguments in this way is called **partial application**.

So `((add 3) 5)` first partially applies `add` to `3`, then applies the resulting function to `5`. We would expect the program to produce `VNumber 8`.

It doesn't.

Instead, FUN reports:

```elm
IdentifierNotFound "a"
```

That's no FUN.

## Hold up, wait a minute, something ain't right

[![Hold up, wait a minute, something ain't right](@/assets/images/fun-first-class-functions/hold-up-wait-a-minute.gif)](https://www.youtube.com/watch?v=pkKNasQXVV0)

When we evaluate `(add 3)`, `a` is bound to `VNumber 3` while the body of `add` is evaluated. But that body produces a function value containing only its parameter and body:

```
VFun "b" (Diff (Var "a") (Diff (Const 0) (Var "b")))
```

The environment containing the binding for `a` isn't part of that value. By the time we apply the returned function to `5`, `b` is available in the current environment, but `a` isn't. Hence `IdentifierNotFound "a"`.

We can make the behaviour even clearer by putting another binding for `a` around the call:

```
let
    a = 11
in
((add 3) 5)
```

Now FUN produces `VNumber 16`. The returned function doesn't use the `a = 3` that existed when it was created. It finds the `a = 11` that's available when its body is evaluated.

This behaviour has a name.

## What is dynamic scope?

In the function returned by `(add 3)`, `b` is bound by the function's parameter, but `a` is not. `a` is a **free variable**.

FUN resolves free variables using the environment in effect when the function is called. This is called **dynamic scope**.

That's why the first program couldn't find `a`, while the second found `a = 11`. The meaning of the free variable depended on the environment surrounding the call.

Our implementation gets this behaviour because a function value stores only its parameter and body. When the function is called, its parameter is added to the current environment and its body is evaluated there.

We followed what seemed like the natural way to evaluate a function call, and dynamically scoped functions emerged from that choice.

## How did Lisp end up here too?

There’s a wonderfully familiar moment in John McCarthy’s [History of Lisp](http://jmc.stanford.edu/articles/lisp.html). He begins his account of the problem with: "In all innocence, James R. Slagle" wrote a LISP function and complained when it didn’t work correctly.

Slagle's function, `testr`, recursively searched an expression. It took a function `u` that should be called if the search failed. During the search, `testr` recursively called itself and passed along a newly created function as the next `u`. That function referred to `x` from the call in which it was created. Slagle expected that reference to keep meaning the outer `x`. Instead, when the function was eventually called, LISP found the `x` belonging to an inner recursive call.

Slagle complained, but McCarthy didn't initially see anything profound going on. "I regarded this difficulty as just a bug," he recalled, and he was confident Steve Russell would fix it. Russell eventually did, but the problem turned out to be more fundamental than an ordinary implementation mistake; McCarthy notes that similar difficulties later appeared in Algol 60 as well.

That's remarkably close to the path we just took with FUN. We followed what seemed like the natural way to evaluate a function call, tried a perfectly reasonable higher-order program, and discovered that a free variable was finding its value somewhere we didn't expect.

## Can we make `add` work the way we expected?

`add` surprised us, but we still want it to work the way we expected.

Maybe you can figure out how to change FUN so that:

```txt
((add 3) 5)
```

produces:

```elm
VNumber 8
```

In the next article, we'll pick up where we left off and work toward a solution.
