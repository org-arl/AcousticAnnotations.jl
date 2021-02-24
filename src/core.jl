import Base.push!

"""
    ADB(root)
    ADB(root; recroot="/path/to/recordings")
    ADB(root; create=true)

Open annotations database. If `create` is set to `true`, a new database is created
if none exists at the given root location. If a `recroot` is provided, it is used as
the root folder for acoustic recordings.
"""
struct ADB

  root::String
  recroot::String
  rec::DataFrame
  recdirty::Ref{Bool}

  function ADB(root; create=false, recroot=joinpath(root, "recordings"))
    root = expanduser(root)
    recroot = expanduser(recroot)
    local rec
    if isdir(root)
      isfile(joinpath(root, "recordings.csv")) || throw(ArgumentError("Bad annotations database format: recordings.csv not found"))
      rec = CSV.read(joinpath(root, "recordings.csv"), DataFrame)
    else
      create || throw(ArgumentError("Annotations database not found at $(root)"))
      rec = _initADB(root, basename(root))
    end
    new(root, recroot, rec, Ref(false))
  end

end # struct

function _initADB(root, name)
  mkpath(joinpath(root, "annotations"))
  open(joinpath(root, "README.md"), "w") do io
    write(io, """
      ---
      project: $(name)
      ---

      # Annotations: $(name)
      """)
  end
  open(joinpath(root, ".gitignore"), "w") do io
    write(io, "recordings")
  end
  df = DataFrame(recid=String[], path=String[], dts=DateTime[], duration=Float64[], device=String[], location=String[])
  CSV.write(joinpath(root, "recordings.csv"), df)
  df
end

Base.show(io::IO, adb::ADB) = print(io, "Annotations database at $(adb.root)")

"""
$(TYPEDSIGNATURES)
Flush annotations database to disk.
"""
function Base.flush(adb::ADB)
  adb.recdirty[] || return
  CSV.write(joinpath(adb.root, "recordings.csv"), adb.rec)
  adb.recdirty[] = false
  nothing
end

"""
$(TYPEDSIGNATURES)
Close annotations database.
"""
Base.close(adb::ADB) = flush(adb)

"""
$(SIGNATURES)
Get project metadata.
"""
function projectinfo(adb::ADB)
  md = Dict{String,String}()
  state = :init
  for s ∈ eachline(joinpath(adb.root, "README.md"))
    if state === :init
      s != "---" && return nothing
      state = :yaml
    elseif state === :yaml
      s == "---" && return md
      s1, s2 = split(s, ':')
      md[strip(s1)] = strip(s2)
    end
  end
  nothing
end

"""
$(SIGNATURES)
Get recID from recording file.
"""
function recid(filename)
  lowercase(last(splitext(filename))) == ".wav" || throw(ArgumentError("Only WAV recordings are supported"))
  open(filename) do io
    bytes2hex(sha2_256(io))
  end
end

"""
$(SIGNATURES)
Get recID from recording file.
"""
recid(adb::ADB, filename) = recid(joinpath(adb.recroot, filename))

"""
$(SIGNATURES)
Get list of recordings.
"""
recordings(adb::ADB) = adb.rec

"""
$(TYPEDSIGNATURES)
Add recording to annotations database.
"""
function Base.push!(adb::ADB, filename, device, location)
  filename = relpath(filename, adb.recroot)
  if filename ∈ adb.rec.path
    @warn "Duplicate recording $(filename) ignored"
    return adb
  end
  id = recid(adb, filename)
  if id ∈ adb.rec.recid
    @warn "Duplicate recording $(id) ($(filename)) ignored"
    return adb
  end
  f = joinpath(adb.recroot, filename)
  dts = unix2datetime(round(Int64, ctime(f)))
  _, fs = wavread(f, format="native", subrange=1)
  sz = wavread(f, format="size")
  push!(adb.rec, (id, filename, dts, size(sz, 1)/fs, device, location))
  adb.recdirty[] = true
  adb
end

"""
$(SIGNATURES)
Get a list of all WAV recordings in a given directory recursively.
"""
function wavfiles(dirname)
  wavs = String[]
  for (root, dirs, files) ∈ walkdir(expanduser(dirname))
    for f ∈ files
      if lowercase(last(splitext(f))) == ".wav"
        push!(wavs, joinpath(root, f))
      end
    end
  end
  wavs
end

struct Annotations
  recid::String
  atype::String
  df::DataFrame
  filename::String
end

Base.show(io::IO, a::Annotations) = print(io, "Annotations $(atype) on $(recid)")

