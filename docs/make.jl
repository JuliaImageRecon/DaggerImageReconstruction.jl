using Documenter, Literate, AbstractImageReconstruction,Observables, Distributed
using DaggerImageReconstruction

# Generate examples
OUTPUT_BASE = joinpath(@__DIR__(), "src/generated")
INPUT_BASE = joinpath(@__DIR__(), "src/literate")
for (_, dirs, _) in walkdir(INPUT_BASE)
    for dir in dirs
        OUTPUT = joinpath(OUTPUT_BASE, dir)
        INPUT = joinpath(INPUT_BASE, dir)
        for file in filter(f -> endswith(f, ".jl"), readdir(INPUT))
            Literate.markdown(joinpath(INPUT, file), OUTPUT)
        end
    end
end

makedocs(
    format = Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://github.com/JuliaImageRecon/DaggerImageReconstruction.jl",
        assets=String[],
        collapselevel=1,
    ),
    repo="https://github.com/JuliaImageRecon/DaggerImageReconstruction.jl/blob/{commit}{path}#{line}",
    modules = [DaggerImageReconstruction],
    sitename = "DaggerImageReconstruction.jl",
    authors = "Niklas Hackelberg, Tobias Knopp",
    pages = [
        "Home" => "index.md",
        "Example: Distributed Radon Reconstruction Package" => Any[
            "Introduction" => "example_intro.md",
            "Algoritm Interface" => "generated/example/algorithm.md",
            "RecoPlan Interface" => "generated/example/daggerplan.md",
        ],
        "API Reference" => "API/api.md",

    ],
    pagesonly = true,
    checkdocs = :none,
    doctest   = false,
    doctestfilters = [r"(\d*)\.(\d{4})\d+"]
    )

deploydocs(repo   = "github.com/JuliaImageRecon/DaggerImageReconstruction.jl.git", push_preview = true)