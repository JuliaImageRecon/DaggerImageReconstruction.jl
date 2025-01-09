module DistributedImageReconstruction

using Distributed
using Dagger
using AbstractImageReconstruction

import AbstractImageReconstruction: process, build, toDictValue!, showtree, showproperty, INDENT, PIPE, TEE, ELBOW

abstract type AbstractDistributedReconstructionAlgorithm{A} <: AbstractImageReconstructionAlgorithm end

include("Utils.jl")
include("DistributedRecoPlan.jl")
include("DistributedReconstructionAlgorithm.jl")

end