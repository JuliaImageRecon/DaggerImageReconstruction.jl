export DaggerReconstructionParameter, DaggerReconstructionAlgorithm
"""
    DaggerReconstructionParameter

Struct representing parameters for a Dagger-based reconstruction algorithm.
"""
struct DaggerReconstructionParameter{T, C <: Dagger.Chunk{T}} <: AbstractImageReconstructionParameters
  algo::C
  worker::Int64
  DaggerReconstructionParameter(algo::C, worker::Int64) where {T <: AbstractImageReconstructionAlgorithm, C <: Dagger.Chunk{T}}= new{T, C}(algo, worker)
end
"""
    DaggerReconstructionParameter(; algo, worker = myid())

Constructs a DaggerReconstructionParameter on the specified worker. The given algorithm is moved to the worker. To avoid movement of large data, one can load a RecoPlan on the worker and configure it locally.
"""
DaggerReconstructionParameter(; algo, worker = myid()) = DaggerReconstructionParameter(algo, worker)
function DaggerReconstructionParameter(algo, worker::Int64)
  chunk = Dagger.@mutable worker = worker algo
  return DaggerReconstructionParameter(chunk, worker)
end

"""
    DaggerReconstructionAlgorithm

Struct representing a Dagger-based reconstruction algorithm, which encapsulates the distrubted reconstruction execution and manages the outputs.
"""
mutable struct DaggerReconstructionAlgorithm{T} <: AbstractDaggerReconstructionAlgorithm{T}
  parameter::DaggerReconstructionParameter{T}
  output::Channel{Any}
end
DaggerReconstructionAlgorithm(param::DaggerReconstructionParameter) = DaggerReconstructionAlgorithm(param, Channel{Any}(Inf))
AbstractImageReconstruction.parameter(algo::DaggerReconstructionAlgorithm) = algo.parameter
Base.lock(algo::DaggerReconstructionAlgorithm) = lock(algo.output)
Base.unlock(algo::DaggerReconstructionAlgorithm) = unlock(algo.output)
Base.take!(algo::DaggerReconstructionAlgorithm) = Base.take!(algo.output)
function Base.put!(algo::DaggerReconstructionAlgorithm, data)
  lock(algo) do
    put!(algo.output, process(algo, algo.parameter, data))
  end
end
Base.wait(algo::DaggerReconstructionAlgorithm) = wait(algo.output)
Base.isready(algo::DaggerReconstructionAlgorithm) = isready(algo.output)

function AbstractImageReconstruction.process(algo::DaggerReconstructionAlgorithm, params::DaggerReconstructionParameter, data)
  result = fetch(Dagger.spawn(params.algo) do algo
      reconstruct(algo, data)
    end
  )
  return result
end

getchunk(plan::RecoPlan{DaggerReconstructionParameter}, name::Symbol) = getfield(plan, :values)[name][]
function setchunk!(plan::RecoPlan{DaggerReconstructionParameter}, name::Symbol, chunk)
  getfield(plan, :values)[name][] = chunk
end
function AbstractImageReconstruction.toPlan(param::DaggerReconstructionParameter)
  plan = RecoPlan(DaggerReconstructionParameter)
  plan.worker = param.worker
  local_plan = DaggerRecoPlan(Dagger.@mutable worker = myid() plan)
  setchunk!(plan, :algo, Dagger.@mutable worker = param.worker fetch(Dagger.spawn(param.algo) do algo 
      remote_plan = toPlan(algo)
      parent!(remote_plan, local_plan)
      return remote_plan
    end))
  return plan
end
function AbstractImageReconstruction.build(plan::RecoPlan{DaggerReconstructionParameter})
  worker = plan.worker
  algo = getchunk(plan, :algo)
  if algo isa Dagger.Chunk
    algo = Dagger.@mutable worker = worker fetch(Dagger.spawn(algo) do tmp
      build(tmp)
    end)
  else
    error("Expected a Dagger.Chunk, found $(typeof(algo))")
  end
  return DaggerReconstructionParameter(algo, worker)
end

# Do not serialize the the worker and collect the remote algo
AbstractImageReconstruction.toDictValue!(dict, plan::RecoPlan{DaggerReconstructionParameter}) = dict["algo"] = fetch(Dagger.@spawn toDict(getchunk(plan, :algo)))

