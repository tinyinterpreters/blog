---
title: "About"
description: "Why Tiny Interpreters exists and how it teaches programming language design and implementation one tiny interpreter at a time."
---

Hi, I’m Dwayne. 👋 Welcome to Tiny Interpreters, where you'll learn how programming languages work, one tiny interpreter at a time.

We start with the smallest complete interpreter we can build and gradually extend it with carefully chosen language features.

Each new feature brings us back to a recurring set of questions:

- What should the feature mean?
- How should we represent it?
- How should we parse it?
- How should we evaluate it?
- How should we test it?

By following each feature through every part of the interpreter, we can understand how the feature works and how a small language change affects the interpreter as a whole.

Tiny Interpreters is the path into programming languages I wish I could have followed when I first tried to learn the subject. It took me years—and one unsuccessful encounter with a dragon—to find that path for myself.

## My first encounter with the dragon

I became interested in programming languages when I discovered that studying, designing, and building them brought together several fields I enjoyed: mathematics, computer science, and software development.

My university didn't offer a course in programming languages or compiler construction while I was there, so I had to explore the subject on my own.

I started with [Compilers: Principles, Techniques, and Tools](https://en.wikipedia.org/wiki/Compilers:_Principles,_Techniques,_and_Tools), better known as the Dragon Book, but I didn't get very far. I learned a great deal about parsing and syntax-directed translation, but I still lacked a clear framework for understanding how programming language features were designed, implemented, and made to work together.

It would be a few more years before my dragon-inflicted wounds healed and I found a path into the subject that worked for me.

## Finding another way in

In the [Getting Started](http://lambda-the-ultimate.org/node/492) thread on Lambda the Ultimate, [Paul Snively](http://lambda-the-ultimate.org/node/492#comment-3760) recommended four books he considered especially good starting points for learning programming language design. One of them was EOPL—[_Essentials of Programming Languages_](https://www.eopl3.com/)—which he suggested beginning with, so I started there.

EOPL was also challenging. I had to work through two introductory chapters and an appendix before reaching the material I had come for: the sequence of interpreters that begins in Chapter 3. Once I got there, however, the challenge felt purposeful rather than obstructive. The book gave me one meaningful problem to work through at a time.

EOPL led me through a sequence of small languages, each implemented with an interpreter and extending the one before it. With each new feature, I could follow the change from the language’s concrete syntax, through its parser and abstract syntax, to the evaluator that gave it meaning—all without losing sight of how the whole interpreter worked.

For the first time, programming language design and implementation felt like a process I could follow. I didn't have to understand an entire compiler before I could build something meaningful. I could begin with a small language, make one focused change, and understand why every resulting change to the interpreter was necessary.

## Why Elm?

We’re starting with Elm because it makes the structures inside an interpreter explicit without adding much unrelated complexity. Custom types let us model syntax, values, errors, and other parts of the language directly, while pattern matching makes it natural to write functions that follow those structures. Elm is small, pure, and call-by-value, and its [`elm/parser`](https://package.elm-lang.org/packages/elm/parser/latest/) library gives us the tools to build complete parsers for the languages we design. Together, these qualities help us keep our attention on the ideas we're trying to understand.

## The bigger picture

As you learn to build interpreters, you’ll also develop skills that apply to software design more broadly. You’ll learn to model ideas with precise data structures, design APIs that express what users can do, test implementations against their intended meaning, and trace how one decision affects an entire system. These are skills you can carry into parsers, libraries, web applications, and other kinds of software.
