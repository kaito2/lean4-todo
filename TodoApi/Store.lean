import TodoApi.Types

namespace TodoApi

structure Store where
  todos : Array Todo
  nextId : Nat
  deriving Repr

def Store.empty : Store :=
  { todos := #[], nextId := 1 }

def Store.getAll (s : Store) : Array Todo :=
  s.todos

def Store.add (s : Store) (title : String) : Store × Todo :=
  let todo : Todo := { id := s.nextId, title, completed := false }
  ({ todos := s.todos.push todo, nextId := s.nextId + 1 }, todo)

def Store.update (s : Store) (id : Nat) (completed : Bool) : Option (Store × Todo) :=
  match s.todos.findIdx? (fun t => t.id == id) with
  | some idx =>
    let old := s.todos[idx]!
    let updated : Todo := { old with completed }
    some ({ s with todos := s.todos.set! idx updated }, updated)
  | none => none

def Store.delete (s : Store) (id : Nat) : Option Store :=
  if s.todos.any (fun t => t.id == id) then
    some { s with todos := s.todos.filter (fun t => t.id != id) }
  else
    none

end TodoApi
