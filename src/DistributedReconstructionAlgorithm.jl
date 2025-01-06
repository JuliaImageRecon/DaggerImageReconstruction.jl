export DistributedReconstructionParameter, DistributedReconstructionAlgorithm
struct DistributedReconstructionParameter{T}
  algo::Dagger.Chunk{T}
  scope::Union{Int64, Dagger.AbstractScope}
  DistributedReconstructionParameter(algo::Dagger.Chunk{T}, scope::Int64) where T = new{T}(algo, scope)
  DistributedReconstructionParameter(algo::Dagger.Chunk{T}, scope::Dagger.AbstractScope) where T = new{T}(algo, scope)
end
DistributedReconstructionParameter(; algo, scope = 1) = DistributedReconstructionParameter(algo, scope)
function DistributedReconstructionParameter(algo, scope::Int64)
  chunk = Dagger.@mutable worker = scope algo
  return DistributedReconstructionParameter(chunk, scope)
end
function DistributedReconstructionParameter(algo, scope)
  chunk = Dagger.@mutable scope = scope algo
  return DistributedReconstructionParameter(chunk, scope)
end

mutable struct DistributedReconstructionAlgorithm{T} <: AbstractDistributedReconstructionAlgorithm{T}
  parameter::DistributedReconstructionParameter{T}
  output::Channel{Any}
end
DistributedReconstructionAlgorithm(param::DistributedReconstructionParameter) = DistributedReconstructionAlgorithm(param, Channel{Any}(Inf))
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