chunktype(::Dagger.Chunk{T}) where T = T

export loadDaggerPlan
"""
    loadDaggerPlan(filename; worker)
  
Read a local `RecoPlan` from `args`  and interpret it on the the specified worker. The resulting `RecoPlan` is embedded within a `DaggerReconstructionAlgorithm`.
"""

function loadDaggerPlan(filename, modules; worker)
  buffer = IOBuffer()
  open(filename) do file
    for line in readlines(file; keep = true)
      write(buffer, line)
    end
  end
  seekstart(buffer)
  plan = Dagger.@mutable worker = worker loadPlan(buffer, modules)
  params = RecoPlan(DaggerReconstructionParameter; worker = worker, algo = plan)
  return RecoPlan(DaggerReconstructionAlgorithm; parameter = params)
end