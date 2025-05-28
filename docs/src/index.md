# DaggerImageReconstruction.jl

*Distributed Image Reconstruction for Medical Image Reconstruction Packages*

## Introduction

**DaggerImageReconstruction.jl** is a Julia package that enables distributed image reconstruction using [**AbstractImageReconstruction.jl**](https://github.com/JuliaImageRecon/AbstractImageReconstruction.jl) across multiple Julia processes and machines. This flexibility allows users to configure image reconstruction locally while executing it on a remote machine, such as one with GPU acceleration.

Any algorithm developed with **AbstractImageReconstruction** is compatible, including all algorithms from [**MPIReco.jl**](https://github.com/MagneticParticleImaging/MPIReco.jl).

This package leverages the **Distributed.jl** standard library and [**Dagger.jl**](https://github.com/JuliaParallel/Dagger.jl/) for its functionality.

## Features
 
* Transparent data movement during image reconstruction 
* Seamless usage of RecoPlans across processes, including tree traversal and observables
* Loading of local algorithms configuration on remote processes

## Installation

To install the package, use Julia's package manager. Open the Julia REPL and run:

```julia
using Pkg
Pkg.add("DaggerImageReconstruction")
```

## Usage

To use DaggerImageReconstruction.jl, one first needs to add a new Julia process using `Distributed`:

```julia
# Add new process (on remote server)
using Distributed
worker = first(addprocs(["gpuServer"]))
```

Afterwards one can load `DaggerImageReconstruction´ and the packages implementing specific image reconstruction algorithms, such as [MPIReco.jl](https://github.com/MagneticParticleImaging/MPIReco.jl). Similar to AbstractImageReconstruction.jl, this package does not offer concrete reconstruction algorithms:

```julia
using DaggerImageReconstruction
@everywhere using AbstractImageReconstruction, ... # Load Reco packages

plan = loadDaggerPlan("plan.toml", ...; worker = worker)

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

Algorithms can be parameterized and constructed as if they were local `RecoPlans`. The example above demonstrates moving the entire image reconstruction to another process. **DaggerImageReconstruction** also provides an `AbstractUtilityReconstructionParameters` to transfer individual processing steps to another process.

## Contributing

Contributions are welcome! If you would like to contribute to DaggerImageReconstruction.jl, please fork the repository and create a pull request.

## Acknowledgements

This package is built on top of **Dagger.jl**, which provides the framefork for the distributed computations.