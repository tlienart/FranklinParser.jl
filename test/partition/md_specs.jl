# These are extra tests + some tyre kicking with the ordering
# following CommonMark.jl's blocks and some extras
#   ✅ means there's some tests,
#   🚫 means it's not supported because ambiguous with something else
#
# 0 paragraphs ✅
# 1 atxheading ✅
# 2 blockquote ✅
# 3 fencedcodeblock ✅
# x htmlblock 🚫
# x indentedcodeblock 🚫
# 4 list ✅ (⚠️ validation done in Franklin)
# x setextheading 🚫
# 5 hrule ✅
# 6 paragraphs --> 0 ✅
# 7 emphasis *, **, ***, _, __, ___  ✅
# 8 autolink <..> ✅ (⚠️ normalisation via URIs is done in Franklin)
# 9 htmlentity ✅ (they're left as is)
# x htmlinline 🚫
# 10 inlinecode ✅
# 11 image, links, footnotes ✅ (⚠️ no check that ref exists)
#
# x hard line breaks 🚫
# 12 comments ✅
# 13 backslash escapes ✅
#
# 14 table blocks ✅ (⚠️ validation done in Franklin)
#
# -- Franklin
#
# f0 raw
# f1 inline math ✅ (including switchoff)
# f2 block math ✅
# f3 code block ✅
# f4 code block with lang ✅
# f5 code block eval ✅ (see 3)
# f6 newcom ✅ (⚠️ assembly done in Franklin, needs the def)
# f7 com ✅
# f7i internal coms
# f8 newenv
# f9 env
# f9i internal envs (e.g. eqs)
# f10 cu brackets  ✅ (see f7 etc)
# f11 dbb ✅
# f12 emojis
# f13 def line   @def ...
# f14 def block  +++...+++
# f15 div block
# f16 html block

@testset "0>paragraphs" begin
    p = """
        abc

        def

        ghi
        """ |> grouper
    @test ct(p[1]) // "abc"
    @test ct(p[2]) // "def"
    @test ct(p[3]) // "ghi"
    @test all(p_i.role == :PARAGRAPH for p_i in p)

    p = """
        abc
        ```
        def
        ```
        ghi
        """ |> grouper
    @test ct(p[1]) // "abc"
    @test p[2].role == :CODE_BLOCK
    @test ctf(p[2]) // "def"
    @test p[3].role == :PARAGRAPH
    @test ct(p[3]) // "ghi"

    p = raw"""
        abc `def` ghi $jkl$ &amp; 123 @@c foo@@ end
        """ |> grouper
    @test ct(p[1]) // raw"abc `def` ghi $jkl$ &amp; 123"
    @test ctf(p[2]) // "foo"
    @test ct(p[3]) // "end"

    # nesting should not matter as inner blocks are disabled
    p = raw"""
        abc @@A aa @@B bb @@ @@ def
        """ |> grouper
    @test ct(p[1]) // "abc"
    @test ctf(p[2]) // "aa @@B bb @@"
    @test ct(p[3]) // "def"
end


# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX


@testset "1>atxheading" begin
    p = """
        # a
        ## b
        ### c
        #### d
        ##### e
        ###### f
        """ |> grouper
    @test length(p) == 6
    @test ct(p[1]) // "# a"
    @test ct(p[2]) // "## b"
    @test ct(p[3]) // "### c"
    @test ct(p[4]) // "#### d"
    @test ct(p[5]) // "##### e"
    @test ct(p[6]) // "###### f"
    @test ctf(p[1]) // "a"
    @test ctf(p[2]) // "b"
    # spaces don't matter
    p = """
        # a
            ## b
        """ |> grouper
    @test ctf(p[1]) // "a"
    @test ctf(p[2]) // "b"

    # has to be at start of line
    p = """
        a # bc
        """ |> grouper
    @test ctf(p[1]) // "a # bc"
end


# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX


@testset "2>blockquotes" begin
    p = """
        > abc
        """ |> grouper
    @test p[1] // "> abc"
    p = """
        > abc
        > def
        > ghi
        """ |> grouper
    @test p[1] // "> abc\n> def\n> ghi"
    p = """
        > abc
        def

        ghi
        """ |> grouper
    @test p[1] // "> abc\ndef"
    @test p[2] // "ghi"
    p = """
        > abc
        > def

        >ghi
        > jkl
        """ |> grouper
    @test p[1] // "> abc\n> def"
    @test p[2] // ">ghi\n> jkl"

    p = """
        > abc
        > > def
        > > ghi
        """ |> grouper
    @test p[1] // "> abc\n> > def\n> > ghi"
end


# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX


