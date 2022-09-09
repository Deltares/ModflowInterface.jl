# ModflowInterface.jl

Call [Modflow 6](https://www.usgs.gov/software/modflow-6-usgs-modular-hydrologic-model), the
USGS Modular Hydrologic Model, from [Julia](https://julialang.org/).

This is a port of [xmipy](https://github.com/Deltares/xmipy).

This package relies on
[Modflow6_jll.jl](https://github.com/JuliaBinaryWrappers/Modflow6_jll.jl) to provide
binaries of Modflow 6, and implements the
[BasicModelInterface.jl](https://github.com/Deltares/BasicModelInterface.jl) with calls to
the Modflow 6 shared library.

Note that it is possible to crash julia if methods are called wrongly or in the wrong order.
For instance `initialize` is safe since we track the initialization status in the
`ModflowModel` struct, but `prepare_time_step` will crash julia if run twice.

See
[examples/mf6lake.jl](https://github.com/Deltares/ModflowInterface.jl/blob/main/examples/mf6lake.jl)
for a usage example.
