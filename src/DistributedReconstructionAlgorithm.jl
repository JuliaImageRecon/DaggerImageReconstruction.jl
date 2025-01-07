export DistributedReconstructionParameter, DistributedReconstructionAlgorithm
struct DistributedReconstructionParameter{T} <: AbstractImageReconstructionParameters
  algo::Dagger.Chunk{T}
  worker::Int64
  DistributedReconstructionParameter(algo::Dagger.Chunk{T}, worker::Int64) where T = new{T}(algo, worker)
  # Not entirely sure how to handle arbitrary scopes with RecoPlans atm
  # DistributedReconstructionParameter(algo::Dagger.Chunk{T}, scope::Dagger.AbstractScope) where T = new{T}(algo, scope)
end
DistributedReconstructionParameter(; algo, worker = 1) = DistributedReconstructionParameter(algo, worker)
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

function AbstractImageReconstruction.toPlan(param::DistributedReconstructionParameter)
  plan = RecoPlan(DistributedReconstructionParameter)
  plan.worker = param.worker
  plan.algo = Dagger.@mutable worker = param.worker fetch(Dagger.spawn(param.algo) do algo 
      toPlan(algo)
    end)
  return plan
end
function AbstractImageReconstruction.build(plan::RecoPlan{DistributedReconstructionParameter})
  worker = plan.worker
  algo = plan.algo
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
AbstractImageReconstruction.toDictValue!(dict, plan::RecoPlan{DistributedReconstructionParameter}) = dict["algo"] = fetch(Dagger.@spawn toDict(plan.algo))

function AbstractImageReconstruction.showtree(io::IO, property::RecoPlan{DistributedReconstructionParameter}, indent::String, depth::Int)
  print(io, indent, ELBOW, "algo", "::$(chunktype(property.algo)) [Distributed, Worker $(property.worker)]", "\n")
  output = fetch(Dagger.spawn(property.algo) do algo
      buffer = IOBuffer()
      showtree(buffer, algo, indent * INDENT, depth + 1)
      seekstart(buffer)
      return read(buffer)
    end
  )
  write(io, output)
end

function AbstractImageReconstruction.clear!(plan::RecoPlan{DistributedReconstructionParameter}, preserve::Bool = true)
  if preserve && !ismissing(plan.algo)
      wait(Dagger.@spawn clear!(plan.algo))
  else
    getfield(plan, :values)[:algo] = Observable{Any}(missing)
  end
end