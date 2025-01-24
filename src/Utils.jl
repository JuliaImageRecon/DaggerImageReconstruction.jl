chunktype(::Dagger.Chunk{T}) where T = T

export loadDaggerPlan
"""
    loadDaggerPlan(args...; worker)
  
Load a `RecoPlan` from on a TOML according to `loadPlan(args...)` on the specified worker. The resulting `RecoPlan` is embedded within a `DaggerReconstructionAlgorithm`.
"""

function loadDaggerPlan(args...; worker)
  plan = Dagger.@mutable worker = worker loadPlan(args...)
  params = RecoPlan(DaggerReconstructionParameter; worker = worker, algo = plan)
  return RecoPlan(DaggerReconstructionAlgorithm; parameter = params)
end