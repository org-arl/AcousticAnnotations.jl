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
      isfile(joinpath(root, "recordings.csv")) || error("Bad annotations database format: recordings.csv not found")
      rec = CSV.read(joinpath(root, "recordings.csv"), DataFrame)
    else
      create || error("Annotations database not found at $(root)")
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
Get recID from recording file.
"""
function recid(filename)
  lowercase(last(splitext(filename))) == ".wav" || error("Only WAV recordings are supported")
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
