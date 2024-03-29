"""
    find_blocks(tokens, templates)

Given a list of tokens and a dictionary of block templates, find all blocks
matching templates. The blocks are sorted by order of appearance and inner
blocks are weeded out.
"""
function find_blocks(
            tokens::SubVector{Token};
            # kwargs
            is_md::Bool=true
        )::Vector{Block}

    blocks = Block[]
    isempty(tokens) && return blocks
    is_active = ones(Bool, length(tokens))

    # ------------------------------------------------------------------------
    if is_md
        ##########
        # PASS 0 #
        ##########
        # raw blocks (??? ... ???)
        _find_blocks!(blocks, tokens, MD_PASS0, is_active)

        ##########
        # PASS 1 #
        ##########
        # basically all container blocks
        # comment, raw html, raw latex, def blocks, code blocks
        # math blocks, div blocks, autolink, cu_brackets, h* blocks
        # and lxbegin/end
        _find_blocks!(blocks, tokens, MD_PASS1_TEMPLATES, is_active,
                      process_linereturn=true)

        sort!(blocks, by=from)

        # At this point we have the cu_brackets and begin/end in blocks
        # Form the begin...end environments and deactivate all tokens within
        _find_env_blocks!(blocks, tokens, is_active)

        ##########
        # PASS 2 #
        ##########
        # brackets which may form a link: brackets and sq_brackets
        dt = _find_blocks!(blocks, tokens, MD_PASS2_TEMPLATES, is_active)
        form_links!(blocks)
        # here there may be brackets that are not part of links which
        # should have their content re-inspected
        @inbounds for b in filter(b_ -> b_.name == :BRACKETS, blocks)
            fromb  = from(b)
            tob    = to(b)
            retoks = Token[]
            for i in dt
                toki = tokens[i]
                fi   = from(toki)
                ti   = to(toki)
                # is the token in the scope ?
                fromb < fi && ti < tob && push!(retoks, toki)
            end
            # recurse
            append!(blocks, find_blocks(subv(retoks), is_md=true))
        end
        # discard leftover bracket blocks
        filter!(b -> b.name != :BRACKETS, blocks)

        ##########
        # PASS 3 #
        ##########
        # remaining stuff e.g. emphasis tokens, lxnew* etc
        _find_blocks!(blocks, tokens, MD_PASS3_TEMPLATES, is_active)

    # ------------------------------------------------------------------------
    else
        # for HTML we barely do anything, a single pass is plenty enough
        _find_blocks!(blocks, tokens, HTML_TEMPLATES, is_active)
    end

    # remove blocks inside larger blocks (recursion)
    sort!(blocks, by=from)
    remove_inner!(blocks)

    # forming of double braces is done here to avoid clash with lx curly braces
    is_md && form_dbb!(blocks)

    return blocks
end

find_blocks(t::Vector{Token}, a...) = find_blocks(subv(t), a...)


"""
    _find_blocks!(...)

Helper function to resolve each of the passes looking at a different set of
templates.
"""
function _find_blocks!(
            blocks::Vector{Block},
            tokens::SubVector{Token},
            templates::Dict{Symbol, BlockTemplate},
            is_active::Vector{Bool}=ones(Bool, length(tokens));
            # kwargs
            process_linereturn::Bool=false
        )::Vector{Int}
    #
    # keep track of what was deactivated, this is useful for md parsing
    # when discarding BRACKET tokens and re-enabling the tokens inside them;
    # only the tokens deactivated by it should be re-enabled.
    # so for instance:
    #   (abc _@@d *g* @@_ ef) --> first pass will deactivate `*`
    #   --> we should only re-enable `_`.
    #
    deactivated_tokens = Int[]

    isempty(templates) && return deactivated_tokens

    template_keys = keys(templates)
    n_tokens      = length(tokens)

    @inbounds for i in eachindex(tokens)

        is_active[i] || continue
        opening = tokens[i].name

        if process_linereturn && opening in (:SOS, :LINE_RETURN)
            process_line_return!(blocks, tokens, i)
            continue
        elseif opening ∉ template_keys
            continue
        end

        template = templates[opening]
        closing  = template.closing
        nesting  = template.nesting

        if closing === NO_CLOSING
            push!(blocks, TokenBlock(tokens[i]))
            continue
        end

        # Try to find the closing token
        closing_index = -1
        open_depth    = 1
        for j in i+1:n_tokens
            # the tokens ahead might be inactive due to first pass
            is_active[j] || continue
            candidate = tokens[j].name
            # has to happen before opener to avoid ambiguity in emphasis tokens
            if candidate in closing
                open_depth -= 1
            elseif candidate == opening && nesting
                open_depth += 1
            end
            if open_depth == 0
                closing_index = j
                break
            end
        end

        if (closing_index == -1)
            # allow those to not be closed properly
            if opening ∈ CAN_BE_LEFT_OPEN
                continue
            end
            # otherwise complain
            block_not_closed_exception(tokens[i])
        end

        tokens_in_span = @view tokens[i:closing_index]
        new_block = Block(template.name, tokens_in_span)
        push!(blocks, new_block)

        # for blocks that end with a line return, do not deactivate
        # that line return which might e.g. lead to the start of an item
        # see process_line_returns
        last_token = tokens[closing_index]
        if last_token.name == :LINE_RETURN
            closing_index -= 1
        end

        # deactivate all tokens in the span of the block
        to_deactivate = i:closing_index
        is_active[to_deactivate] .= false
        append!(deactivated_tokens, collect(to_deactivate))
    end
    return deactivated_tokens
