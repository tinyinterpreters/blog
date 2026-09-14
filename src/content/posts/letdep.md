---
title: "LETDEP: Dependency-Ordered Binding Semantics for let Expressions"
description: Define LETDEP, resolve forward references with dependency analysis and topological sorting, and explore the lexical-scope edge cases that make it interesting.
pubDatetime: 2026-09-11T09:00:00
tags:
  - interpreters
  - programming languages
  - elm
---

When I started exploring multiple-binding `let` expressions, I planned to stop with two variations: LETPAR and LETSEQ.

LETPAR gave us parallel binding semantics. LETSEQ gave us sequential binding semantics.

But while thinking about LETSEQ, another question came up: what if source order did not have to determine the order in which bindings were evaluated?

Consider:

```txt
let
    a = b
    b = 1
in
a
```

With LETSEQ, evaluating `a = b` fails because `b` has not been bound yet.

But there is nothing inherently ambiguous about this expression. We can see that `a` depends on `b`, so we could evaluate `b` first and then evaluate `a`.

That led to an unplanned third variation: LETDEP.

With LETDEP, source order stops determining binding availability. Dependencies do.

The bindings may refer to one another in either direction, provided those dependencies give us some valid order in which to evaluate them.

So our example can be understood as:

```txt
b = 1
a = b
```

even though that is not the order in which the bindings were written.

This changes `let` in an important way. Instead of treating the bindings as a sequence whose meaning is determined by their position, we can begin treating them as a group of definitions related by their dependencies.

## Table of contents

## The meaning of LETDEP

Let's make the semantics precise.

For:

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

1. The binding names `x1` through `xn` must be distinct.
2. An initializer expression may refer to any other binding in the same group, regardless of whether that binding appears earlier or later in source order.
3. A binding does not bind references to its own name inside its initializer.
4. A binding must be evaluated only after the sibling bindings that its initializer depends on have been evaluated.
5. After a binding is evaluated, its value becomes available to bindings that depend on it.
6. If the dependencies between sibling bindings form a cycle, the `let` expression is rejected with a static error.
7. Once all bindings have been evaluated, evaluate `body` in the resulting environment, where all of the bindings are available.

Rule 3 means that in:

```txt
let
    x = x
in
x
```

the `x` in the initializer refers to an `x` from the incoming environment, if one exists. It does not make the binding recursive.

Taken together, these rules allow a binding to depend on siblings that appear either earlier or later in source order, as long as the dependencies between siblings remain acyclic.

## Dependencies instead of source order

Once forward references are allowed, we can no longer assume that evaluating the bindings from first to last will work.

Instead, we need to determine which bindings depend on which others.

Consider:

```txt
let
    result = if ready then -(a, b) else -(b, a)
    a = if zero?(d) then c else -(c, d)
    ready = zero?(-(g, e))
    b = if zero?(-(f, 1)) then -(e, f) else e
    c = -(g, h)
    d = -(h, h)
    e = g
    f = 1
    h = 2
    g = 10
in
result
```

There are forward references throughout this expression. `result`, for example, depends on three bindings that appear later, and those bindings depend on still others farther down the group.

The source order is not a valid evaluation order here. We first need an order that respects those dependencies.

One valid evaluation order is:

```txt
g
h
f
e
d
c
ready
a
b
result
```

This is not the only valid order. Some bindings are independent of one another, so several different orders can satisfy the same dependencies.

We can represent the relationships between the bindings as a directed graph. Each binding is a vertex, and an edge from one binding to another records that the first must be evaluated before the second.

Finding a valid evaluation order then becomes a standard graph problem: **topological sorting**.

LETDEP does not specify which topological ordering must be chosen. What matters is that every binding is evaluated after the sibling bindings it depends on.

And if no topological ordering exists, then the dependency graph contains a cycle.

## When dependencies cannot be resolved

Consider:

```txt
let
    a = b
    b = c
    c = a
in
a
```

To evaluate `a`, we first need `b`. To evaluate `b`, we first need `c`. And to evaluate `c`, we first need `a`.

There is no valid place to start.

LETPAR avoided this problem because sibling bindings could not depend on one another. LETSEQ avoided it because a binding could depend only on siblings that appeared earlier in source order.

LETDEP allows dependencies in either direction, so cycles become possible. When the dependencies form a cycle, the `let` expression is rejected.

LETDEP also requires binding names to be unique:

```txt
let
    x = 1
    y = 2
    x = 3
in
y
```

is rejected rather than assigning shadowing semantics to the duplicate `x`.

Both problems can be discovered after parsing but before evaluating the program. They are therefore **static errors**:

- cyclic binding dependencies;
- duplicate binding names.

This gives our interpreter a new phase between parsing and evaluation. Before running the program, we first check whether its `let` bindings can be given a valid dependency order.

## Turning LETDEP into LETSEQ

We can implement LETDEP as a static transformation over the AST.

