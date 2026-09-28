---
title: "FUN: Making Curried Functions Work in the Presence of Free Variables"
description: Fix a subtle problem with currying and free variables by changing what FUN stores in a function value, uncovering closures along the way.
pubDatetime: 2026-09-28T03:30:00
tags:
  - currying
  - closures
  - elm
---

In the previous article, [FUN: First-Class Functions, Currying, and a Surprise](/posts/fun-first-class-functions), we added support for first-class functions.

We saw how functions can be passed around like any other value and, more importantly for us, how a function can return another function. That gave us currying, a way to represent a function of more than one argument as a sequence of one-argument functions. Using currying, we wrote `add` like this:

```txt
let
    add =
        fun (a)
            fun (b)
                -(a, -(0, b))
in
((add 3) 5)
```

We expected `8`. Instead, FUN couldn't find `a`.

We ended the last article knowing why FUN behaves this way. What we haven't figured out yet is what a returned function needs in order for this example to work the way we expected.

Let's find out. 🧐

## What does `(add 3)` return?

When we evaluate `(add 3)`, FUN returns the inner function as a value:

```elm
VFun
    "b"
    (Diff
        (Var "a")
        (Diff (Const 0) (Var "b"))
    )
```

`a` is free in this function. However, we expect it to be `3` because that's what it was just bound to.

The value contains the parameter `b` and the body `Diff (Var "a") (Diff (Const 0) (Var "b"))`. But it doesn't remember the binding `a = 3`.

When the value is later applied to `5`, that binding is no longer in scope. That's the information our returned function is missing.

## Save the environment

When the inner function is created, `a = 3` is still in the current environment.

So instead of throwing that environment away, we can save it as part of the function value:

```elm
type Value
    = -- ...
    | VFun Id Expr Env
```

Then evaluating a function becomes:

```elm
Fun param body ->
    Ok <| VFun param body env
```

Now the value returned by `(add 3)` contains everything it needs:

- the parameter `b`
- the body
- the environment where `a` is bound to `3`

A function value that carries the environment in which it was created is called a **closure**.

## Use the saved environment

Saving the environment isn't enough. We also have to use it when the function is applied.

Previously, `evalCall` evaluated the body using the environment where the call happened. Now it can use the environment stored in the closure instead:

```elm
evalCall : Value -> Value -> Result RuntimeError Value
evalCall vF vArg =
    case vF of
        VFun param body savedEnv ->
            runExpr body (Env.extend param vArg savedEnv)

        _ ->
            Err <|
                TypeError
                    { expected = [ TFun ]
                    , actual = [ typeOf vF ]
                    }
```

The argument is added to the saved environment before the body is evaluated.

So when the function returned by `(add 3)` is later applied to `5`, its saved environment already contains `a = 3`, and applying it adds `b = 5`.

## Does it work?

Let's step through `((add 3) 5)` again.

Evaluating `(add 3)` produces a closure:

```elm
VFun
    "b"
    (Diff
        (Var "a")
        (Diff (Const 0) (Var "b"))
    )
    savedEnv
```

where `savedEnv` contains:

```txt
a ↦ VNumber 3
```

Next, we apply that value to `5`, extending the saved environment with `b`:

```txt
a ↦ VNumber 3
b ↦ VNumber 5
```

Now when the body is evaluated, both variables refer to the values we expect:

```txt
-(3, -(0, 5))
```

which evaluates to:

```elm
VNumber 8
```

At last, our curried `add` works. 🥲

## What else changed?

In the previous article, this program returned `16`:

```txt
let
    a = 11
in
((add 3) 5)
```

The inner function found `a = 11` in the environment where it was called.

That doesn't happen anymore.

`(add 3)` now returns a closure whose saved environment contains `a = 3`. When we later apply it to `5`, its body is evaluated in that saved environment, so the `a = 11` surrounding the call has no effect. The result is still `8`.

Before this change, FUN resolved a function's free variables using the environment where the function was called. That's **dynamic scope**.

Now it resolves them using the environment where the function was defined. The meaning of `a` in our inner function is determined by the bindings surrounding the function where it appears in the program, not by whatever bindings happen to exist later when it is called.

That's **lexical scope**.

By turning our function values into closures, FUN can now resolve their free variables lexically instead of dynamically.

You can find [the complete source code for FUN, of both variations, on GitHub](https://github.com/tinyinterpreters/fun).

## Closures go back to 1964

The idea we just arrived at isn't new.

In 1964, Peter Landin described closures in [The Mechanical Evaluation of Expressions](https://www.cs.cmu.edu/~crary/819-f09/Landin64.pdf) as having an **environment part** and a **control part**. The environment preserves the bindings a function needs, while the control part contains the expression to evaluate.

Landin even pointed out that the environment part wouldn't be necessary if functions weren't allowed to contain free variables.

## The FUNARG problem was an environment problem

In the previous article, we saw that early LISP ran into the same issue with functions containing free variables. It became known as the **FUNARG problem**.

In 1970, Joel Moses revisited it in [The Function of FUNCTION in LISP, or Why the FUNARG Problem Should Be Called the Environment Problem](https://dl.acm.org/doi/10.1145/1093410.1093411).

He framed the problem as determining what values to assign to free variables in functions and compared different ways LISP implementations dealt with their environments.

His title gets to the heart of it: once a function contains free variables, the language has to determine which environment supplies their values.

## Scheme combined lexical scope with first-class procedures

A few years later, Scheme made a clear choice about how procedures and their environments should work.

In their 1975 report, [SCHEME: An Interpreter for Extended Lambda Calculus](https://research.scheme.org/lambda-papers/lambda-papers-scheme-report.html), Gerald Jay Sussman and Guy Steele described a closure as a lambda expression together with the environment to use when it is applied. Free variables refer to the environment saved with the closure, not the environment where the closure is later applied.

The [1978 Revised Report on Scheme](https://research.scheme.org/lambda-papers/lambda-papers-revised-report.html) made the consequence explicit: variables in Scheme were normally lexically scoped, while procedures were treated as first-class values.

## A challenge for next time

Consider:

```txt
let
    sum =
        fun (n)
            if zero?(n) then
                0
            else
                -(n, -(0, (sum -(n, 1))))
in
(sum 5)
```

What do you think FUN does with this?

Can you make it work without adding anything new to the language?

We'll find out next time.
