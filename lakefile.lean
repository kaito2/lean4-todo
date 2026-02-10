import Lake
open Lake DSL
open System (FilePath)

package «todo_api» where
  version := v!"0.1.0"

lean_lib «TodoApi» where
  srcDir := "."

@[default_target]
lean_exe «todo_api» where
  root := `Main

target ffi.o pkg : FilePath := do
  let oFile := pkg.buildDir / "ffi" / "ffi.o"
  let srcJob ← inputFile (pkg.dir / "ffi" / "ffi.c") true
  let leanInclude := (← getLeanIncludeDir).toString
  buildO oFile srcJob (weakArgs := #["-I", leanInclude, "-fPIC"]) (compiler := "cc")

extern_lib libleanffi pkg := do
  let ffiO ← fetch (pkg.target ``ffi.o)
  let name := nameToStaticLib "leanffi"
  buildStaticLib (pkg.buildDir / "lib" / name) #[ffiO]
