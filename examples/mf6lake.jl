import BasicModelInterface as BMI
import ModflowInterface as MF

mf6_modelname = "MF6LAKE"
cd("examples/mf6lake")

m = BMI.initialize(MF.ModflowModel)
BMI.get_component_name(m)

##

MF.prepare_time_step(m, 0.0)
MF.prepare_solve(m, 1)

##

function solve_to_convergence(model)
    converged = false
    iteration = 0
    while !converged
        @show iteration
        converged = MF.solve(model, 1)
        iteration += 1
    end
    println("converged")
    return iteration
end

solve_to_convergence(m)

##

headtag = MF.get_var_address(m, "X", mf6_modelname)
head = BMI.get_value_ptr(m, headtag)

##

# Note, this de-allocates the head array!
BMI.finalize(m)
