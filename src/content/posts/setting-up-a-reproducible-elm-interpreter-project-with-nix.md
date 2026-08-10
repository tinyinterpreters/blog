---
title: "Setting Up a Reproducible Elm Interpreter Project with Nix"
description: Set up a reproducible Elm interpreter project with a Nix flake, Elm tooling, helper commands, source and test structure, and grammar documentation.
pubDatetime: 2026-08-06T08:50:00
tags:
  - nix
  - elm
  - interpreters
---

In [CONST: The Structure of a Tiny Interpreter in Elm](/posts/const), we established the structure of a tiny interpreter. Then, in [Testing an Elm Interpreter with elm-test](/posts/testing-an-elm-interpreter-with-elm-test), we looked more closely at how its tests are organized.

Before moving on to [DIFF: Adding Recursive Expressions to a Tiny Interpreter in Elm](/posts/diff), let’s step back and set up the reusable project foundation shared by these interpreters:

- `elm`, `elm-format`, and `elm-test`
- a consistent source and test-module hierarchy
- helper commands for common development tasks
- a place to document the language grammar

We use Nix to provide the development tools and record the resolved inputs so the environment can be recreated later. This isn’t a general introduction to Nix or an argument that every Elm project should use it. We only need enough Nix to create and enter the project environment.

## Table of contents

## Prerequisites

You’ll need:

