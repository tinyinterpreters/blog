---
title: "Simplifying Whitespace with Lexeme Parsers in Elm"
description: Learn how lexeme parsers simplify whitespace handling in elm/parser by consuming trailing whitespace and keeping parsers close to the grammar.
pubDatetime: 2026-08-14T11:50:00
tags:
  - parser combinators
  - elm
  - parsing
---

[CONST](/posts/const) already accepts whitespace around its number. [DIFF](/posts/diff) makes the usefulness of that whitespace policy much easier to see:

```txt
-(
    -(5, 3),
    -(0, 1)
)
```

Despite the spaces and line breaks, the parsers for constant and difference expressions contain no explicit whitespace handling:

```elm
constExpr : Parser Expr
constExpr =
    P.map Const number


number : Parser Number
number =
    L.digits


diffExpr : Parser Expr
diffExpr =
    P.succeed Diff
        |. L.symbol "-"
        |. L.symbol "("
        |= P.lazy (\_ -> expr)
        |. L.symbol ","
        |= P.lazy (\_ -> expr)
        |. L.symbol ")"
```

That’s possible because `digits` and the parsers produced by `symbol` are **lexeme parsers**.

A lexeme parser parses one complete lexical unit and then consumes the permitted trailing whitespace. This small convention keeps whitespace handling out of the grammar-level parsers, allowing their structure to remain close to the grammar they implement.

## Table of contents

## Moving whitespace into the lexeme parsers

The pattern begins with a small helper:

```elm
lexeme : Parser a -> Parser a
lexeme p =
    P.succeed identity
        |= p
        |. spaces
```

`lexeme` runs a parser, keeps its result, and then runs `spaces`.

What `spaces` consumes is up to us. For CONST and DIFF, we reuse the [`spaces` parser provided by `elm/parser`](https://package.elm-lang.org/packages/elm/parser/latest/Parser#spaces). It consumes zero or more spaces, line feeds, or carriage returns. It doesn't consume tabs or comments.

CONST uses `lexeme` to turn `digits` into a lexeme parser:

```elm
digits =
    chompOneOrMore Char.isDigit
        |> P.getChompedString
        |> P.map (Maybe.withDefault 0 << String.toInt)
        |> lexeme
```

DIFF applies the same pattern to symbols:

```elm
symbol : String -> Parser ()
symbol =
    lexeme << P.symbol
```

Because the number and symbol parsers consume their own trailing whitespace, `diffExpr` doesn't need to handle whitespace between each part of the expression.

The only whitespace left to account for comes before the first lexeme. The program parser consumes it once:

```elm
program : Parser AST.Program
program =
    P.succeed Program
        |. L.spaces
        |= expr
        |. P.end
```

The convention is simple: the program parser handles whitespace before the first lexeme, and each lexeme parser handles the whitespace that follows it.

A useful contrast appears in [my Brainfuck interpreter](https://github.com/dwayne/elm-brainfuck/blob/d6bbc59e85e8a495c1bd4f4b84febe564477ab85/src/Brainfuck/Lexer.elm#L69-L83), where the language has a broader notion of ignorable input:

```elm
spaces : Parser ()
spaces =
    P.chompWhile isSpace


isSpace : Char -> Bool
isSpace ch =
    not <| Set.member ch nonSpaceChars


nonSpaceChars : Set Char
nonSpaceChars =
    "><+-.,[]"
        |> String.toList
        |> Set.fromList
```

Here, `spaces` consumes any character that isn't a Brainfuck instruction, so it represents all ignorable input rather than whitespace alone.

The `lexeme` helper doesn't need to change. We can change what the parser treats as ignorable input simply by changing the parser that `lexeme` runs afterward.

## Where I learned about lexeme parsers

I first encountered the term **lexeme parser** while reading Daan Leijen’s [_Parsec, a fast combinator parser_](https://users.cecs.anu.edu.au/~Clem.Baker-Finch/parsec.pdf). The paper gave me a name for the convention I’m using here.

Once I knew what the pattern was called, I became curious about where it came from. Following it backward through earlier parser-combinator papers reveals a few ghosts of the same idea.

## Following the idea backward

- **Daan Leijen, [_Parsec, a fast combinator parser_](https://users.cecs.anu.edu.au/~Clem.Baker-Finch/parsec.pdf) (2001).** This paper uses the term _lexeme parser_ for parsers that skip trailing whitespace.
- **Graham Hutton and Erik Meijer, [_Monadic Parser Combinators_](https://people.cs.nott.ac.uk/pszgmh/monparsing.pdf) (1996).** This paper describes a close earlier version of the same arrangement. Its `parse` combinator consumes whitespace and comments before the main parser begins, while `token` consumes them after parsers for complete tokens. It even defines `symbol` by applying `token` to a string parser.
- **Graham Hutton, [_Higher-Order Functions for Parsing_](https://www.cs.nott.ac.uk/~pszgmh/parsing.pdf) (1992).** This paper presents a related earlier approach called `nibble`, which consumes whitespace before and after another parser. Hutton then uses it to define a whitespace-aware `symbol` parser. It isn’t the trailing-whitespace convention used in our parsers, but it shows the same broader idea: whitespace handling can be packaged into a reusable combinator instead of repeated throughout the grammar parser.
