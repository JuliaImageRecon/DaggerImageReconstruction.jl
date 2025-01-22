export DaggerReconstructionProcess
struct DaggerReconstructionProcess{P, T <: Union{P, AbstractUtilityReconstructionParameters{P}}, C <: Dagger.Chunk{T}} <: AbstractUtilityReconstructionParameters{P}
  param::C
  worker::Int64
  function DaggerReconstructionProcess(params::Union{P, AbstractUtilityReconstructionParameters{P}}, worker::Int64) where P <: AbstractImageReconstructionParameters 
    chunk = Dagger.@mutable worker = worker params
    return new{P, typeof(params), typeof(chunk)}(chunk, worker)
  end
  # TODO arbitrary scope
end
DaggerReconstructionProcess(; params, worker = myid()) = DaggerReconstructionProcess(params, worker)

AbstractImageReconstruction.process(algo::A, param::DaggerReconstructionProcess, inputs...) where {A <: AbstractImageReconstructionAlgorithm} = dagger_process(algo, param, inputs...)
AbstractImageReconstruction.process(algoT::Type{<:A}, param::DaggerReconstructionProcess, inputs...) where {A <: AbstractImageReconstructionAlgorithm} = dagger_process(algoT, param, inputs...)
function dagger_process(algo, param::DaggerReconstructionProcess, inputs...)
  return fetch(Dagger.spawn(param.param) do p
    return AbstractImageReconstruction.process(algo, p, inputs...)
  end)
end

function getchunk(plan::RecoPlan{DaggerReconstructionProcess}, name::Symbol)
  if name != :param
    error("$name is not a chunk of DaggerReconstructionProcess")
  end
  return getfield(plan, :values)[name][]
end
function setchunk!(plan::RecoPlan{DaggerReconstructionProcess}, name::Symbol, chunk)
  if name != :param
    error("$name is not a chunk of DaggerReconstructionProcess")
  end
  getfield(plan, :values)[name][] = chunk
end

# Make distr. process transparent for property getter/setter
function Base.setproperty!(plan::RecoPlan{<:DaggerReconstructionProcess}, name::Symbol, value)
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
AbstractImageReconstruction.validvalue(plan::RecoPlan{DaggerReconstructionProcess}, ::Type{<:Dagger.Chunk}, value::Union{AbstractImageReconstructionParameters, RecoPlan{<:AbstractImageReconstructionParameters}}) = true
AbstractImageReconstruction.validvalue(plan::RecoPlan{DaggerReconstructionProcess}, ::Type{<:Dagger.Chunk}, value::Missing) = true
AbstractImageReconstruction.validvalue(plan::RecoPlan{DaggerReconstructionProcess}, ::Type{<:Dagger.Chunk}, value) = false

function Base.getproperty(plan::RecoPlan{<:DaggerReconstructionProcess}, name::Symbol)
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
AbstractImageReconstruction.toDictValue!(dict, plan::RecoPlan{DaggerReconstructionProcess}) = dict["param"] = fetch(Dagger.@spawn toDict(getchunk(plan, :param)))

function AbstractImageReconstruction.toPlan(param::DaggerReconstructionProcess)
  plan = RecoPlan(DaggerReconstructionProcess)
  plan.worker = param.worker
  setchunk!(plan, :param, Dagger.@mutable worker = param.worker fetch(Dagger.spawn(param.param) do tmp 
      toPlan(tmp)
    end))
  return plan
end
# First load the plan in the current worker, then make it chunk for the current worker. Afterwards with setproperty! one can move the chunk to another process 
function AbstractImageReconstruction.loadPlan!(plan::RecoPlan{DaggerReconstructionProcess}, dict::Dict{String, Any}, modDict)
  param = missing
  if haskey(dict, "param")
    param = AbstractImageReconstruction.loadPlan!(dict["param"], modDict)
    parent!(param, plan)
  end
  setchunk(plan, :param, Dagger.@mutable worker = myid() param)
  plan.worker = myid()
  return plan
end
function AbstractImageReconstruction.build(plan::RecoPlan{DaggerReconstructionProcess})
  worker = plan.worker
  param = getchunk(plan, :param)
  if param isa Dagger.Chunk
    param = Dagger.@mutable worker = worker fetch(Dagger.spawn(param) do tmp
      build(tmp)
    end)
  else
    error("Expected a Dagger.Chunk, found $(typeof(param))")
  end
  return DaggerReconstructionProcess(param, worker)
end