function _annofile(adb::ADB, recid, atype)
  dts = adb.rec[adb.rec.recid .== recid, :dts]
  length(dts) != 1 && throw(ArgumentError("No such recording"))
  s = Dates.format(first(dts), "yyyymmdd")
  atype === nothing && return joinpath(adb.root, "annotations", s, "$(recid)-")
  joinpath(adb.root, "annotations", s, "$(recid)-$(atype).csv")
end

"""
$(SIGNATURES)
Begin annotation.

# Examples:
```julia
adb = ADB("mydb")
a = annotate!(adb, "somerecid", "myanno")
push!(a, 3.0, 1.0; remark="Interesting sound")
push!(a, 7.0, 1.0; remark="Another interesting sound")
close(a)
close(adb)
```
"""
function annotate!(adb::ADB, recid, atype; append=false)
  occursin('-', atype) && throw(ArgumentError("Annotation type cannot contain '-'"))
  filename = _annofile(adb, recid, atype)
  df = DataFrame(dts=DateTime[], start=Float64[], duration=Float64[])
  append && isfile(filename) && (df = CSV.read(filename, DataFrame))
  Annotations(recid, atype, df, filename)
end

"""
$(SIGNATURES)
Begin annotation.

# Examples:
```julia
adb = ADB("mydb")
annotate!(adb, "somerecid", "myanno") do a
  push!(a, 3.0, 1.0; remark="Interesting sound")
  push!(a, 7.0, 1.0; remark="Another interesting sound")
end
close(adb)
"""
function annotate!(cb, adb::ADB, recid, atype; append=false)
  a = annotate!(adb, recid, atype; append=append)
  try
    cb(a)
  finally
    close(a)
  end
end

"""
$(SIGNATURES)
Add single annotation.
"""
function annotate!(adb::ADB, recid, atype, start, duration; kwargs...)
  a = annotate!(adb, recid, atype; append=true)
  push!(a, start, duration; kwargs...)
  close(a)
end

"""
$(TYPEDSIGNATURES)
Add annotation.
"""
function push!(a::Annotations, start, duration; kwargs...)
  row = Dict(:dts => now(), :start => start, :duration => duration)
  length(kwargs) > 0 && merge!(row, kwargs)
  push!(a.df, row; cols=:union)
end

"""
$(TYPEDSIGNATURES)
Flush annotations to disk.
"""
function Base.flush(a::Annotations)
  mkpath(dirname(a.filename))
  CSV.write(a.filename, a.df)
  nothing
end

"""
$(TYPEDSIGNATURES)
End annotation and flush to disk.
"""
Base.close(a::Annotations) = flush(a)

"""
$(SIGNATURES)
Get annotations for a specific recording.
"""
function annotations(adb::ADB, recid, atype)
  filename = _annofile(adb, recid, atype)
  isfile(filename) || return DataFrame(dts=DateTime[], start=Float64[], duration=Float64[])
  CSV.read(filename, DataFrame)
end

"""
$(SIGNATURES)
Get annotations for recordings given by criterion specified using keyword arguments.
"""
function annotations(adb::ADB, atype; location=missing, from=missing, to=missing)
  df = DataFrame(recid=String[], dts=DateTime[], start=Float64[], duration=Float64[])
  b = ones(Bool, size(adb.rec, 1))
  location === missing || (b .&= adb.rec.location .== location)
  from === missing || (b .&= adb.rec.dts .≥ from)
  to === missing || (b .&= adb.rec.dts .≤ to)
  for recid ∈ adb.rec[b, :recid]
    filename = _annofile(adb, recid, atype)
    if isfile(filename)
      df1 = CSV.read(filename, DataFrame)
      df1.recid = repeat([recid], size(df1, 1))
      append!(df, df1; cols=:union)
    end
  end
  df
end

"""
$(SIGNATURES)
Get a list of annotation types.
"""
function annotationtypes(adb::ADB)
  anno = Set{String}()
  for (root, dirs, files) ∈ walkdir(joinpath(adb.root, "annotations"))
    for f ∈ files
      if occursin('-', f) && endswith(f, ".csv")
        ndx = findlast('-', f)
        push!(anno, f[ndx+1:end-4])
      end
    end
  end
  anno
end

"""
$(SIGNATURES)
Get a list of annotation types for a recording.
"""
function annotationtypes(adb::ADB, recid)
  anno = Set{String}()
  pat = _annofile(adb, recid, nothing)
  fpat = basename(pat)
  if isdir(dirname(pat))
    for f ∈ readdir(dirname(pat))
      if startswith(f, fpat) && endswith(f, ".csv")
        push!(anno, f[length(fpat)+1:end-4])
      end
    end
  end
  anno
end
