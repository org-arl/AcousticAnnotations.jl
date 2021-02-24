using Test, CSV, DataFrames, Dates
using AcousticAnnotations

@testset "open/create/close" begin
  dbroot = tempname()
  @test_throws ArgumentError ADB(dbroot)
  adb = ADB(dbroot; create=true)
  @test adb isa ADB
  @test close(adb) === nothing
  @test isdir(dbroot)
  @test isdir(joinpath(dbroot, "annotations"))
  @test isfile(joinpath(dbroot, "README.md"))
  @test isfile(joinpath(dbroot, ".gitignore"))
  @test isfile(joinpath(dbroot, "recordings.csv"))
  df = CSV.read(joinpath(dbroot, "recordings.csv"), DataFrame)
  @test size(df) == (0, 6)
  adb = ADB(dbroot)
  @test adb isa ADB
  info = projectinfo(adb)
  @test info isa Dict
  @test length(info) == 1
  @test info["project"] == basename(dbroot)
  adb.recdirty[] = true
  @test flush(adb) === nothing
  @test adb.recdirty[] == false
  adb.recdirty[] = true
  @test close(adb) === nothing
  @test adb.recdirty[] == false
end

@testset "recordings" begin
  dbroot = tempname()
  id1 = recid("test1.wav")
  id2 = recid("test2.wav")
  @test id1 != id2
  @test id1 == recid("test1.wav")
  @test id2 == recid("test2.wav")
  adb = ADB(dbroot; create=true)
  mkpath(joinpath(dbroot, "recordings"))
  cp("test1.wav", joinpath(dbroot, "recordings/test1.wav"))
  cp("test1.wav", joinpath(dbroot, "recordings/test1a.wav"))
  cp("test2.wav", joinpath(dbroot, "recordings/test2.wav"))
  @test id1 == recid(joinpath(dbroot, "recordings/test1.wav"))
  @test id1 == recid(joinpath(dbroot, "recordings/test1a.wav"))
  @test id2 == recid(joinpath(dbroot, "recordings/test2.wav"))
  f = wavfiles(joinpath(dbroot, "recordings"))
  @test length(f) == 3
  @test size(recordings(adb), 1) == 0
  for f1 ∈ f
    push!(adb, f1, "Test", "Test")
  end
  @test size(recordings(adb), 1) == 2
  for f1 ∈ f
    push!(adb, f1, "Test", "Test")
  end
  @test size(recordings(adb), 1) == 2
  close(adb)
  adb = ADB(dbroot)
  @test size(recordings(adb), 1) == 2
  close(adb)
end

