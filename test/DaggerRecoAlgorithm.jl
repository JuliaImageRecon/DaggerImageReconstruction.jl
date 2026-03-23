@testset "DaggerRecoAlgortihm" begin
  pre = RadonPreprocessingParameters(frames = collect(1:3))
  reco = IterativeRadonReconstructionParameters(; shape = size(images)[1:3], angles = angles, iterations = 1, reg = [L2Regularization(0.001), PositiveRegularization()], solver = CGNR);
  algo = IterativeRadonAlgorithm(IterativeRadonParameters(pre, reco))
  plan = toPlan(algo)
  reco = reconstruct(algo, sinograms)

  @testset "Algorithm Interface" begin
    parameter = DaggerReconstructionParameter(; algo = algo, worker = worker)
    algoD = DaggerReconstructionAlgorithm(parameter)
    
    @test isready(algoD) == false
    recoD1 = reconstruct(algoD, sinograms)
    @test isready(algoD) == false
    @test isapprox(reco, recoD1)

    @async put!(algoD, sinograms)
    wait(algoD)
    @test isready(algoD)
    recoD2 = take!(algoD)
    @test isapprox(recoD1, recoD2)
  end

  @testset "RecoPlan Interface" begin
    parameter = RecoPlan(DaggerReconstructionParameter; worker = 1, algo = plan)
    planD = RecoPlan(DaggerReconstructionAlgorithm; parameter = parameter)
    algoD = build(planD)

    @test algoD isa DaggerReconstructionAlgorithm

    @test isready(algoD) == false
    recoD1 = reconstruct(algoD, sinograms)
    @test isready(algoD) == false
    @test isapprox(reco, recoD1)

    @async put!(algoD, sinograms)
    wait(algoD)
    @test isready(algoD)
    recoD2 = take!(algoD)
    @test isapprox(recoD1, recoD2)

    @testset "Serialization" begin
      @everywhere begin
        @parameter struct SerTestParams <: AbstractTestParameters
          value::Float64 = 1.0
          iterations::Int64 = 10
        end

        @reconstruction struct SerTestAlgorithm <: AbstractTestBase
          @parameter parameter::SerTestParams
        end

        function (params::SerTestParams)(algo::SerTestAlgorithm, input)
          return input + params.value
        end
      end

      @testset "Basic save and load" begin
        params = SerTestParams(value=10.0)
        algo = SerTestAlgorithm(params)
        parameter = DaggerReconstructionParameter(; algo = algo, worker = worker)
        algoD = DaggerReconstructionAlgorithm(parameter)
        
        reco_original = reconstruct(algoD, 5.0)
        
        plan = toPlan(algoD)
        io = IOBuffer()
        savePlan(io, plan)
        seekstart(io)
        
        loaded = loadPlan(io, [Main, AbstractImageReconstruction, DaggerImageReconstruction])
        loaded_algo = build(loaded)
        reco_loaded = reconstruct(loaded_algo, 5.0)
        
        @test typeof(plan) == typeof(loaded)
        @test typeof(plan.parameter.algo) == typeof(loaded.parameter.algo)
        @test reco_original == reco_loaded
      end

      @testset "loadDaggerPlan integration" begin
        params = SerTestParams(value=7.0)
        algo = SerTestAlgorithm(params)        
        plan = toPlan(algo)
        
        io = IOBuffer()
        savePlan(io, plan)
        seekstart(io)
        
        loaded = loadDaggerPlan(io, [Main, AbstractImageReconstruction, DaggerImageReconstruction], worker = worker)
        
        @test loaded isa RecoPlan{DaggerReconstructionAlgorithm}
        built = build(loaded)
        @test built isa DaggerReconstructionAlgorithm
        @test built.parameter isa DaggerReconstructionParameter{SerTestAlgorithm}
      end
    end
   end
  
end