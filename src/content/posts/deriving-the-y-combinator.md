---
title: "Deriving the Y-combinator"
description: Derive the Z-combinator from self-application using simple program transformations, then discover its relationship to the Y-combinator.
pubDatetime: 2026-11-02T15:50:00
tags:
  - fixed-point-combinator
  - recursion
  - lambda-calculus
---

In [Recursion without Recursive Bindings](/posts/recursion-without-recursive-bindings/), we discovered how to write recursive functions using self-application, even though FUN doesn't support recursive bindings.

We also saw that the same technique works for several different recursive functions. But each time, we had to repeat the machinery that makes recursion possible.

Can we extract that machinery into a reusable function that takes care of recursion for us?

Let's find out by starting with our `sum` example and applying a series of simple transformations.

## Table of contents

## Step 1: Give self-application a name

Let's start with our `makesum` function and try replacing `(self self)` with a local binding named `sum`:

```
let
    makesum =
        fun (self)
            let
                sum = (self self)
            in
            fun (n)
                if zero?(n) then
                    0
                else
                    -(n, -(0, (sum -(n, 1))))
in
let
    sum = (makesum makesum)
in
(sum 10)
```

Why try this transformation?

Look at the inner function:

```
fun (n)
    if zero?(n) then
        0
    else
        -(n, -(0, (sum -(n, 1))))
```

It looks exactly like the recursive function we'd write if our language supported recursive bindings. That's promising!

Unfortunately, when we run the program, it doesn't terminate. Instead, we get:

```
RangeError: Maximum call stack size exceeded
```

What went wrong?

The problem is this binding:

```
let
    sum = (self self)
in
...
```

In FUN, `let` bindings are evaluated eagerly: the initializer `(self self)` must be evaluated before the body of the `let` expression.

But evaluating `(self self)` leads right back to evaluating `(self self)` again, and the process continues indefinitely.

In the previous version, `(self self)` was only evaluated when `n` wasn't zero. Now it gets evaluated before we even reach the conditional.

So we've changed when the recursive self-application happens, and that change prevents the recursion from ever reaching its base case.

Is there a way to delay the evaluation of `(self self)` until we actually need it?

## Step 2: Delay self-application

Yes! Instead of binding `sum` directly to `(self self)`, we can wrap the expression in a function:

```
let
    sum = fun (x) ((self self) x)
in
...
```

Our program becomes:

```
let
    makesum =
        fun (self)
            let
                sum = fun (x) ((self self) x)
            in
            fun (n)
                if zero?(n) then
                    0
                else
                    -(n, -(0, (sum -(n, 1))))
in
let
    sum = (makesum makesum)
in
(sum 10)
```

Now, evaluating the initializer of the `let` binding produces a function value. The body of that function, which contains `(self self)`, isn't evaluated until the function is called.

This delays self-application until `sum` is actually needed. In particular, when `n` is zero, the conditional returns `0` without evaluating `(self self)`.

The program works again and produces the same result as our original recursive version.

The transformation we used is called **eta expansion**. Given an expression `f` that evaluates to a function value, we can expand it from:

```
f
```

into:

```
fun (x) (f x)
```

We've used this idea of delaying evaluation before. In [Why Recursive Elm Parsers Need `Parser.lazy`](/posts/why-recursive-elm-parsers-need-parser-lazy), we placed a recursive parser reference inside a function to prevent Elm from evaluating it immediately. Here, we're using the same underlying idea, but through eta expansion rather than a thunk.

## Step 3: Desugar `let` into function application

Let's see what happens if we express our program using fewer language constructs.

In FUN, a `let` expression of the form:

```
let
    f = g
in
h
```

has the same meaning as:

```
(fun (f) h g)
```

This follows from the evaluation rules we've given `let` bindings and function applications in FUN. Both evaluate `g` and then make its value available as `f` while evaluating `h`.

We can use this equivalence to replace the inner `let` expression in `makesum`:

```
let
    sum = fun (x) ((self self) x)
in
fun (n)
    if zero?(n) then
        0
    else
        -(n, -(0, (sum -(n, 1))))
```

with function application.

Our program becomes:

```
let
    makesum =
        fun (self)
            (fun (sum)
                fun (n)
                    if zero?(n) then
                        0
                    else
                        -(n, -(0, (sum -(n, 1))))
             fun (x) ((self self) x))
in
let
    sum = (makesum makesum)
in
(sum 10)
```

We've removed the inner `let` expression without changing the meaning of our program.

This transformation is an example of **desugaring**: replacing a convenient syntactic form with another expression that has the same meaning. In FUN, we can understand this form of `let` as syntactic sugar for applying an anonymous function.

## Step 4: Move the function outside `makesum`

Now that we've replaced the `let` expression with function application, take another look at the anonymous function we've exposed:

```
fun (sum)
    fun (n)
        if zero?(n) then
            0
        else
            -(n, -(0, (sum -(n, 1))))
```

Notice anything interesting?

