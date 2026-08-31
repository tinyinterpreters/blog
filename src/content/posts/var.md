---
title: "VAR: Adding Variables and Environments to a Tiny Interpreter in Elm"
description: Add variable expressions and environments to a tiny interpreter in Elm, then see how variable lookup makes evaluation depend on context.
pubDatetime: 2026-08-31T11:55:00
tags:
  - interpreters
  - programming languages
  - elm
---

Our programs still cannot refer to values by name.

What should this program mean?

```
x
```

We could decide that `x` refers to the number `10`. But how does the interpreter know that?

The AST can record that the program refers to the name `x`, but the name alone does not determine its value. Evaluating the expression requires information that is not present in the AST itself.

Before VAR, the evaluator didn't need any additional context to evaluate an expression. A variable changes that.

> Variables make evaluation depend on context.

For VAR, that context is an **environment**: a mapping from variable names to values.

In this article, we'll add variable references to the language, introduce environments, and update the evaluator so that it passes the current environment to every recursive call.

You can find the [complete source code for VAR on GitHub](https://github.com/tinyinterpreters/var).

## Table of contents

## What should a variable expression mean?

For now, every program will be evaluated in an initial environment supplied by the interpreter:

```txt
x ↦ VNumber 10
v ↦ VNumber 5
i ↦ VNumber 1
```

Given this environment, the variable expression:

```txt
x
```

should evaluate to:

```elm
VNumber 10
```

In another environment, the same name could be associated with a different value. The value of a variable expression depends on the environment in which it is evaluated.

We can state the meaning of a variable expression more generally:

> To evaluate a variable, look up its name in the current environment. If the environment contains a value associated with that name, return that value. Otherwise, report an identifier-not-found error.

Programs will not yet be able to introduce new names themselves. That limitation is intentional. Referring to a name and introducing a name are separate ideas. By adding only variable references for now, we can focus on lookup and the role of the environment before adding ways for programs to introduce names.

## Extending the language with variable expressions

VAR supports everything [IF](/posts/if) supports and adds variable expressions.

We extend the grammar with:

```txt
Expr ::= Const
       | Diff
       | Zero
       | If
       | Var
Var ::= Id
Id  ::= [a-z]+
```

A variable expression consists of an identifier containing one or more lowercase letters. This gives us identifiers such as `x`, `value`, and `onetwothree`.

The grammar describes which strings are valid identifiers. It doesn't say which value a name refers to. Whether the environment contains a value for a name is determined later, during evaluation.

For example, the parser should accept:

```txt
y
```

because `y` follows the identifier grammar. However, our initial environment doesn't contain a value for `y`, so evaluation should report an identifier-not-found error.

We represent variable expressions by adding `Var` to `Expr`:

```elm
type Expr
    = -- ...
    | Var Id

type alias Id =
    String
```

`Id` is an alias for `String`. It does not create a new Elm type, but it gives the string a more meaningful role in the AST: it represents an identifier in our language.

For example:

```txt
x
```

is represented as:

```elm
Program (Var "x")
```

## Parsing identifiers and reserved words

A sequence of lowercase letters is not always a variable name.

Names such as `x` and `value` should be parsed as identifiers, but words such as `if`, `then`, and `else` already have special roles in the language's syntax. Even though they look like identifiers, we don't want the parser to treat them as variable names.

We add an `id` lexeme parser to `VAR.Lexer`:

```elm
id : List String -> Parser String
id keywords =
    lexeme <|
        P.variable
            { start = Char.isLower
            , inner = Char.isLower
            , reserved = Set.fromList keywords
            }
```

The `start` and `inner` fields say that every character in an identifier must be a lowercase letter. Together, they implement the identifier grammar.

The `reserved` field contains names that would otherwise be valid identifiers but have a special meaning in the language. [`P.variable`](https://package.elm-lang.org/packages/elm/parser/latest/Parser#variable) rejects those names instead of returning them as identifiers.

We can now add variable expressions to the `expr` parser in `VAR.Parser`:

```elm
expr : Parser Expr
expr =
    P.oneOf
        [ constExpr
        , diffExpr
        , zeroExpr
        , ifExpr
        , varExpr
        ]

varExpr : Parser Expr
varExpr =
    P.map Var (L.id keywords)

keywords : List String
keywords =
    [ "else"
    , "if"
    , "then"
    ]
```

`L.id keywords` parses an identifier and returns its name as a `String`. `P.map Var` uses that name to construct a variable expression.

We don’t include `zero?` in the list because it cannot match the identifier grammar.

## Evaluating variable references with an environment

Now we can implement the lookup rule by giving the evaluator an environment.

### Representing the environment

For VAR, an environment only needs to support three operations:

- create an empty environment;
- associate a name with a value;
- look up the value associated with a name.

We could use Elm’s `Dict` type directly throughout the interpreter, but instead we’ll hide it behind a small `VAR.Env` module:

```elm
module VAR.Env exposing (Env, empty, extend, lookup)

import Dict exposing (Dict)

type Env k v
    = Env (Dict k v)

empty : Env k v
empty =
    Env Dict.empty

extend : comparable -> v -> Env comparable v -> Env comparable v
extend name value (Env dict) =
    Env (Dict.insert name value dict)

lookup : comparable -> Env comparable v -> Maybe v
lookup name (Env dict) =
    Dict.get name dict
```

A successful `lookup` returns `Just value`, while a missing name returns `Nothing`.

The module hides the `Env` constructor, so the evaluator must use environments through `empty`, `extend`, and `lookup` rather than depending on the underlying `Dict` representation. This means we can change how environments are represented later without changing the evaluator.

In `VAR.Interpreter`, we specialize the generic environment to map identifiers to language values:

```elm
import VAR.Env as Env

type alias Env =
    Env.Env Id Value
```

### Passing an environment to the evaluator

Before VAR, `runExpr` needed only an expression:

```elm
runExpr : Expr -> Result RuntimeError Value
```

It now needs both the expression and the current environment:

```elm
runExpr : Expr -> Env -> Result RuntimeError Value
```

We supply that initial environment in `runProgram`:

```elm
runProgram : AST.Program -> Result RuntimeError Value
runProgram (Program expr) =
    runExpr expr initEnv

initEnv : Env
initEnv =
    Env.empty
        |> Env.extend "x" (VNumber 10)
        |> Env.extend "v" (VNumber 5)
        |> Env.extend "i" (VNumber 1)
```

VAR cannot extend the environment during evaluation yet, so `initEnv` is the only environment used.

### Looking up a variable’s value

The `Var` branch implements the lookup rule we defined earlier:

```elm
runExpr : Expr -> Env -> Result RuntimeError Value
runExpr expr env =
    case expr of
        -- ...

        Var name ->
            case Env.lookup name env of
                Just value ->
                    Ok value

                Nothing ->
                    Err <| IdentifierNotFound name
```

We add `IdentifierNotFound` to the runtime error type we introduced in [ZERO](/posts/zero):

```elm
type RuntimeError
    = -- ...
    | IdentifierNotFound Id
```

Evaluating `x` in `initEnv` produces:

```elm
VNumber 10
```

The identifier `y` is syntactically valid, but `initEnv` does not contain an association for it. Evaluating `y` produces:

```elm
IdentifierNotFound "y"
```

## Passing the environment through recursive evaluation

Variable expressions can also appear as subexpressions of other expressions.

For example:

```txt
-(5, v)
```

is a difference expression, but its second operand is a variable. To evaluate it, the evaluator must pass the current environment to both operands.

The same applies when variables appear more deeply nested:

```txt
zero?(-(5, v))
```

The outer `Zero` passes the environment to its operand, and the nested `Diff` then passes it to both of its operands.

This means the new environment argument affects every recursive call to `runExpr`:

```elm
runExpr : Expr -> Env -> Result RuntimeError Value
runExpr expr env =
    case expr of
        -- ...

        Diff a b ->
            runExpr a env
                |> Result.andThen
                    (\va ->
                        runExpr b env
                            |> Result.andThen
                                (\vb ->
                                    evalDiff va vb
                                )
                    )

        Zero a ->
            runExpr a env
                |> Result.andThen
                    (\va ->
                        evalZero va
                    )

        If condition consequent alternative ->
            runExpr condition env
                |> Result.andThen
                    (\vCondition ->
                        evalIf vCondition consequent alternative env
                    )

        -- ...
```

The `Diff` branch does not inspect the environment itself. It passes `env` to its operands because either one may contain a variable.

A conditional also needs the environment after evaluating its condition, because whichever branch it selects may contain variables. `evalIf` therefore gains an environment argument:

```elm
evalIf : Value -> Expr -> Expr -> Env -> Result RuntimeError Value
evalIf vCondition consequent alternative env =
    case vCondition of
        VBool True ->
            runExpr consequent env

        VBool False ->
            runExpr alternative env

        -- ...
```

We can see the environment being passed through several expression forms in:

```elm
I.run "if zero?(-(5, v)) then i else v"
-- Ok (VNumber 1)
```

The condition contains a reference to `v`. Looking up `v` produces `VNumber 5`, so the difference evaluates to `VNumber 0` and `zero?` produces `VBool True`.

The conditional selects `i`, which evaluates to:

```elm
VNumber 1
```

Although only variable expressions inspect the environment directly, the evaluator must pass it through every enclosing expression so that a variable can be evaluated wherever it appears.

## Testing variable behaviour

We can now add tests that describe the behaviour of variable expressions:

```elm
suite : Test
suite =
    describe "VAR.Interpreter"
        [ describe "run" <|
            List.map (testRun I.run)
                -- Constant expressions
                [
                -- ...

                -- Difference expressions
                -- ...

                -- Is it zero?
                -- ...

                -- Conditionals
                -- ...

                -- Variables
                , ( "x", SucceedsWith (VNumber 10) )
                , ( "if zero?(-(5, v)) then i else v", SucceedsWith (VNumber 1) )
                , ( "y", RuntimeError <| I.IdentifierNotFound "y" )
                ]
        ]
```

The first test checks a direct variable lookup. The second confirms that the environment is passed through the enclosing expressions before `v` and `i` are looked up. The final test checks the new `IdentifierNotFound` runtime error.

## What VAR changed

Before VAR, the evaluator could determine an expression’s value from the AST alone. A variable expression changes that because the AST contains a name, but not the value associated with that name.

The evaluator needs an environment. The `Var` branch looks up a name in that environment, while every recursive call passes the environment along so that variables can appear inside larger expressions.

VAR also adds another way evaluation can fail. An identifier can be syntactically valid but have no associated value in the current environment, producing an `IdentifierNotFound` runtime error.

## Where we go next

VAR lets programs refer to names, but they still cannot introduce names of their own.

Next, we’ll add a language feature that introduces a new name by extending the environment, then evaluates an expression in that extended environment.

That raises our next question:

> When a program introduces a name, which expressions should be able to use it?
