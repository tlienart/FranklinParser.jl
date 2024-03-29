const ARGS_TOKENS = Dict{Char, Vector{Pair{TokenFinder, Symbol}}}(
    '\\' => [
        forward_match("\\\"") => :SKIP,
    ],
    '"' => [
        forward_match("\"", ['"'], false)     => :SINGLE_QUOTE,
        forward_match("\"\"\"", ['"'], false) => :TRIPLE_QUOTE
    ]
)