This function has no free variables. In particular, it doesn't refer to `self`, the parameter of the surrounding `makesum` function.

That means it doesn't depend on anything in its surrounding environment. We can move it outside `makesum` without changing the meaning of our program.

Let's give it a name: `almostsum`.

Our program becomes:

```
let
    almostsum =
        fun (sum)
            fun (n)
                if zero?(n) then
                    0
                else
                    -(n, -(0, (sum -(n, 1))))
in
let
    makesum =
        fun (self)
            (almostsum
             fun (x) ((self self) x))
in
let
    sum = (makesum makesum)
in
(sum 10)
```

We've separated the function that describes how `sum` computes its result from the self-application machinery that makes recursion possible.

## Step 5: Abstract over `almostsum`

Let's focus on `makesum` and `sum`, leaving `almostsum` aside for a moment:

```
let
    makesum =
        fun (self)
            (almostsum
             fun (x) ((self self) x))
in
let
    sum = (makesum makesum)
in
...
```

Notice that `almostsum` is a free variable in this part of the program.

What if we made that dependency explicit by introducing a function that takes `almostsum` as a parameter?

Let's call it `makerec`:

```
let
    makerec =
        fun (almostsum)
            let
                makesum =
                    fun (self)
                        (almostsum
                         fun (x) ((self self) x))
            in
            (makesum makesum)
in
let
    sum = (makerec almostsum)
in
(sum 10)
```

We've moved the definition of `makesum` and its self-application into `makerec`.

Instead of constructing `sum` directly with:

```
(makesum makesum)
```

we now construct it with:

```
(makerec almostsum)
```

## Step 6: Generalize `makerec`

Let's take another look at `makerec`:

```
makerec =
    fun (almostsum)
        let
            makesum =
                fun (self)
                    (almostsum
                     fun (x) ((self self) x))
        in
        (makesum makesum)
```

Notice that there's nothing specific to summation in this function anymore.

So let's give these names a more general meaning:

- Rename `almostsum` to `almostf`.
- Rename `makesum` to `makef`.

We get:

```
let
    makerec =
        fun (almostf)
            let
                makef =
                    fun (self)
                        (almostf
                         fun (x) ((self self) x))
            in
            (makef makef)
in
let
    sum = (makerec almostsum)
in
(sum 10)
```

## Step 7: Try `makerec` on the other examples

We've used `makerec` to construct `sum`. But can we use it to construct our other recursive functions too?

Let's try `double`, `mult`, `fact`, and `fib` from the previous article.

For each one, we'll write a function similar to `almostsum` that takes the recursive function as an argument.

For `double`:

```
almostdouble =
    fun (double)
        fun (n)
            if zero?(n) then
                0
            else
                -(2, -(0, (double -(n, 1))))
```

For `mult`:

```
almostmult =
    fun (mult)
        fun (a)
            fun (b)
                if zero?(b) then
                    0
                else
                    -(a, -(0, ((mult a) -(b, 1))))
```

For `fact`:

```
almostfact =
    fun (fact)
        fun (n)
            if zero?(n) then
                1
            else
                ((mult n) (fact -(n, 1)))
```

And for `fib`:

```
almostfib =
    fun (fib)
        fun (n)
            if zero?(n) then
                0
            else if zero?(-(n, 1)) then
                1
            else
                -((fib -(n, 1)), -(0, (fib -(n, 2))))
```

Now we can construct all five functions in the same way:

```
sum    = (makerec almostsum)
double = (makerec almostdouble)
mult   = (makerec almostmult)
fact   = (makerec almostfact)
fib    = (makerec almostfib)
```

## What have we accomplished?

We started with a technique for writing recursive functions without recursive bindings. But each recursive function needed its own version of the self-application machinery.

Through a series of transformations, we've managed to extract that machinery into a single function:

```
makerec =
    fun (almostf)
        let
            makef =
                fun (self)
                    (almostf
                     fun (x) ((self self) x))
        in
        (makef makef)
```

Now, instead of repeating the technique every time we want to write a recursive function, we can simply pass its `almost` function to `makerec`.

**We've built a function that makes recursive functions using nothing more than closures and self-application. No recursive bindings required!**

## Fixed points

We've seen that `makerec` can construct several different recursive functions. But there's another interesting relationship between those functions and their `almost` counterparts.

What happens if we evaluate the following expressions?

```
(almostsum sum)
(almostdouble double)
(almostmult mult)
(almostfact fact)
(almostfib fib)
```

Think about `(almostsum sum)`.

`almostsum` takes a function as its argument and returns another function that uses that argument wherever a recursive call to `sum` would occur.

When we pass it `sum` itself, we get a function that behaves exactly like `sum`.

The same reasoning applies to our other examples:

```
(almostsum sum)       = sum
(almostdouble double) = double
(almostmult mult)     = mult
(almostfact fact)     = fact
(almostfib fib)       = fib
```

Here, `=` means that the functions have the same behaviour, not that they are necessarily identical function values.

