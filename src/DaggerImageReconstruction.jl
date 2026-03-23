module DaggerImageReconstruction

using Distributed
using Dagger
using AbstractImageReconstruction
using AbstractImageReconstruction.AbstractTrees
using AbstractImageReconstruction.Observables
using AbstractImageReconstruction.StructUtils

import AbstractImageReconstruction: @reconstruction, @parameter, RecoPlanStyle, build, showtree, showproperty, INDENT, PIPE, TEE, ELBOW

abstract type AbstractDaggerReconstructionAlgorithm{A} <: AbstractImageReconstructionAlgorithm end

include("Utils.jl")
include("DaggerRecoPlan.jl")
include("DaggerReconstructionAlgorithm.jl")
include("DaggerReconstructionUtility.jl")

end