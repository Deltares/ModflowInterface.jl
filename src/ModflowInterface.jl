module ModflowInterface

using Printf
using Modflow6_jll
import BasicModelInterface as BMI

export ModflowModel

const BMI_LENCOMPONENTNAME = unsafe_load(cglobal((:BMI_LENCOMPONENTNAME, libmf6), Cint))
const BMI_LENVARADDRESS = unsafe_load(cglobal((:BMI_LENVARADDRESS, libmf6), Cint))
const BMI_LENVARTYPE = unsafe_load(cglobal((:BMI_LENVARTYPE, libmf6), Cint))
const BMI_LENGRIDTYPE = unsafe_load(cglobal((:BMI_LENGRIDTYPE, libmf6), Cint))
const BMI_LENERRMESSAGE = unsafe_load(cglobal((:BMI_LENERRMESSAGE, libmf6), Cint))

@enum Status begin
    success = 0
    failure = 1
end

@enum State begin
    uninitialized = 1
    initialized = 2
end

mutable struct ModflowModel
    # Modflow requires the current directory to be the one where mfsim.nam is placed.
    # We store this as `working_directory` such that we can go there when needed.
    working_directory::String
    state::State
end

function ModflowModel(path::String)
    working_directory = if isdir(path)
        namfile = normpath(path, "mfsim.nam")
        isfile(namfile) || error("No mfsim.nam file found in $path")
        path
    elseif isfile(path)
        if basename(path) == "mfsim.nam"
            dirname(path)
        else
            error("Path should point to mfsim.nam or its directory, got: $path")
        end
    else
        error("Path does not contain a Modflow model: $path")
    end
    ModflowModel(normpath(working_directory), uninitialized)
end

function Base.show(io::IO, m::ModflowModel)
    println(io, "ModflowModel(", repr(basename(m.working_directory)), ", ", m.state, ')')
end

# Utilities

function trimmed_string(buffer)::String
    i = findfirst(iszero, buffer)
    if i === nothing
        return String(buffer)
    else
        bufview = view(buffer, 1:(i-1))
        return String(bufview)
    end
end

function parse_type(type::String)::DataType
    type = lowercase(type)
    return if startswith(type, "double")
        Float64
    elseif startswith(type, "float")
        Float32
    elseif startswith(type, "int")
        Int32
    else
        error("unsupported type")
    end
end

function execute_function(m::ModflowModel, f::Function, args...)
    result = f(args...)
    if result != success
        try
            error_message = get_last_bmi_error(m)
            component_name = get_component_name(m)
            @printf("--- Kernel message (%s) --- \n=> %s", component_name, error_message)
        catch
            println("--- Kernel Message --- \n=> no details ...")
        end
        error("BMI exception")
    end
    return m
end

# BMI proper

function BMI.initialize(m::ModflowModel)
    if m.state == uninitialized
        cd(m.working_directory) do
            @ccall libmf6.initialize()::Cint
        end
        m.state = initialized
    else
        BMI.finalize(m)
        BMI.initialize(m)
    end
    return m
end

# better to user the ::ModflowModel method since it is safer
function BMI.initialize(::Type{ModflowModel})
    @ccall libmf6.initialize()::Cint
    return ModflowModel(pwd(), initialized)
end

function BMI.finalize(m::ModflowModel)
    if m.state == initialized
        cd(m.working_directory) do
            @ccall libmf6.finalize()::Cint
        end
        m.state = uninitialized
    end
    return m
end

function BMI.update(m::ModflowModel)
    cd(m.working_directory) do
        @ccall libmf6.update()::Cint
    end
    return m
end

function BMI.get_start_time(::ModflowModel)::Float64
    start_time = Ref{Float64}(0)
    @ccall libmf6.get_current_time(start_time::Ptr{Float64})::Cint
    return start_time[]
end

function BMI.get_current_time(::ModflowModel)::Float64
    current_time = Ref{Float64}(0)
    @ccall libmf6.get_current_time(current_time::Ptr{Float64})::Cint
    return current_time[]
end

function BMI.get_end_time(::ModflowModel)::Float64
    end_time = Ref{Float64}(0)
    @ccall libmf6.get_end_time(end_time::Ptr{Float64})::Cint
    return end_time[]
end

function BMI.get_time_step(::ModflowModel)::Float64
    time_step = Ref{Float64}(0)
    @ccall libmf6.get_end_time(time_step::Ptr{Float64})::Cint
    return time_step[]
end

"Returns the string `MODFLOW 6`"
function BMI.get_component_name(::ModflowModel)::String
    buffer = zeros(UInt8, BMI_LENCOMPONENTNAME)
    @ccall libmf6.get_component_name(buffer::Ptr{UInt8})::Cint
    return trimmed_string(buffer)
end

function BMI.get_input_item_count(::ModflowModel)::Int
    count = Ref{Cint}(0)
    @ccall libmf6.get_input_item_count(count::Ptr{Cint})::Cint
    return Int(count[])
end

