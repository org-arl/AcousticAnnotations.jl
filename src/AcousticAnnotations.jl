module AcousticAnnotations

using Dates
using DataFrames
using CSV
using SHA
using WAV

using DocStringExtensions

export ADB, projectinfo, recordings, recid, wavfiles
export annotations, annotate!, annotationtypes
export metadata

include("core.jl")

end # module
