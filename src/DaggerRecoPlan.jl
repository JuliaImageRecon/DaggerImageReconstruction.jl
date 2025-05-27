export DaggerRecoPlan
struct DaggerRecoPlan{T, C <: Dagger.Chunk{RecoPlan{T}}} <: AbstractRecoPlan{T}
  _chunk::C
end

Base.propertynames(plan::DaggerRecoPlan) = fetch(Dagger.@spawn propertynames(getchunk(plan)))
function Base.getproperty(plan::DaggerRecoPlan{T}, name::Symbol) where T
  if name == :_chunk
    return getchunk(plan)
  else
    chunk = getchunk(plan)
    prop_chunk = Dagger.@mutable scope = chunk.scope fetch(Dagger.@spawn getproperty(chunk, name))
    if prop_chunk.chunktype <: AbstractRecoPlan
      return DaggerRecoPlan(prop_chunk)
    else
      return collect(prop_chunk)
    end
  end
end

getchunk(plan::DaggerRecoPlan) = getfield(plan, :_chunk)

function AbstractImageReconstruction.setAll!(plan::DaggerRecoPlan, name::Symbol, x, set, found)
  (remoteSet, remoteFound) = fetch(Dagger.spawn(getchunk(plan)) do chunk
    remoteSet = Ref(false)
    remoteFound = Ref(true)
    setAll!(chunk, name, x, remoteSet, remoteFound)
    return (remoteSet[], remoteFound[])
  end)
  set[] |= remoteSet
  found[] |= remoteFound
  return nothing
end
function Base.setproperty!(plan::DaggerRecoPlan, name::Symbol, x)
  fetch(Dagger.spawn(getchunk(plan)) do chunk
    Base.setproperty!(chunk, name, x)
    return true # Hacky workaround, we don't want to return anything expensive
    # But we still want to notice errors, so we fetch the result and let the happy-path return just true
  end)
  return nothing
end
function Base.setproperty!(f::Base.Callable, plan::DaggerRecoPlan, name::Symbol)
  fetch(Dagger.spawn(getchunk(plan)) do chunk
    Base.setproperty!(chunk, name, f())
    return true # See setproperty above
  end)
  return nothing
end
function AbstractImageReconstruction.clear!(plan::DaggerRecoPlan, args...)
  wait(Dagger.spawn(getchunk(plan)) do chunk
    AbstractImageReconstruction.clear!(chunk, args...)
  end)
  return plan
end


function AbstractImageReconstruction.showtree(io::IO, plan::DaggerRecoPlan{T}, indent::String = "", depth::Int = 1) where T
  io = IOContext(io, :limit => true, :compact => true)

  if depth == 1
    print(io, indent, "DaggerRecoPlan{$T} [Scope: {$(getchunk(plan).scope)}]", "\n")
  end

  props = propertynames(plan)
  for (i, prop) in enumerate(props)
    tmp = fetch(Dagger.spawn(getchunk(plan)) do chunk
      buffer = IOBuffer()
      property = getproperty(chunk, prop)
      showproperty(IOContext(buffer, :limit => true, :compact => true), prop, property, indent, i == length(props), depth)
      seekstart(buffer)
      return read(buffer)
    end)
    write(io, tmp)
  end
end

AbstractTrees.ParentLinks(::Type{<:DaggerRecoPlan}) = AbstractTrees.StoredParents()
function AbstractTrees.parent(plan::DaggerRecoPlan)
  chunk = getchunk(plan)
  parent_chunk = Dagger.@mutable scope = chunk.scope fetch(Dagger.@spawn AbstractTrees.parent(chunk))
  return DaggerRecoPlan(parent_chunk)
end
function AbstractTrees.children(plan::DaggerRecoPlan)
  result = Vector{DaggerRecoPlan}()
  for prop in propertynames(plan)
    if getproperty(plan, prop) isa DaggerRecoPlan
      push!(result, getproperty(plan, prop))
    end
  end
  return result
end

# Observables have the value as internal state -> don't want to transfer those
function Base.getindex(plan::DaggerRecoPlan, name::Symbol)
  chunk = getchunk(plan)
  return Dagger.@mutable scope = chunk.scope fetch(Dagger.@spawn getindex(chunk, name))
end
function Observables.on(f, plan::DaggerRecoPlan, property::Symbol; processing = identity, kwargs...)
  # We don't want to send f directly, this seems to copy certain values!
  f_chunk = Dagger.@mutable worker = myid() f
  # Don't return directly the obs_fn, because that containts all the data
  return Dagger.@mutable scope = getchunk(plan).scope fetch(Dagger.spawn(getchunk(plan)) do chunk
    # We want to execute f on our current worker, while triggering on changes on the (remote) worker
    obs_fn = on(chunk, property) do newval
      # If the value changes, we spawn a new worker with the value
      processed = processing(newval)
      wait(Dagger.@spawn f_chunk(processed)) # wait for f to finish s.t. it's all synchronous
    end
    return obs_fn
  end)
end
function Observables.off(plan::DaggerRecoPlan, property::Symbol, f_chunk::Dagger.Chunk{<:ObserverFunction})
  wait(Dagger.spawn(getchunk(plan)) do chunk
    f = fetch(f_chunk)
    off(chunk, property, f)
  end)
end