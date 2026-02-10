import TodoApi.Types
import TodoApi.Db
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

/-- Handle an HTTP request using the database. -/
def handleRequest (req : HttpRequest) (conn : PgConn) : IO HttpResponse :=
  match req.path, req.method with
  -- GET /todos
  | "/todos", .GET => do
    let todos ← dbGetAll conn
    return ok (todosToJson todos)
  -- POST /todos
  | "/todos", .POST =>
    match parseJsonBody req.body with
    | some (some title, _) => do
      let todo ← dbAdd conn title
      return created todo.toJson
    | _ =>
      return badRequest "Invalid JSON. Expected: {\\\"title\\\": \\\"...\\\"}"
  -- PUT /todos/:id
  | path, .PUT =>
    match extractId path with
    | some id =>
      match parseJsonBody req.body with
      | some (_, some completed) => do
        match ← dbUpdate conn id completed with
        | some todo => return ok todo.toJson
        | none => return notFound
      | _ => return badRequest "Invalid JSON. Expected: {\\\"completed\\\": true/false}"
    | none => return notFound
  -- DELETE /todos/:id
  | path, .DELETE =>
    match extractId path with
    | some id => do
      if ← dbDelete conn id then
        return noContent
      else
        return notFound
    | none => return notFound
  -- Anything else
  | "/todos", _ => return methodNotAllowed
  | _, _ => return notFound

end TodoApi
