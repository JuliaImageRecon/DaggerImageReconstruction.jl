export DaggerRecoPlan

"""
    DaggerRecoPlan{T}

A configuration template for an image reconstruction algorithm or parameters of type `T` in a different Julia process. 

The `DaggerRecoPlan{T}` struct provides an interface similar to that of a `RecoPlan`, with the key distinction that setting and getting properties results in transparent data transfer to the specified remote process.
`DaggerRecoPlans` are temporary data structures that are recreated whenever traversing the remote `RecoPlan` tree. They track no state, except for the reference to their remote `RecoPlan` counterpart.
"""
struct DaggerRecoPlan{T, C <: Dagger.Chunk{RecoPlan{T}}} <: AbstractRecoPlan{T}
  _chunk::C
end

Base.propertynames(plan::DaggerRecoPlan) = fetch(Dagger.@spawn propertynames(getchunk(plan)))

"""
    Base.getproperty(plan::DaggerRecoPlan, name::Symbol)
  
Get the property `name` of the counterpart `plan`. If the property is another `RecoPlan`, this returns a new `DaggerRecoPlan` pointing to the `RecoPlan` property.
"""
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

"""
    setAll!(plan::DaggerRecoPlan, name::Symbol, x)

Recursively set the property `name` of each nested DaggerRecoPlan of `plan` to `x`. Updates the respective remote `RecoPlan`s.
Data is transfered once to the remote `RecoPlan` tree.
"""
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

"""
    Base.setproperty!(plan::DaggerRecoPlan, name::Symbol, x)

Set the property `name` of the remote plan to `x`. Equivalent to plan.name = x. Triggers callbacks attached to the property.
"""
function Base.setproperty!(plan::DaggerRecoPlan, name::Symbol, x)
  fetch(Dagger.spawn(getchunk(plan)) do chunk
    Base.setproperty!(chunk, name, x)
    return true # Hacky workaround, we don't want to return anything expensive
    # But we still want to notice errors, so we fetch the result and let the happy-path return just true
  end)
  return nothing
end

"""
    Base.setproperty!(plan::DaggerRecoPlan, name::Symbol, x)

Set the property `name` of the remote plan to result of `f()`. The function is only evaluated on the remote process. This can be used to access resources only available on the remote or to avoid expensive data transfers.
Triggers callbacks attached to the property.
"""
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

"""
    parent(plan::DaggerRecoPlan)

Return the `parent` of the remote `plan` as another `DaggerRecoPlan`.
Returns nothing if there is no parent.
"""
function AbstractTrees.parent(plan::DaggerRecoPlan)
  chunk = getchunk(plan)
  parent_chunk = Dagger.@mutable scope = chunk.scope fetch(Dagger.@spawn AbstractTrees.parent(chunk))
  if chunktype(parent_chunk) == Nothing
    return nothing
  elseif chunktype(parent_chunk) <: DaggerRecoPlan
    daggerplan = fetch(parent_chunk)
    return fetch(getchunk(daggerplan))
  end
  return DaggerRecoPlan(parent_chunk)
end

"""
    children(plan::DaggerRecoPlan)

Return the `children` of the remote `plan` as a vector of `DaggerRecoPlan`s.
"""
function AbstractTrees.children(plan::DaggerRecoPlan)
  result = Vector{DaggerRecoPlan}()
  for prop in propertynames(plan)
    if getproperty(plan, prop) isa DaggerRecoPlan
      push!(result, getproperty(plan, prop))
    end
  end
  return result
end
function AbstractImageReconstruction.parentproperty(plan::DaggerRecoPlan)
  p = AbstractTrees.parent(plan)
  if !isnothing(p)
    return findparentproperty(plan, p)
  end
  return nothing
end
function findparentproperty(plan::DaggerRecoPlan, parentD::DaggerRecoPlan)
  # TODO handle different scopes, perhaps via objectid?
  # Check on parents-scope to avoid data transfer for non Recoplan properties
  return fetch(Dagger.spawn(getchunk(parentD)) do parent
    child = fetch(getchunk(plan))
    for property in propertynames(parent)
      if getproperty(parent, property) === child
        return property
      end
    end
    return nothing
  end)
end
function findparentproperty(planD::DaggerRecoPlan, parent::RecoPlan)
  # TODO handle different scopes, perhaps via objectid?
  for property in propertynames(parent)
    childD = getproperty(parent, property)
    if childD isa DaggerRecoPlan
      match = fetch(Dagger.spawn(getchunk(planD)) do plan
        child = fetch(getchunk(childD))
        return child === plan
      end)
      if match
        return property
      end
    end
  end
end

# Observables have the value as internal state -> don't want to transfer those
function Base.getindex(plan::DaggerRecoPlan, name::Symbol)
  chunk = getchunk(plan)
  return Dagger.@mutable scope = chunk.scope fetch(Dagger.@spawn getindex(chunk, name))
end

"""
    on(f, plan::DaggerRecoPlan, property::Symbol; preprocessing = identity, kwargs...)
  
Registers a callback function `f` to be executed whenever the specified `property` of the given `plan` changes.
The function `f` will be executed with the new value of the property on the current worker. Returns a Dagger.Chunk of the ObservableFunction.
This chunk is required to unregister the listener `f`

To preprocess the data before it is passed to `f`, use the `preprocessing` keyword argument.
"""
function Observables.on(f, plan::DaggerRecoPlan, property::Symbol; preprocessing = identity, kwargs...)
  # We don't want to send f directly, this seems to copy certain values!
  f_chunk = Dagger.@mutable worker = myid() f
  # Don't return directly the obs_fn, because that containts all the data
  return Dagger.@mutable scope = getchunk(plan).scope fetch(Dagger.spawn(getchunk(plan)) do chunk
    # We want to execute f on our current process, while triggering on changes on the (remote) process
    obs_fn = on(chunk, property) do newval
      # If the value changes, we spawn a new task with the value
      processed = preprocessing(newval)
      wait(Dagger.@spawn f_chunk(processed)) # wait for f to finish s.t. it's all synchronous
    end
    return obs_fn
  end)
end

"""
    off(plan::DaggerRecoPlan, property::Symbol, f_chunk::Dagger.Chunk{<:ObserverFunction})

Unregisters a previously registered callback function from observing changes to the specified `property` of the given `plan`. This stops any further execution of  the callback when the property changes.
"""
function Observables.off(plan::DaggerRecoPlan, property::Symbol, f_chunk::Dagger.Chunk{<:ObserverFunction})
  wait(Dagger.spawn(getchunk(plan)) do chunk
    f = fetch(f_chunk)
    off(chunk, property, f)
  end)
end