function BMI.get_output_item_count(::ModflowModel)::Int
    count = Ref{Cint}(0)
    @ccall libmf6.get_output_item_count(count::Ptr{Cint})::Cint
    return Int(count[])
end

function BMI.get_input_var_names(m::ModflowModel)::Vector{String}
    shape = (BMI_LENVARADDRESS, BMI.get_input_item_count(m))
    buffer = zeros(UInt8, shape)
    @ccall libmf6.get_input_var_names(buffer::Ptr{UInt8})::Cint
    return [trimmed_string(part) for part in eachcol(buffer)]
end

function BMI.get_output_var_names(m::ModflowModel)::Vector{String}
    shape = (BMI_LENVARADDRESS, BMI.get_output_item_count(m))
    buffer = zeros(UInt8, shape)
    @ccall libmf6.get_output_var_names(buffer::Ptr{UInt8})::Cint
    return [trimmed_string(part) for part in eachcol(buffer)]
end

function BMI.get_var_grid(::ModflowModel, name::String)::Int
    grid = Ref{Cint}(0)
    @ccall libmf6.get_var_grid(name::Ptr{UInt8}, grid::Ptr{Cint})::Cint
    return Int(grid[])
end

function BMI.get_var_type(::ModflowModel, name::String)::String
    buffer = zeros(UInt8, BMI_LENVARTYPE)
    @ccall libmf6.get_var_type(name::Ptr{UInt8}, buffer::Ptr{UInt8})::Cint
    return trimmed_string(buffer)
end

function BMI.get_var_itemsize(::ModflowModel, name::String)::Int
    item_size = Ref{Cint}(0)
    @ccall libmf6.get_var_itemsize(name::Ptr{UInt8}, item_size::Ptr{Cint})::Cint
    return Int(item_size[])
end

function BMI.get_var_nbytes(::ModflowModel, name::String)::Int
    nbytes = Ref{Cint}(0)
    @ccall libmf6.get_var_nbytes(name::Ptr{UInt8}, nbytes::Ptr{Cint})::Cint
    return Int(nbytes[])
end

function BMI.get_value(m::ModflowModel, name::String)
    return copy(BMI.get_value_ptr(m, name))
end

function BMI.get_value(m::ModflowModel, name::String, dest::Array{T}) where {T<:Real}
    data = BMI.get_value_ptr(m, name)
    return copyto!(dest, data)
end

function BMI.get_value_ptr(m::ModflowModel, name::String)
    type = parse_type(BMI.get_var_type(m, name))
    shape = get_var_shape(m, name)
    ptr = Ref(Ptr{type}(0))
    if type == Int32
        @ccall libmf6.get_value_ptr_int(name::Ptr{UInt8}, ptr::Ptr{Cvoid})::Cint
    elseif type == Float32
        @ccall libmf6.get_value_ptr_float(name::Ptr{UInt8}, ptr::Ptr{Cvoid})::Cint
    elseif type == Float64
        @ccall libmf6.get_value_ptr_double(name::Ptr{UInt8}, ptr::Ptr{Cvoid})::Cint
    else
        error("unsupported type")
    end

    values = unsafe_wrap(Array, ptr[], shape)
    return values
end

function BMI.get_grid_rank(::ModflowModel, grid::Integer)::Int
    grid_rank = Ref{Cint}(0)
    c_grid = Ref{Cint}(grid)
    @ccall libmf6.get_grid_rank(c_grid::Ptr{Cint}, grid_rank::Ptr{Cint})::Cint
    return Int(grid_rank[])
end

function BMI.get_grid_size(::ModflowModel, grid::Integer)::Int
    grid_size = Ref{Cint}(0)
    c_grid = Ref{Cint}(grid)
    @ccall libmf6.get_grid_size(c_grid::Ptr{Cint}, grid_size::Ptr{Cint})::Cint
    return Int(grid_size[])
end

function BMI.get_grid_type(::ModflowModel, grid::Integer)::String
    buffer = zeros(UInt8, BMI_LENGRIDTYPE)
    c_grid = Ref{Cint}(grid)
    @ccall libmf6.get_grid_type(c_grid::Ptr{Cint}, buffer::Ptr{UInt8})::Cint
    return trimmed_string(buffer)
end

function BMI.get_grid_shape(m::ModflowModel, grid::Integer)
    rank = BMI.get_grid_rank(m, grid)
    shape = zeros(Cint, rank)
    c_grid = Ref{Cint}(grid)
    @ccall libmf6.get_grid_shape(c_grid::Ptr{Cint}, shape::Ptr{Cint})::Cint
    # The BMI interface returns row major shape; Julia's memory layout is
    # column major, so we flip the shape around.
    return Tuple(Int(x) for x in reverse(shape))
end

function BMI.get_grid_x(::ModflowModel, grid::Integer, x::Vector{Float64})::Vector{Float64}
    c_grid = Ref{Cint}(grid)
    @ccall libmf6.get_grid_x(c_grid::Ptr{Cint}, x::Ptr{Float64})::Cint
    return x
