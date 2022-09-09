using Test
using Statistics
using ModflowInterface
import ModflowInterface as MF
import BasicModelInterface as BMI

modeldir = normpath(@__DIR__, "../examples/mf6lake")
mf6_modelname = "MF6LAKE"

m = ModflowModel(modeldir)

@test string(m) == "ModflowModel(\"mf6lake\", uninitialized)\n"

@test m.state == MF.uninitialized
BMI.initialize(m)
@test m.state == MF.initialized
BMI.initialize(m)
@test m isa ModflowModel

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

function solve_to_convergence(m::ModflowModel)
    converged = false
    iteration = 0
    while !converged
        converged = MF.solve(m)
        iteration += 1
    end
    return iteration
end

iteration = solve_to_convergence(m)
@test iteration == 3

@test mean(head) ≈ 99.88290434027091f0
@test minimum(head) ≈ 90.0f0
@test maximum(head) ≈ 100.0f0

@test BMI.get_start_time(m) == 1.0
@test BMI.get_current_time(m) == 1.0
@test BMI.get_end_time(m) == 1.0

@testset "variables" begin
    n_item = BMI.get_input_item_count(m)
    @test BMI.get_input_item_count(m) == n_item
    @test BMI.get_output_item_count(m) == n_item
    invars = BMI.get_input_var_names(m)
    outvars = BMI.get_output_var_names(m)
    @test invars == outvars
    @test outvars isa Vector{String}
    @test length(outvars) == n_item
    @test "TDIS/NPER" in outvars

    n_cell = length(head)
    @test n_cell == 102010
    @test BMI.get_var_itemsize(m, headtag) == 8
    @test BMI.get_var_nbytes(m, headtag) == 8 * n_cell

    # copy data into pre allocated dest array
    dest = zero(head)
    BMI.get_value(m, headtag, dest)
    # not the same memory, but same values
    @test dest !== head
    @test dest == head

    # can also copy to a lower precision dest array
    dest = zeros(Float32, size(head))
    BMI.get_value(m, headtag, dest)
    @test dest != head
    @test dest ≈ head

    var_type = BMI.get_var_type(m, headtag)
    @test BMI.get_var_type(m, headtag) == "DOUBLE ($n_cell)"
    @test MF.parse_type(var_type) == Float64
    @test MF.get_var_rank(m, headtag) == 1
    @test MF.get_var_shape(m, headtag) === (102010,)
end

@testset "grids" begin
    grid = BMI.get_var_grid(m, headtag)
    @test grid === 1
    @test BMI.get_grid_rank(m, grid) == 3
    @test BMI.get_grid_size(m, grid) == 102010
    @test BMI.get_grid_type(m, grid) == "rectilinear"
    @test BMI.get_grid_shape(m, grid) === (101, 101, 10)
    @test BMI.get_grid_x(m, grid, zeros(101)) == 0:1:100
    @test BMI.get_grid_y(m, grid, zeros(101)) == 101:-1:1
    @test BMI.get_grid_node_count(m, grid) == 0
    @test BMI.get_grid_face_count(m, grid) == 0
end

@testset "cglobal" begin
    @test MF.BMI_LENCOMPONENTNAME == 256
    @test MF.BMI_LENVARADDRESS == 51
    @test MF.BMI_LENVARTYPE == 51
    @test MF.BMI_LENGRIDTYPE == 17
    @test MF.BMI_LENERRMESSAGE == 1025
end

@testset "utils" begin
    @test MF.parse_type("Double (3)") == Float64
    @test MF.parse_type("Float (3)") == Float32
    @test MF.parse_type("INT (3)") == Int32
    @test_throws ErrorException MF.parse_type("DateTime")

    @test MF.trimmed_string(UInt8[]) == ""
    @test MF.trimmed_string(UInt8[0]) == ""
    @test MF.trimmed_string(UInt8[0, 65]) == ""
    @test MF.trimmed_string(UInt8[65]) == "A"
    @test MF.trimmed_string(UInt8[65, 66]) == "AB"
    @test MF.trimmed_string(UInt8[65, 66, 0]) == "AB"
    @test MF.trimmed_string(UInt8[65, 66, 0, 68]) == "AB"
end

# destroys the model, and deallocates the head array, don't use it anymore after this
# if you need data to be separate from modflow, copy it, which is what `BMI.get_value` does
head_copy = BMI.get_value(m, headtag)
@test head !== head_copy
@test head == head_copy

@test m.state == MF.initialized
BMI.finalize(m)
@test m.state == MF.uninitialized
BMI.finalize(m)

# can still be accessed
@test head_copy[1] == 100.0
