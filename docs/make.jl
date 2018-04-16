Pkg.checkout("Documenter")

using Documenter, JuAFEM

# Generate examples
include("generate.jl")

GENERATEDEXAMPLES = [joinpath("examples", "generated", f) for f in ("heat_equation.md", )]

# Build documentation.
makedocs(
    format = :html,
    sitename = "JuAFEM.jl",
    doctest = false,
    # strict = VERSION.minor == 6 && sizeof(Int) == 8, # only strict mode on 0.6 and Int64
    strict = false,
    pages = Any[
        "Home" => "index.md",
        "manual/fe_intro.md",
        "Manual" => [
            "manual/cell_integration.md",
            "manual/degrees_of_freedom.md",
            "manual/assembly.md",
            "manual/boundary_conditions.md",
            "manual/grid.md",
            "manual/export.md"
            ],
        "Examples" => GENERATEDEXAMPLES,
        "API Reference" => [
            "reference/quadrature.md",
            "reference/interpolations.md",
            "reference/fevalues.md",
            "reference/dofhandler.md",
            "reference/assembly.md",
            "reference/boundary_conditions.md",
            "reference/grid.md",
            "reference/export.md"
            ]
        ]
    )

# Deploy built documentation from Travis.
deploydocs(
    repo = "github.com/KristofferC/JuAFEM.jl.git",
    target = "build",
    julia = "0.6", # deploy from release bot
    deps = nothing,
    make = nothing,
)
