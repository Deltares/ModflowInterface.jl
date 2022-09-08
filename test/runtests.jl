using Test
using ModflowInterface
import ModflowInterface as MF
import BasicModelInterface as BMI

@testset "ModflowInterface" begin
    include("mf6lake.jl")
end
