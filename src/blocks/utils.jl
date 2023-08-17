"""
    get_classes(divblock)

Return the classe(s) of a div block. E.g. `@@c1,c2` will return `"c1 c2"` so
that it can be injected in a `<div class="..."`.
"""
function get_classes(b::Block)::String
    return replace(subs(b.open.ss, 3:lastindex(b.open.ss)), "," => " ")
end

"""
    prepare_md_text(blocks)

For a text block, replace the remaining tokens for special characters.
"""
function prepare_md_text(
            b::Block;
            tohtml=true,
            tokenizer=default_md_tokenizer
        )::String

    c = b.ss

    inner_tokens = filter(t -> t.name ∉ MD_IGNORE, tokenizer(c))
    isempty(inner_tokens) && return String(c)

    parent = parent_string(c)
    io     = IOBuffer()
    head   = from(c)
    for t in inner_tokens
        write(io, subs(parent, head, prev_index(t)))
        write(io, insert(t; tohtml))
        head = next_index(t)
    end
    write(io, subs(parent, head, to(c)))
    return String(take!(io))
end

"""
    insert(token)

For tokens representing special characters, insert the relevant string.
"""
function insert(t::Token; tohtml=true)::String
    stname = String(t.name)
    s = String(t.ss)  # safe default
    if t.name == :CHAR_HTML_ENTITY
        s = String(t.ss)
    elseif startswith(stname, "CHAR_") && tohtml # CHAR_*
        id = stname[6:end]
        s = "&#$(id);"
    elseif t.name == :CAND_EMOJI
        # check if it's a valid emoji
        s = get(emoji_symbols, "\\$(t.ss)", s)
    end
    tohtml || (s = replace(s, "&" => "\\&"))
    return s
end