function AbstractImageReconstruction.showtree(io::IO, property::RecoPlan{DaggerReconstructionParameter}, indent::String, depth::Int)
  if !ismissing(property.algo)
    print(io, indent, ELBOW, "algo", "::$((getfield(property, :values)[:algo][]).chunktype) [Distributed, Worker $(property.worker)]", "\n")
    output = fetch(Dagger.spawn(getchunk(property, :algo)) do algo
        buffer = IOBuffer()
        showtree(buffer, algo, indent * INDENT, depth + 1)
        seekstart(buffer)
        return read(buffer)
      end
    )
    write(io, output)
  else
    print(io, indent, ELBOW, "algo", "\n")
  end
end

function AbstractImageReconstruction.clear!(plan::RecoPlan{DaggerReconstructionParameter}, preserve::Bool = true)
  if preserve && !ismissing(getchunk(plan, :algo))
      wait(Dagger.@spawn AbstractImageReconstruction.clear!(getchunk(plan, :algo)))
  else
    getfield(plan, :values)[:algo] = Observable{Any}(missing)
  end
end

# First load the plan in the current worker, then make it chunk for the current worker. Afterwards with setproperty! one can move the chunk to another process 
function AbstractImageReconstruction.loadPlan!(plan::RecoPlan{DaggerReconstructionParameter}, dict::Dict{String, Any}, modDict)
  algo = missing
  if haskey(dict, "algo")
    algo = AbstractImageReconstruction.loadPlan!(dict["algo"], modDict)
    parent!(algo, plan)
  end
  setchunk(plan, :algo, Dagger.@mutable worker = myid() algo)
  plan.worker = myid()
  return plan
end

function AbstractImageReconstruction.setAll!(plan::RecoPlan{DaggerReconstructionParameter}, name::Symbol, x, set, found)
  if !ismissing(getchunk(plan, :algo))
    setAll!(plan.algo, name, x, set, found)
  end

  # Set the value of the field
  if hasproperty(plan, name)
    try
      found[] |= true
      Base.setproperty!(plan, name, x)
      set[] |= true
    catch ex
      @error ex
      @warn "Could not set $name of DaggerReconstructionParameter with value of type $(typeof(x))"
    end
  end
end
function Base.setproperty!(plan::RecoPlan{DaggerReconstructionParameter}, name::Symbol, x)
  if !haskey(getfield(plan, :values), name)
    error("type $T has no field $name")
  end

  t = type(plan, name)
  value = missing
  if AbstractImageReconstruction.validvalue(plan, t, x) 
    value = x
  else
    value = convert(t, x)
  end

  if value isa AbstractRecoPlan
    local_plan = DaggerRecoPlan(Dagger.@mutable worker = myid() plan)
    parent!(value, local_plan)
  end

  # When we change the worker, we move the chunk around
  if name == :worker
    if !ismissing(getchunk(plan, :algo))
      setchunk!(plan, :algo, Dagger.@mutable worker = value collect(getchunk(plan, :algo)))
    end
    getfield(plan, :values)[name][] = value
  elseif name == :algo
    setchunk!(plan, :algo, Dagger.@mutable worker = plan.worker value)
  end

  return Base.getproperty(plan, name)
end
AbstractImageReconstruction.validvalue(plan::RecoPlan{DaggerReconstructionParameter}, ::Type{<:Dagger.Chunk}, value::Union{AbstractImageReconstructionAlgorithm, RecoPlan{<:AbstractImageReconstructionAlgorithm}}) = true
AbstractImageReconstruction.validvalue(plan::RecoPlan{DaggerReconstructionParameter}, ::Type{<:Dagger.Chunk}, value::Missing) = true
AbstractImageReconstruction.validvalue(plan::RecoPlan{DaggerReconstructionParameter}, ::Type{<:Dagger.Chunk}, value) = false

function Base.getproperty(plan::RecoPlan{DaggerReconstructionParameter}, name::Symbol)
  if name == :worker
    return getfield(plan, :values)[name][]
  elseif name == :algo
    chunk = getfield(plan, :values)[name][]
    return ismissing(chunk) ? chunk : DaggerRecoPlan(chunk)
  else
    error("type $(DaggerReconstructionParameter) has no field $name")
  end
end