- Git
- [Nix](https://zero-to-nix.com/start/install/) with the `nix-command` and `flakes` features enabled
- basic familiarity with the command line

## Create the repository

We’ll use CONST as the example:

```bash
git init const
cd const
touch README.md flake.nix
```

For another interpreter, use its lowercase name in the first two commands.

Every interpreter repository will have a `README.md`, though we won’t cover its contents here.

## Define the Nix development environment

Add the following to `flake.nix`:

```nix
{
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem(system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          name = "const";

          packages = [
            pkgs.elmPackages.elm
            pkgs.elmPackages.elm-format
            pkgs.elmPackages.elm-test
          ];

          shellHook = ''
            export PROJECT_ROOT="$(git rev-parse --show-toplevel)"
            export PS1="($name)\n$PS1"

            f () {
              elm-format "$PROJECT_ROOT/"{src,tests} "''${@:---yes}"
            }

            t () {
              elm-test "$@"
            }

            c () {
              nix flake check -L &&
              f --validate &&
              t
            }

            clean () {
              rm -rf "$PROJECT_ROOT/elm-stuff"
            }

            echo "Development environment loaded"
            echo ""
            echo "Type 'f' to run elm-format"
            echo "Type 't' to run elm-test"
            echo "Type 'c' to run all checks"
            echo "Type 'clean' to remove build artifacts"
            echo ""
          '';
        };
      }
    );
}
```

The `outputs` function receives the flake itself as `self`, along with the `nixpkgs` and `flake-utils` inputs. Because those inputs are not declared explicitly, Nix resolves their names through its [flake registry](https://zero-to-nix.com/concepts/flakes/#registries). The specific revisions it finds will be recorded in `flake.lock`.

[`flake-utils.lib.eachDefaultSystem`](https://github.com/numtide/flake-utils#eachdefaultsystem--system---attrs) defines the same outputs for each of its default systems. For each system, the following line selects the corresponding collection of packages from Nixpkgs and names it `pkgs`:

```nix
pkgs = nixpkgs.legacyPackages.${system};
```

That gives us access to packages such as:

```nix
pkgs.elmPackages.elm
```

`devShells.default` defines the environment we enter with `nix develop`.

The `packages` list gives us the three development tools we need:

- `elm`
- `elm-format`
- `elm-test`

The `shellHook` runs whenever we enter the environment. It sets the project root, updates the shell prompt, defines a few helper commands, and prints a reminder of the commands available.

The only value we need to change in `flake.nix` for each interpreter is the shell name:

```nix
name = "const";
```

For DIFF, that becomes:

```nix
name = "diff";
```

For the interpreters in this series, the rest of the file remains the same.

## Enter the development environment

Add `flake.nix` to the staging area before asking Nix to evaluate it:

```bash
git add flake.nix
nix develop
```

A flake inside a Git repository can only see files that Git knows about, which is why the new `flake.nix` must be staged first.

Run `nix develop` from the repository root. The development environment uses Git to find the repository root and assigns it to `PROJECT_ROOT`, so the helper commands can find the project files even after you move into a subdirectory.

You can confirm that the tools are available by checking their versions:

```bash
elm --version
elm-format --version
elm-test --version
```

The first time you run `nix develop`, Nix also creates `flake.lock`.

`flake.nix` describes the development environment. `flake.lock` records the specific revisions that Nix resolved. Later runs reuse those revisions until the flake is updated.

Add the lock file to Git:

```bash
git add flake.lock
```

Committing `flake.lock` ensures that those resolved revisions travel with the project, so other developers and future checkouts use the same Nix inputs.

## Ignore Elm build artifacts

Create `.gitignore` at the root of the project:

```txt
elm-stuff/
```

`elm-stuff` contains generated build data and doesn’t need to be committed.

## Initialize Elm and the tests

Start the Elm project:

```bash
elm init
```

Press Enter to accept the default answer.

This creates:

```txt
.
├── src/
└── elm.json
```

The interpreter’s source modules will live under `src`.

Our interpreters use `elm/parser`, so install it next:

```bash
elm install elm/parser
```

Press Enter to confirm the changes to `elm.json`.

Now set up `elm-test`:

```bash
elm-test init
```

This adds `elm-explorations/test` to the test dependencies in `elm.json` and creates an example test module:

```txt
.
└── tests/
    └── Example.elm
```

Remove the example:

```bash
rm tests/Example.elm
```

We’ll replace it with a structure that mirrors the interpreter modules.

At this point, both `src` and `tests` exist. Next, we’ll organize the interpreter modules and give the tests a matching structure.

## Organize the interpreter modules

Each interpreter’s source modules live under an uppercase namespace directory in `src`.

For CONST:

```bash
mkdir -p src/CONST
```

The source structure will be:

```txt
.
└── src/
    └── CONST/
        ├── AST.elm
        ├── Interpreter.elm
        ├── Lexer.elm
        └── Parser.elm
```

Each module has a familiar responsibility:

- `AST.elm` defines the types used to represent programs.
- `Lexer.elm` recognizes the smallest pieces of syntax.
- `Parser.elm` turns source text into an AST.
- `Interpreter.elm` runs complete programs from source text to evaluated result.

For DIFF, the directory and module namespace will change from `CONST` to `DIFF`, but the basic organization will remain the same.

## Mirror the source modules in the tests

Create the test-module directory:

```bash
mkdir -p tests/Test/CONST
```

The tests follow the source structure beneath a top-level `Test` namespace:

```txt
.
└── tests/
    └── Test/
        ├── CONST/
        │   ├── Interpreter.elm
        │   ├── Lexer.elm
        │   └── Parser.elm
        └── Lib.elm
```

Each test module mirrors the source module it tests. For example:

```txt
src/CONST/Lexer.elm
tests/Test/CONST/Lexer.elm
```

These files define the modules:

```txt
CONST.Lexer
Test.CONST.Lexer
```

The same pattern applies to `Parser.elm` and `Interpreter.elm`.

We don’t currently need a test module for `CONST.AST` because it only defines the types used to represent valid programs.

Each test module exposes one value named `suite`:

```elm
module Test.CONST.Lexer exposing (suite)

import Test exposing (Test, describe)


suite : Test
suite =
    describe "CONST.Lexer"
        [ -- Lexer test groups go here.
        ]
```

`elm-test` discovers exposed top-level values with the type `Test`. The value does not have to be named `suite`; that’s just the convention we’ll use throughout the series.

The top-level `describe` uses the name of the module under test. The specific groups of test cases live inside it.

Reusable test helpers belong in:

```txt
.
└── tests/
    └── Test/
        └── Lib.elm
```

For example, the `testValue` helper developed in [Testing an Elm Interpreter with elm-test](/posts/testing-an-elm-interpreter-with-elm-test) lives in `Test.Lib` and can be imported by the lexer, parser, and interpreter tests.

That keeps each test module focused on its language examples rather than the mechanics used to run them.

## Use the helper commands

The development environment defines four helper commands.

### Format the project

Run:

```bash
f
```

This formats the Elm files under both `src` and `tests`.

With no arguments, `f` passes `--yes` to `elm-format`. You can override that default by passing another option:

```bash
f --validate
```

That validates the formatting without changing any files.

### Run the tests

Run:

```bash
t
```

This calls `elm-test` and forwards any additional arguments:

```bash
t --watch
```

### Run all checks

Run:

```bash
c
```

This runs the following commands in sequence:

```bash
nix flake check -L
f --validate
t
```

The first command checks the flake. The other two validate the Elm formatting and run the tests. If any command fails, `c` stops and reports the failure.

### Remove build artifacts

Run:

```bash
clean
```

This removes the generated `elm-stuff` directory.

## Document the grammar

Create the `docs` directory and the grammar file:

```bash
mkdir -p docs
touch docs/grammar.ebnf
```

The `grammar.ebnf` file contains the context-free grammar for the interpreter.

For CONST:

```txt
Program ::= Expr
Expr    ::= Const
Const   ::= Number
Number  ::= [0-9]+
```

We’ll also generate a Markdown version of the grammar with railroad diagrams. Once generated, the documentation structure will be:

```txt
.
└── docs/
    ├── grammar/
    │   ├── diagram/
    │   │   └── *.svg
    │   └── README.md
    └── grammar.ebnf
```

`docs/grammar` contains the generated Markdown documentation and the SVG railroad diagrams it references.

You can see the [generated grammar documentation for CONST](https://github.com/tinyinterpreters/const/tree/master/docs/grammar) in its repository.

To generate them:

1. Edit `docs/grammar.ebnf`.
2. Open the [Bottlecaps Railroad Diagram Generator](https://www.bottlecaps.de/rr/ui).
3. Paste the grammar into the **Edit Grammar** tab.
4. Open the **View Diagram** tab.
5. Under **Download Diagram**, select Markdown and SVG, then download the archive.
6. Extract the archive and rename `index.md` to `README.md`.
7. Move the generated directory to `docs/grammar`.

When the grammar changes, update `grammar.ebnf` and regenerate the documentation.

## Review the finished project structure

Once the interpreter, its tests, and the grammar documentation are in place, the project will look like this:

```txt
.
├── docs/
│   ├── grammar/
│   │   ├── diagram/
│   │   │   └── *.svg
│   │   └── README.md
│   └── grammar.ebnf
├── src/
│   └── CONST/
│       ├── AST.elm
│       ├── Interpreter.elm
│       ├── Lexer.elm
│       └── Parser.elm
├── tests/
│   └── Test/
│       ├── CONST/
│       │   ├── Interpreter.elm
│       │   ├── Lexer.elm
│       │   └── Parser.elm
│       └── Lib.elm
├── .gitignore
├── README.md
├── elm.json
├── flake.lock
└── flake.nix
```

The interpreter name changes from project to project. The surrounding structure stays the same.

## Verify the setup

With the source and test modules in place, exit the current development shell and open a fresh one from the repository root:

```bash
exit
nix develop
```

Then run the combined project checks:

```bash
c
```

This checks the flake, validates the Elm formatting, and runs the tests. If the command succeeds, the project setup is ready to use.

## Ready for the next interpreter

We now have a reusable foundation for the interpreters in this series: the development tools and helper commands are configured, and the source, test, and grammar documentation structures are defined.

Later posts can therefore concentrate on what changes from one interpreter to the next: the grammar, lexer, AST, parser, evaluator, and tests.

Next, we’ll use this foundation to add difference expressions in [DIFF](/posts/diff).
