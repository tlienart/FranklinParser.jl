@testset "math partitioning" begin
    s = raw"A $B \com{C}$ D"
    parts = FP.default_md_partition(s)
    mathb = parts[2]
    @test mathb.name == :MATH_A
    parts = FP.default_math_partition(FP.content(mathb))
    @test parts[1].name == :TEXT
    @test parts[2].name == :LX_COMMAND
    @test parts[3].name == :LXB
    @test FP.content(parts[1]) == "B "
    @test FP.content(parts[3]) == "C"
end
