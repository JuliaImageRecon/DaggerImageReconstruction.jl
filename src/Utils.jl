chunktype(::Dagger.Chunk{T}) where T = T

export loadDaggerPlan
"""
    loadDaggerPlan(args...; worker)
  
Load a local `RecoPlan` from on a TOML according to `loadPlan(args...)` and move it to the specified worker. The resulting `RecoPlan` is embedded within a `DaggerReconstructionAlgorithm`.
"""

function loadDaggerPlan(args...; worker)
  local_plan = loadPlan(args...)
  plan = Dagger.@mutable worker = worker local_plan
  params = RecoPlan(DaggerReconstructionParameter; worker = worker, algo = plan)
  return RecoPlan(DaggerReconstructionAlgorithm; parameter = params)
end