end


"""
    process_line_return!(blocks, tokens, i)

Process a line return followed by any number of white spaces and one or more
characters. Depending on these characters, it will lead to a different
interpretation and an update of the token.

if the next non-space character(s) is/are:

* another lret      --> interpret as paragraph break (double line skip)
* two -,* or _      --> a hrule that will need to be validated later
* one *, +, -, etc. --> an item candidate
* |                 --> table row candidate
* >                 --> a blockquote (startswith >).

We disambiguate the different cases based on the **two** characters after the
whitespaces of the line return (the line return token captures `\n[ \t]*`).
"""
function process_line_return!(
            b::Vector{Block},
            tv::SubVector{Token},
            i::Int
        )::Nothing

    t = tv[i]
    # start of string (SOS) is a "virtual" line return.
    if t.name == :SOS
        c = [first(t.ss), next_chars(t, 1)...]
    else
        c = next_chars(t, 2)
    end

    if isempty(c) || c[1] ∈ ('\n', EOS)
        # P_BREAK; if there's not two chars beyond `c` will be empty
        # otherwise if there's `\n` or `EOS` then it's a line skip
        push!(b, Block(:P_BREAK, t.ss))

    # ------------------------------------------------------------------------
    # Hrules
    # NOTE the line MUST start with a triple followed only by
    # the same character, whitespaces and the eventual line return.
    elseif c[1] == c[2] == '-'
        _hrule!(b, t, HR1_PAT)

    elseif c[1] == c[2] == '_'
        _hrule!(b, t, HR2_PAT)

    elseif c[1] == c[2] == '*'
        _hrule!(b, t, HR3_PAT)

    # ------------------------------------------------------------------------
    # List items
    # NOTE for an item candidate, the candidate might not capture
    # the full item if the full item is on several lines, this has to
    # be post-processed when assembling ITEM_x_CAND into lists.
    elseif c[1] in ('+', '-', '*') && c[2] in (' ', '\t')
        cand = until_next_line_return(t)
        ps   = parent_string(cand)
        push!(b, Block(:ITEM_U_CAND, subs(ps, from(t), to(cand))))

    elseif c[1] ∈ NUM_CHAR && c[2] in vcat(NUM_CHAR, ['.', ')'])
        cand = until_next_line_return(t)
        if match(OL_ITEM_PAT, cand) !== nothing
            ps   = parent_string(cand)
            push!(b, Block(:ITEM_O_CAND, subs(ps, from(t), to(cand))))
        end

    # ------------------------------------------------------------------------
    # Table Rows
    # NOTE we're stricter here than usual GFM, every row must start and end
    # with a pipe, every row must be on a single line.
    elseif c[1] == '|'
        # TABLE_ROW_CAND
        cand = until_next_line_return(t)
        if strip(cand)[end] == '|'
            ps = parent_string(cand)
            push!(b, Block(:TABLE_ROW_CAND, subs(ps, from(t), to(cand))))
        end

    # ------------------------------------------------------------------------
    # Blockquote
    elseif c[1] == '>'
        # Blockquote
        cand = until_next_line_return(t)
        ps   = parent_string(cand)
        push!(b, Block(:BLOCKQUOTE_LINE, subs(ps, from(t), to(cand))))
    end
    return
