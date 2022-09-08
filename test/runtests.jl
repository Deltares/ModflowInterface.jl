using Test
using ModflowInterface
import ModflowInterface as MF
import BasicModelInterface as BMI
import Aqua

@testset "ModflowInterface" begin
    include("mf6lake.jl")
    Aqua.test_all(ModflowInterface)
end
