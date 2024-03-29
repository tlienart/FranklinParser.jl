# Franklin Parser

[![CI Actions Status](https://github.com/tlienart/FranklinParser.jl/workflows/CI/badge.svg)](https://github.com/tlienart/FranklinParser.jl/actions)
[![codecov](https://codecov.io/gh/tlienart/FranklinParser.jl/branch/main/graph/badge.svg?token=mNry6r2aIn)](https://codecov.io/gh/tlienart/FranklinParser.jl)


Markdown parser for Franklin. See [Dev](#dev) at the bottom for information
about how it's structured. This isn't expected to be used by itself but may
be interesting for users who would like to extend the parsing or understand
how the parsing is done.

The way it's expected to be used is:


````julia-repl
julia> using FranklinParser

julia> s = raw"""
  a **b** _c_ `d` ~~html~~ $math$
  +++
  def
  +++
  """;

julia> p = FranklinParser.md_partition(s)
11-element Vector{FranklinParser.Block}:
(...)

julia> g = FranklinParser.md_grouper(p)
2-element Vector{FranklinParser.Group}:
(...)
````

* _Blocks_ are recuperated at parsing time by finding opening and closing tokens (e.g. a first `**` and the next matching `**`).
* _Groups_ are sets of blocks (potentially laced with text) that should be considered together (e.g. a paragraph).
* lastly note that we use `md_partition` and `md_parser` which do a few things by default, however someone could re-define those (see `partition.jl`).




## Why not just CommonMark.jl?

[CommonMark.jl](https://github.com/MichaelHatherly/CommonMark.jl) is great, well coded, and aims to respect the [commonmark specs](https://commonmark.org).

At its core, Franklin also uses markdown and so leveraging CommonMark.jl seemed a natural step, possibly with additions.
At some point however, it turned out that it was more difficult (for me) to work _with_ CommonMark than re-write some of its functionalities.
This is by no means related to the quality of CommonMark.jl but rather to how some of the additions in "Franklin-Markdown" require specific parsing rules, specifically to handle nesting and latex-like commands.

One big difference in the specs is that Franklin does **not** support indented lines for code blocks, only fenced code blocks are allowed and indentation is not significant.
In CommonMark, allowing this requires a number of checks that some special markers start after at most 3 whitespaces after a line return, in Franklin this is irrelevant and, among other things, allows nesting with indentation which helps with readability e.g.:

```
@@class1
  @@class2
    ## section
  @@
  Some text
@@
```

In the example above the fact that the ATXHeading starts on an idented line does not matter.

For more details, check out `test/partition/md_specs.jl` and `cmark/cmark.jl`, where things are discussed in a bit more details on a case-by-case basis.

### CM specs that are +- respected

Note: sometimes the parser is more, sometimes less tolerant, usually there's a good reason.

* atxheadings (`# ...`)
* blockquote (`> ...`)
* fenced code blocks (```` ```julia ... ``` ````) no more than 5 backticks allowed
* lists (only tight lists are allowed)
* hrules (`---`, ...) requires a triple
* emphasis (`*a*`, `_a_`, `**a**`, ...)
* autolink (`<...>`)
* htmlentity (`&amp;`)
* inlinecode (`` `a` ``)
* image, links (`![...](...)`, `[...](...)`, `[...]: ...`)

Notes:
* for links, putting the destination between `<...>` is not supported
* for links, the format `[A](B C)` is not supported, for refs, the format `[A]: B C` with `B` a link is not supported

### CM specs that are not respected

* setextheading
* indented code blocks
* html not inside `~~~...~~~`
* hard line breaks (use `\\`)

### Additional "Franklin" specs

* raw blocks `??? ... ???` (the content will be passed "as is" to X)
* latex blocks `%%% ... %%%` (the content will be passed "as is" to HTML, nothing will be passed to HTML)
* html blocks `~~~ ... ~~~` (the content will be passed "as is" to HTML, nothing will be passed to LaTeX)
* math `$...$`, `$$...$$`, `\[...\]` etc
* ...

## Specs

For the specs with respect to CommonMark, see `test/partition/md_specs.jl`.

## Notes

* assumption of LF convention i.e. that end of lines are `\n` and not `\r\n`.
Windows users who are using an editor with that convention should switch their preferences (in
VSCode this can be done by Settings > Text Editor > Files > EOL or putting `"files.eol": "\n"` in
`settings.json`).
* dropping `@def` multiline support; there's ambiguity with line returns; better to use `+++...+++`
blocks; `@def x = 5` is still allowed.
* adding `??? ... ???` as an overarching "escape" block, the effect is pretty much the same as that
of `~~~ ... ~~~` but an advantage is that `???` is not recognised by Markdown highlighters
(e.g. Atom's) and therefore if for instance a user wants to pass a block of text untouched to
CommonMark.jl it's nicer if the Markdown remains highlighted properly between the `???`.
* adding possibility to disable some tokens for instance `$` or indeed `???` by passing
`disable=[:MATH_INLINE, :RAW]` etc.

---

## Dev

* `find_tokens` reads string left to right, form tokens out of template, should not throw errors.
* `find_blocks`