end

"""
    _hrule!(blocks, token, regex)

Helper function to match and process a hrule.
"""
function _hrule!(b, t, r)
    cand  = until_next_line_return(t)
    check = match(r, cand)
    ps    = parent_string(cand)
    isnothing(check) || push!(b, Block(:HRULE, subs(ps, from(t), to(cand))))
    return
end


"""
    form_links!(blocks)

Here we catch the following:

    * [A]     LINK_A   for <a href="ref(A)">html(A)</a>
    * [A][B]  LINK_AR  for <a href="ref(B)">html(A)</a>
    * [A](B)  LINK_AB  for <a href="escape(B)">html(A)</a>
    * ![A]    IMG_A    <img src="ref(A)" alt="esc(A)" />
    * ![A](B) IMG_AB   <img src="escape(B)" alt="esc(A)" />
    * [A]: B  REF      (--> aggregate B, will need to distinguish later)

where 'A' is necessarily non empty, 'B' may be empty.

Note: currently we DO NOT support links with titles such as the following out
of simplicity:

* [A]: B C
* [A](B C)

this allows to not have to check whether B is a link and C is text. If the
user wants links with titles, they should create a command for it. We also do
not support link destinations between <...>.

Note: in the case of a LINK_A, we check around if the previous non whitespace
character and the next non whitespace character don't happen to be } {. In
that specific case, the link is
"""
function form_links!(
            blocks::Vector{Block}
        )::Nothing
    
    isempty(blocks) && return
    nblocks = length(blocks)
    remove  = Int[]
    i       = 1
    nb      = blocks[i]
    ps      = parent_string(nb)

    while i < nblocks
        b  = nb
        nb = blocks[i+1]

        if b.name == :SQ_BRACKETS
            pchar = previous_chars(b)
            nchar = next_chars(b)

            # NOTE: ![]: --> ![] takes precedence.
            # img: is it preceded by '!'?
            # ref: is it followed by ':'?
            # lnk: is the next char '('
            img = false
            if !isempty(pchar)
                img = pchar[1] == '!'
            end
            ref = false
            lab = false
            lar = false
            if !isempty(nchar)
                ref = !img && nchar[1] == ':'
                lab = nchar[1] == '(' && nb.name == :BRACKETS
                lar = nchar[1] == '[' && nb.name == :SQ_BRACKETS
            end
            lnk = lab | lar

            # ref ==> REF, stop
            #
            # img  & !lnk => IMG_A
            # img  & lab  => IMG_AB
            # img  & lar  => IMG_AR
            # !img & !lnk => LINK_A
            # !img & lab  => LINK_AB
            # !img & lar  => LINK_AR

            if ref
                # [...]: block
                # check if the block is at the start of line, otherwise discard
                ss = until_previous_line_return(b)
                if isempty(strip(ss))
                    blocks[i] = Block(:REF, subs(ps, from(b), next_index(b)))
                else
                    push!(remove, i)
                end
            else
                if img
                    if !lnk
                        blocks[i] = Block(:IMG_A, subs(ps, prev_index(b), to(b)))
                    elseif lab
                        blocks[i] = Block(:IMG_AB, subs(ps, prev_index(b), to(nb)))
                        push!(remove, i+1)
                    else
                        blocks[i] = Block(:IMG_AR, subs(ps, prev_index(b), to(nb)))
                        push!(remove, i+1)
                    end
                else
                    if !lnk
                        blocks[i] = Block(:LINK_A, subs(ps, from(b), to(b)))
                    elseif lab
                        blocks[i] = Block(:LINK_AB, subs(ps, from(b), to(nb)))
                        push!(remove, i+1)
                    else
                        blocks[i] = Block(:LINK_AR, subs(ps, from(b), to(nb)))
                        push!(remove, i+1)
                    end
                end
            end
        end
        i += 1
    end

    # check if the last block is maybe a standalone `(!)[...](:)`.
    i = nblocks
    b = blocks[i]
    if i ∉ remove && b.name == :SQ_BRACKETS
        pchar = previous_chars(b)
        nchar = next_chars(b)
        if isempty(pchar)
            img = false
        else
            img = pchar[1] == '!'
        end
        if isempty(nchar)
            ref = false
        else
            ref = !img && nchar[1] == ':'
        end

        if ref
            ss = until_previous_line_return(b)
            if isempty(strip(ss))
                blocks[i] = Block(:REF, subs(ps, from(b), next_index(b)))
            else
                push!(remove, i)
            end
        elseif img
            blocks[i] = Block(:IMG_A, subs(ps, prev_index(b), to(b)))
        else
            blocks[i] = Block(:LINK_A, subs(ps, from(b), to(b)))
        end
    end
    deleteat!(blocks, remove)
    return
