import TodoApi.Types

namespace TodoApi

/-! ## Simple JSON serialization / deserialization
    Uses List Char for parsing to avoid String.Pos complexities. -/

private def quoteJsonString (s : String) : String :=
  "\"" ++ (s.toList.foldl (fun acc c =>
    acc ++ match c with
    | '"'  => "\\\""
    | '\\' => "\\\\"
    | '\n' => "\\n"
    | '\t' => "\\t"
    | c    => c.toString
  ) "") ++ "\""

def Todo.toJson (t : Todo) : String :=
  "{\"id\":" ++ toString t.id ++
  ",\"title\":" ++ quoteJsonString t.title ++
  ",\"completed\":" ++ toString t.completed ++ "}"

def todosToJson (ts : Array Todo) : String :=
  "[" ++ ",".intercalate (ts.toList.map Todo.toJson) ++ "]"

/-! ### Char-list based JSON body parser -/

private def isWs (c : Char) : Bool :=
  c == ' ' || c == '\n' || c == '\r' || c == '\t'

private def dropWs : List Char → List Char
  | c :: cs => if isWs c then dropWs cs else c :: cs
  | []      => []

/-- Parse a JSON string literal from a char list. Returns (value, rest). -/
private def parseStr : List Char → Option (String × List Char)
  | '"' :: cs => go "" cs
  | _         => none
where
  go (acc : String) : List Char → Option (String × List Char)
    | '"' :: rest        => some (acc, rest)
    | '\\' :: '"' :: cs  => go (acc.push '"') cs
    | '\\' :: '\\' :: cs => go (acc.push '\\') cs
    | '\\' :: 'n' :: cs  => go (acc.push '\n') cs
    | '\\' :: 't' :: cs  => go (acc.push '\t') cs
    | c :: cs            => go (acc.push c) cs
    | []                 => none

/-- Expect a specific char (skip whitespace). Returns rest on success. -/
private def expect (c : Char) (cs : List Char) : Option (List Char) :=
  match dropWs cs with
  | c' :: rest => if c' == c then some rest else none
  | []         => none

/-- Parse a bool literal. Returns (value, rest). -/
private def parseBoolLit (cs : List Char) : Option (Bool × List Char) :=
  match cs with
  | 't' :: 'r' :: 'u' :: 'e' :: rest         => some (true, rest)
  | 'f' :: 'a' :: 'l' :: 's' :: 'e' :: rest  => some (false, rest)
  | _                                          => none

/-- Parse JSON body: `{"title":"..."}` or `{"completed":true}` etc.
    Both fields are optional. Returns `none` only on malformed JSON. -/
def parseJsonBody (s : String) : Option (Option String × Option Bool) := do
  let cs := dropWs s.toList
  let cs ← expect '{' cs
  let mut rest := cs
  let mut title : Option String := none
  let mut completed : Option Bool := none
  for _ in List.range 10 do
    let ws := dropWs rest
    match ws with
    | '}' :: _ => break
    | ',' :: cs' => rest := dropWs cs'
    | _ => rest := ws
    -- Parse key
    let (key, afterKey) ← parseStr (dropWs rest)
    let afterColon ← expect ':' afterKey
    let valCs := dropWs afterColon
    match key with
    | "title" =>
      let (v, r) ← parseStr valCs
      title := some v
      rest := r
    | "completed" =>
      let (v, r) ← parseBoolLit valCs
      completed := some v
      rest := r
    | _ =>
      -- skip unknown value (crude: skip until , or })
      rest := valCs.dropWhile (fun c => c != ',' && c != '}')
  some (title, completed)

end TodoApi
