export DaggerReconstructionUtility

"""
    DaggerReconstructionUtility(; param, worker)

Wraps reconstruction parameters for distributed execution using Dagger.

`DaggerReconstructionUtility` takes parameters (or parameters wrapped in 
`AbstractUtilityReconstructionParameters`) and executes them on a specified 
worker process via `Dagger.spawn`. This is useful when parameters need to 
execute on a specific worker for resource access (e.g., GPU) without the 
overhead of distributing entire algorithms.

See also: [`DaggerReconstructionAlgorithm`](@ref)
"""
@parameter struct DaggerReconstructionUtility{P, T <: Union{P, AbstractUtilityReconstructionParameters{P}}, C <: Dagger.Chunk{T}} <: AbstractUtilityReconstructionParameters{P}
  param::C
  worker::Int64 = myid()
  # TODO arbitrary scope
end
function DaggerReconstructionUtility(params::Union{P, AbstractUtilityReconstructionParameters{P}}, worker::Int64) where P <: AbstractImageReconstructionParameters 
  chunk = Dagger.@mutable worker = worker params
  return DaggerReconstructionUtility{P, typeof(params), typeof(chunk)}(chunk, worker)
end


(param::DaggerReconstructionUtility)(algo::A, inputs...) where {A <: AbstractImageReconstructionAlgorithm} = dagger_process(algo, param, inputs...)
(param::DaggerReconstructionUtility)(algoT::Type{<:A}, inputs...) where {A <: AbstractImageReconstructionAlgorithm} = dagger_process(algoT, param, inputs...)
function dagger_process(algo, param::DaggerReconstructionUtility, inputs...)
  return fetch(Dagger.spawn(param.param) do p
    return p(algo, inputs...)
  end)
end

function getchunk(plan::RecoPlan{DaggerReconstructionUtility}, name::Symbol)
  if name != :param
    error("$name is not a chunk of DaggerReconstructionUtility")
  end
  return getfield(plan, :values)[name][]
end
function setchunk!(plan::RecoPlan{DaggerReconstructionUtility}, name::Symbol, chunk)
  if name != :param
    error("$name is not a chunk of DaggerReconstructionUtility")
  end
  getfield(plan, :values)[name][] = chunk
end

# Make distr. process transparent for property getter/setter
function Base.setproperty!(plan::RecoPlan{<:DaggerReconstructionUtility}, name::Symbol, x)
  if in(name, [:param, :worker])
    t = type(plan, name)
    value = missing
    if AbstractImageReconstruction.validvalue(plan, t, x) 
      value = x
    else
      value = convert(t, x)
    end
  
    if value isa RecoPlan
      parent!(value, plan)
    end
    
    if name == :worker
      if !ismissing(getchunk(plan, :param))
        setchunk!(plan, :param, Dagger.@mutable worker = value collect(getchunk(plan, :param)))
      end
      getfield(plan, :values)[name][] = value
    elseif name == :param
      setchunk!(plan, :param, Dagger.@mutable worker = plan.worker value)
    end
  else
    setproperty!(plan.param, name, value)
  end
  return Base.getproperty(plan, name)
end
AbstractImageReconstruction.validvalue(plan::RecoPlan{DaggerReconstructionUtility}, ::Type{<:Dagger.Chunk}, value::Union{AbstractImageReconstructionParameters, RecoPlan{<:AbstractImageReconstructionParameters}}) = true
AbstractImageReconstruction.validvalue(plan::RecoPlan{DaggerReconstructionUtility}, ::Type{<:Dagger.Chunk}, value::Missing) = true
AbstractImageReconstruction.validvalue(plan::RecoPlan{DaggerReconstructionUtility}, ::Type{<:Dagger.Chunk}, value) = false

# TODO: requires support of nested utility in AbstractImageReconstruction
function AbstractImageReconstruction.validvalue(plan, union::Type{Union{T, DaggerReconstructionUtility{<:T}}}, value::RecoPlan{DaggerReconstructionUtility}) where T
  innertype = value.param isa DaggerRecoPlan ? typeof(value.param).parameters[1] : typeof(value.param)
  return DaggerReconstructionUtility{<:innertype} <: union 
end

function AbstractImageReconstruction.validvalue(plan, union::UnionAll, value::RecoPlan{DaggerReconstructionUtility})
  innertype = value.param isa DaggerRecoPlan ? typeof(value.param).parameters[1] : typeof(value.param)
  return DaggerReconstructionUtility{<:innertype} <: union 
end

function AbstractImageReconstruction.validvalue(plan, union::UnionAll, value::RecoPlan{<:DaggerReconstructionUtility})
  innertype = value.param isa DaggerRecoPlan ? typeof(value.param).parameters[1] : typeof(value.param)
  return DaggerReconstructionUtility{<:innertype} <: union 
end

function Base.getproperty(plan::RecoPlan{<:DaggerReconstructionUtility}, name::Symbol)
  if name == :param
    chunk = getfield(plan, :values)[name][]
    return ismissing(chunk) ? chunk : DaggerRecoPlan(chunk)
  elseif name == :worker
    return getfield(plan, :values)[name][]
  else
    return getproperty(plan.param, name)
  end
end


# Do not serialize the the worker and collect the remote algo
function StructUtils.lower(style::RecoPlanStyle, plan::RecoPlan{T}) where T <: DaggerReconstructionUtility
  dict = Dict{String, Any}(
    MODULE_TAG => string(parentmodule(T)),
    TYPE_TAG => "RecoPlan{$(nameof(T))}"
  )
  dict["param"] = fetch(Dagger.@spawn StructUtils.lower(style, getchunk(plan, :param)))
  return dict
end

function AbstractImageReconstruction.toPlan(param::DaggerReconstructionUtility)
  plan = RecoPlan(DaggerReconstructionUtility)
  plan.worker = param.worker
  setchunk!(plan, :param, Dagger.@mutable worker = param.worker fetch(Dagger.spawn(param.param) do tmp 
      toPlan(tmp)
    end))
  return plan
end
# First load the plan in the current worker, then make it chunk for the current worker. Afterwards with setproperty! one can move the chunk to another process 
function StructUtils.make!(style::RecoPlanStyle, plan::RecoPlan{DaggerReconstructionUtility}, dict::Dict{String, Any})
  param = missing
  if haskey(dict, "param")
    param, _ = StructUtils.make(style, RecoPlan, dict["param"])
    parent!(param, plan)
  end
  setchunk!(plan, :param, Dagger.@mutable worker = myid() param)
  plan.worker = myid()
  return plan
end
function AbstractImageReconstruction.build(plan::RecoPlan{DaggerReconstructionUtility})
  worker = plan.worker
  param = getchunk(plan, :param)
  if param isa Dagger.Chunk
    param = Dagger.@mutable worker = worker fetch(Dagger.spawn(param) do tmp
      build(tmp)
    end)
  else
    error("Expected a Dagger.Chunk, found $(typeof(param))")
  end
  return DaggerReconstructionUtility(param, worker)
end