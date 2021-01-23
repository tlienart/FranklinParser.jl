"""
$(SIGNATURES)

Return the classe(s) of a div block. E.g. `@@c1,c2` will return `"c1 c2"` so that it
can be injected in a `<div class="..."`.
"""
function get_classes(b::Block)::String
    return replace(subs(b.open.ss, 3:lastindex(b.open.ss)), "," => " ")
end

"""
$(SIGNATURES)

For a text block, replace the remaining tokens for special characters.
"""
function prepare_text(b::Block)::String
    # in a text block the substring is the content
    c = b.ss
    # if there's no tokens over that content, return
    isempty(b.inner_tokens) && return String(c)
    # otherwise inject as appropriate
    parent = parent_string(c)
    io = IOBuffer()
    head = from(c)
    for t in b.inner_tokens
        t.name in MD_IGNORE && continue
        write(io, subs(parent, head, previous_index(t)))
        write(io, insert(t))
        head = next_index(t)
    end
    write(io, subs(parent, head, to(c)))
    return String(take!(io))
end

"""
$(SIGNATURES)

For tokens representing special characters, insert the relevant string.
"""
function insert(t::Token)::String
    s = ""
    if t.name == :LINEBREAK
        s = "~~~<br>~~~"
    elseif t.name == :HRULE
        s = "~~~<hr>~~~"
    elseif t.name == :CHAR_HTML_ENTITY
        s = String(t.ss)
    else # CHAR_*
        id = String(t.name)[6:end]
        s = "&#$(id);"
    end
    return s
end
