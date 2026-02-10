import TodoApi.Types
import TodoApi.Store
import TodoApi.Json
import TodoApi.Http

namespace TodoApi

/-! ## Route matching and request dispatch -/

/-- Extract numeric ID from path like "/todos/42" -/
private def extractId (path : String) : Option Nat := do
  let parts := path.splitOn "/"
  -- "/todos/42" splits to ["", "todos", "42"]
  guard (parts.length == 3)
  guard (parts[1]! == "todos")
  parts[2]!.toNat?

/-- Handle an HTTP request, returning a response and updated store. -/
def handleRequest (req : HttpRequest) (store : Store) : HttpResponse × Store :=
  match req.path, req.method with
  -- GET /todos
  | "/todos", .GET =>
    let json := todosToJson store.getAll
    (ok json, store)
  -- POST /todos
  | "/todos", .POST =>
    match parseJsonBody req.body with
    | some (some title, _) =>
      let (newStore, todo) := store.add title
      (created todo.toJson, newStore)
    | _ =>
      (badRequest "Invalid JSON. Expected: {\\\"title\\\": \\\"...\\\"}", store)
  -- PUT /todos/:id
  | path, .PUT =>
    match extractId path with
    | some id =>
      match parseJsonBody req.body with
      | some (_, some completed) =>
        match store.update id completed with
        | some (newStore, todo) => (ok todo.toJson, newStore)
        | none => (notFound, store)
      | _ => (badRequest "Invalid JSON. Expected: {\\\"completed\\\": true/false}", store)
    | none => (notFound, store)
  -- DELETE /todos/:id
  | path, .DELETE =>
    match extractId path with
    | some id =>
      match store.delete id with
      | some newStore => (noContent, newStore)
      | none => (notFound, store)
    | none => (notFound, store)
  -- Anything else
  | "/todos", _ => (methodNotAllowed, store)
  | _, _ => (notFound, store)

end TodoApi
