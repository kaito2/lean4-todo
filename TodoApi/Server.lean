import TodoApi.Router

namespace TodoApi

/-! ## TCP server via C FFI -/

@[extern "lean_tcp_listen"]
opaque tcpListen (port : UInt16) : IO UInt32

@[extern "lean_tcp_accept"]
opaque tcpAccept (serverFd : UInt32) : IO UInt32

@[extern "lean_tcp_recv"]
opaque tcpRecv (fd : UInt32) : IO String

@[extern "lean_tcp_send"]
opaque tcpSend (fd : UInt32) (data : @& String) : IO Unit

@[extern "lean_tcp_close"]
opaque tcpClose (fd : UInt32) : IO Unit

/-- Handle a single client connection. -/
def handleClient (clientFd : UInt32) (store : IO.Ref Store) : IO Unit := do
  try
    let raw ← tcpRecv clientFd
    let response ← match parseRequest raw with
      | some req => do
        let s ← store.get
        let (resp, newStore) := handleRequest req s
        store.set newStore
        pure resp
      | none => pure (badRequest "Malformed HTTP request")
    tcpSend clientFd response.serialize
  catch e =>
    let errResp : HttpResponse :=
      { status := 500, statusText := "Internal Server Error",
        body := s!"\{\"error\":\"{e.toString}\"}",
        contentType := "application/json" }
    try tcpSend clientFd errResp.serialize catch _ => pure ()
  finally
    tcpClose clientFd

/-- Start the HTTP server on the given port. -/
def serve (port : UInt16 := 8080) : IO Unit := do
  let serverFd ← tcpListen port
  IO.println s!"Server listening on http://localhost:{port}"
  let store ← IO.mkRef Store.empty
  repeat do
    let clientFd ← tcpAccept serverFd
    handleClient clientFd store

end TodoApi
