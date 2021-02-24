using Test, CSV, DataFrames
using AcousticAnnotations

@testset "open/create/close" begin
  dbroot = tempname()
  @test_throws ErrorException ADB(dbroot)
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
  @test id1 == recid("test1.wav")
  adb = ADB(dbroot; create=true)
  mkpath(joinpath(dbroot, "recordings"))
  cp("test1.wav", joinpath(dbroot, "recordings/test1.wav"))
  cp("test1.wav", joinpath(dbroot, "recordings/test2.wav"))
  @test id1 == recid(joinpath(dbroot, "recordings/test1.wav"))
  @test id1 == recid(joinpath(dbroot, "recordings/test2.wav"))
  f = wavfiles(joinpath(dbroot, "recordings"))
  @test length(f) == 2
  @test size(recordings(adb), 1) == 0
  for f1 ∈ f
    push!(adb, f1, "Test", "Test")
  end
  @test size(recordings(adb), 1) == 1
  for f1 ∈ f
    push!(adb, f1, "Test", "Test")
  end
  @test size(recordings(adb), 1) == 1
  close(adb)
  adb = ADB(dbroot)
  @test size(recordings(adb), 1) == 1
  close(adb)
end
