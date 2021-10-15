module ModflowInterface

using Printf
using Modflow6_jll
import BasicModelInterface as BMI

struct ModflowModel end

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
    return
end


function get_component_name(::ModflowModel)
    buf = zeros(UInt8, BMI_LENCOMPONENTNAME)
    @ccall mf6lib.get_component_name(buf::Ptr{UInt8})::Cint
    return String(buf)
end


"Returns the string `MODFLOW 6`"
function BMI.get_component_name(::ModflowModel)::String
    buf = zeros(UInt8, BMI_LENCOMPONENTNAME)
    @ccall libmf6.get_component_name(buf::Ptr{UInt8})::Cint
    string_end = findfirst(iszero, buf) - 1
    return String(buf[1:string_end])
end


function get_last_bmi_error(::ModflowModel)
    buf = zeros(UInt8, BMI_LENERRMESSAGE)
    @ccall libmf6.get_last_bmi_error(buf::Ptr{UInt8})::Cint
    return String(buf)
end


# Maybe check for non-ASCII chars
function prepare_string(s::String)
    return uppercase(s)
end


function get_var_address(
    ::ModflowModel,
    var_name,
    component_name;
    subcomponent_name = "",
)::String
    v = prepare_string(var_name)
    c = prepare_string(component_name)
    s = prepare_string(subcomponent_name)
    buf = zeros(UInt8, BMI_LENVARADDRESS)

    @ccall libmf6.get_var_address(
        c::Ptr{UInt8},
        s::Ptr{UInt8},
        v::Ptr{UInt8},
        buf::Ptr{UInt8},
    )::Cint
    string_end = findfirst(iszero, buf) - 1
    return String(buf[1:string_end])
end


function get_var_rank(::ModflowModel, name::String)
    rank = Ref(Cint(0))
    @ccall libmf6.get_var_rank(name::Ptr{UInt8}, rank::Ptr{Cint})::Cint
    return Integer(rank.x)
end


function get_var_shape(m::ModflowModel, name::String)
    rank = get_var_rank(m, name)
    shape = Vector{Int32}(undef, rank)
    @ccall libmf6.get_var_shape(name::Ptr{UInt8}, shape::Ptr{Int32})::Cint
    return tuple(shape...)
end


function BMI.get_var_type(::ModflowModel, name::String)::String
    buf = zeros(UInt8, BMI_LENVARTYPE)
    @ccall libmf6.get_var_type(name::Ptr{UInt8}, buf::Ptr{UInt8})::Cint
    string_end = findfirst(iszero, buf) - 1
    return String(buf[1:string_end])
end


function parse_type(type::String)::Type
    type = lowercase(type)
    if startswith(type, "double")
        return Float64
    elseif startswith(type, "float")
        return Float32
    elseif startswith(type, "int")
        return Int32
    else
        error("Unsupported type")
    end
    return
end


function get_value_ptr(::ModflowModel, name::String)
    type = parse_type(BMI.get_var_type(m, name))
    shape = get_var_shape(m, tag)

    null_pointer = Ref(C_NULL)
    if type == Int32
        @ccall libmf6.get_value_ptr_int(name::Ptr{UInt8}, null_pointer::Ptr{Cvoid})::Cint
    elseif type == Float32
        @ccall libmf6.get_value_ptr_float(name::Ptr{UInt8}, null_pointer::Ptr{Cvoid})::Cint
    elseif type == Float64
        @ccall libmf6.get_value_ptr_double(name::Ptr{UInt8}, null_pointer::Ptr{Cvoid})::Cint
    else
        error("unsupported type")
    end
    typed_pointer = Base.unsafe_convert(Ptr{type}, null_pointer.x)

    values = unsafe_wrap(Array, typed_pointer, shape)
    return values
end


end # module
