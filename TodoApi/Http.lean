namespace TodoApi

/-! ## Minimal HTTP/1.1 request parser and response builder -/

inductive HttpMethod where
  | GET | POST | PUT | DELETE | OTHER (s : String)
  deriving Repr, BEq

structure HttpRequest where
  method : HttpMethod
  path : String
  headers : List (String × String)
  body : String
  deriving Repr

structure HttpResponse where
  status : Nat
  statusText : String
  contentType : String := "application/json"
  body : String := ""

def parseMethod (s : String) : HttpMethod :=
  match s with
  | "GET"    => .GET
  | "POST"   => .POST
  | "PUT"    => .PUT
  | "DELETE" => .DELETE
  | other    => .OTHER other

def parseRequest (raw : String) : Option HttpRequest := do
  -- Split header section and body at blank line
  let parts := raw.splitOn "\r\n\r\n"
  let headerSection := parts.head!
  let body := if parts.length > 1 then
    "\r\n\r\n".intercalate parts.tail!
  else ""
  -- Parse request line
  let lines := headerSection.splitOn "\r\n"
  let requestLine := lines.head!
  let tokens := requestLine.splitOn " "
  guard (tokens.length ≥ 2)
  let method := parseMethod tokens[0]!
  let path := tokens[1]!
  -- Parse headers using splitOn
  let headerLines := lines.tail!
  let headers := headerLines.filterMap fun line =>
    match line.splitOn ": " with
    | key :: rest =>
      if rest.isEmpty then none
      else some (key, ": ".intercalate rest)
    | _ => none
  some { method, path, headers, body }

def HttpResponse.serialize (r : HttpResponse) : String :=
  let statusLine := "HTTP/1.1 " ++ toString r.status ++ " " ++ r.statusText ++ "\r\n"
  let headers := "Content-Type: " ++ r.contentType ++ "\r\n" ++
                 "Content-Length: " ++ toString r.body.utf8ByteSize ++ "\r\n" ++
                 "Connection: close\r\n"
  statusLine ++ headers ++ "\r\n" ++ r.body

def ok (body : String) : HttpResponse :=
  { status := 200, statusText := "OK", body }

def created (body : String) : HttpResponse :=
  { status := 201, statusText := "Created", body }

def noContent : HttpResponse :=
  { status := 204, statusText := "No Content", body := "" }

def badRequest (msg : String := "Bad Request") : HttpResponse :=
  { status := 400, statusText := "Bad Request",
    body := "{\"error\":\"" ++ msg ++ "\"}" }

def notFound : HttpResponse :=
  { status := 404, statusText := "Not Found",
    body := "{\"error\":\"Not Found\"}" }

def methodNotAllowed : HttpResponse :=
  { status := 405, statusText := "Method Not Allowed",
    body := "{\"error\":\"Method Not Allowed\"}" }

end TodoApi
