export DistributedReconstructionParameter, DistributedReconstructionAlgorithm
struct DistributedReconstructionParameter{T} <: AbstractImageReconstructionParameters
  algo::Dagger.Chunk{T}
  worker::Int64
  DistributedReconstructionParameter(algo::Dagger.Chunk{T}, worker::Int64) where T = new{T}(algo, worker)
  # Not entirely sure how to handle arbitrary scopes with RecoPlans atm
  # DistributedReconstructionParameter(algo::Dagger.Chunk{T}, scope::Dagger.AbstractScope) where T = new{T}(algo, scope)
end
DistributedReconstructionParameter(; algo, worker = myid()) = DistributedReconstructionParameter(algo, worker)
function DistributedReconstructionParameter(algo, worker::Int64)
  chunk = Dagger.@mutable worker = worker algo
  return DistributedReconstructionParameter(chunk, worker)
end
#function DistributedReconstructionParameter(algo, scope)
#  chunk = Dagger.@mutable scope = scope algo
#  return DistributedReconstructionParameter(chunk, scope)
#end

mutable struct DistributedReconstructionAlgorithm{T} <: AbstractDistributedReconstructionAlgorithm{T}
  parameter::DistributedReconstructionParameter{T}
  output::Channel{Any}
end
DistributedReconstructionAlgorithm(param::DistributedReconstructionParameter) = DistributedReconstructionAlgorithm(param, Channel{Any}(Inf))
AbstractImageReconstruction.parameter(algo::DistributedReconstructionAlgorithm) = algo.parameter
Base.lock(algo::DistributedReconstructionAlgorithm) = lock(algo.output)
Base.unlock(algo::DistributedReconstructionAlgorithm) = unlock(algo.output)
Base.take!(algo::DistributedReconstructionAlgorithm) = Base.take!(algo.output)
function Base.put!(algo::DistributedReconstructionAlgorithm, data)
  lock(algo) do
    put!(algo.output, process(algo, algo.parameter, data))
  end
end
Base.wait(algo::DistributedReconstructionAlgorithm) = wait(algo.output)
Base.isready(algo::DistributedReconstructionAlgorithm) = isready(algo.output)

function AbstractImageReconstruction.process(algo::DistributedReconstructionAlgorithm, params::DistributedReconstructionParameter, data)
  result = fetch(Dagger.spawn(params.algo) do algo
      reconstruct(algo, data)
    end
  )
  put!(algo.output, result)
end

getchunk(plan::RecoPlan{DistributedReconstructionParameter}, name::Symbol) = getfield(plan, :values)[name][]
function setchunk!(plan::RecoPlan{DistributedReconstructionParameter}, name::Symbol, chunk)
  getfield(plan, :values)[name][] = chunk
end
function AbstractImageReconstruction.toPlan(param::DistributedReconstructionParameter)
  plan = RecoPlan(DistributedReconstructionParameter)
  plan.worker = param.worker
  setchunk!(plan, :algo, Dagger.@mutable worker = param.worker fetch(Dagger.spawn(param.algo) do algo 
      toPlan(algo)
    end))
  return plan
end
function AbstractImageReconstruction.build(plan::RecoPlan{DistributedReconstructionParameter})
  worker = plan.worker
  algo = getchunk(plan, :algo)
  if algo isa Dagger.Chunk
    algo = Dagger.@mutable worker = worker fetch(Dagger.spawn(algo) do tmp
      build(tmp)
    end)
  else
    algo = Dagger.@mutable worker = worker build(worker)
  end
  return DistributedReconstructionParameter(algo, worker)
end

# Do not serialize the the worker and collect the remote algo
AbstractImageReconstruction.toDictValue!(dict, plan::RecoPlan{DistributedReconstructionParameter}) = dict["algo"] = fetch(Dagger.@spawn toDict(getchunk(plan, :algo)))

function AbstractImageReconstruction.showtree(io::IO, property::RecoPlan{DistributedReconstructionParameter}, indent::String, depth::Int)
  print(io, indent, ELBOW, "algo", "::$((getfield(property, :values)[:algo][]).chunktype) [Distributed, Worker $(property.worker)]", "\n")
  output = fetch(Dagger.spawn(getchunk(property, :algo)) do algo
      buffer = IOBuffer()
      showtree(buffer, algo, indent * INDENT, depth + 1)
      seekstart(buffer)
      return read(buffer)
    end
  )
  write(io, output)
end

function AbstractImageReconstruction.clear!(plan::RecoPlan{DistributedReconstructionParameter}, preserve::Bool = true)
  if preserve && !ismissing(getchunk(plan, :algo))
      wait(Dagger.@spawn AbstractImageReconstruction.clear!(getchunk(plan, :algo)))
  else
    getfield(plan, :values)[:algo] = Observable{Any}(missing)
  end
end

# First load the plan in the current worker, then make it chunk for the current worker. Afterwards with setproperty! one can move the chunk to another process 
function AbstractImageReconstruction.loadPlan!(plan::RecoPlan{DistributedReconstructionParameter}, dict::Dict{String, Any}, modDict)
  algo = missing
  if haskey(dict, "algo")
    algo = AbstractImageReconstruction.loadPlan!(dict["algo"], modDict)
    parent!(algo, plan)
  end
  setchunk(plan, :algo, Dagger.@mutable worker = myid() algo)
  plan.worker = myid()
  return plan
end

function AbstractImageReconstruction.setAll!(plan::RecoPlan{DistributedReconstructionParameter}, name::Symbol, x)
  if !ismissing(getchunk(plan, :algo))
    wait(Dagger.spawn(getchunk(plan, :algo)) do algo
      if algo isa RecoPlan
        setAll!(algo, name, x)
      end
    end)
  end

  # Set the value of the field
  if hasproperty(plan, name)
    try
      Base.setproperty!(plan, name, x)
    catch ex
      @error ex
      @warn "Could not set $name of $T with value of type $(typeof(x))"
    end
  end
end
function Base.setproperty!(plan::RecoPlan{DistributedReconstructionParameter}, name::Symbol, x)
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

  if value isa RecoPlan
    parent!(value, plan)
  end

  # When we change the worker, we move the chunk around
  if name == :worker
    if !ismissing(getchunk(plan, :algo))
      setchunk!(plan, :algo, Dagger.@mutable worker = value collect(getchunk(plan, :algo)))
    end
    getfield(plan, :values)[name][] = value
  end

  if name == :algo
    setchunk(plan, :algo, Dagger.@mutable worker = plan.worker value)
  end

  return Base.getproperty(plan, name)
end
AbstractImageReconstruction.validvalue(plan::RecoPlan{DistributedReconstructionParameter}, ::Type{<:Dagger.Chunk}, value::Union{AbstractImageReconstructionAlgorithm, RecoPlan{<:AbstractImageReconstructionAlgorithm}}) = true
AbstractImageReconstruction.validvalue(plan::RecoPlan{DistributedReconstructionParameter}, ::Type{<:Dagger.Chunk}, value::Missing) = true
AbstractImageReconstruction.validvalue(plan::RecoPlan{DistributedReconstructionParameter}, ::Type{<:Dagger.Chunk}, value) = false

function Base.getproperty(plan::RecoPlan{DistributedReconstructionParameter}, name::Symbol)
  if name == :worker
    return getfield(plan, :values)[name][]
  elseif name == :algo
    chunk = getfield(plan, :values)[name][]
    return ismissing(chunk) ? chunk : DistributedRecoPlan(chunk)
  else
    error("type $(DistributedReconstructionParameter) has no field $name")
  end
end