@testset "DaggerRecoAlgortihm" begin
  pre = RadonPreprocessingParameters(frames = collect(1:3))
  reco = IterativeRadonReconstructionParameters(; shape = size(images)[1:3], angles = angles, iterations = 1, reg = [L2Regularization(0.001), PositiveRegularization()], solver = CGNR);
  algo = IterativeRadonAlgorithm(IterativeRadonParameters(pre, reco))
  plan = toPlan(algo)

  @testset "Algorithm Interface" begin
    parameter = DaggerReconstructionParameter(; algo = algo, worker = worker)
    algoD = DaggerReconstructionAlgorithm(parameter)

    reco = reconstruct(algo, sinograms)
    
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
  
end