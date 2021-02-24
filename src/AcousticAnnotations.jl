module AcousticAnnotations

using Dates
using DataFrames
using CSV
using SHA
using WAV

using DocStringExtensions

export ADB, projectinfo, recordings, metadata, annotations, annotate!
export recid, wavfiles

include("core.jl")

end # module
