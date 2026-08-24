---
title: "IF: Adding Conditional Expressions to a Tiny Interpreter in Elm"
description: Add conditional expressions to a tiny Elm interpreter and see how Boolean conditions introduce control flow by selecting which branch gets evaluated.
pubDatetime: 2026-08-24T06:40:00
tags:
  - interpreters
  - programming languages
  - elm
---

In [ZERO](/posts/zero), we gave our interpreter Boolean values but we couldn't do much with them. Conditional expressions change that by letting us use Boolean values to decide which expression the interpreter evaluates next:

```txt
if zero?(0) then 2 else 3
```

This gives our language its first form of **control flow**: the value of one expression determines which expression the interpreter evaluates next.

Our previous compound expressions didn't have to make that choice. A difference expression evaluates both operands before subtracting their values, and `zero?` evaluates its operand before testing its value. A conditional works differently: it evaluates the condition first, then evaluates only one of its two branches. The other branch is never evaluated.

In this article, we'll add conditional expressions and see how this form of control flow is implemented through selective evaluation.

You can find the [complete source code for IF on GitHub](https://github.com/tinyinterpreters/if).

## Table of contents

## What should a conditional expression mean?

Our conditional expressions will have this general form:

```txt
if condition then consequent else alternative
```

Here, `condition`, `consequent`, and `alternative` name the three parts of the expression. We'll usually refer to the latter two as the **then branch** and the **else branch**.

The concrete syntax tells us how to recognize a conditional expression, but it doesn't completely determine what the expression means. We still have some language-design decisions to make:

- Must the condition evaluate to a Boolean, or can other kinds of values also be used as conditions?
- Do we require the then and else branches to produce the same kind of value?
- After evaluating the condition, should the interpreter evaluate both branches or only the selected branch?

For IF, we'll make the following decisions:

- The condition must evaluate to a Boolean.
- If the condition evaluates to `true`, the then branch is evaluated.
- If the condition evaluates to `false`, the else branch is evaluated.
- If the condition produces any other kind of value, evaluation fails with a type error.
- Only the selected branch is evaluated.
- The two branches do not need to produce the same kind of value.

We can combine these decisions into a precise description of the expression's meaning:

> To evaluate `if condition then consequent else alternative`, first evaluate the condition. If that evaluation fails, the conditional fails with the same error. Otherwise, the condition must produce a Boolean; if it produces any other kind of value, evaluation fails with a type error. If it produces `true`, evaluate the consequent. If it produces `false`, evaluate the alternative instead. The result of the selected branch becomes the result of the conditional expression, while the unselected branch is not evaluated. The two branches do not need to produce the same kind of value.

This specification will guide the implementation. We're deciding what the conditional expression means first, then writing an evaluator that implements that meaning.

## Updating the grammar for conditional expressions

IF supports everything ZERO supports and adds conditional expressions:

```txt
Expr ::= Const
       | Diff
       | Zero
       | If
If   ::= 'if' Expr 'then' Expr 'else' Expr
```

We add `If` as another alternative in the existing `Expr` rule and define its concrete syntax.

The condition and both branches are expressions. This means each may contain any expression supported by the language, including another conditional expression.

The grammar also allows expressions like:

```txt
if 0 then 2 else 3
```

This is syntactically valid because it follows the structure defined by the grammar. However, the grammar does not enforce that the condition evaluates to a Boolean value—it only specifies that an expression can appear in that position. Enforcing the requirement that the condition produces a Boolean is the responsibility of the evaluator.

The new concrete syntax introduces the reserved words `if`, `then`, and `else`, but we don’t need to change the lexer. We can recognize them using the existing `keyword` helper introduced in [ZERO](/posts/zero).

## Representing conditional expressions in the AST

We represent conditionals in the AST by adding an `If` constructor to `Expr`:

```elm
type Expr
    = Const Number
    | Diff Expr Expr
    | Zero Expr
    | If Expr Expr Expr
```

The three arguments correspond, in order, to the condition, the then branch, and the else branch.

For example:

```txt
if zero?(0) then 2 else 3
```

is represented as:

```elm
Program
    (If
        (Zero (Const 0))
        (Const 2)
        (Const 3)
    )
```

The first argument is the condition:

```elm
Zero (Const 0)
```

The second is the then branch:

```elm
Const 2
```

The third is the else branch:

```elm
Const 3
```

The `if`, `then`, and `else` keywords do not need to appear separately in the AST. They help the parser recognize the concrete syntax, but the `If` constructor already captures the structure the interpreter needs.

## Parsing a conditional expression

Let's extend the parser by adding `ifExpr` as another alternative in `expr`:

```elm
expr : Parser Expr
expr =
    P.oneOf
        [ constExpr
        , diffExpr
        , zeroExpr
        , ifExpr
        ]
```

Recall the grammar rule we introduced earlier:

```txt
If ::= 'if' Expr 'then' Expr 'else' Expr
```

Now we want to turn that rule into a parser. Before looking at my implementation, take a moment to try writing the parser for yourself.

Here's my implementation:

```elm
ifExpr : Parser Expr
ifExpr =
    P.succeed If
        |. L.keyword "if"
        |= P.lazy (\_ -> expr)
        |. L.keyword "then"
        |= P.lazy (\_ -> expr)
        |. L.keyword "else"
        |= P.lazy (\_ -> expr)
```

The parser follows the grammar from left to right. It discards the `if`, `then`, and `else` keywords because they are not needed in the AST, and it keeps the three expressions required to construct `If`.

Each reference to `expr` is wrapped in `P.lazy` because `expr` includes `ifExpr`, while `ifExpr` refers back to `expr`. This is the same recursive parser structure we first introduced in [DIFF: Adding Recursive Expressions to a Tiny Interpreter in Elm](/posts/diff), so IF gives us a chance to apply that idea again rather than introducing a new parsing technique.

## Evaluating the condition before choosing a branch

The evaluator is where IF introduces something new.

For a difference expression, both operands are evaluated before `evalDiff` is called. That's why it takes two `Value`s:

```elm
evalDiff : Value -> Value -> Result RuntimeError Value
```

A conditional with the meaning we chose cannot work that way. If we evaluated the condition and both branches before calling its helper, we would evaluate a branch that may never be selected. Instead, `evalIf` has this type:

```elm
evalIf : Value -> Expr -> Expr -> Result RuntimeError Value
```

The condition has already been evaluated into a `Value`, but the then and else branches remain as `Expr` values. This allows the interpreter to inspect the condition before deciding which branch to evaluate.

We add the following case to `runExpr`:

```elm
runExpr : Expr -> Result RuntimeError Value
runExpr expr =
    case expr of
        -- ...

        If condition consequent alternative ->
            runExpr condition
                |> Result.andThen
                    (\vCondition ->
                        evalIf vCondition consequent alternative
                    )
```

`runExpr` evaluates the condition first. If that evaluation fails, `Result.andThen` propagates the error. If it succeeds, `evalIf` receives the resulting value together with the two unevaluated branches:

```elm
evalIf : Value -> Expr -> Expr -> Result RuntimeError Value
evalIf vCondition consequent alternative =
    case vCondition of
        VBool True ->
            runExpr consequent

        VBool False ->
            runExpr alternative

        _ ->
            Err <|
                TypeError
                    { expected = [ TBool ]
                    , actual = [ typeOf vCondition ]
                    }
```

When the condition produces `VBool True`, `evalIf` evaluates the then branch. When it produces `VBool False`, it evaluates the else branch. Any other value produces a type error.

### The condition must produce a Boolean

For example, the parser accepts:

```txt
if 0 then 2 else 3
```

but evaluating its condition produces:

```elm
VNumber 0
```

The conditional therefore fails with:

```elm
TypeError
    { expected = [ TBool ]
    , actual = [ TNumber ]
    }
```

This enforces our decision that the condition must produce a Boolean value.

### The branches may produce different kinds of values

The two branches do not need to produce the same kind of value. For example:

```txt
if zero?(0) then 2 else zero?(3)
```

The then branch would produce a number, while the else branch would produce a Boolean. Because the condition evaluates to `true`, only the then branch is evaluated, and the complete conditional produces:

```elm
VNumber 2
```

The selected branch determines the result of the conditional expression.

### Only one branch is evaluated

Notice that `evalIf` never evaluates both branches. It calls `runExpr` only once, with the branch selected by the condition.

We can make that behaviour observable by placing an expression that would fail in the unselected branch:

```txt
if zero?(0) then 2 else -(zero?(0), 1)
```

If the interpreter evaluated the else branch, `zero?(0)` would produce a Boolean where `Diff` expects a number, causing a type error. But the condition evaluates to `true`, so only the then branch is evaluated and the complete conditional produces:

```elm
VNumber 2
```

This example does more than show which branch supplies the result. It shows that the else branch remains unevaluated when the condition is true.

## Testing the meaning of conditional expressions

We can now add tests that describe the meaning we chose for conditional expressions:

```elm
suite : Test
suite =
    describe "IF.Interpreter"
        [ describe "run" <|
            List.map (testRun I.run)
                -- Conditionals
                [ ( "if zero?(0) then 2 else 3", SucceedsWith (VNumber 2) )

                --- A false condition
                , ( "if zero?(1) then 2 else 3", SucceedsWith (VNumber 3) )

                --- Nested conditionals
                , ( """
                    if zero?(0) then
                        if zero?(1) then 2 else 4
                    else
                        if zero?(3) then 5 else 7
                    """
                  , SucceedsWith (VNumber 4)
                  )

                --- A non-Boolean condition
                , ( "if 0 then 2 else 3"
                  , RuntimeError <|
                        I.TypeError
                            { expected = [ I.TBool ]
                            , actual = [ I.TNumber ]
                            }
                  )

                --- The consequent would evaluate to a number
                --- The alternative would evaluate to a Boolean
                , ( "if zero?(0) then 2 else zero?(3)", SucceedsWith (VNumber 2) )

                --- Verify that the unselected else branch is not evaluated
                , ( "if zero?(0) then 2 else -(zero?(0), 1)", SucceedsWith (VNumber 2) )

                --- Verify that the unselected then branch is not evaluated
                , ( "if zero?(1) then -(zero?(0), 1) else 3", SucceedsWith (VNumber 3) )
                ]
        ]
```

The first two tests establish the basic behaviour: `true` selects the then branch, while `false` selects the else branch. The nested example confirms that either branch may contain another conditional expression.

The remaining tests describe the less obvious design decisions. A condition that produces a number fails with a type error, while the then and else branches are allowed to produce different kinds of values.

The final two tests verify that only the selected branch is evaluated. The first leaves an invalid else branch unselected; the second leaves an invalid then branch unselected.

## Where we go next

Our programs still cannot refer to values by name.

Next, in VAR, we'll add variable expressions. That will raise a new question for the interpreter:

> When we encounter a variable, how do we find the value associated with its name?

Think about what new information the interpreter might need while evaluating an expression.
