using Distributed
worker = first(addprocs(1))

using DaggerImageReconstruction
using DaggerImageReconstruction.Dagger
using DaggerImageReconstruction.AbstractImageReconstruction
using DaggerImageReconstruction.AbstractImageReconstruction.AbstractTrees
using Test

@everywhere include(joinpath(@__DIR__(), "..", "docs", "src", "literate", "example", "example_include_all.jl"))


@testset "DaggerImageReconstruction.jl" begin
    include("DaggerRecoPlan.jl")
    include("DaggerRecoAlgorithm.jl")
    include("DaggerReconstructionProcess.jl")
end
