worker = 1 # hide
using DaggerImageReconstruction # hide
include("../../literate/example/example_include_all.jl") #hide

# # Distributed Image Reconstruction using DaggerReconstructionUtility
# This example demonstrates how to use `DaggerReconstructionUtility` to wrap reconstruction parameters and execute them on a separate worker process.

# ## Parameter Wrapping
# The `DaggerReconstructionUtility` wraps parameters (not the entire algorithm), allowing the wrapped parameters to execute on a specified worker.
# We begin with the preprocessing parameters we defined earlier:

pre = RadonPreprocessingParameters(frames = collect(1:3))

# To distribute these parameters to a worker, we wrap them using `DaggerReconstructionUtility`:

pre_dagger = DaggerReconstructionUtility(pre, worker)

# The `DaggerReconstructionUtility` takes the parameters and a worker ID. Internally, it creates a `Dagger.Chunk` of the parameters and schedules execution on the specified worker.
# The `DirectRadonParameters` defined in the example don't accept utility parameters just yet. As a workaround we define a new preprocessing steps, however usually it would be better to do this directly in the type:
@parameter struct RadonPreprocessingWithUtilityParameters{P <: AbstractRadonPreprocessingParameters, PU <: AbstractUtilityReconstructionParameters{P}} <: AbstractRadonPreprocessingParameters
  params::Union{P, PU}
end
(params::RadonPreprocessingWithUtilityParameters)(algoT::Type{<:AbstractRadonAlgorithm}, args...) = params.params(algoT, args...)
# This is a similar artifical case to the caching example from AbstractImageReconstruction.

# ## Algorithm Construction with Distributed Parameters
# We can now construct our reconstruction algorithm using the distributed parameters. We will use the direct reconstruction algorithm for this example:
pre_wrapped = RadonPreprocessingWithUtilityParameters(pre_dagger)
algo_direct = DirectRadonAlgorithm(DirectRadonParameters(pre = pre_wrapped, reco = RadonBackprojectionParameters(angles)));

# Note that we can mix local and distributed parameters. Only the parameters wrapped with `DaggerReconstructionUtility` will execute on the worker.

# ## Reconstruction
# We can now reconstruct our sinograms. The reconstruction will be executed on the worker, but the result will be returned to the main process:

imag_direct = reconstruct(algo_direct, sinograms)

# ## RecoPlan Interface
# The `DaggerReconstructionUtility` also works with the `RecoPlan` interface, allowing for distributed configuration of parameters.
# We can create a `RecoPlan` for our distributed preprocessing parameters:
plan = toPlan(algo_direct)

# We can now configure the parameters Distributedly using the `RecoPlan` interface:

plan.parameter.pre.params.param.frames = collect(1:3)

# The configuration changes will be executed on the worker, not locally.

# The `DaggerReconstructionUtility` provides a simple and flexible way to distribute reconstruction parameters without the overhead of distributing entire algorithms.
# However, it requires parameters to accept utility parameters
