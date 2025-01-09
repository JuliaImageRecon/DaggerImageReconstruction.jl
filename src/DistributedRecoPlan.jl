struct DistributedRecoPlan{T, C <: Dagger.Chunk{RecoPlan{T}}} <: AbstractRecoPlan{T}
  _chunk::C
end

Base.propertynames(plan::DistributedRecoPlan) = fetch(Dagger.@spawn propertynames(plan._chunk))
function Base.getproperty(plan::DistributedRecoPlan{T}, name::Symbol) where T
  if name == :_chunk
    return getfield(plan, :_chunk)
  else
    chunk = getfield(plan, :_chunk)
    prop_chunk = Dagger.@mutable scope = chunk.scope fetch(Dagger.@spawn getproperty(chunk, name))
    if prop_chunk.chunktype <: AbstractRecoPlan
      return DistributedRecoPlan(prop_chunk)
    else
      return collect(prop_chunk)
    end
  end
end

function AbstractImageReconstruction.setAll!(plan::DistributedRecoPlan, name::Symbol, x)
  wait(Dagger.spawn(plan._chunk) do chunk
    setAll!(chunk, name, x)
  end)
end
function Base.setproperty!(plan::DistributedRecoPlan, name::Symbol, x)
  fetch(Dagger.spawn(plan._chunk) do chunk
    Base.setproperty!(chunk, name, x)
    return true # Hacky workaround, we don't want to return any expensive
    # But we still want to notice errors, so we fetch the result and let the happy-path return just true
  end)
  return nothing
end
function Base.setproperty!(f::Base.Callable, plan::DistributedRecoPlan, name)
  fetch(Dagger.spawn(plan._chunk) do chunk
    Base.setproperty!(chunk, name, f())
    return true # See setproperty above
  end)
  return nothing
end


function AbstractImageReconstruction.showtree(io::IO, plan::DistributedRecoPlan{T}, indent::String = "", depth::Int = 1) where T
  io = IOContext(io, :limit => true, :compact => true)

  if depth == 1
    print(io, indent, "DistributedRecoPlan{$T} [Scope: {$(plan._chunk.scope)}]", "\n")
  end

  props = propertynames(plan)
  for (i, prop) in enumerate(props)
    tmp = fetch(Dagger.spawn(plan._chunk) do chunk
      buffer = IOBuffer()
      property = getproperty(chunk, prop)
      showproperty(IOContext(buffer, :limit => true, :compact => true), prop, property, indent, i == length(props), depth)
      seekstart(buffer)
      return read(buffer)
    end)
    write(io, tmp)
  end
end