@testset "annotations" begin
  dbroot = tempname()
  adb = ADB(dbroot; create=true)
  mkpath(joinpath(dbroot, "recordings"))
  cp("test1.wav", joinpath(dbroot, "recordings/test1.wav"))
  cp("test2.wav", joinpath(dbroot, "recordings/test2.wav"))
  push!(adb, joinpath(dbroot, "recordings/test1.wav"), "Zoom", "Loc1")
  push!(adb, joinpath(dbroot, "recordings/test2.wav"), "Zoom", "Loc2")
  @test size(recordings(adb), 1) == 2
  id1 = recordings(adb).recid[1]
  id2 = recordings(adb).recid[2]
  @test annotationtypes(adb) isa AbstractSet
  @test length(annotationtypes(adb)) == 0
  @test annotationtypes(adb, id1) isa AbstractSet
  @test length(annotationtypes(adb, id1)) == 0
  annotate!(adb, id1, "anno1", 1.5, 1.0; remark="works")
  @test length(annotationtypes(adb)) == 1
  @test length(annotationtypes(adb, id1)) == 1
  @test length(annotationtypes(adb, id2)) == 0
  @test annotations(adb, id1, "anno1") isa DataFrame
  @test size(annotations(adb, id1, "anno1"), 1) == 1
  @test annotations(adb, id2, "anno1") isa DataFrame
  @test size(annotations(adb, id2, "anno1"), 1) == 0
  a = annotations(adb, id1, "anno1")
  @test propertynames(a) == [:dts, :recid, :start, :duration, :remark]
  @test a[1,:dts] isa DateTime
  @test a[1,:start] == 1.5
  @test a[1,:duration] == 1.0
  @test a[1,:remark] == "works"
  annotate!(adb, id1, "anno1", 2.0, 1.2; remark="works too!", newcol="new column")
  @test size(annotations(adb, id1, "anno1"), 1) == 2
  @test size(annotations(adb, id2, "anno1"), 1) == 0
  a = annotations(adb, id1, "anno1")
  @test propertynames(a) == [:dts, :recid, :start, :duration, :remark, :newcol]
  @test a[1,:newcol] === missing
  @test a[2,:start] == 2.0
  @test a[2,:duration] == 1.2
  @test a[2,:remark] == "works too!"
  @test a[2,:newcol] === "new column"
  @test length(annotationtypes(adb)) == 1
  @test length(annotationtypes(adb, id1)) == 1
  @test length(annotationtypes(adb, id2)) == 0
  annotate!(adb, id1, "anno2", 2.5, 1.0; remark="hope")
  annotate!(adb, id2, "anno2", 2.5, 1.0; remark="epoh")
  @test length(annotationtypes(adb)) == 2
  @test length(annotationtypes(adb, id1)) == 2
  @test length(annotationtypes(adb, id2)) == 1
  a = annotations(adb, id1, "anno2")
  @test propertynames(a) == [:dts, :recid, :start, :duration, :remark]
  @test size(a, 1) == 1
  a = annotations(adb, id2, "anno2")
  @test propertynames(a) == [:dts, :recid, :start, :duration, :remark]
  @test size(a, 1) == 1
  annotate!(adb, id2, "anno2") do a
    for j ∈ 1:10
      push!(a, randn(), randn())
    end
  end
  a = annotations(adb, id2, "anno2")
  @test propertynames(a) == [:dts, :recid, :start, :duration]
  @test size(a, 1) == 10
  annotate!(adb, id2, "anno2"; append=true) do a
    for j ∈ 1:5
      push!(a, randn(), randn(); newcol=rand())
    end
  end
  a = annotations(adb, id2, "anno2")
  @test propertynames(a) == [:dts, :recid, :start, :duration, :newcol]
  @test size(a, 1) == 15
  a = annotations(adb, "anno2")
  @test propertynames(a) == [:dts, :recid, :start, :duration, :remark, :newcol]
  @test size(a, 1) == 16
  @test size(annotations(adb, "anno2"; location="Loc1"), 1)  == 1
  @test size(annotations(adb, "anno2"; location="Loc2"), 1) == 15
  @test size(annotations(adb, "anno2"; recids=[]), 1) == 0
  @test size(annotations(adb, "anno2"; recids=[id1]), 1) == 1
  @test size(annotations(adb, "anno2"; recids=[id2]), 1) == 15
  @test size(annotations(adb, "anno2"; recids=[id1, id2]), 1) == 16
  close(adb)
end

@testset "metadata" begin
  dbroot = tempname()
  adb = ADB(dbroot; create=true, recroot=".")
  md = metadata(adb)
  @test md isa DataFrame
  @test size(md) == (0, 1)
  for f ∈ wavfiles(".")
    id = push!(adb, f, "Zoom", "Clementi")
    push!(md, Dict(:recid => id, :temperature => 25 + 5 * randn()); cols=:union)
  end
  metadata!(adb, md)
  md = metadata(adb)
  @test md isa DataFrame
  @test size(md) == (2, 2)
  @test propertynames(md) == [:recid, :temperature]
  close(adb)
  adb = ADB(dbroot; create=true)
  md = metadata(adb)
  @test md isa DataFrame
  @test size(md) == (2, 2)
  @test propertynames(md) == [:recid, :temperature]
  close(adb)
end

@testset "soundclips" begin
  dbroot = tempname()
  adb = ADB(dbroot; create=true)
  mkpath(joinpath(dbroot, "recordings"))
  cp("test1.wav", joinpath(dbroot, "recordings/test1.wav"))
  cp("test2.wav", joinpath(dbroot, "recordings/test2.wav"))
  id1 = push!(adb, joinpath(dbroot, "recordings/test1.wav"), "Zoom", "Loc1")
  id2 = push!(adb, joinpath(dbroot, "recordings/test2.wav"), "Zoom", "Loc2")
  data, fs = soundclip(adb, id1)
  @test fs == 44100.0f0
  @test size(data) == (132091, 1)
  data, fs = soundclip(adb, id2; duration=1.0)
  @test fs == 44100.0f0
  @test size(data) == (44100, 1)
  data, fs = soundclip(adb, id2; start=1.0, duration=1.0)
  @test fs == 44100.0f0
  @test size(data) == (44100, 1)
  data, fs = soundclip(adb, id1; start=1.0)
  @test fs == 44100.0f0
  @test size(data) == (132090 - 44100, 1)
  annotate!(adb, id1, "anno1", 1.2, 1.5; remark="works")
  a = annotations(adb, id1, "anno1")
  data, fs = soundclip(adb, first(a))
  @test fs == 44100.0f0
  @test size(data) == (66150, 1)
  close(adb)
  adb = ADB(dbroot; recroot="wrong")
  @test soundclip(adb, id1) === missing
  @test soundclip(adb, id2) === missing
  close(adb)
  adb = ADB(dbroot)
  @test soundclip(adb, id1) !== missing
  @test soundclip(adb, id2) !== missing
  close(adb)
end
