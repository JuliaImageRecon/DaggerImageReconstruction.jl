# API for DaggerImageReconstruction
This page contains documentation of the public API of the AbstractImageReconstruction. In the Julia
REPL one can access this documentation by entering the help mode with `?`

## Algorithm and Parameters
```@docs
DaggerImageReconstruction.DaggerReconstructionAlgorithm
DaggerImageReconstruction.DaggerReconstructionParameter
```

## DaggerRecoPlan
```@docs
DaggerImageReconstruction.DaggerRecoPlan
Base.getproperty(::DaggerRecoPlan, ::Symbol)
Base.setproperty!(::DaggerRecoPlan, ::Symbol, ::Any)
Observables.on(::Any, ::DaggerRecoPlan, ::Symbol)
Observables.off(::DaggerRecoPlan, ::Symbol, ::Any)
DaggerImageReconstruction.loadDaggerPlan
```