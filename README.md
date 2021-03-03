## Acoustic Annotations Database

This package is for ARL internal use only at present and is therefore not a registered package.

### Installation

To install:
```julia
using Pkg
Pkg.add(url="https://github.com/org-arl/AcousticAnnotations.jl")
```
and then to use it:
```julia
using AcousticAnnotations
```

### Creating a new database

To create a new annotations database:
```julia
adb = ADB("/path/to/dbfolder"; create=true, recroot="/path/to/acoustic/recordings")
```
This creates a new database in a folder `/path/to/dbfolder`. This folder can be committed to a `git`
repository directly. The database only holds annotations and metadata (as CSV or markdown files).
The acoustic recordings are assumed to be available at the path given by `recroot`.

### Adding recordings to the database

Recordings can be individually added using `push!()`:
```julia
push!(adb, "/path/to/acoustic/recordings/somerec.wav", "LS1", "Sisters Island")
```
If you have a folder full of recordings, you can bulk add them:
```julia
for f ∈ wavfiles("/path/to/acoustic/recordings/20210127")
  push!(adb, f, "LS1", "Sisters Island")
end
```
Once you are done adding all recordings, close the database to flush data to disk:
```julia
close(adb)
```
or by using `flush(adb)`.

Each recording is associated with a unique recording ID (`recID`) that is generated by hashing part of the
wav file. This allows the database to detect duplicate recordings (which it will disallow adding). You can
generate a `recID` for any wav file you may have:
```julia
julia> recid("/path/to/acoustic/recordings/somerec.wav")
"37c196e889ae1bb487a7c5c99632a051ce0ae556d44a717dadffb6f29bc5d683"
```

### Accessing the database

A database can be opened with the `ADB()` function:
```julia
adb = ADB("/path/to/dbfolder"; recroot="/path/to/acoustic/recordings")
```
If the `recroot` is not specified, it defaults to the `recordings` folder inside the database folder.
This folder is added to `.gitinore`, so that it is not checked in by `git`, but can be used for storing
or caching acoustic recordings.

You can get database information using the `projectinfo()` function:
```julia
julia> projectinfo(adb)
Dict{String, String} with 1 entry:
  "project" => "dbfolder"
```
This information is read from the YAML header in the `README.md` file, and may be manually edited to
add project-specific properties, if desired.

You can also access the full list of recordings as a `DataFrame`:
```julia
julia> recordings(adb)
1×6 DataFrame
 Row │ recid                              path                       dts                  duration  device  location
     │ String                             String                     DateTime…            Float64   String  String
─────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────
   1 │ 37c196e889ae1bb487a7c5c99632a051…  20210127/ZOOM0007_Tr1.WAV  2021-01-03T19:23:40   6821.57  LS1     Sisters Island
```

### Metadata

Recordings may be associated with additional metadata:
```julia
md = metadata(adb)
```
The metadata is represented as a `DataFrame` with a `recid` column. Users may add other columns to the metadata
table as desired. Metadata can be saved back to the database using the `metadata!()` function. As an example, we
add random temperature metadata to all recordings being added to the database:
```julia
for f ∈ wavfiles("/path/to/recordings/20210127")
  id = push!(adb, f, "Zoom", "Clementi")
  push!(md, Dict(:recid => id, :temperature => 25 + 5 * randn()); cols=:union)
end
metadata!(adb, md)
```

### Annotating your recordings

You can add individual annotations to the database using a simple API:
```julia
annotate!(adb, "37c196e889ae1bb487a7c5c99632a051", "my_annotation", 5.0, 1.0; remarks="interesting sound")
```
This annotates the section from 5-6 seconds in the recording with ID `37c196e889ae1bb487a7c5c99632a051` with
an annotation type `my_annotation`. Any key-value pairs may be added to an annotation type. In this example,
we have a key `remarks` associated with this annotation type.

For bulk annotations, this API is not very efficient. A better way to do bulk annotations is shown below:
```julia
a = annotate!(adb, "37c196e889ae1bb487a7c5c99632a051", "my_annotation")
push!(a, 3.0, 1.0; remark="Interesting sound")
push!(a, 7.0, 1.0; remark="Another interesting sound")
close(a)
```
or using an alternative syntax:
```julia
annotate!(adb, "37c196e889ae1bb487a7c5c99632a051", "my_annotation") do a
  push!(a, 3.0, 1.0; remark="Interesting sound")
  push!(a, 7.0, 1.0; remark="Another interesting sound")
end
```

Both of these bulk annotation APIs overwrite previous annotations with the same annotation type. This behavior
allows annotation scripts to be re-run with changed parameters without creating duplicate annotations. If you
wish to retain old annotations and add on new ones, just add a `append=true` keyword argument when calling
`annotate!()` for bulk operations.

### Accessing your annotations

You can check what annotations are available in the database:
```julia
julia> annotationtypes(adb)
Set{String} with 1 element:
  "my_annotation"
```
or for a specific recording:
```julia
julia> annotationtypes(adb, "37c196e889ae1bb487a7c5c99632a051")
Set{String} with 1 element:
  "my_annotation"
```
You can access annotations for a specific recording:
```julia
julia> df = annotations(adb, "37c196e889ae1bb487a7c5c99632a051", "my_annotation")
2×5 DataFrame
 Row │ dts                      recid                              start    duration  remark
     │ DateTime…                Any                                Float64  Float64   String?
─────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────
   1 │ 2021-02-25T03:54:47.209  37c196e889ae1bb487a7c5c99632a051       3.0       1.0  Interesting sound
   2 │ 2021-02-25T03:54:47.567  37c196e889ae1bb487a7c5c99632a051       7.0       1.0  Another interesting sound
```
or you can query multiple recordings based on a criterion:
```julia
df = annotations(adb, "my_annotation"; location="Sisters Island")
```
You can specify criterion based on locations or date ranges, or you may manually filter based on metadata and
provide a list of `recIDs` to retreive annotations for.

### Sound clips

If the recordings are locally available (annotation database can be used without having all the recordings on
your local computer), you can fetch sound clips for any recording easily:
```julia
julia> samples, fs = soundclip(adb, "37c196e889ae1bb487a7c5c99632a051"; duration=1.5);
julia> fs
48000.0f0
julia> samples
72000×1 Matrix{Float64}:
  0.021996619939401142
  0.021030190113805546
  0.018787505482137857
  ⋮
 -0.02629256561905928
 -0.027895453917438258
 -0.029879573569246955
```
You can specify a `start` time (defaults to 0.0) and a `duration` (defaults to infinity). When working with annotations,
you can get the start time and duration automatically from the annotation:
```julia
julia> df = annotations(adb, recordings(adb).recid[1], "my_annotation");
julia> samples, fs = soundclip(adb, df[1,:])
([0.12964071388729975; 0.12362481637296872; … ; -0.0844528775755021; -0.08288086448679739], 48000.0f0)
```

COMING SOON: Automatic download of sound clips if not locally available!
