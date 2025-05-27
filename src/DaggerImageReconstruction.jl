module DaggerImageReconstruction

using Distributed
using Dagger
using AbstractImageReconstruction
using AbstractImageReconstruction.AbstractTrees
using AbstractImageReconstruction.Observables

import AbstractImageReconstruction: process, build, toDictValue!, showtree, showproperty, INDENT, PIPE, TEE, ELBOW

abstract type AbstractDaggerReconstructionAlgorithm{A} <: AbstractImageReconstructionAlgorithm end

include("Utils.jl")
include("DaggerRecoPlan.jl")
include("DaggerReconstructionAlgorithm.jl")
include("DaggerReconstructionProcess.jl")

end