end


"""
    remove_inner!(blocks)

Remove blocks which are part of larger blocks (these will get re-formed and
re-processed at an ulterior step).
"""
function remove_inner!(
            blocks::Vector{Block}
        )::Nothing

    isempty(blocks) && return
    n_blocks  = length(blocks)
    is_active = ones(Bool, n_blocks)
    @inbounds for i in eachindex(blocks)
        is_active[i] || continue
        to_current = to(blocks[i])
        next_outer = n_blocks + 1
        for j in i+1:n_blocks
            bj = blocks[j]
            fj, tj = from(bj), to(bj)
            # there can be a one-character block exactly at the end
            # of the span, see misc_fixes dec9'22.
            if (fj > to_current) || (fj == to_current && tj > fj)
                next_outer = j
                break
            end
        end
        is_active[i+1:next_outer-1] .= false
    end
    deleteat!(blocks, [i for i in eachindex(blocks) if !is_active[i]])
    return
end


"""
    form_dbb!(blocks)

Find CU_BRACKETS blocks that start with `{{` and and with `}}` and mark them as
:DBB.
"""
function form_dbb!(b::Vector{Block})
    @inbounds for i in eachindex(b)
        b[i].name === :CU_BRACKETS || continue
        ss = b[i].ss
        (startswith(ss, "{{") && endswith(ss, "}}")) || continue

        open  = Token(:DBB_OPEN, subs(ss, 1:2))
        li    = lastindex(ss)
        close = Token(:DBB_CLOSE, subs(ss, li-1:li))
        it    = @view b[i].inner_tokens[2:end-1]
        b[i]  = Block(:DBB, open => close, it)
    end
end


function _find_env_blocks!(
            blocks::Vector{Block},
            tokens::SubVector{Token},
            is_active::Vector{Bool}
        )::Nothing

    isempty(blocks) && return

    envs     = Block[]
    discard  = Int[]
    i        = 1
    n_blocks = length(blocks)
    curb     = blocks[i]

    @inbounds while i < n_blocks
        nxtb = blocks[i+1]
        j    = i

        if curb.name == :LX_BEGIN
            # Note that the next block here is **necessarily** a CU_BRACKETS
            # indeed, LX_BEGIN is detected only if it's followed by `{` which
            # at this point, must have been closed (otherwise an error would
            # have been formed at block creation time).
            env_name = content(nxtb) |> strip

            # look ahead trying to find the proper closing \end{...}
            open_depth    = 1
            closing_index = -1
            probe         = nxtb
            j            += 1

            while j < n_blocks && open_depth != 0
                cand  = probe.name
                probe = blocks[j + 1]

                closer = (cand == :LX_END) &&
                         (probe.name == :CU_BRACKETS) &&
                         (env_name == content(probe) |> strip)

                opener = (cand == :LX_BEGIN) &&
                         (probe.name == :CU_BRACKETS) &&
                         (env_name == content(probe) |> strip)

                if closer
                    open_depth -= 1
                elseif opener
                    open_depth += 1
                end

                j += 1
            end
            open_depth   != 0 && env_not_closed_exception(curb, env_name)
            closing_index = j

            # tokens in span (there is always at least LX_BEGIN and END)
            env_from = from(curb)
            env_to   = to(blocks[closing_index])

            toks_1   = findfirst(t -> from(t) >= env_from, tokens)
            toks_n   = findlast(t -> to(t) <= env_to, tokens)
            toks_r   = toks_1:toks_n

            # deactivate them all
            is_active[toks_r] .= false

            # mark all blocks in the range as to be discarded
            append!(discard, i:closing_index)

            # keep track of the block and its tokens
            b = Block(
                Symbol("ENV_$(env_name)"),
                tokens[toks_1] => tokens[toks_n],
                @view tokens[toks_r]
            )
            push!(envs, b)
        end

        curb = nxtb
        i    = j + 1
    end
    # discard all blocks within the env
    deleteat!(blocks, discard)
    append!(blocks, envs)
    return
end
