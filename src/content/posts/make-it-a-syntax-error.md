---
title: "Make it a Syntax Error"
description: See how grammar and AST design in a tiny Elm interpreter can turn runtime type errors into syntax errors, simplify evaluation, and connect to GADTs.
pubDatetime: 2026-08-20T12:00:00
tags:
  - interpreters
  - programming languages
  - elm
---

In [ZERO: Adding Booleans and Runtime Type Errors to a Tiny Interpreter in Elm](/posts/zero), we looked at this program:

```txt
zero?(zero?(0))
```

and I wrote:

> Whether the value produced by that expression is suitable for the outer `zero?` is a question for the evaluator, not the parser.

That's true for the grammar we chose for ZERO, but it isn't the only way we could have designed the language.

A different grammar can make `zero?(zero?(0))` syntactically invalid. If we carry the same distinction into the AST, we can go even further: the AST can make expressions like this impossible to represent.

That raises an interesting language-design question:

> How much should the grammar know about the kinds of values expressions produce?

Let's try the alternative and see what changes.

## Table of contents

## Why `zero?(zero?(0))` is valid syntax in ZERO

ZERO’s grammar treats constants, differences, and `zero?` expressions as three alternatives of the same syntactic category:

```txt
Expr ::= Const
       | Diff
       | Zero

Diff ::= '-' '(' Expr ',' Expr ')'
Zero ::= 'zero?' '(' Expr ')'
```

The operand of `zero?` is an `Expr`, so this is valid syntax:

```txt
zero?(zero?(0))
```

The inner:

```txt
zero?(0)
```

is itself an `Expr`, which means it can appear in the `Expr` position required by the outer `zero?`.

With this grammar, the parser only establishes that the operand is an expression. Evaluation later discovers that the inner expression produces a Boolean where the outer `zero?` expects a number.

That’s why the published ZERO interpreter reports a runtime type error.

But `Expr` is our design choice. We could make the operand category more specific.

## Separate numeric and Boolean expressions in the grammar

Suppose we introduce two syntactic categories:

```txt
NExpr
BExpr
```

`NExpr` is the syntactic category for expressions that produce numbers, while `BExpr` is the syntactic category for expressions that produce Booleans.

ZERO’s grammar can then become:

```txt
Program ::= Expr
Expr    ::= NExpr
          | BExpr
NExpr   ::= Const
          | Diff
Const   ::= Number
Diff    ::= '-' '(' NExpr ',' NExpr ')'
BExpr   ::= Zero
Zero    ::= 'zero?' '(' NExpr ')'
Number  ::= [0-9]+
```

The important changes are the definitions of `Diff` and `Zero`.

Difference no longer accepts arbitrary expressions:

```txt
Diff ::= '-' '(' NExpr ',' NExpr ')'
```

Both operands must be numeric expressions.

Similarly, `zero?` no longer accepts an arbitrary expression:

```txt
Zero ::= 'zero?' '(' NExpr ')'
```

Its operand must be a numeric expression too.

Now let’s reconsider:

```txt
zero?(zero?(0))
```

The inner `zero?(0)` belongs to `BExpr` because `zero?` produces a Boolean.

But the operand of the outer `zero?` must be an `NExpr`.

The categories no longer match, so the complete program cannot be parsed.

The same thing happens with:

```txt
-(zero?(0), 1)
```

`zero?(0)` belongs to `BExpr`, but a difference expression requires two `NExpr`s.

