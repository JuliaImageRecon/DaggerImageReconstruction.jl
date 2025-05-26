export DaggerRecoPlan
struct DaggerRecoPlan{T, C <: Dagger.Chunk{RecoPlan{T}}} <: AbstractRecoPlan{T}
  _chunk::C
end

Base.propertynames(plan::DaggerRecoPlan) = fetch(Dagger.@spawn propertynames(plan._chunk))
function Base.getproperty(plan::DaggerRecoPlan{T}, name::Symbol) where T
  if name == :_chunk
    return getfield(plan, :_chunk)
  else
    chunk = getfield(plan, :_chunk)
    prop_chunk = Dagger.@mutable scope = chunk.scope fetch(Dagger.@spawn getproperty(chunk, name))
    if prop_chunk.chunktype <: AbstractRecoPlan
      return DaggerRecoPlan(prop_chunk)
    else
      return collect(prop_chunk)
    end
  end
end

getchunk(plan::DaggerRecoPlan) = plan._chunk

function AbstractImageReconstruction.setAll!(plan::DaggerRecoPlan, name::Symbol, x, set, found)
  (remoteSet, remoteFound) = fetch(Dagger.spawn(plan._chunk) do chunk
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
  fetch(Dagger.spawn(plan._chunk) do chunk
    Base.setproperty!(chunk, name, x)
    return true # Hacky workaround, we don't want to return anything expensive
    # But we still want to notice errors, so we fetch the result and let the happy-path return just true
  end)
  return nothing
end
function Base.setproperty!(f::Base.Callable, plan::DaggerRecoPlan, name::Symbol)
  fetch(Dagger.spawn(plan._chunk) do chunk
    Base.setproperty!(chunk, name, f())
    return true # See setproperty above
  end)
  return nothing
end


function AbstractImageReconstruction.showtree(io::IO, plan::DaggerRecoPlan{T}, indent::String = "", depth::Int = 1) where T
  io = IOContext(io, :limit => true, :compact => true)

  if depth == 1
    print(io, indent, "DaggerRecoPlan{$T} [Scope: {$(plan._chunk.scope)}]", "\n")
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

AbstractTrees.ParentLinks(::Type{<:DaggerRecoPlan}) = AbstractTrees.StoredParents()
function AbstractTrees.parent(plan::DaggerRecoPlan)
  chunk = getfield(plan, :_chunk)
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