There's a mathematical name for this relationship: a **fixed point**.

A fixed point of a function $f$ is a value $x$ for which:

$$
f(x) = x
$$

In our examples, `sum` is a fixed point of `almostsum`, `double` is a fixed point of `almostdouble`, and so on, in the sense that applying each `almost` function to its corresponding recursive function gives us a function with the same behaviour.

Now consider how we constructed those fixed points.

We know that:

```
sum = (makerec almostsum)
```

Substituting this into:

```
(almostsum sum) = sum
```

gives us:

```
(almostsum (makerec almostsum)) = (makerec almostsum)
```

The same relationship holds for our other examples:

```
(almostdouble (makerec almostdouble)) = (makerec almostdouble)
(almostmult (makerec almostmult))     = (makerec almostmult)
(almostfact (makerec almostfact))     = (makerec almostfact)
(almostfib (makerec almostfib))       = (makerec almostfib)
```

It looks like `makerec` takes a function and produces a fixed point of that function.

That's why a function like `makerec` is called a **fixed-point finder**, often named `fix`.

Let's rename `makerec` to `fix` and `almostf` to `f`. We can express the relationship more generally:

```
(f (fix f)) = (fix f)
```

Or, in mathematical notation:

$$
f(\operatorname{fix}(f)) = \operatorname{fix}(f)
$$

Here, the equality means that both sides produce functions with the same behaviour when called. It doesn't mean that evaluating the two expressions follows the same steps.

This distinction matters in FUN because function arguments are evaluated eagerly. Our `fix` uses eta expansion to delay self-application, allowing recursive calls to happen only when they're needed.

## From `fix` to the Z-combinator

Let's take another look at the function we've derived:

```
fix =
    fun (f)
        let
            makef = fun (self) (f fun (x) ((self self) x))
        in
        (makef makef)
```

We can simplify its appearance with a few transformations.

First, let's eliminate the `let` binding by replacing both occurrences of `makef` with its definition:

```
fix =
    fun (f)
        (fun (self) (f fun (x) ((self self) x))
         fun (self) (f fun (x) ((self self) x)))
```

This transformation is called **inlining**. Instead of referring to `makef` by name, we've substituted its definition wherever it was used.

Next, let's rename the variables:

- Rename the inner `x` to `y`.
- Rename `self` to `x`.

These are examples of **alpha-renaming**. Since we're only changing the names of bound variables consistently, the meaning of the function remains unchanged.

We get:

```
fix =
    fun (f)
        (fun (x) (f fun (y) ((x x) y))
         fun (x) (f fun (y) ((x x) y)))
```

If you look up fixed-point functions, you'll often encounter expressions written using lambda-calculus notation. Let's rewrite our function in that notation so we can recognize it elsewhere.

The notation is quite simple. Instead of:

```
fun (x) body
```

we write:

```
λx.body
```

The Greek letter `λ` (lambda) introduces a function, the name following it is the parameter, and the expression after the dot is the function body.

Using this notation, our `fix` function becomes:

```
fix = λf.(λx.f (λy.(x x) y))(λx.f (λy.(x x) y))
```

Notice that this expression has no free variables. Every variable is bound by a function parameter.

In lambda calculus, an expression with no free variables is called a **combinator**.

Since our `fix` function finds fixed points and has no free variables, it's a **fixed-point combinator**.

And the particular fixed-point combinator we've derived has a name: the **Z-combinator**, usually written:

```
Z = λf.(λx.f (λy.(x x) y))(λx.f (λy.(x x) y))
```

We've derived the Z-combinator, a fixed-point combinator suitable for call-by-value evaluation.

And there's something familiar hiding inside it:

```
λy.(x x) y
```

That's the eta expansion we introduced back in Step 2 to delay self-application.

It survived every transformation we made.

That small detail is also the key to understanding how Z relates to the more familiar Y-combinator.

## From the Z-combinator to the Y-combinator

What happens if we reverse that eta expansion, replacing:

```
λy.(x x) y
```

with:

```
x x
```

We get:

```
Y = λf.(λx.f (x x))(λx.f (x x))
```

This is the **Y-combinator**, one of the best-known fixed-point combinators in lambda calculus.

The transformation we just performed is called **eta contraction**, the reverse of eta expansion.

But there's an important difference between Y and Z.

Under **normal-order reduction**, we reduce the leftmost, outermost reducible expression first, without requiring function arguments to be evaluated beforehand. This allows Y to work without immediately getting stuck evaluating `(x x)`.

In FUN, however, function arguments are evaluated before the function body. If we tried to use Y, we'd encounter the same problem we faced in Step 1: evaluating `(x x)` would trigger another self-application, and the process would continue indefinitely.

Z avoids that problem by wrapping self-application inside a function:

```
λy.(x x) y
```

This delays the evaluation until the function is called.

So the eta expansion we introduced to rescue our `sum` program turns out to be the very thing that distinguishes Z from Y.