@testset "3+f3+f4+f5>codeblock" begin
    p = """
        abc
        ```
        def
        ```
        ghi
        """ |> grouper
    @test p[1].role == :PARAGRAPH
    @test ctf(p[2]) // "def"
    @test p[3].role == :PARAGRAPH

    p = """
        abc
        ````
        def
        ```
        ghi
        ```
        jkl
        ````
        mno
        """ |> grouper
    @test p[1] // "abc"
    @test ctf(p[2]) // "def\n```\nghi\n```\njkl"
    @test p[3] // "mno"

    p = """
        abc
        ```def
        ghi
        ```
        jkl
        """ |> grouper
    @test ctf(p[2]) // "def\nghi"

    p = """
        abc
        ```!
        def
        ```
        ghi
        """ |> grouper
    @test ctf(p[2]) // "!\ndef"
end


# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX


@testset "4>list" begin
    p = """
        abc
        * i
        * j
            * k
        """ |> grouper
    @test p[1] // "abc"
    @test p[2] // "* i\n* j\n    * k"

    p = """
        abc
        * i
          * j
        still part of j
          * k
        """ |> grouper
    @test p[1] // "abc"
    @test p[2] // "* i\n  * j\nstill part of j\n  * k"

    p = """
        abc
        1. i
        1) j
        1 k
        """ |> grouper
    @test p[2] // "1. i\n1) j\n1 k"
end


# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX


@testset "5>hrule" begin
    p = """
        abc
        ---
        def
        """ |> grouper
    @test isp(p[1])
    @test p[2] // "---"
    @test isp(p[3])

    p = """
        > abc
        ***
        > def
        """ |> grouper
    @test p[1] // "> abc"
    @test p[2] // "***"
    @test p[3] // "> def"

    p = """
        > abc
        xxx
        ___
        > def
        """ |> grouper
    @test p[1] // "> abc\nxxx"
    @test p[2] // "___"
    @test p[3] // "> def"
end


# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX


@testset "6>paragraph" begin
    # see 0>
end


# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX


@testset "7>emph" begin
    p = """
        a *b* _c_ **d** __e__ ***f*** ___g___

        **b _c_ d**
        """ |> md_blockifier
    @test p[1].name == :EMPH_EM
    @test ct(p[1]) == "b"
    @test p[2].name == :EMPH_EM
    @test ct(p[2]) == "c"
    @test p[3].name == :EMPH_STRONG
    @test ct(p[3]) == "d"
    @test p[4].name == :EMPH_STRONG
    @test ct(p[4]) == "e"
    @test p[5].name == :EMPH_EM_STRONG
    @test ct(p[5]) == "f"
    @test p[6].name == :EMPH_EM_STRONG
    @test ct(p[6]) == "g"
    @test p[end-1].name == :EMPH_STRONG
    @test ct(p[end-1]) == "b _c_ d"

    s = "a*b*c*"
    t = s |> toks
    b = s |> md_blockifier
    @test ct(b[1]) == "b"
    @test length(b) == 1
end


# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX


@testset "8>autolink" begin
    p = """
        a <bc> def <http://example.com> and < done >>.
        """ |> md_blockifier
    @test p[1].name == :AUTOLINK
    @test ct(p[1]) == "bc"
    @test p[2].name == :AUTOLINK
    @test ct(p[2]) == "http://example.com"
    @test p[3].name == :P_BREAK
end


# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX


# entities are just left 'as is'.
@testset "9>entity" begin
    p = """
        abc & def &amp; but &amp. &#42;
        """ |> grouper
    @test ctf(p[1]) == "abc & def &amp; but &amp. &#42;"
end


# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX


@testset "10>inline code" begin
    s = """
        abc `def` and `` ` `` and *`fo*o`*.
        """
    p = s |> slice
    @test ct(p[1]) // "abc"
    @test ct(p[2]) // "def"  # `def`
    @test ct(p[3]) // "and"
    @test ct(p[4]) // " ` "
    @test ct(p[5]) // "and"
    @test ct(p[6]) // "`fo*o`"
    @test ct(p[7]) // "."
    g = s |> grouper
    @test length(g) == 1  # all inline blocks
end


# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX


@testset "11>img, links, footnotes" begin
    s = """
        [abc] [def](ghi) ![jkl] ![mno](pqr)
        [ref]: aaa
        """
    b = s |> md_blockifier
    @test b[1].name == :LINK_A
    @test b[1] // "[abc]"
    @test b[2].name == :LINK_AB
    @test b[2] // "[def](ghi)"
    @test b[3].name == :IMG_A
    @test b[3] // "![jkl]"
    @test b[4].name == :IMG_AB
    @test b[4] // "![mno](pqr)"
    @test b[5].name == :REF
    @test b[5] // "[ref]:"

    # not ok because not at the start of a line bar spaces
    s = "abc [def]: hello" |> md_blockifier
    @test length(s) == 0

    # aggregation over multiline for ref
    s = """
        abc
        [def]: foo
        bar

        baz
        """
    p = s |> grouper
    @test ctf(p[1]) // "abc"
    @test length(p[2].blocks) == 1
    @test p[2].blocks[1] // "[def]: foo\nbar"
    @test ctf(p[3]) // "baz"

    # AR links
    p = """
        [A][B] ![C][D] ![E][F]:
        """ |> grouper
    @test p[1].blocks[1] // "[A][B]"
    @test p[1].blocks[3] // "![C][D]"
    @test p[1].blocks[5] // "![E][F]" # precedence of the img
    @test p[1].blocks[6] // ":"

    # final img
    p = """
        [A][B] ![C]
        """ |> grouper
    @test p[1].blocks[1] // "[A][B]"
    @test p[1].blocks[3] // "![C]"
