@testset "DaggerRecoAlgortihm" begin
  pre = RadonPreprocessingParameters(frames = collect(1:3))
  reco = IterativeRadonReconstructionParameters(; shape = size(images)[1:3], angles = angles, iterations = 1, reg = [L2Regularization(0.001), PositiveRegularization()], solver = CGNR);
  algo = IterativeRadonAlgorithm(IterativeRadonParameters(pre, reco))
  plan = toPlan(algo)

  @testset "RecoPlan Interface" begin
    parameter = DaggerReconstructionParameter(; algo = algo, worker = worker)
    algoD = DaggerReconstructionAlgorithm(parameter)

    
    @testset "Property Interface" begin
      planD = toPlan(algoD)

      # Traversal switches to remote plan
      @test planD.parameter isa RecoPlan
      @test planD.parameter.algo isa DaggerRecoPlan
      preD = planD.parameter.algo.parameter.pre
      @test preD isa DaggerRecoPlan
      @test preD.frames == [1, 2, 3]

      # Clear! works
      AbstractImageReconstruction.clear!(planD)
      @test ismissing(preD.frames)
      
      # Setproperty! works
      preD.frames = [1, 2, 3]
      @test preD.frames == [1, 2, 3]
      setproperty!(preD, :frames) do
        collect(1:42)
      end
      @test preD.frames == collect(1:42)

      # setAll! works
      params = Dict{Symbol, Any}()
      params[:shape] = size(images)[1:3]
      params[:angles] = angles
      params[:iterations] = 1
      params[:reg] = [L2Regularization(0.001), PositiveRegularization()]
      params[:solver] = CGNR
      setAll!(planD, params)
      recoD = planD.parameter.algo.parameter.reco
      for key in keys(params)
        @test getproperty(recoD, key) == params[key]
      end
    end

    @testset "Observables" begin
      planD = toPlan(algoD)
      rootD = planD.parameter.algo
      observed = Ref{Bool}(false)
      fun = (val) -> observed[] = true

      obs_fun = on(fun, rootD.parameter.reco, :angles)
      rootD.parameter.reco.angles = angles
      @test observed[]
      observed[] = false
      try 
        rootD.parameter.reco.angles = "Test"
      catch e
      end
      @test !(observed[])
  
      off(rootD.parameter.reco, :angles, obs_fun)
      rootD.parameter.reco.angles = angles
      @test !(observed[])
  
      obsv = rootD.parameter.reco[:angles]
      @test obsv isa Dagger.Chunk{<:Observable}
  
      on(fun, rootD.parameter.reco, :angles)
      AbstractImageReconstruction.clear!(rootD.parameter.reco)
      rootD.parameter.reco.angles = angles
      @test !(observed[])  
    end


    @testset "Tree Traversal" begin
      planD = toPlan(algoD)
      rootD = planD.parameter.algo
      parameter = rootD.parameter
      # Cant do direct equality, check objectid on remote
      getId(val) = fetch(Dagger.@spawn objectid(DaggerImageReconstruction.getchunk(val)))
      @test getId(parameter) == getId(first(AbstractTrees.children(rootD)))
      @test getId(rootD) == getId(AbstractTrees.parent(parameter))
  
      pre_plan = parameter.pre
      reco_plan = parameter.reco
      param_children = AbstractTrees.children(parameter)
      @test length(param_children) == 2
      for child in [pre_plan, reco_plan]
        @test child isa DaggerRecoPlan
        @test getId(parameter) == getId(AbstractTrees.parent(child))
        @test in(getId(child), map(getId, param_children))
      end
    end
  end
end