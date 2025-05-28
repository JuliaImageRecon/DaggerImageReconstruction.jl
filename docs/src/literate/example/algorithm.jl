# # Distributed Image Reconstruction
# This example demonstrates how to execute an iterative Radon reconstruction using the OurRadonReco package on a separate process.
# We start by adding a new worker process:
using Distributed
worker = first(addprocs(1))
# In this example we create a new local process, but usually one would create a process on another machine for example via ssh.

# We retrieve the worker's ID, which will be used to designate the target for our algorithm.
# Ensure that required packages are loaded on both the main and worker processes:
# ```julia
# @everywhere using OurRadonReco
# ```
include("../../literate/example/example_include_all.jl") #hide


# ## Iterative Radon Reconstruction
# We first recall the algorithms we defined for OurRadonreco. We will use iterative methods to reconstruct the first three images from our time series. For more information, refer to the AbstractImageReconstruction documentation.
# We first prepare our parameters. For this example we will use the Conjugate Gradient Normal Residual solver with 20 iterations and a L2 regularization of 0.001. Furthermore, we will project the final result to positive values:
pre = RadonPreprocessingParameters(frames = collect(1:3))
iter_reco = IterativeRadonReconstructionParameters(; shape = size(images)[1:3], angles = angles, iterations = 20, reg = [L2Regularization(0.001), PositiveRegularization()], solver = CGNR);

# We can construct the algorithm with our parameters:
algo_iter = IterativeRadonAlgorithm(IterativeRadonParameters(pre, iter_reco));

# And apply it to our sinograms:
imag_iter = reconstruct(algo_iter, sinograms);

# Finally we can visualize the results:
fig = Figure()
for i = 1:3
  plot_image(fig[i,1], reverse(images[:, :, 24, i]))
  plot_image(fig[i,2], sinograms[:, :, 24, i])
  plot_image(fig[i,3], reverse(imag_iter[:, :, 24, i]))
end
resize_to_layout!(fig)
fig

# ## Distributed Iterative Radon Reconstruction
# To execute the reconstruction process on our worker process we will use the `DaggerReconstructionAlgorithm`. This is an image reconstruction algorithm provided by **DaggerImageReconstruction** and features the same
# interface as other algorithms implemented with **AbstractImageReconstruction**. To use this algorithm, we again need to prepare our parameters:
iter_dagger = DaggerReconstructionParameter(algo = algo_iter, worker = worker);

# Here our parameter are give the complete iterative algorithm we constructed previously, as well as the worker. Internally, this moves the whole algorithm to the specified worker.
# If an algorithm contains a large amounts of data, such a transfer might be infeasible/costly. To avoid this, consider using the `RecoPlan` interface instead.

# Once we have our parameters, we can construct our algorithm:
algo_dagger = DaggerReconstructionAlgorithm(iter_dagger);

# Afterwards, we can reconstruct as before:
imag_dagger = reconstruct(algo_dagger, sinograms);

# This moves the sinogram to the other process and performs the image reconstruction there.
# At the end the algorithm retrieves the result and we can treat it the same way as the local reconstruction:
fig = Figure()
for i = 1:3
  plot_image(fig[i,1], reverse(images[:, :, 24, i]))
  plot_image(fig[i,2], sinograms[:, :, 24, i])
  plot_image(fig[i,3], reverse(imag_dagger[:, :, 24, i]))
end
resize_to_layout!(fig)
fig