On the experimental [`make-it-a-syntax-error`](https://github.com/tinyinterpreters/zero/tree/make-it-a-syntax-error) branch, these changes turn the runtime type errors from ZERO into syntax errors.

The parser can now reject more programs because the grammar distinguishes expressions according to the kinds of values they produce.

## Encode the same distinction in the AST

We can carry the same distinction into the AST:

```elm
type Expr
    = NExpr NExpr
    | BExpr BExpr


type NExpr
    = Const Number
    | Diff NExpr NExpr


type BExpr
    = Zero NExpr
```

The constraints from the grammar now appear in the types that represent our expressions.

A `Diff` can contain only two `NExpr`s and is itself an `NExpr`. A `Zero` can contain only an `NExpr` and is itself a `BExpr`.

That means we cannot construct an AST corresponding to:

```txt
zero?(zero?(0))
```

The inner `Zero` produces a `BExpr`, while the outer `Zero` requires an `NExpr`.

The types do not fit together.

The invalid combination is no longer something the evaluator needs to detect later. It cannot be represented by this AST in the first place.

This is an example of using the data model to [make impossible states impossible](https://www.youtube.com/watch?v=IcgmSRJHu_8).

## The evaluator becomes surprisingly small

This change has a large effect on evaluation.

In the published ZERO interpreter, evaluating an expression returns:

```elm
Result RuntimeError Value
```

`Diff` has to check that both of its operands produced numbers. `zero?` has to check that its operand produced a number. If either check fails, evaluation returns a runtime type error.

With the new AST, those checks are no longer necessary.

The evaluator can return a `Value` directly, while the more specific evaluators return the corresponding Elm values:

```elm
runExpr : Expr -> Value
runExpr expr =
    case expr of
        NExpr n ->
            VNumber <| runNExpr n

        BExpr b ->
            VBool <| runBExpr b


runNExpr : NExpr -> Number
runNExpr expr =
    case expr of
        Const n ->
            n

        Diff a b ->
            runNExpr a - runNExpr b


runBExpr : BExpr -> Bool
runBExpr expr =
    case expr of
        Zero a ->
            runNExpr a == 0
```

When evaluating a `Diff`, Elm already knows that both operands are `NExpr`s, so recursively evaluating them produces numbers. Likewise, the operand of `Zero` is already known to be an `NExpr`.

The AST has established the conditions that the published ZERO evaluator previously had to check at runtime.

For this version of ZERO, those operand mismatches can no longer reach evaluation, so the evaluator no longer needs runtime type errors for them.

## We changed more than the implementation

There’s an important difference between the two designs.

In the published ZERO language, `zero?(zero?(0))` is a syntactically valid program. Parsing succeeds, but evaluation eventually discovers that the inner `zero?` produces a Boolean where the outer `zero?` expects a number. The interpreter reports a runtime type error.

In the experimental language, the same source text is not a syntactically valid program at all. The grammar prevents it from reaching evaluation.

So we haven’t merely changed when the interpreter discovers the problem. We have changed how the language classifies it:

```txt
published ZERO
valid syntax → runtime type error

experimental ZERO
invalid syntax → syntax error
```

We haven’t merely found a cleverer implementation of the same language. We have changed what counts as a valid program.

That’s a language-design decision.

The experimental design gives us stronger guarantees and a simpler evaluator, so the obvious question is:

> Why didn’t I build ZERO this way?

## Why parsing and type checking are often separate

This approach works especially well in ZERO because the kind of value produced by each expression follows directly from its syntactic form.

A constant produces a number:

```txt
123
```

A difference expression produces a number:

```txt
-(3, 1)
```

And `zero?` produces a Boolean:

```txt
zero?(0)
```

That makes it easy to divide the grammar into `NExpr` and `BExpr`.

As the language grows, however, the kind of value an expression produces may depend on information that isn't present in its syntax alone.

Suppose we later add variables:

```txt
x
```

Should `x` be an `NExpr` or a `BExpr`?

We can't tell just by looking at `x`. We need to know what is associated with that name.

Conditional expressions would make the distinction even less convenient. Suppose we later add expressions like:

```txt
if zero?(0) then 2 else zero?(3)
```

The then branch produces a number, while the else branch produces a Boolean. If our language allows that, which syntactic category should the complete conditional belong to?

These are the kinds of problems that motivate separating different questions about a program.

A parser can ask:

> Does this source text have the syntactic structure of a valid expression?

A statically typed language can then have a type checker ask:

> Are the expressions being used with compatible types?

A dynamically typed language can instead defer that question until evaluation:

> Can this operation use this kind of value?

That gives us at least three possible designs for the problem we encountered in ZERO:

```txt
experimental ZERO
parse → syntax error

statically typed alternative
parse → type check → type error

published ZERO
parse → evaluate → runtime type error
```

The grammar-based approach isn't wrong. For ZERO, it's remarkably elegant.

But as type information begins to depend on variables, branches, functions, and other surrounding context, separating these questions often gives the language implementation a cleaner structure.

## How GADTs encode the expression type

There’s another way to express the same idea as our experimental AST.

In Elm, we created separate types for numeric and Boolean expressions:

```elm
NExpr
BExpr
```

A language with generalized algebraic data types, or GADTs, can encode the distinction in the type of the expression itself.

In Haskell, a ZERO-like AST could look like this:

```haskell
data Expr a where
    Const :: Int -> Expr Int
    Diff  :: Expr Int -> Expr Int -> Expr Int
    Zero  :: Expr Int -> Expr Bool
```

The type parameter records the type of value the expression produces. `Const` and `Diff` produce `Expr Int`, while `Zero` takes an `Expr Int` and produces an `Expr Bool`.

So this is well typed:

```haskell
Zero (Const 0)
```

It has type `Expr Bool`.

But the equivalent of:

```txt
zero?(zero?(0))
```

does not type-check:

```haskell
Zero (Zero (Const 0))
```

The inner `Zero` produces an `Expr Bool`, while the outer `Zero` requires an `Expr Int`. The types don't fit together.

This also lets the expression evaluator have a particularly strong type:

```haskell
runExpr :: Expr a -> a
```

An `Expr Int` evaluates to an `Int`, while an `Expr Bool` evaluates to a `Bool`. The result type is encoded directly in the type of the AST.

That’s essentially the same guarantee we obtained in Elm by separating `NExpr` and `BExpr`, but GADTs let us express both categories through one parameterized `Expr` type.

GADTs solve the AST representation problem here; they do not make the parsing problem disappear.

## Which design is better?

Neither design is universally better.

The experimental version rejects these operand mismatches during parsing and makes them impossible to represent in the AST. That gives the evaluator stronger guarantees and removes the corresponding runtime checks.

But the simplicity has moved somewhere else.

The grammar now distinguishes expressions according to the kinds of values they produce, and the AST preserves that distinction with separate `NExpr` and `BExpr` types. That works neatly for ZERO because the result of each expression form is obvious from its syntax.

As we saw earlier, that becomes harder to maintain once result types depend on surrounding information.

There is also a teaching tradeoff.

One of the main ideas in ZERO is that once an `Expr` can produce more than one kind of `Value`, an operation may receive a value it cannot use:

```txt
zero?(zero?(0))
```

The published interpreter lets us follow that program through parsing and into evaluation, where the mismatch becomes a runtime type error.

The experimental design prevents us from reaching that point. It gives us stronger guarantees, but it removes the very runtime behavior ZERO was intended to introduce.

That’s why I kept the broader grammar in the published version.

The experiment still reveals something important about the original claim:

> Whether `zero?(zero?(0))` becomes a syntax error, a static type error, or a runtime type error depends on how we choose to design the language and its implementation.

The evaluator was responsible for the error in ZERO because that was the boundary we chose—not because the parser could never have prevented it.