end

function BMI.get_grid_y(::ModflowModel, grid::Integer, y::Vector{Float64})::Vector{Float64}
    c_grid = Ref{Cint}(grid)
    @ccall libmf6.get_grid_y(c_grid::Ptr{Cint}, y::Ptr{Float64})::Cint
    return y
end

function BMI.get_grid_node_count(::ModflowModel, grid::Integer)::Int
    grid_node_count = Ref{Cint}(0)
    c_grid = Ref{Cint}(grid)
    @ccall libmf6.get_grid_node_count(c_grid::Ptr{Cint}, grid_node_count::Ptr{Cint})::Cint
    return Int(grid_node_count[])
end

function BMI.get_grid_face_count(::ModflowModel, grid::Integer)::Int
    grid_face_count = Ref{Cint}(0)
    c_grid = Ref{Cint}(grid)
    @ccall libmf6.get_grid_face_count(c_grid::Ptr{Cint}, grid_face_count::Ptr{Cint})::Cint
    return Int(grid_face_count[])
end

function BMI.get_grid_face_nodes(
    ::ModflowModel,
    grid::Integer,
    face_nodes::Vector{Cint},
)::Vector{Cint}
    c_grid = Ref{Cint}(grid)
    @ccall libmf6.get_grid_face_nodes(c_grid::Ptr{Cint}, face_nodes::Ptr{Cint})::Cint
    return face_nodes
end

function BMI.get_grid_nodes_per_face(
    ::ModflowModel,
    grid::Integer,
    nodes_per_face::Vector{Cint},
)::Vector{Cint}
    c_grid = Ref{Cint}(grid)
    @ccall libmf6.get_grid_nodes_per_face(
        c_grid::Ptr{Cint},
        nodes_per_face::Ptr{Cint},
    )::Cint
    return nodes_per_face
end

# Strictly speaking not BMI

function get_last_bmi_error(::ModflowModel)
    buffer = zeros(UInt8, BMI_LENERRMESSAGE)
    @ccall libmf6.get_last_bmi_error(buffer::Ptr{UInt8})::Cint
    return trimmed_string(buffer)
end

function get_var_rank(::ModflowModel, name::String)
    rank = Ref(Cint(0))
    @ccall libmf6.get_var_rank(name::Ptr{UInt8}, rank::Ptr{Cint})::Cint
    return Integer(rank[])
end

function get_var_shape(m::ModflowModel, name::String)
    rank = get_var_rank(m, name)
    shape = Vector{Int32}(undef, rank)
    @ccall libmf6.get_var_shape(name::Ptr{UInt8}, shape::Ptr{Int32})::Cint
    # The BMI interface returns row major shape; Julia's memory layout is
    # column major, so we flip the shape around.
    return Tuple(Int(x) for x in reverse(shape))
end

# XMI

function prepare_time_step(m::ModflowModel, dt::Float64)
    timestep = Ref(dt)
    cd(m.working_directory) do
        @ccall libmf6.prepare_time_step(timestep::Ptr{Float64})::Cint
    end
    return m
end

function do_time_step(m::ModflowModel)
    cd(m.working_directory) do
        @ccall libmf6.do_time_step()::Cint
    end
    return m
end

function finalize_time_step(m::ModflowModel)
    cd(m.working_directory) do
        @ccall libmf6.finalize_time_step()::Cint
    end
    return m
end

function get_subcomponent_count(::ModflowModel)::Int
    count = Ref{Cint}(0)
    @ccall libmf6.get_subcomponent_count(count::Ptr{Cint})::Cint
    return Int(count[])
end

function prepare_solve(m::ModflowModel, component_id::Int = 1)
    id = Ref{Cint}(component_id)
    cd(m.working_directory) do
        @ccall libmf6.prepare_solve(id::Ptr{Cint})::Cint
    end
    return m
end

function solve(m::ModflowModel, component_id::Int = 1)::Bool
    id = Ref{Cint}(component_id)
    converged = Ref(false)
    cd(m.working_directory) do
        @ccall libmf6.solve(id::Ptr{Cint}, converged::Ptr{Bool})::Cint
    end
    return converged[]
end

function finalize_solve(m::ModflowModel, component_id::Int = 1)
    id = Ref{Cint}(component_id)
    cd(m.working_directory) do
        @ccall libmf6.finalize_solve(id::Ptr{Cint})::Cint
    end
    return m
end

function get_var_address(
    ::ModflowModel,
    var_name,
    component_name;
    subcomponent_name = "",
)::String
    v = uppercase(var_name)
    c = uppercase(component_name)
    s = uppercase(subcomponent_name)
    buffer = zeros(UInt8, BMI_LENVARADDRESS)

    @ccall libmf6.get_var_address(
        c::Ptr{UInt8},
        s::Ptr{UInt8},
        v::Ptr{UInt8},
        buffer::Ptr{UInt8},
    )::Cint
    string_end = findfirst(iszero, buffer) - 1
    return String(buffer[1:string_end])
end

end # module
