import TodoApi.Types

namespace TodoApi

/-! ## PostgreSQL database layer via libpq FFI -/

opaque PgConnPointedType : NonemptyType
def PgConn : Type := PgConnPointedType.type
instance : Nonempty PgConn := PgConnPointedType.property

@[extern "lean_pg_connect"]
opaque pgConnect : @& String → IO PgConn

@[extern "lean_pg_exec"]
opaque pgExec : @& PgConn → @& String → @& Array String → IO Nat

@[extern "lean_pg_query"]
opaque pgQuery : @& PgConn → @& String → @& Array String → IO (Array (Array String))

/-! ### High-level DB operations -/

private def rowToTodo (row : Array String) : Option Todo := do
  let id ← row[0]?.bind (·.toNat?)
  let title ← row[1]?
  let compStr ← row[2]?
  let completed := compStr == "t"
  some { id, title, completed }

def dbInit (conn : PgConn) : IO Unit := do
  let _ ← pgExec conn
    "CREATE TABLE IF NOT EXISTS todos (id SERIAL PRIMARY KEY, title TEXT NOT NULL, completed BOOLEAN NOT NULL DEFAULT FALSE)"
    #[]

def dbGetAll (conn : PgConn) : IO (Array Todo) := do
  let rows ← pgQuery conn "SELECT id, title, completed FROM todos ORDER BY id" #[]
  return rows.filterMap rowToTodo

def dbAdd (conn : PgConn) (title : String) : IO Todo := do
  let rows ← pgQuery conn
    "INSERT INTO todos (title) VALUES ($1) RETURNING id, title, completed"
    #[title]
  match rows[0]?.bind rowToTodo with
  | some todo => return todo
  | none => throw (.userError "INSERT returned no rows")

def dbUpdate (conn : PgConn) (id : Nat) (completed : Bool) : IO (Option Todo) := do
  let rows ← pgQuery conn
    "UPDATE todos SET completed = $2 WHERE id = $1 RETURNING id, title, completed"
    #[toString id, if completed then "t" else "f"]
  return rows[0]?.bind rowToTodo

def dbDelete (conn : PgConn) (id : Nat) : IO Bool := do
  let n ← pgExec conn "DELETE FROM todos WHERE id = $1" #[toString id]
  return n > 0

end TodoApi