end


# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX


@testset "12>comment" begin
    p = "Hello <!--bar--> baz foo `<!--aa-->`" |> grouper
    @test length(p) == 1
    @test p[1].blocks[1] // "Hello"
    @test p[1].blocks[2] // "<!--bar-->"
    @test p[1].blocks[3] // "baz foo"
    @test p[1].blocks[4] // "`<!--aa-->`"
end


# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX


@testset "13>escapes" begin
    p = raw"abc \_ foo" |> slice
    @test Int('_') == 95
    @test text(p[1]) // "abc &#95; foo"
    for c in raw"""*_`@#{}$~!"%&'+,-./:;<=>?^|"""
        p = "a \\" * c * " b" |> slice
        ic = Int(c)
        @test text(p[1]) // "a &#$(ic); b"
    end
    p = "a \\ b" |> slice
    @test text(p[1]) // "a &#92; b"
end


# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX


@testset "14>table" begin
    p = """
        abc
        | a | b | c |
        | - | - | - |
        | 1 | 2 | 3 |
        def
        """ |> grouper
    @test p[1] // "abc"
    @test p[3] // "def"
    p = "abc | def" |> md_blockifier
    @test length(p) == 0
    p = "| abc | def |" |> md_blockifier
    @test p[1].name == :TABLE_ROW_CAND
    p = "|abc|def|" |> md_blockifier
    @test p[1].name == :TABLE_ROW_CAND
    p = "|abc|def" |> md_blockifier   # doesn't end with '|'
    @test length(p) == 0
end


# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# ===========================================================================
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# ===========================================================================
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX


@testset "f0>raw" begin
    # doesn't fail because we don't inspect what goes on in `???`.
    p = """
        foo bar ??? <!-- etc __ ??? baz
        """ |> grouper
    @test p[1].blocks[1] // "foo bar"
    @test p[1].blocks[2] // "??? <!-- etc __ ???"
    @test p[1].blocks[3] // "baz"
end


@testset "f1>inline math" begin
    s = raw"abc $ghi$ mkl"
    b = s |> md_blockifier
    @test ct(b[1]) == "ghi"
    p = s |> grouper
    @test p[1] // s
    @test p[1].blocks[2] // raw"$ghi$"

    # disable math
    s = raw"foo $800"
    p = FP.md_partition(s, disable=[:MATH_INLINE])
    @test p[1].name == :TEXT
    @test ct(p[1]) == s
end


# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX


@testset "f2>block math" begin
    p = raw"""
        abc $$x = 1+1$$ end
        """ |> grouper
    @test length(p) == 3
    @test ctf(p[2]) // "x = 1+1"
    p = raw"""
        abc \[x = 1+1\] end
        """ |> grouper
    @test length(p) == 3
    @test ctf(p[2]) // "x = 1+1"
end


# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX


@testset "f6+f7>newcoms,coms" begin
    s = raw"""
        \newcommand{\foo}{abc}
        \newcommand{\bar}[1]{abc#1}
        \foo \bar{def}
        """
    p = s |> grouper
    @test p[1] // s
    @test p[1].blocks[1] // raw"\newcommand"
    @test p[1].blocks[2] // raw"{\foo}"
    @test p[1].blocks[3] // raw"{abc}"
    @test p[1].blocks[4] // "\n"
    @test p[1].blocks[5] // raw"\newcommand"
    @test p[1].blocks[6] // raw"{\bar}"
    @test p[1].blocks[7] // raw"[1]"
    @test p[1].blocks[8] // raw"{abc#1}"

    p = raw"\newcommand{\foo}  [1 ] {abc}" |> grouper
    @test p[1].blocks[2] // raw"{\foo}"
    @test p[1].blocks[3].ss == "  "
    @test p[1].blocks[4] // "[1 ]"
    @test p[1].blocks[5].ss == " "
    @test p[1].blocks[6] // "{abc}"
end


# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX


@testset "f10>cu_brackets" begin
    # see f6,f7
end


# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX


@testset "f11>dbb" begin
    p = "abc {{def}} ghi" |> grouper
    @test length(p) == 1
    @test p[1].blocks[2].name == :DBB
    @test ct(p[1].blocks[2]) // "def"
end


# ////////////////////////////////////////////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# ////////////////////////////////////////////////////////////////////////////
# XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
# ////////////////////////////////////////////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////


@testset "xx corner cases" begin
    s = "[`]`]"
    b = s |> md_blockifier
    @test b[1].ss == "[`]`]"

    s = "*abc<!--d*-->"
    b = s |> md_blockifier
    @test ct(b[1]) == "d*"
    g = s |> grouper
    @test g[1].ss == s
end
