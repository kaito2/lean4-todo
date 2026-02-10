import TodoApi

def main (args : List String) : IO Unit := do
  let port : UInt16 := match args.head? >>= (·.toNat?) with
    | some p => p.toUInt16
    | none   => 8080
  TodoApi.serve port
