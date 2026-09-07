---
title: "LET: Adding Local Bindings to a Tiny Interpreter in Elm"
description: Add let expressions to a tiny interpreter in Elm and explore local bindings, scope, variable shadowing, and evaluation order through examples and tests.
pubDatetime: 2026-09-07T12:30:00
tags:
  - interpreters
  - programming languages
  - elm
---

In [VAR](/posts/var), we gave our programs the ability to refer to values by name. But those names came from the interpreter’s initial environment. Programs couldn’t introduce names of their own.

We'll add that ability with `let` expressions:

```txt
let a = 5 in -(a, 3)
```

If you've used `let` in another language, you probably have an idea of what this should do. Before we implement it, though, we need to decide exactly what our `let` means.

## Table of contents

## Syntax does not determine semantics

Our `let` expressions will have this general form:

```txt
let name = expression in body
```

This tells us how the expression is written, but it leaves several questions unanswered:

- Can `expression` refer to the `name` being introduced?
- What happens if the surrounding environment already contains that name?
- Must we evaluate `expression` if `body` never uses its value?
- What value does the complete `let` expression produce?

Those are questions about **semantics**: what the expression means. The syntax alone does not answer them.

Elm also uses `let` and `in`, but we don't have to copy its rules. For example, Elm rejects a local definition that reuses the name of an enclosing definition. Our language will allow this, letting the inner binding **shadow** the outer one. Elm's [explanation of variable shadowing](https://elm-lang.org/0.19.0/shadowing) describes the reasoning behind its choice.

We are free to choose the behaviour of our language. Once we've chosen it, the interpreter needs to implement that choice consistently.

## Choosing a meaning for let

We'll call the expression between `=` and `in` the **bound expression**, and the expression after `in` the **body**. Both can be any expression supported by the language, including another `let`.

In:

```txt
let a = 5 in -(a, 3)
```

the name is `a`, the bound expression is `5`, and the body is `-(a, 3)`.

The two occurrences of `a` have different roles. The first introduces a **binding**, associating a name with a value. The second is a **variable reference**, which retrieves the value associated with that name.

Here's the rule we'll implement:

> To evaluate `let name = expression in body`, first evaluate `expression` in the current environment. If that evaluation fails, the entire `let` expression fails with the same error. Otherwise, extend the environment by binding `name` to the resulting value. Then evaluate `body` in the extended environment. The body's value becomes the value of the complete `let` expression.

Errors from evaluating the body likewise become errors from the complete `let` expression.

Extending an environment produces a new environment. It retains the other bindings and makes a lookup of `name` return the newly bound value. The original environment remains unchanged.

That gives us two environments to keep track of:

|Part|Environment used to evaluate it|
|---|---|
|Bound expression|The current environment|
|Body|The current environment extended with the new binding|

The new binding's **scope**, the region of the program where it applies, is the body. An inner binding for the same name can shadow it within the inner body.

The new binding is unavailable while evaluating its own bound expression. A reference to the same name there uses the surrounding environment, which may already contain a binding for that name.

## Predict the results

Before looking at the implementation, try applying the evaluation rule yourself. What value or runtime error should each program produce? Assume that `missing` has no binding in the initial environment.

**1.**

```txt
let a = 5 in -(a, 3)
```

**2.**

```txt
let a = zero?(0) in if a then 2 else 3
```

**3.**

```txt
let a = 5 in let b = -(a, 2) in -(a, b)
```

**4.**

```txt
let a = 5 in let a = 3 in a
```

**5.**

```txt
let a = 5 in let a = -(a, 1) in a
```

**6.**

```txt
let a = 5 in -(let a = 3 in a, a)
```

**7.**

```txt
let a = missing in 42
```

Write down your predictions and a short explanation for each. For nested expressions, keep track of the environment used to evaluate each bound expression and body.

We'll return to all seven examples as we work through the evaluator.

## Try implementing LET

You now have the syntax, the evaluation rule, and some programs to reason about. If you'd like to try implementing LET yourself, pause here and extend VAR.

Add support for `let name = expression in body`. The new reserved words are `let` and `in`, and the new symbol is `=`. The identifier rules otherwise stay the same.

Work through the grammar, AST, parser, evaluator, and tests. Decide which pieces need to change and which existing pieces you can reuse. Turn your predictions into test cases, then compare the interpreter's results with your reasoning.

When you're ready, continue with the walkthrough below. We'll implement the feature and explain the results of the examples.

## Extending the grammar with let expressions

LET supports everything VAR supports and adds one expression form:

```txt
Expr ::= Const
       | Diff
       | Zero
       | If
       | Var
       | Let
Let  ::= 'let' Id '=' Expr 'in' Expr
```

The `Id` identifies the name being introduced. The first `Expr` is the bound expression, and the second is the body.

Both the bound expression and the body can be any `Expr`, including another `let`. Since `Let` is also an alternative in the `Expr` rule, a `let` expression can appear wherever an expression is allowed.

The new syntax introduces two reserved words, `let` and `in`, and one symbol, `=`. The existing `keyword`, `symbol`, and `id` helpers are sufficient to recognize these parts, so we don't need to change the lexer implementation.

## Representing let expressions in the AST

The AST needs to retain three things: the name, the bound expression, and the body. We add a constructor to `Expr`:

```elm
type Expr
    = -- ...
    | Let Id Expr Expr
```

For example:

```txt
let a = 5 in -(a, 3)
```

is represented as:

```elm
Program
    (Let
        "a"
        (Const 5)
        (Diff (Var "a") (Const 3))
    )
```

The binding name is stored as the identifier `"a"`. The reference to that name in the body is represented by `Var "a"`.

The bound expression is still an `Expr` at this stage. We won't know its value until we evaluate it.

## Parsing a let expression

In `LET.Parser`, we add `letExpr` to the expression parser:

```elm
expr : Parser Expr
expr =
    P.oneOf
        [ constExpr
        , diffExpr
        , zeroExpr
        , ifExpr
        , varExpr
        , letExpr
        ]


varExpr : Parser Expr
varExpr =
    P.map Var id


letExpr : Parser Expr
letExpr =
    P.succeed Let
        |. L.keyword "let"
        |= id
        |. L.symbol "="
        |= P.lazy (\_ -> expr)
        |. L.keyword "in"
        |= P.lazy (\_ -> expr)


id : Parser Id
id =
    L.id keywords


keywords : List String
keywords =
    [ "else"
    , "if"
    , "in"
    , "let"
    , "then"
    ]
```

The parser follows the grammar in order. The `|.` operator discards the results of parsing the keywords and symbol, while `|=` passes the identifier and two expressions to `Let`.

As with our earlier recursive expression parsers, `P.lazy` delays construction of the nested expression parsers. For a refresher on why we need this delay, see [Why Recursive Elm Parsers Need `Parser.lazy`](/posts/why-recursive-elm-parsers-need-parser-lazy/).

We extract `id` because both `varExpr` and `letExpr` now need the same identifier rules.

Adding `let` and `in` to `keywords` prevents them from being used as identifiers. For example, this is a syntax error:

```txt
let in = 5 in 0
```

The parser expects an identifier after `let`, but `in` is now reserved.

The lexer helpers also handle trailing whitespace, so we can spread an expression across several lines:

```txt
let
    answer =
        -(10, 2)
in
zero?(answer)
```

The line breaks and indentation help us read the program without changing how it's parsed.

## Evaluating the bound expression and the body

VAR already gave `runExpr` an environment argument:

```elm
runExpr : Expr -> Env -> Result RuntimeError Value
```

It also gave us `Env.extend` and `Env.lookup`. We can use those existing pieces to implement the evaluation rule.

The new branch in `runExpr` is:

```elm
        Let name bound body ->
            runExpr bound env
                |> Result.andThen
                    (\vBound ->
                        runExpr body (Env.extend name vBound env)
                    )
```

First, `runExpr bound env` evaluates the bound expression in the current environment.

If it fails, `Result.andThen` propagates the error without evaluating the body. If it succeeds, `Result.andThen` passes the resulting value to the function as `vBound`. We extend `env` with the association between `name` and `vBound`, then evaluate `body` in that extended environment.

The result of evaluating the body is returned directly, making the body's value the value of the complete `let` expression.

Let's return to **example 1**:

```txt
let a = 5 in -(a, 3)
```

1. Evaluate `5` in the current environment, producing `VNumber 5`.
2. Extend the environment with a binding from `a` to `VNumber 5`.
3. Evaluate `-(a, 3)` in the extended environment. Looking up `a` produces `VNumber 5`, so the difference produces `VNumber 2`.

The complete `let` expression produces `VNumber 2`.

The environment stores the value produced by the bound expression. For example, when we evaluate:

```txt
let a = -(5, 3) in zero?(a)
```

we evaluate `-(5, 3)` first and bind `a` to `VNumber 2`. Looking up `a` in the body retrieves that value. It does not evaluate the difference again.

In **example 2**, we bind a Boolean value:

```txt
let a = zero?(0) in if a then 2 else 3
```

Here, the bound expression produces `VBool True`. The body uses that Boolean as its condition, selects the then branch, and produces `VNumber 2`.

The `Let` branch needs no type check of its own. It can bind either kind of value already supported by the interpreter.

## Nested let expressions and scope

An extended environment retains the other bindings from the surrounding environment. That lets an inner `let` use a name introduced by an outer one, as in **example 3**:

```txt
let a = 5 in let b = -(a, 2) in -(a, b)
```

The outer `let` evaluates its body with `a` bound to `VNumber 5`.

That body is another `let`. Its bound expression, `-(a, 2)`, uses the environment it receives, so it can look up `a`. The difference produces `VNumber 3`.

The inner `let` then extends that environment with `b` bound to `VNumber 3`. Its body, `-(a, b)`, can use both bindings and produces `VNumber 2`.

This works because VAR already passes the environment through recursive evaluation. A variable can use an enclosing binding even when it appears inside a difference, a conditional, or another `let`.

## Variable shadowing

**Example 4** asks what happens when the inner `let` uses a name that is already bound:

```txt
let a = 5 in let a = 3 in a
```

The outer `let` supplies an environment where `a` refers to `VNumber 5`. The inner `let` extends it with a new binding for `a`, so looking up `a` in the inner body produces `VNumber 3`.

The inner binding **shadows** the outer binding within the inner body.

Our existing `Env.extend` operation already supports this. It produces an environment in which a lookup of that name returns the newly supplied value.

### The bound expression uses the surrounding environment

**Example 5** changes the inner bound expression:

```txt
let a = 5 in let a = -(a, 1) in a
```

Which binding does the `a` in `-(a, 1)` refer to?

We evaluate the inner bound expression before extending the environment with the inner binding. At that point, `a` still refers to `VNumber 5`, so `-(a, 1)` produces `VNumber 4`.

Only then do we create the extended environment where `a` refers to `VNumber 4`. The inner body evaluates to that value, and so does the complete program.

The new binding is unavailable in its own bound expression. If that expression refers to the same name, it needs a binding from the surrounding environment.

### The outer binding remains unchanged

**Example 6** checks whether shadowing changes the binding in the original environment:

```txt
let a = 5 in -(let a = 3 in a, a)
```

The outer body is a difference expression. Its first operand is `let a = 3 in a`, and its second operand is `a`.

When evaluating the difference, `runExpr` passes the same environment to both operands. In that environment, `a` refers to `VNumber 5`.

|Evaluation|What happens|Value|
|---|---|---|
|First operand: `let a = 3 in a`|The inner `let` evaluates its body in an extended environment where `a` refers to `VNumber 3`.|`VNumber 3`|
|Second operand: `a`|Lookup uses the difference's environment, where `a` still refers to `VNumber 5`.|`VNumber 5`|
|Complete difference|Subtract `5` from `3`.|`VNumber -2`|

We don't need to restore `a` to `5` after evaluating the first operand because the original environment never changed.

`Env.extend` creates a new environment using an immutable dictionary. The inner `let` uses that extended environment to evaluate its body, then returns the body's value. The evaluator still has the original environment to use for the second operand.

This is how the evaluator keeps the binding local to the inner body.

## Evaluation order and errors

Our evaluation rule for `let` also determines how errors propagate.

If the bound expression fails, `Result.andThen` returns that error without evaluating the body. If the bound expression succeeds but the body fails, the body's error becomes the result of the whole expression.

For example:

```txt
let a = zero?(0) in -(a, 1)
```

Binding `a` to `VBool True` succeeds. Evaluating the body then fails because the difference expects two numbers and receives a Boolean and a number.

We can also use errors to check which part is evaluated first:

```txt
let a = zero?(zero?(0)) in missing
```

The bound expression fails because the outer `zero?` receives a Boolean. The interpreter returns that type error without trying to look up `missing` in the body.

**Example 7** asks what happens when the body never uses the binding:

```txt
let a = missing in 42
```

With no binding for `missing` in the current environment, this program fails with an identifier-not-found error. The body does not use `a`, but our rule still requires the bound expression to be evaluated first.

In [IF](/posts/if), we chose to evaluate only the selected branch. For LET, we choose to evaluate the bound expression before the body.

Here are the results of all seven examples together:

|Example|Result|Reason|
|---|---|---|
|1|`VNumber 2`|The body subtracts `3` from the value bound to `a`, which is `5`.|
|2|`VNumber 2`|The bound Boolean selects the then branch.|
|3|`VNumber 2`|The inner bound expression can use `a`; the inner body can use both `a` and `b`.|
|4|`VNumber 3`|The inner binding shadows the outer binding.|
|5|`VNumber 4`|The inner bound expression uses the outer value of `a`.|
|6|`VNumber -2`|The inner body uses `a = 3`; the second operand still uses `a = 5`.|
|7|`IdentifierNotFound "missing"`|The bound expression must be evaluated even though the body does not use `a`.|

If one of your predictions differed, revisit the evaluation rule and trace that example again. Check both the order of evaluation and the environment used for each expression.

## Testing local bindings and scope

We can turn the examples into test cases using the existing `testRun` helper. For example:

```elm
[ ( "let a = 5 in -(let a = 3 in a, a)"
  , SucceedsWith (VNumber -2)
  )
, ( "let a = missing in 42"
  , RuntimeError <| I.IdentifierNotFound "missing"
  )
]
```

Add cases for the remaining examples, including the type error that verifies the bound expression is evaluated before the body.

For the parser, test the expected ASTs, nested expressions, and whitespace handling. Also check that invalid forms such as `let in = 5 in 0` and `let a = 5 in` are rejected.

You can find the [complete source code for LET, including the tests, on GitHub](https://github.com/tinyinterpreters/let).

## Where we go next

Our programs can now introduce local bindings and use them to name intermediate results.

Next, in PROC, we'll add functions. That gives us several language-design questions to consider:

- Should we allow variables to be bound to functions?
- Should we allow functions to be passed as arguments to other functions?
- Should we allow functions to be returned from other functions?
- When a function's body refers to a name defined outside the function, where should we look up its value?
