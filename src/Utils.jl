chunktype(::Dagger.Chunk{T}) where T = T

export loadDaggerPlan
"""
    loadDaggerPlan(filename, modules; worker)
    loadDaggerPlan(io, modules; worker)
  
Load a local `RecoPlan` from the specified `filename` and interpret it on the designated `worker`. The resulting `RecoPlan` is encapsulated within a `DaggerReconstructionAlgorithm`.
"""
function loadDaggerPlan(filename::String, modules; worker)
  buffer = IOBuffer()
  open(filename) do file
    for line in readlines(file; keep = true)
      write(buffer, line)
    end
  end
  seekstart(buffer)
  return loadDaggerPlan(buffer, modules; worker)
end
function loadDaggerPlan(io, modules; worker)
  plan = Dagger.@mutable worker = worker loadPlan(io, modules)
  params = RecoPlan(DaggerReconstructionParameter; worker = worker, algo = plan)
  return RecoPlan(DaggerReconstructionAlgorithm; parameter = params)
end