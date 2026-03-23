@testset "DaggerReconstructionUtility" begin
  @everywhere begin 
    @parameter struct SimpleTestParams <: AbstractTestParameters
      value::Float64 = 1.0
      iterations::Int64 = 100
    end
    @reconstruction mutable struct SimpleAlgorithm{P <: Union{SimpleTestParams, AbstractUtilityReconstructionParameters{SimpleTestParams}}} <: AbstractTestBase
      @parameter parameter::P
    end
    function (param::SimpleTestParams)(algo::SimpleAlgorithm, input::Int64)
      return param.value * input + param.iterations
    end
  end

  params = SimpleTestParams()
  wrapped = DaggerReconstructionUtility(; param = params, worker = worker)

  # Direct
  algo = SimpleAlgorithm(params)
  algoD = SimpleAlgorithm(wrapped)
  @test algoD.parameter.worker == worker
  @test reconstruct(algo, 42) == reconstruct(algoD, 42)
  
  # To Plan
  plan = toPlan(algo)
  planD = toPlan(algoD)
  @test planD.parameter isa RecoPlan{DaggerReconstructionUtility}
  @test planD.parameter.worker == worker
  @test plan.parameter.value == planD.parameter.param.value
  
  # From Plan
  algoD = build(planD)
  @test algoD.parameter.worker == worker
  @test reconstruct(algo, 42) == reconstruct(algoD, 42)
  
  # From "file"
  io = IOBuffer()
  savePlan(io, planD)
  seekstart(io)
  loaded = loadPlan(io, [Main, AbstractImageReconstruction, DaggerImageReconstruction])
  algoD = build(planD)
  @test algoD.parameter.worker == worker
  @test reconstruct(algo, 42) == reconstruct(algoD, 42)

end