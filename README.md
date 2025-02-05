# DaggerImageReconstruction

[![Build Status](https://github.com/JuliaImageRecon/DaggerImageReconstruction.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/JuliaImageRecon/DaggerImageReconstruction.jl/actions/workflows/CI.yml?query=branch%3Amain)

[![](https://img.shields.io/badge/docs-latest-blue.svg)](https://JuliaImageRecon.github.io/DaggerImageReconstruction.jl)

This package allows algorithms developed with [AbstractImageReconstruction.jl](https://github.com/JuliaImageRecon/AbstractImageReconstruction.jl) to be exeucted partially or fully in different (and potentially distributed) Julia processes using [Dagger.jl](https://github.com/JuliaParallel/Dagger.jl/)

# DaggerImageReconstruction.jl

DaggerImageReconstruction.jl is a Julia package that utilizes [Dagger.jl](https://github.com/JuliaParallel/Dagger.jl/) to distribute image reconstruction algorithms across multiple Julia processes, either partially or fully. This package is designed to extend the generic interface of [AbstractImageReconstruction.jl](https://github.com/JuliaImageRecon/AbstractImageReconstruction.jl).

## Installation

You can install the package using Julia's package manager. Open the Julia REPL and run:

```julia
using Pkg
Pkg.add("DaggerImageReconstruction")
```

## Usage

To use DaggerImageReconstruction.jl, one first needs to add a new Julia process using `Distributed`:

```julia
# Add new process (on remote server)
using Distributed
addprocs(["gpuServer"])
```

Afterwards one can load `DaggerImageReconstruction´ and the packages implementing specific image reconstruction algorithms, such as [MPIReco.jl]. Similar to AbstractImageReconstruction.jl, this package does not offer concrete reconstruction algorithms:

```julia
using DaggerImageReconstruction
@everywhere using AbstractImageReconstruction, ... # Load Reco packages

plan = loadDaggerPlan("plan.toml", ...; worker = 2)

# Transparently configure algorithm in the remote process
dict = Dict{Symbol, Any}()
dict[:iterations] = 20
dict[:file] = () -> File("path/on/remote")
setAll!(plan, dict)

data = ... # read local data

# Transfer data to the remote, reconstruct there and return the result
algo = build(plan)
image = reconstruct(algo, raw)
```

Algorithms can be parameterized and constructed as if they were local `RecoPlans`. The usage example moves the whole image reconstruction to another process. `DaggerImageReconstruction` also offers an `AbstractUtilityReconstructionParameters` to move individual `process` steps to another process.

## Contributing

Contributions are welcome! If you would like to contribute to DaggerImageReconstruction.jl, please fork the repository and create a pull request.

## License

This package is licensed under the MIT License. See the LICENSE file for more information.

## Acknowledgements

This package is built on top of Dagger.jl, which provides the framefork for the distributed computations.