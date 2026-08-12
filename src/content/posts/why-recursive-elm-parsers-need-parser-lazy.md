---
title: "Why Recursive Elm Parsers Need Parser.lazy"
description: Learn why recursive Elm parsers create cyclic definitions, how Parser.lazy breaks the cycle, and when recursive parsers do and don't need it.
pubDatetime: 2026-08-12T12:50:00
tags:
  - parser combinators
  - elm
  - recursion
---

In [DIFF](/posts/diff), we extended our language with difference expressions:

```txt
-(expression, expression)
```

Each operand is another expression, so difference expressions can be nested:

```txt
-(2, -(4, 3))
```

The grammar describes that recursive structure directly:

```txt
Expr ::= Const
       | Diff

Diff ::= '-' '(' Expr ',' Expr ')'
```

A natural translation into parser combinators looks like this:

```elm
expr : Parser Expr
expr =
    P.oneOf
        [ constExpr
        , diffExpr
        ]


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

The code appears to say exactly what the grammar says: a difference expression contains two expressions.

Elm rejects it, however, because `expr` and `diffExpr` form a cyclic dependency between parser values. In DIFF, we fixed the problem by replacing each direct reference to `expr`:

```elm
|= expr
```

with:

```elm
|= P.lazy (\_ -> expr)
```

The corrected parser works, but the small change raises several questions.

1. Why does referring directly to `expr` create a cycle?
2. Why does placing the same reference inside a lambda break that cycle?
3. What does `P.lazy` actually delay?
4. When should we use it?

To answer those questions, we need to understand what `expr` actually is.

## Table of contents

## A parser value is not a parse in progress

Consider the type of `expr`:

```elm
expr : Parser Expr
```

`expr` is a value of type `Parser Expr`. It describes how to parse source text and produce an `Expr`.

Defining `expr` doesn't itself parse a program. It constructs a parser value that can later be run on some source text.

We can see the difference by comparing `expr` with `P.run`:

```elm
P.run : Parser a -> String -> Result (List P.DeadEnd) a
```

`P.run` receives a parser and the source text to parse:

```elm
P.run expr "-(2, 1)"
```

Here, `expr` describes how to recognize an expression, while `"-(2, 1)"` is the source text being parsed.

Combinators such as `P.oneOf`, `P.succeed`, `|.`, and `|=` let us define larger parser values in terms of smaller ones. In our case, `expr` is defined in terms of `constExpr` and `diffExpr`.

No input is being consumed while these parser values are being constructed. Elm finds the problem before we ever try to run the parser on some source text.

The cycle is not caused by recursively parsing a nested DIFF program.

It's a cycle among the parser values themselves.

## Following the dependency cycle

Let’s follow the definitions.

`expr` includes `diffExpr` as one of its alternatives, so `expr` depends on `diffExpr`.

But `diffExpr` uses `expr` to parse both operands, so `diffExpr` also depends on `expr`.

That gives us the dependency cycle:

```txt
expr → diffExpr → expr
```

Neither parser value can be constructed without the other one already being available.

The recursive grammar itself is not the problem. A difference expression really does contain two expressions, and those expressions may be difference expressions too.

The problem is how we translated that recursion into Elm:

> The parser values depend on each other immediately.

We need to keep the recursive relationship while preventing Elm from following it as soon as the parser values are constructed.

## Put the recursive reference behind a function

Compare these two expressions:

```elm
expr
```

```elm
\_ -> expr
```

The first uses the `expr` parser directly, so Elm needs that parser immediately.

The second defines a function that returns the `expr` parser.

Elm is a strict, call-by-value language, but a function is already a value. Constructing the function doesn't evaluate its body, so Elm doesn't need to obtain the `expr` parser yet. The parser is only obtained when the function is called.

In programming-language terminology, this function is a **thunk**: a function used to delay a computation.

The thunk lets us keep the recursive reference without requiring Elm to obtain `expr` while the parser values are being constructed.

Putting `expr` behind a function also changes its type.

`expr` has this type:

```elm
Parser Expr
```

The thunk has this type:

```elm
() -> Parser Expr
```

It's a function that accepts `()` and returns the `expr` parser.

We cannot pass that function directly to `|=`. The right-hand side of `|=` must be a parser. Here, because we're parsing an operand expression, it must be a `Parser Expr`, but our thunk has type `() -> Parser Expr`.

We need something that accepts the thunk and gives us a parser value again.

That's what [`P.lazy`](https://package.elm-lang.org/packages/elm/parser/latest/Parser#lazy) does:

```elm
P.lazy : (() -> Parser a) -> Parser a
```

Its argument matches the type of our thunk, so:

```elm
P.lazy (\_ -> expr)
```

gives us the `Parser Expr` required by `|=`.

Now let’s see when `P.lazy` calls the thunk.

## When does `P.lazy` call the thunk?

Consider this program:

```txt
-(2, -(4, 3))
```

When we run `expr` on this program, it selects `diffExpr`, which first recognizes the beginning of the outer difference expression:

```txt
-(
```

When parsing reaches the first operand, `P.lazy` calls the thunk:

```elm
\_ -> expr
```

and obtains the `expr` parser needed at that position.

The first operand is:

```txt
2
```

so `expr` selects `constExpr`.

Parsing then continues to the second operand:

```txt
-(4, 3)
```

Again, `P.lazy` calls the thunk and obtains `expr`. This time, `expr` selects `diffExpr`, whose operands eventually require `expr` again.

The recursion ends when `expr` selects `constExpr` for `2`, `4`, and `3`. Because `constExpr` does not depend on `expr`, it provides the base case.

The important distinction is that Elm no longer needs to obtain `expr` while the parser values are being constructed. It obtains `expr` later, when parsing reaches a position where another expression is required, turning what was an immediate dependency between parser values into a recursive dependency followed while parsing the input.

## When should you use `P.lazy` in a recursive parser?

`P.lazy` is useful when a recursive parser reference would otherwise create an immediate dependency cycle among parser values.

In DIFF, putting the recursive uses of `expr` behind functions breaks the immediate dependency cycle.

Not every recursive parser needs `P.lazy`, though. If the recursive use of the parser is already behind a function, the immediate dependency has already been broken.

For example, [`P.andThen`](https://package.elm-lang.org/packages/elm/parser/latest/Parser#andThen) takes a function:

```elm
P.andThen : (a -> Parser b) -> Parser a -> Parser b
```

If the recursive parser is referred to inside that function, Elm doesn't need to obtain it until the function is called. In that situation, `P.andThen` already places the recursive reference behind a function, so `P.lazy` isn't needed to break the immediate dependency cycle.

What matters, then, is not simply whether a parser is recursive. The important question is whether constructing the parser creates an immediate dependency cycle.

If it does, put the recursive use behind a function so Elm doesn't need that parser while constructing the surrounding parser value. Use `P.lazy` when the surrounding parser combinator requires a `Parser a`, but the recursive parser is behind a `() -> Parser a` thunk.

You don't have to spot every cycle before compiling the code. If you forget `P.lazy` where it is needed, the Elm compiler will detect the cyclic definition and show you the chain of parser values involved.

Once you understand why recursive parser values can create this cycle, that error becomes much more useful. Instead of seeing a mysterious infinite-loop warning, you can look for the recursive parser use that is creating the immediate dependency.

## The key idea

Recursive parsers are not the problem. The problem is an immediate dependency cycle among parser values; putting the recursive reference behind a function breaks that cycle, and `P.lazy` lets us use that thunk where a parser value is required.
