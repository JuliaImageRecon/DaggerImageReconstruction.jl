# Distributed Radon Image Reconstruction

In this example, we will build upon the [Radon example](https://juliaimagerecon.github.io/AbstractImageReconstruction.jl/dev/example_intro/) from **AbstractImageReconstruction**. We will demonstrate how our reconstruction package, **OurRadonReco**, can be distributed across multiple processes.

## Installation

In addition to the packages from the Radon example, you need to add **DaggerImageReconstruction** using the Julia package manager. Open a Julia REPL and execute the following command:

```julia
using Pkg
Pkg.add("DaggerImageReconstruction")
```
This command will download and install **DaggerImageReconstruction.jl** along with its dependencies.

### Required Packages

You will also need to install the necessary packages for the Radon example. Please refer to the [example documentation](https://juliaimagerecon.github.io/AbstractImageReconstruction.jl/dev/example_intro/) for specific installation steps.

Note that there is no direct dependency between **OurRadonReco** and **DaggerImageReconstruction**. While it is possible to specialize parts of the image reconstruction through package extensions, the core functionality is provided solely via the AbstractImageReconstruction interface.

### Environment Setup

Ensure that the required packages are installed in the environment of both Julia processes. For detailed instructions on launching Julia processes across different workers or computers, consult the [Distributed Computing](https://docs.julialang.org/en/v1/stdlib/Distributed/) documentation.
