using Distributed #hide
worker = first(addprocs(1)) #hide
include("../../literate/example/example_include_all.jl") #hide

# # Distributed Image Reconstruction using RecoPlans
# This example demonstrates how to configure an iterative reconstruction algorithm directly on a worker, which helps to avoid transferring large parameters between processes and allows access to resources that may only exist on a specific worker.

# We follow a similar procedure as with the algorithm interface, but we will not configure the parameters just yet.
pre = RecoPlan(RadonPreprocessingParameters)
iter_reco = RecoPlan(IterativeRadonReconstructionParameters)
params = RecoPlan(IterativeRadonParameters; pre = pre, reco = iter_reco)
plan_iter = RecoPlan(IterativeRadonAlgorithm, parameter = params)

# We can traverse the parameters of our algorithm and configure them locally:
plan_iter.parameter.pre.frames = collect(1:3)

# To transfer the plan to the worker process, we will use `DaggerReconstructionParameter` and `DaggerReconstructionAlgorithm` as a `RecoPlan`:
params_dagger = RecoPlan(DaggerReconstructionParameter; worker = worker, algo = plan_iter)
plan_dagger = RecoPlan(DaggerReconstructionAlgorithm; parameter = params_dagger)

# In this setup, only the `DaggerReconstructionParameter` and `DaggerReconstructionAlgorithm` exist on the local worker; all other `RecoPlans` reside on the chosen worker.
# When traversing the `RecoPlan` tree across workers, we receive a `DaggerRecoPlan` instead of the usual data type:
typeof(plan_dagger.parameter.algo)

#This ephemeral structure manages communication with its remote `RecoPlan` counterpart, allowing us to use the same interface as if the entire plan were local.
plan_dagger.parameter.algo.parameter.reco.solver = CGNR

dict = Dict{Symbol, Any}()
dict[:shape] = size(images)[1:3]
dict[:angles] = angles
dict[:iterations] = 20
dict[:reg] = [L2Regularization(0.001), PositiveRegularization()]
dict[:solver] = CGNR
setAll!(plan_dagger, dict)

# To configure the algorithm with resources only available on the worker, such as files or GPU data, we can use the following interface:
setproperty!(plan_dagger.parameter.algo.parameter.reco, :angles) do
  angles[1:2:end]
end
# The provided function is evaluated solely on the remote worker.

# Once the algorithm is fully configured, we can build and use it as usual:
imag_dagger = reconstruct(build(plan_dagger), sinograms)
fig = Figure()
for i = 1:3
  plot_image(fig[i,1], reverse(images[:, :, 24, i]))
  plot_image(fig[i,2], sinograms[:, :, 24, i])
  plot_image(fig[i,3], reverse(imag_dagger[:, :, 24, i]))
end
resize_to_layout!(fig)
fig

# ## Serialization
# The serialization process of `DaggerReconstructionAlgorithm` and `DaggerReconstructionParameter` ignores the worker parameter and retrieves the entire plan tree:
toTOML(stdout, plan_dagger)

# It is also possible to directly load and distribute a serialized plan from a file using:
# ```julia
# loadDaggerPlan(filename, modules; worker = worker)
# ```
# This automatically wraps everything in a `DaggerReconstructionAlgorithm`.

# ## Observables
# `RecoPlans` can attach callbacks to property value changes using Observables from [Observables.jl](https://github.com/JuliaGizmos/Observables.jl).
# If a `RecoPlan` is set up with listeners and then moved to a different worker, the plans execute within that worker.
# This functionality also applies to the `loadDaggerPlan` method mentioned earlier.

# Additionally, listeners can be attached across workers using the Observable interface on a `DaggerRecoPlan`:
using Observables
localVariable = 3
fun = on(plan_iter.parameter.pre, :frames) do newval
  @info "Number of frames was updated to: $(length(newval))"
  localVariable = length(newval)
end
setAll!(plan_iter, :frames, collect(1:42))

# Note: We retain the observable function in the variable `fun` to allow for later removal of the listener. The anonymous function cannot be used directly due to internal listener management in **DaggerImageReconstruction**.
off(plan_iter.parameter.pre, :frames, fun)
setAll!(plan_iter, :frames, collect(1:32))

# Since the listener executes on the local worker, updated data must be transferred between workers. If this involves large data, a preprocessing function can be provided to the Observable:
fun = on(plan_iter.parameter.pre, :frames; preprocessing = length) do newval
  @info "Number of frames was updated to: $(newval)"
  localVariable = newval
end
setAll!(plan_iter, :frames, collect(1:42))
