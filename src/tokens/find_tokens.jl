"""
    find_tokens(s, templates)

Go through a text left to right, one (valid) char at the time and keep track
of sequences of chars that match specific tokens. The list of tokens found is
returned.

**Arguments**

* `s`: the initial text
* `templates`: dictionary of possible tokens
"""
function find_tokens(
            s::SS,
            templates::LittleDict{Char, Vector{Pair{TokenFinder, Symbol}}}
            )::Vector{Token}

    tokens = Token[]
    isempty(s) && return tokens

    # start with a LINERETURN to allow proper treatment of special lines
    # such as blockquote lines or items that could be right at the start
    # see "process_line_return!"
    push!(tokens, Token(:LINE_RETURN, subs(s, 1:0)))

    head_idx = firstindex(s)
    end_idx  = lastindex(s)

    @inbounds while head_idx <= end_idx
        head_char = s[head_idx]
        if haskey(templates, head_char)
            # Look at each possible finder sequentially
            for (tf, case) in templates[head_char]
                # ------------------------------------
                # exact match of a given fixed pattern
                # --> we form a candidate substring with a fixed number of characters
                # and try to see if it matches a fixed rule. Possibly the substring
                # contains an extra character for rules where we must match only when
                # the next character is or isn't something.
                if (tf.steps >= 0)
                    tail_idx = nextind(s, head_idx, tf.steps)
                    at_eos   = false
                    if tail_idx == nextind(s, end_idx)
                        tail_idx = end_idx
                        at_eos = true
                    end
                    (tail_idx > end_idx) && continue

                    # if there is space, consider the substring and verify whether it matches
                    candidate       = subs(s, head_idx, tail_idx)
                    matches, offset = fixed_lookahead(tf, candidate, at_eos)

                    # if it matches, form the token and break the for loop: no need to check
                    # other cases.
                    if matches
                        head_idx = prevind(s, tail_idx, offset)
                        token    = Token(case, chop(candidate, tail=offset))
                        push!(tokens, token)
                        break
                    end
                # -----------------------------------------
                # rule-based match: greedy catch until fail
                # --> we gradually form a candidate substring of increasing length until
                # the next character doesn't meet the condition.
                else
                    nchars    = 1
                    tail_idx  = head_idx
                    probe_idx = nextind(s, head_idx)
                    probe_idx > end_idx && continue
                    probe_char::Char = s[probe_idx]

                    # while the condition holds, consume get next char
                    while greedy_lookahead(tf, nchars, probe_char)
                        tail_idx   = probe_idx
                        probe_idx  = nextind(s, probe_idx)
                        (probe_idx > end_idx) && break
                        probe_char = s[probe_idx]
                        nchars    += 1
                    end

                    # if we took in at least a char, validate then form the token
                    if tail_idx > head_idx
                        candidate = subs(s, head_idx, tail_idx)
                        # check if the backward validator is happy otherwise skip
                        check(tf, candidate) || continue
                        # if it's happy move head and push the token
                        head_idx = tail_idx
                        token = Token(case, candidate)
                        push!(tokens, token)
                        break
                    end
                end
            end
        end
        head_idx = nextind(s, head_idx)
    end

    # finally push the end token on the stack observe that it can overlap a token
    # that would be at the end of the string.
    eos = Token(:EOS, subs(s, end_idx))
    push!(tokens, eos)

    # discard header tokens that are not at the start of a line or
    # only preceded by whitespaces
    process_header_tokens!(tokens)
    # validate or drop emphasis tokens
    process_emphasis_tokens!(tokens)
    # discard autolink_close tokens which are preceded by a space
    process_autolink_close_tokens!(tokens)
    return tokens
end

@inline find_tokens(s::String, templates) = find_tokens(subs(s), templates)


"""
    process_header_tokens!(tokens)

Discard header tokens that are not at the start of a line or only preceded by
whitespaces.
"""
function process_header_tokens!(tokens::Vector{Token})
    remove = Int[]
    @inbounds for (i, t) in enumerate(tokens)
        if t.name in MD_HEADERS
            ss = until_previous_line_return(t)
            isempty(strip(ss)) || push!(remove, i)
        end
    end
    deleteat!(tokens, remove)
end


"""
    process_emphasis_tokens!(tokens)

Process emphasis token candidates and either take them or discard them if
they don't look correct.

`xTy` with token `T` is invalid if both `x` and `y` are space characters.
"""
function process_emphasis_tokens!(tokens::Vector{Token})
    isempty(tokens) && return
    remove = Int[]
    ps = parent_string(first(tokens))
    N  = lastindex(ps)
    @inbounds for (i, t) in enumerate(tokens)

        if t.name in (:EM, :STRONG, :EM_STRONG)
            prev_char = previous_chars(t)
            next_char = next_chars(t)
            # if the token is surrounded by spaces, discard it
            bad = !isempty(prev_char) && first(prev_char) in (' ', '\t') &&
                  !isempty(next_char) && first(next_char) in (' ', '\t')
            bad && push!(remove, i)
        end
    end
    deleteat!(tokens, remove)
    return
end

"""
    process_autolink_close_tokens!(tokens)

Discard :AUTOLINK_CLOSE that are not preceded by an ALPHA_LATIN character.
"""
function process_autolink_close_tokens!(tokens::Vector{Token})
    isempty(tokens) && return
    remove = Int[]
    @inbounds for (i, t) in enumerate(tokens)
        t.name == :AUTOLINK_CLOSE || continue
        c = previous_chars(t)
        (isempty(c) || first(c) ∉ ALPHA_LATIN) && push!(remove, i)
    end
    deleteat!(tokens, remove)
    return
end