For each `let` expression, we determine how the bindings depend on one another, rejecting the expression if the binding names are not unique or if the dependencies form a cycle.

Otherwise, we topologically sort the bindings and rewrite the `let` expression so that the bindings appear in a valid dependency order.

For the example from earlier, one possible result of that transformation is:

```txt
let
    g = 10
    h = 2
    f = 1
    e = g
    d = -(h, h)
    c = -(g, h)
    ready = zero?(-(g, e))
    a = if zero?(d) then c else -(c, d)
    b = if zero?(-(f, 1)) then -(e, f) else e
    result = if ready then -(a, b) else -(b, a)
in
result
```

Now every binding appears after the sibling bindings it depends on.

We apply the same process recursively to nested expressions, so every `let` in the program is transformed into a valid dependency order before evaluation begins.

Once the bindings have been reordered, the existing LETSEQ evaluator can evaluate them sequentially.

So LETDEP can be understood as a static transformation that turns dependency-ordered bindings into an order that LETSEQ already knows how to evaluate.

## Lexical scope makes this interesting

The subtle part is determining which sibling bindings an initializer actually depends on.

It is not enough to collect every variable name that appears in the initializer. A name may be bound by a nested `let`, in which case it is not a dependency on the surrounding binding group.

What matters are the initializer's **free variables** and which of those names refer to sibling bindings.

For example:

```txt
let
    x = let y = 1 in y
    y = 2
in
x
```

The `y` inside the initializer for `x` is bound by the nested `let`, so `x` does not depend on the outer `y`.

Self-references need similar care.

Consider:

```txt
let
    x = x
in
x
```

The binding for `x` does not bind the `x` in its own initializer. That reference is free and refers to an `x` from an enclosing environment, if one exists.

This gets more interesting when the self-reference appears inside a nested `let`:

```txt
let
    z =
        let
            a = a
        in
        a
    a = 1
in
z
```

The inner binding for `a` does not bind the `a` in its own initializer, so that reference reaches outward to the outer sibling `a`. As a result, `z` depends on `a`.

These cases are why the dependency graph has to be built from the lexical meaning of the program, not merely from the names that happen to appear in the source.

## Try building LETDEP yourself

If you want to get the most out of this variation, I recommend trying to implement LETDEP before looking at my solution.

You already know the semantics. The main challenge is figuring out how to turn those semantics into a static transformation that produces an order LETSEQ can evaluate.

You can use the tests in the [`letdep` branch](https://github.com/tinyinterpreters/let/tree/letdep) to check your work as you go.

If you get stuck, or just want to compare approaches, these are the parts of my solution worth looking at:

### Functions

- [`DirectedGraph.tsort`](https://github.com/tinyinterpreters/let/blob/a5647522d51d65f8d89ab1993b5456a82a0b5d6b/src/DirectedGraph.elm#L59-L123) — performs the topological sort and detects cyclic dependency graphs.
- [`LET.AST.freeVariables`](https://github.com/tinyinterpreters/let/blob/a5647522d51d65f8d89ab1993b5456a82a0b5d6b/src/LET/AST.elm#L38-L91) — determines which names are free in an expression while respecting nested `let` scopes and self-references.
- [`LET.Interpreter.resolveDependencies`](https://github.com/tinyinterpreters/let/blob/a5647522d51d65f8d89ab1993b5456a82a0b5d6b/src/LET/Interpreter.elm#L203-L273) — the entry point for transforming a program so its bindings appear in a valid dependency order.
- [`LET.Interpreter.sort`](https://github.com/tinyinterpreters/let/blob/a5647522d51d65f8d89ab1993b5456a82a0b5d6b/src/LET/Interpreter.elm#L276-L340) — determines the dependencies within a binding group and produces a valid ordering or a static error.

### Test modules

- [`Test.DirectedGraph`](https://github.com/tinyinterpreters/let/blob/a5647522d51d65f8d89ab1993b5456a82a0b5d6b/tests/Test/DirectedGraph.elm) — tests topological sorting and cycle detection independently from the interpreter.
- [`Test.LET.AST`](https://github.com/tinyinterpreters/let/blob/a5647522d51d65f8d89ab1993b5456a82a0b5d6b/tests/Test/LET/AST.elm) — tests free-variable analysis, including nested scopes and self-reference edge cases.
- [`Test.LET.Interpreter`](https://github.com/tinyinterpreters/let/blob/a5647522d51d65f8d89ab1993b5456a82a0b5d6b/tests/Test/LET/Interpreter.elm#L215-L329) — tests the LETDEP semantics, including forward references, duplicate bindings, cycles, nested `let` expressions, and self-reference edge cases.

Once you can make all the tests pass, you know your implementation handles the semantics we have defined here.

The edge cases are what make LETDEP especially interesting to solve. Nested scopes, self-references, duplicate bindings, and cycles force you to think carefully about what a dependency really means rather than just topologically sorting a few names.
