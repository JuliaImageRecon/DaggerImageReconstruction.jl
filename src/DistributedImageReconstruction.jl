module DistributedImageReconstruction

using Dagger
using AbstractImageReconstruction

abstract type AbstractDistributedReconstructionAlgorithm{A} <: AbstractImageReconstructionAlgorithm end

include("DistributedReconstructionAlgorithm.jl")

end