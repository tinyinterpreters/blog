---
title: "Recursion without Recursive Bindings"
description: Learn how to express recursion in FUN even though it lacks recursive bindings.
pubDatetime: 2026-10-12T06:20:00
tags:
  - recursion
  - self-application
  - elm
---

I ended the previous post with a [challenge](/posts/fun-currying-free-variables/#a-challenge-for-next-time). Were you able to figure it out?

If we evaluate it in the `elm repl` we get an `IdentifierNotFound` error:

```elm
> import FUN.Interpreter as I
> I.run """
    let
        sum =
            fun (n)
                if zero?(n) then
                    0
                else
                    -(n, -(0, (sum -(n, 1))))
    in
    (sum 5)
    """
Err (RuntimeError (IdentifierNotFound "sum"))
```

Why?

The value of `sum` is:

```elm
VFun
  (Closure
    "n"
    (If
      (Zero (Var "n"))
      (Const 0)
      (Diff
        (Var "n")
        (Diff
          (Const 0)
          (Call
            (Var "sum")
            (Diff (Var "n") (Const 1))
          )
        )
      )
    )
    (Env
      (Dict.fromList
        [ ( "i", VNumber 1 )
        , ( "v", VNumber 5 )
        , ( "x", VNumber 10)
        ]
      )
    )
  )
```

It's a closure that captures the initial environment. Notice that `sum` is not in the saved environment. So when we apply `sum` to `5`, the body of the function is evaluated in the saved environment that doesn't contain a binding for `sum`. Hence, the error.

Is there some other approach that works? Can we really implement `sum` with only the language features that exist in FUN? Surprisingly, the answer is a resounding YES! The rest of this post attempts to explain how it's possible.

## From `sum` to `makesum`

The variable reference to `sum` that appears in `-(n, -(0, (sum -(n, 1))))` is free or unbound in the function for `sum`:

```
fun (n)
    if zero?(n) then
        0
    else
        -(n, -(0, (sum -(n, 1))))
```

Let's fix that by wrapping the above function in another function that has `sum` as a parameter. We'll call the new function `makesum` because when it's given a value for `sum` it returns a function that looks exactly like the original summation function we started off with.

```
let
  makesum =
    fun (sum)
      fun (n)
          if zero?(n) then
              0
          else
              -(n, -(0, (sum -(n, 1))))
in
((makesum ???) 5)
```

Huh, so to implement the summation function we have to somehow pass in the summation function. It feels like we've taken a huge step backwards and then forwards and then backwards and then .... I mean, where do we even begin with something like that?

To explore `makesum` I got the idea to just replace `???` with any function for now just to see what happens. After playing around with many different functions I found a few that illustrated what was going on quite nicely. I'd pick one of them and show you what I mean.

## Start with an obviously incorrect summation function

```
let
  makesum =
    fun (sum)
      fun (n)
          if zero?(n) then
              0
          else
              -(n, -(0, (sum -(n, 1))))
in
let
  badsum = fun (n) 10000
in
((makesum badsum) 5)
```

That returns `VNumber 10005`. Now try the following:

1. `((makesum (makesum badsum)) 5)`
2. `((makesum (makesum (makesum badsum))) 5)`
3. `((makesum (makesum (makesum (makesum badsum)))) 5)`
4. `((makesum (makesum (makesum (makesum (makesum badsum))))) 5)`
5. `((makesum (makesum (makesum (makesum (makesum (makesum badsum)))))) 5)`
6. `((makesum (makesum (makesum (makesum (makesum (makesum (makesum badsum))))))) 5)`
7. `((makesum (makesum (makesum (makesum (makesum (makesum (makesum (makesum badsum)))))))) 5)`

In each case we get better and better approximations to the sum of the first 5 positive integers until we only get the correct answer from a certain point onward:

1. `VNumber 10009`
2. `VNumber 10012`
3. `VNumber 10014`
4. `VNumber 10015`
5. `VNumber 15`
6. `VNumber 15`
7. `VNumber 15`

That's progress.

## Time to think

### Thought 1

For `n = 5` we needed at least `6` uses of `makesum` to get to the correct answer. What's the minimum number of uses of `makesum` we need when `n = 10`, `n = 100`, and in general?

In general, the minimum seems to be `n+1`.

That means we won't be able to predict ahead of time the number of `makesum` calls to use that would work for every `n`.

Somehow we have to arrange for `makesum` to be called at least `n+1` times.

### Thought 2

When you trace the 5th, 6th, and 7th examples you realize that it doesn't even matter what `x` is in the following:

```
((makesum (makesum (makesum (makesum (makesum (makesum x)))))) 5)
```

Why?

The base case is reached before it has a chance to use `x`. This suggests that `x` could be anything once we've made the minimum number of `makesum` calls.

### Thought 3

Since `x` can be anything why not let it be `makesum`?

```
((makesum (makesum (makesum (makesum (makesum (makesum makesum)))))) 5)
```

Passing `makesum` to itself means we could start to control how many times we call `makesum`. If we call `makesum` everytime `n` is decremented then `makesum` would be called `n` times. Counting the initial call of `makesum` gives us an additional call. This carries the total number of times we call `makesum` to `n+1`. Just what we need.

Let's try that.

## Self-application

```
let
  makesum =
    fun (self)
      fun (n)
          if zero?(n) then
              0
          else
              -(n, -(0, ((self self) -(n, 1))))
in
((makesum makesum) 5)
```

It works! We get `VNumber 15`. That's so amazing. Try it with other non-negative integers to see that it also works in all those cases.

If you trace `((makesum makesum) 5)` it appears as though `(makesum makesum)` is propelling itself throughout the computation until the base case is reached.

```
((makesum makesum) 5)

; n = 5, self = makesum
= -(5, -(0, ((makesum makesum) 4)))

; n = 4, self = makesum
= -(5, -(0, -(4, -(0, ((makesum makesum) 3)))))

; n = 3, self = makesum
= -(5, -(0, -(4, -(0, -(3, -(0, ((makesum makesum) 2)))))))

; n = 2, self = makesum
= -(5, -(0, -(4, -(0, -(3, -(0, -(2, -(0, ((makesum makesum) 1)))))))))

; n = 1, self = makesum
= -(5, -(0, -(4, -(0, -(3, -(0, -(2, -(0, -(1, -(0, ((makesum makesum) 0)))))))))))

; n = 0, self = makesum
= -(5, -(0, -(4, -(0, -(3, -(0, -(2, -(0, -(1, -(0, 0))))))))))
= 15
```

It appears then that `(makesum makesum)` is `sum`.

We were able to express recursion without having the language provide a recursive binding form.

## More examples

Does this work for other recursive functions?

Let's try out our new found technique on the following:

- `(double n)` returns twice `n`
- `((mult a) b)` returns the product of `a` and `b`
- `(fact n)` returns the [factorial](https://en.wikipedia.org/wiki/Factorial) of `n`
- `(fib n)` returns the `n`-th [Fibonacci](https://en.wikipedia.org/wiki/Fibonacci_sequence) number

In each case I'd show you the recursive version in Elm and then I'd show you the version that uses self-application in FUN. To guage your understanding you can try writing out the functions for yourself before looking at my solutions below.

### `double`

#### The recursive version in Elm

```elm
double : Int -> Int
double n =
  if n == 0 then
    0

  else
    2 + double (n - 1)
```

#### The self-application version in FUN

```
let
  makedouble =
    fun (self)
      fun (n)
        if zero?(n) then
          0
        else
          -(2, -(0, ((self self) -(n, 1))))
in
let
  double = (makedouble makedouble)
in
(double 100)
```

### `mult`

#### The recursive version in Elm

```elm
mult : Int -> Int -> Int
mult a b =
  if b == 0 then
    0

  else
    a + mult a (b - 1)
```

#### The self-application version in FUN

```
let
  makemult =
    fun (self)
      fun (a)
        fun (b)
          if zero?(b) then
            0
          else
            -(a, -(0, (((self self) a) -(b, 1))))
in
let
  mult = (makemult makemult)
in
((mult 3) 7)
```

### `fact`

#### The recursive version in Elm

```elm
fact : Int -> Int
fact n =
  if n == 0 then
    1

  else
    n * fact (n - 1)
```

#### The self-application version in FUN

```
let
  makemult =
    fun (self)
      fun (a)
        fun (b)
          if zero?(b) then
            0
          else
            -(a, -(0, (((self self) a) -(b, 1))))
in
let
  mult = (makemult makemult)
in
let
  makefact =
    fun (self)
      fun (n)
        if zero?(n) then
          1
        else
          ((mult n) ((self self) -(n, 1)))
in
let
  fact = (makefact makefact)
in
(fact 5)
```

### `fib`

#### The recursive version in Elm

```elm
fib : Int -> Int
fib n =
  if n == 0 then
    0

  else if n == 1 then
    1

  else
    fib (n - 1) + fib (n - 2)
```

#### The self-application version in FUN

```
let
  makefib =
    fun (self)
      fun (n)
        if zero?(n) then
          0
        else if zero?(-(n, 1)) then
          1
        else
          -(((self self) -(n, 1)), -(0, ((self self) -(n, 2))))
in
let
  fib = (makefib makefib)
in
(fib 10)
```

**N.B.** You can check out these [tests](https://github.com/tinyinterpreters/fun/blob/b662835059c8230cb8e5a25a5f42c67758cc3530/tests/Test/FUN/Recursion.elm) that confirm the implementations above work as expected.

## Conclusion

The technique appears to work for any recursive function we'd want to write. Also, there's a clear pattern emerging for expressing recursion via self-application.

```
let
  makef =
    fun (self)
      ...some function involving (self self)...
in
let
  f = (makef makef)
in
(... f ...)
```

Think about what properties of FUN allowed us to be able to do this. Which languages do you know that also have these properties? Try expressing recursion like we did here in those languages.

I really want to make sure you understand the technique so please ask me any questions in the comments below about anything that remains unclear for you.

Next time we're going to be extracting, through a series of simple transformations, an interesting function based on this technique.
