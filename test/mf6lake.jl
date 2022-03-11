using Test
using Statistics
import ModflowInterface as MF
import BasicModelInterface as BMI

mf6lake_dir = abspath(@__DIR__, "../examples/mf6lake")
cd(mf6lake_dir)

mf6_modelname = "MF6LAKE"

m = BMI.initialize(MF.ModflowModel)

@test m isa MF.ModflowModel
@test m === MF.ModflowModel()

@test BMI.get_component_name(m) === "MODFLOW 6"

MF.prepare_time_step(m, 0.0)
MF.prepare_solve(m, 1)

headtag = MF.get_var_address(m, "X", mf6_modelname)
@test headtag === "MF6LAKE/X"
head = BMI.get_value_ptr(m, headtag)

@testset "initial condition" begin
    @test head isa Vector{Float64}
    @test length(head) == 102010
    @test unique(head) == [100.0, 0.0, 90.0]
end

function solve_to_convergence(model)
    converged = false
    iteration = 0
    while !converged
        converged = MF.solve(model, 1)
        iteration += 1
    end
    return iteration
end

iteration = solve_to_convergence(m)
@test iteration == 3

@test mean(head) ≈ 99.88290434027091
@test minimum(head) ≈ 90.0
@test maximum(head) ≈ 100.0 atol=1e-4

@test BMI.get_start_time(m) == 1.0
@test BMI.get_current_time(m) == 1.0
@test BMI.get_end_time(m) == 1.0

@testset "variables" begin
    n = BMI.get_input_item_count(m)
    @test BMI.get_input_item_count(m) == n
    @test BMI.get_output_item_count(m) == n
    invars = BMI.get_input_var_names(m)
    outvars = BMI.get_output_var_names(m)
    @test invars == outvars
    @test outvars isa Vector{String}
    @test length(outvars) == n
    @test "TDIS/NPER" in outvars
end

@testset "cglobal" begin
    @test MF.BMI_LENCOMPONENTNAME == 256
    @test MF.BMI_LENVARADDRESS == 51
    @test MF.BMI_LENVARTYPE == 51
    @test MF.BMI_LENGRIDTYPE == 17
    @test MF.BMI_LENERRMESSAGE == 1025
end

# destroys the model, and deallocates the head array, don't use it anymore after this
# if you need data to be separate from modflow, copy it, which is what `BMI.get_value` does
head_copy = BMI.get_value(m, headtag)
@test head == head_copy
BMI.finalize(m)

# can still be accessed
@test head_copy[1] == 100.0
