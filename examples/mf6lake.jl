using ModflowInterface
import ModflowInterface as MF
import BasicModelInterface as BMI

mf6_modelname = "MF6LAKE"
cd("examples/mf6lake")

m = BMI.initialize(MF.ModflowModel)
BMI.get_component_name(m)  # -> "MODFLOW 6"

##

MF.prepare_time_step(m, 0.0)
MF.prepare_solve(m, 1)

##

function solve_to_convergence(model::ModflowModel)
    converged = false
    iteration = 0
    while !converged
        converged = MF.solve(model, 1)
        iteration += 1
    end
    return iteration
end

solve_to_convergence(m)  # -> 3

##

headtag = MF.get_var_address(m, "X", mf6_modelname)  # -> "MF6LAKE/X"
head = BMI.get_value_ptr(m, headtag)  # -> 102010-element Vector{Float64}

##

# Note, this de-allocates the head array!
BMI.finalize(m)
