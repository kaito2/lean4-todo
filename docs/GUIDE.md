# lean-todo コードガイド

バックエンドエンジニア向けに、Lean 4 の知識がなくてもこのプロジェクトを理解できるようにしたドキュメント。Go / TypeScript / Python あたりの経験を想定している。

---

## 目次

1. [Lean 4 構文クイックリファレンス](#1-lean-4-構文クイックリファレンス)
2. [ビルドシステム (Lake)](#2-ビルドシステム-lake)
3. [ファイル別コードウォークスルー](#3-ファイル別コードウォークスルー)
4. [C FFI の仕組み](#4-c-ffi-の仕組み)
5. [リクエストライフサイクル](#5-リクエストライフサイクル)
6. [よくある疑問](#6-よくある疑問)

---

## 1. Lean 4 構文クイックリファレンス

このプロジェクトに登場する Lean 4 の構文を、他言語との対比で解説する。

### 1.1 基本型

| Lean 4 | Go | TypeScript | 意味 |
|---|---|---|---|
| `Nat` | `uint` | `number` | 自然数 (0以上の整数) |
| `String` | `string` | `string` | 文字列 |
| `Bool` | `bool` | `boolean` | 真偽値 |
| `UInt16` | `uint16` | `number` | 16bit 符号なし整数 |
| `UInt32` | `uint32` | `number` | 32bit 符号なし整数 |
| `Unit` | `struct{}` | `void` | 「値なし」を表す型 |
| `Array T` | `[]T` | `T[]` | 可変長配列 |
| `List T` | — | — | 連結リスト (配列とは別物) |
| `Option T` | `*T` (nilable) | `T \| undefined` | 値があるかないか |

### 1.2 構造体 (structure)

```lean
-- Lean 4
structure Todo where
  id : Nat
  title : String
  completed : Bool
```

```go
// Go 相当
type Todo struct {
    ID        uint
    Title     string
    Completed bool
}
```

`structure` は Go の struct、TypeScript の interface に近い。`where` の後にフィールドを列挙する。

**インスタンス生成:**

```lean
let todo : Todo := { id := 1, title := "Buy milk", completed := false }
```

```go
// Go 相当
todo := Todo{ID: 1, Title: "Buy milk", Completed: false}
```

**デフォルト値付きフィールド:**

```lean
structure HttpResponse where
  status : Nat
  statusText : String
  contentType : String := "application/json"  -- デフォルト値
  body : String := ""
```

`:= "application/json"` がデフォルト値。インスタンス生成時に省略可能。

### 1.3 列挙型 (inductive)

```lean
inductive HttpMethod where
  | GET | POST | PUT | DELETE | OTHER (s : String)
```

```go
// Go なら iota + 特別ケース
type HttpMethod int
const (
    GET HttpMethod = iota
    POST
    PUT
    DELETE
)
// OTHER は Go だと別の型が必要
```

```typescript
// TypeScript なら
type HttpMethod = "GET" | "POST" | "PUT" | "DELETE" | { other: string }
```

`OTHER (s : String)` のようにデータを持つバリアントが作れるのが Lean の特徴。TypeScript の discriminated union に近い。

### 1.4 パターンマッチ (match)

```lean
match req.path, req.method with
| "/todos", .GET    => ...    -- パスが "/todos" かつ GET
| "/todos", .POST   => ...    -- パスが "/todos" かつ POST
| path, .DELETE      => ...    -- パスは変数 path に束縛、メソッドは DELETE
| _, _               => ...    -- それ以外すべて
```

Go の `switch` に近いが、**複数の値を同時にマッチ**できる。`.GET` は `HttpMethod.GET` の省略形。`_` は「何でもいい」のワイルドカード。

### 1.5 Option とモナディック操作

`Option T` は「値があるかもしれないし、ないかもしれない」を表す型。

```lean
-- some = 値がある、none = 値がない
let x : Option Nat := some 42
let y : Option Nat := none
```

```go
// Go ならポインタで表現
var x *int = &fortyTwo  // some 42
var y *int = nil         // none
```

**`do` 記法で `Option` を連鎖:**

```lean
private def extractId (path : String) : Option Nat := do
  let parts := path.splitOn "/"
  guard (parts.length == 3)       -- false なら即 none を返す
  guard (parts[1]! == "todos")
  parts[2]!.toNat?                -- 数値変換失敗なら none
```

`do` ブロック内では `←` で値を取り出し、途中で `none` になったら **関数全体が即座に `none` を返す**。Go の early return パターンに近い:

```go
// Go 相当 (疑似コード)
func extractId(path string) *int {
    parts := strings.Split(path, "/")
    if len(parts) != 3 { return nil }
    if parts[1] != "todos" { return nil }
    id, err := strconv.Atoi(parts[2])
    if err != nil { return nil }
    return &id
}
```

### 1.6 IO モナド

Lean 4 は**純粋関数型言語**なので、副作用 (DB アクセス、ネットワーク I/O、コンソール出力) がある関数は戻り値の型に `IO` をつけて明示する。

```lean
def dbGetAll (conn : PgConn) : IO (Array Todo) := do ...
--                                ^^ 「副作用あり」のマーク
```

```go
// Go では特別なマークはないが、error を返すのが慣例
func dbGetAll(conn *PgConn) ([]Todo, error) { ... }
```

**`do` ブロックと `←`:**

```lean
def serve (port : UInt16 := 8080) : IO Unit := do
  let conn ← pgConnect connStr       -- ← は IO 操作の実行 (await に近い)
  dbInit conn                         -- 戻り値を使わない IO 操作
  let serverFd ← tcpListen port
  IO.println s!"Listening on {port}"  -- s!"..." は文字列補間
```

`←` は TypeScript の `await` と同じ感覚。IO 操作を実行して結果を取り出す。

```typescript
// TypeScript 相当
async function serve(port: number = 8080) {
  const conn = await pgConnect(connStr)   // ← と同じ
  await dbInit(conn)
  const serverFd = await tcpListen(port)
  console.log(`Listening on ${port}`)
}
```

### 1.7 `let` と `:=`

```lean
let x := 42                     -- 不変の変数束縛 (const に近い)
let mut counter := 0            -- 可変の変数束縛 (let に近い)
counter := counter + 1          -- 再代入

def foo (x : Nat) : String :=   -- 関数定義
  toString x
```

- `let` = ローカル変数の束縛
- `def` = トップレベル関数/定数の定義
- `:=` = 定義の本体を開始するマーク (Go の `:=` とは意味が違う)

### 1.8 `deriving`

```lean
structure Todo where
  id : Nat
  title : String
  completed : Bool
  deriving Repr, BEq, Inhabited
```

`deriving` は Go の code generation や Rust の `#[derive(...)]` に相当。コンパイラにインスタンスを自動生成させる。

| deriving | 意味 | 他言語の相当物 |
|---|---|---|
| `Repr` | デバッグ表示 (`repr todo`) | Go: `String()`, Rust: `Debug` |
| `BEq` | `==` で比較可能にする | Go: 構造体はデフォルトで比較可能 |
| `Inhabited` | デフォルト値を持つ | Go: ゼロ値 |

### 1.9 名前空間 (namespace)

```lean
namespace TodoApi

def serve ... := ...

end TodoApi
```

```go
// Go ならパッケージ
package todoapi

func Serve() { ... }
```

`namespace TodoApi` 内で定義された `serve` は、外部から `TodoApi.serve` として参照する。

### 1.10 import

```lean
import TodoApi.Types     -- TodoApi/Types.lean をインポート
import TodoApi.Db        -- TodoApi/Db.lean をインポート
```

ファイルパスがそのままモジュール名。`TodoApi/Types.lean` → `TodoApi.Types`。

### 1.11 private

```lean
private def extractId (path : String) : Option Nat := ...
```

`private` はそのファイル内でのみ使える関数。Go の小文字始まり (unexported) に相当。

### 1.12 try / catch / finally

```lean
try
  let raw ← tcpRecv clientFd
  ...
catch e =>
  ...    -- e は例外オブジェクト
finally
  tcpClose clientFd
```

Go の `defer` + error handling、TypeScript の `try/catch/finally` とほぼ同じ。

### 1.13 `@&` (borrowed reference)

```lean
opaque pgExec : @& PgConn → @& String → @& Array String → IO Nat
--               ^^          ^^          ^^
```

`@&` は「借用参照」。C FFI で呼び出し先に所有権を渡さないことを示す。C 側のシグネチャで `b_lean_obj_arg` (borrowed) に対応する。呼び出し側は普通に値を渡すだけで意識しなくてよい。

### 1.14 `#[]` (配列リテラル)

```lean
#[]                      -- 空配列
#["hello", "world"]      -- 要素2つの配列
#[title]                 -- 変数1つの配列
```

Go の `[]string{}` や `[]string{"hello", "world"}` に相当。

### 1.15 `String × String` (タプル / 直積型)

```lean
headers : List (String × String)     -- ヘッダーのキーバリューペアのリスト
```

`String × String` は2要素のタプル。Go の `struct{ Key, Value string }` や TypeScript の `[string, string]` に相当。

### 1.16 `some` / `none` と `match`

```lean
match store.delete id with
| some newStore => ...    -- 成功
| none => ...             -- 見つからなかった
```

```go
// Go 相当
if newStore, ok := store.Delete(id); ok {
    ...
} else {
    ...
}
```

### 1.17 パイプ演算子

```lean
args.head? >>= (·.toNat?)
```

`>>=` はモナドの bind。ここでは `Option` に対して使っている:

```
args.head?          -- Option String を返す
>>= (·.toNat?)     -- String があれば toNat? を適用、なければ none
```

`·` は無名関数の引数プレースホルダ。`(·.toNat?)` は `(fun x => x.toNat?)` の省略形。

---

## 2. ビルドシステム (Lake)

Lake は Lean 4 の公式ビルドツール。npm + webpack、Go の `go build` に相当する。設定は `lakefile.lean` に Lean 自身で記述する。

### lakefile.lean の読み方

```lean
import Lake
open Lake DSL
open System (FilePath)

-- パッケージ定義 (package.json の name + version に相当)
package «todo_api» where
  version := v!"0.1.0"
  moreLinkArgs := #["-L/opt/homebrew/opt/libpq/lib", "-lpq"]
  --               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  --               リンカに渡す追加フラグ (libpq をリンク)

-- Lean ライブラリ (TodoApi/ 配下の .lean ファイル群)
lean_lib «TodoApi» where
  srcDir := "."

-- 実行バイナリ (Main.lean がエントリーポイント)
@[default_target]
lean_exe «todo_api» where
  root := `Main

-- C ファイルのコンパイルルール
target ffi.o pkg : FilePath := do
  let oFile := pkg.buildDir / "ffi" / "ffi.o"
  let srcJob ← inputFile (pkg.dir / "ffi" / "ffi.c") true
  let leanInclude := (← getLeanIncludeDir).toString
  buildO oFile srcJob
    (weakArgs := #["-I", leanInclude,
                   "-I", "/opt/homebrew/opt/libpq/include",
                   "-I", "/usr/include/postgresql",
                   "-fPIC"])
    (compiler := "cc")

-- C オブジェクトファイルから静的ライブラリを作る
extern_lib libleanffi pkg := do
  let ffiO ← fetch (pkg.target ``ffi.o)
  let name := nameToStaticLib "leanffi"
  buildStaticLib (pkg.buildDir / "lib" / name) #[ffiO]
```

**ビルドフロー:**

```
ffi/ffi.c
  │  cc -c (コンパイル)
  ▼
.lake/build/ffi/ffi.o
  │  ar (静的ライブラリ化)
  ▼
.lake/build/lib/libleanffi.a ──┐
                                │
TodoApi/*.lean                  │  lake build
  │  lean (コンパイル → C → .o) │
  ▼                             │
.lake/build/ir/*.c.o ──────────┤
                                │  clang (リンク) + -lpq
                                ▼
                    .lake/build/bin/todo_api
```

### よく使うコマンド

```bash
lake build          # ビルド
lake clean          # ビルド成果物を削除
lake env printPaths # ツールチェーンのパスを表示
```

---

## 3. ファイル別コードウォークスルー

### 3.1 Main.lean — エントリーポイント

```lean
import TodoApi

def main (args : List String) : IO Unit := do
  let port : UInt16 := match args.head? >>= (·.toNat?) with
    | some p => p.toUInt16
    | none   => 8080
  TodoApi.serve port
```

**行ごとの解説:**

| 行 | 解説 |
|---|---|
| `import TodoApi` | `TodoApi.lean` を読み込む (これが全サブモジュールを re-export) |
| `def main (args : List String) : IO Unit` | Go の `func main()` に相当。Lean ではコマンドライン引数が `List String` として渡される |
| `args.head?` | リストの先頭要素を取得。空なら `none` |
| `>>= (·.toNat?)` | 先頭要素があれば `Nat` に変換を試みる |
| `some p => p.toUInt16` | 変換成功 → `UInt16` にキャスト |
| `none => 8080` | 引数なしまたは変換失敗 → デフォルト 8080 |

**Go 相当:**

```go
func main() {
    port := uint16(8080)
    if len(os.Args) > 1 {
        if p, err := strconv.Atoi(os.Args[1]); err == nil {
            port = uint16(p)
        }
    }
    todoapi.Serve(port)
}
```

### 3.2 TodoApi/Types.lean — データモデル

```lean
namespace TodoApi

structure Todo where
  id : Nat
  title : String
  completed : Bool
  deriving Repr, BEq, Inhabited

end TodoApi
```

プロジェクト全体で使うドメインモデルの定義。DB のレコード、JSON レスポンス、関数の引数/戻り値すべてでこの型を使う。

### 3.3 TodoApi/Http.lean — HTTP パーサーとレスポンスビルダー

このファイルは2つの役割を持つ。

#### 型定義

```lean
inductive HttpMethod where
  | GET | POST | PUT | DELETE | OTHER (s : String)

structure HttpRequest where
  method : HttpMethod
  path : String
  headers : List (String × String)
  body : String

structure HttpResponse where
  status : Nat
  statusText : String
  contentType : String := "application/json"
  body : String := ""
```

#### HTTP リクエストパーサー

```lean
def parseRequest (raw : String) : Option HttpRequest := do
```

生のソケットデータを `HttpRequest` に変換する。戻り値が `Option` なので、パースに失敗すると `none` を返す。

処理の流れ:

1. `\r\n\r\n` でヘッダーとボディを分割
2. 1行目 (リクエストライン) からメソッドとパスを取得
3. 残りの行からヘッダーを `key: value` 形式でパース
4. `some { method, path, headers, body }` を返す

**注意:** `parts.head!` の `!` は「この値は確実に存在する」という表明。存在しない場合はパニック (Go の `must()` パターンに近い)。`parts[0]!` のようにインデックスアクセスにも使う。

#### レスポンスヘルパー

```lean
def ok (body : String) : HttpResponse :=
  { status := 200, statusText := "OK", body }
```

Express.js の `res.status(200).json(body)` に相当するヘルパー関数群:

| 関数 | ステータス | 用途 |
|---|---|---|
| `ok` | 200 | 正常レスポンス |
| `created` | 201 | リソース作成成功 |
| `noContent` | 204 | 削除成功 |
| `badRequest` | 400 | リクエスト不正 |
| `notFound` | 404 | リソースなし |
| `methodNotAllowed` | 405 | メソッド不正 |

#### レスポンスのシリアライズ

```lean
def HttpResponse.serialize (r : HttpResponse) : String :=
  let statusLine := "HTTP/1.1 " ++ toString r.status ++ " " ++ r.statusText ++ "\r\n"
  let headers := "Content-Type: " ++ r.contentType ++ "\r\n" ++
                 "Content-Length: " ++ toString r.body.utf8ByteSize ++ "\r\n" ++
                 "Connection: close\r\n"
  statusLine ++ headers ++ "\r\n" ++ r.body
```

`HttpResponse` を HTTP/1.1 形式のバイト列 (文字列) に変換する。Go の `http.ResponseWriter.Write()` の中身を手書きしているイメージ。

`HttpResponse.serialize` という命名は「`HttpResponse` 型に対するメソッド `serialize`」を意味する (Go のレシーバ付き関数に相当)。呼び出し側では `response.serialize` とドット記法で使える。

### 3.4 TodoApi/Json.lean — JSON 処理

外部ライブラリを使わない手書き JSON パーサー/シリアライザ。

#### シリアライズ (Todo → JSON文字列)

```lean
def Todo.toJson (t : Todo) : String :=
  "{\"id\":" ++ toString t.id ++
  ",\"title\":" ++ quoteJsonString t.title ++
  ",\"completed\":" ++ toString t.completed ++ "}"
```

Go なら `json.Marshal()` でやることを手書きしている。`quoteJsonString` はエスケープ処理 (`"` → `\"`, `\n` → `\\n` など)。

#### デシリアライズ (JSON文字列 → フィールド値)

```lean
def parseJsonBody (s : String) : Option (Option String × Option Bool) := do
```

戻り値の型 `Option (Option String × Option Bool)` の読み方:

- 外側の `Option` → パース自体の成否
- 内側の `Option String` → `title` フィールドがあったか
- 内側の `Option Bool` → `completed` フィールドがあったか

```
"{"title":"Buy milk"}"             → some (some "Buy milk", none)
"{"completed":true}"               → some (none, some true)
"{"title":"foo","completed":true}" → some (some "foo", some true)
"{invalid"                         → none
```

**パーサーの内部実装:**

文字列を `List Char` (文字のリスト) に変換してから1文字ずつ消費していく手法を取っている。これは Lean の文字列インデックス操作が煩雑なため。

- `dropWs` — 先頭の空白を読み飛ばす
- `expect c` — 特定の文字を期待して消費
- `parseStr` — JSON文字列リテラルを読む (`"..."`)
- `parseBoolLit` — `true` / `false` リテラルを読む
- `for _ in List.range 10` — 最大10フィールドまでループ (無限ループ防止)

### 3.5 TodoApi/Db.lean — PostgreSQL データベース層

このファイルは3つの層で構成されている:

#### 層1: Opaque 型定義

```lean
opaque PgConnPointedType : NonemptyType
def PgConn : Type := PgConnPointedType.type
instance : Nonempty PgConn := PgConnPointedType.property
```

**これは何をやっている?**

C の `PGconn *` (libpq のコネクションポインタ) を Lean の型システムに持ち込むためのパターン。

- `opaque` — Lean コンパイラに「中身を見るな、型だけ知っていればいい」と伝える
- `NonemptyType` — 「最低1つの値が存在する型」であることの証明 (コンパイラが安全性を担保するために必要)
- `PgConn` — 実際に使う型名の別名

Go で例えると:

```go
// PgConn は C のポインタのラッパー。中身は隠蔽されている。
type PgConn struct{ ptr unsafe.Pointer }
```

#### 層2: FFI 宣言

```lean
@[extern "lean_pg_connect"]
opaque pgConnect : @& String → IO PgConn
```

これは「`lean_pg_connect` という名前の C 関数が存在し、`String` を受け取って `IO PgConn` を返す」という宣言。実体は `ffi/ffi.c` にある。

Go の `cgo` や Node.js の `node-ffi` に相当:

```go
// cgo 相当
// #include <libpq-fe.h>
// PGconn *lean_pg_connect(const char *conn_str);
import "C"
```

3つの FFI 関数:

| Lean 側 | C 側 | 用途 |
|---|---|---|
| `pgConnect : String → IO PgConn` | `lean_pg_connect` | DB接続を開く |
| `pgExec : PgConn → String → Array String → IO Nat` | `lean_pg_exec` | INSERT/UPDATE/DELETE (影響行数を返す) |
| `pgQuery : PgConn → String → Array String → IO (Array (Array String))` | `lean_pg_query` | SELECT (2次元配列を返す) |

#### 層3: 高レベル DB 操作

```lean
def dbGetAll (conn : PgConn) : IO (Array Todo) := do
  let rows ← pgQuery conn "SELECT id, title, completed FROM todos ORDER BY id" #[]
  return rows.filterMap rowToTodo
```

`pgQuery` が返す `Array (Array String)` (2次元文字列配列) を、`rowToTodo` で `Todo` 構造体に変換する。

`rowToTodo` の詳細:

```lean
private def rowToTodo (row : Array String) : Option Todo := do
  let id ← row[0]?.bind (·.toNat?)   -- row[0] を Nat に変換
  let title ← row[1]?                 -- row[1] をそのまま
  let compStr ← row[2]?               -- row[2] は "t" or "f"
  let completed := compStr == "t"      -- PostgreSQL の boolean text 表現
  some { id, title, completed }
```

- `row[0]?` — インデックスアクセス。範囲外なら `none` (`?` 付きなので安全)
- `.bind (·.toNat?)` — 文字列を自然数に変換を試みる
- `"t"` / `"f"` — PostgreSQL の `BOOLEAN` 型はテキストモードでこの値を返す

**SQL インジェクション防止:**

すべてのクエリで `$1`, `$2` プレースホルダを使い、`PQexecParams` で実行。ユーザー入力が SQL に直接埋め込まれることはない。

```lean
let rows ← pgQuery conn
  "INSERT INTO todos (title) VALUES ($1) RETURNING id, title, completed"
  #[title]    -- ← $1 に対応するパラメータ
```

### 3.6 TodoApi/Router.lean — ルーティング

Express.js のルーターに相当。パスとメソッドのマッチングを行い、適切なハンドラに振り分ける。

```lean
def handleRequest (req : HttpRequest) (conn : PgConn) : IO HttpResponse :=
  match req.path, req.method with
  | "/todos", .GET => do ...
  | "/todos", .POST => ...
  | path, .PUT => ...
  | path, .DELETE => ...
  | "/todos", _ => return methodNotAllowed
  | _, _ => return notFound
```

**Express.js で書くと:**

```javascript
router.get('/todos', async (req, res) => { ... })
router.post('/todos', async (req, res) => { ... })
router.put('/todos/:id', async (req, res) => { ... })
router.delete('/todos/:id', async (req, res) => { ... })
```

ただし Lean 版はフレームワークなしで `match` 式を使ったパターンマッチで実装している。

**PUT ハンドラの詳細:**

```lean
| path, .PUT =>
  match extractId path with            -- "/todos/42" → some 42
  | some id =>
    match parseJsonBody req.body with  -- body をパース
    | some (_, some completed) => do   -- completed フィールドあり
      match ← dbUpdate conn id completed with
      | some todo => return ok todo.toJson    -- 更新成功
      | none => return notFound               -- ID が存在しない
    | _ => return badRequest "..."
  | none => return notFound
```

ネストした `match` が深いが、やっていることは:

1. パスから ID を抽出
2. ボディの JSON をパース
3. DB を更新
4. 結果に応じてレスポンスを返す

### 3.7 TodoApi/Server.lean — TCP サーバー

サーバーのメインループと TCP 操作の FFI 宣言。

#### TCP FFI 宣言

```lean
@[extern "lean_tcp_listen"]
opaque tcpListen (port : UInt16) : IO UInt32
```

Go の `net.Listen("tcp", ":8080")` に相当する操作を C FFI で実装。ファイルディスクリプタ (`UInt32`) を直接扱う。

| 関数 | 対応する POSIX API | Go 相当 |
|---|---|---|
| `tcpListen` | `socket` + `bind` + `listen` | `net.Listen` |
| `tcpAccept` | `accept` | `listener.Accept()` |
| `tcpRecv` | `read` | `conn.Read()` |
| `tcpSend` | `write` (ループ) | `conn.Write()` |
| `tcpClose` | `close` | `conn.Close()` |

#### サーバー起動 (`serve`)

```lean
def serve (port : UInt16 := 8080) : IO Unit := do
  -- 1. DATABASE_URL 環境変数を読む (なければデフォルト)
  let connStr ← do
    match ← IO.getEnv "DATABASE_URL" with
    | some url => pure url
    | none => pure "host=localhost dbname=todo_api"

  -- 2. PostgreSQL に接続
  let conn ← pgConnect connStr

  -- 3. テーブルがなければ作成
  dbInit conn

  -- 4. TCP ソケットを開く
  let serverFd ← tcpListen port
  IO.println s!"Server listening on http://localhost:{port}"

  -- 5. 無限ループでクライアントを accept
  repeat do
    let clientFd ← tcpAccept serverFd
    handleClient clientFd conn
```

**`repeat do`** は無限ループ。Go の `for { ... }` に相当。

**注意:** このサーバーはシングルスレッド。1つのリクエストを処理している間、次のリクエストはブロックされる。

#### クライアント処理 (`handleClient`)

```lean
def handleClient (clientFd : UInt32) (conn : PgConn) : IO Unit := do
  try
    let raw ← tcpRecv clientFd              -- ソケットから読み取り
    let response ← match parseRequest raw with
      | some req => handleRequest req conn  -- パース成功 → ルーター
      | none => pure (badRequest "...")     -- パース失敗 → 400
    tcpSend clientFd response.serialize     -- レスポンス送信
  catch e =>
    ...                                     -- 500 エラー
  finally
    tcpClose clientFd                       -- 必ずソケットを閉じる
```

Go で書くと:

```go
func handleClient(fd int, conn *PgConn) {
    defer syscall.Close(fd)
    raw, err := recv(fd)
    if err != nil { ... }
    req, ok := parseRequest(raw)
    var resp HttpResponse
    if ok {
        resp = handleRequest(req, conn)
    } else {
        resp = badRequest("...")
    }
    send(fd, resp.Serialize())
}
```

---

## 4. C FFI の仕組み

### 4.1 概要

Lean 4 は C 言語との FFI (Foreign Function Interface) をサポートしている。仕組みは:

1. Lean コンパイラは **Lean コードを C に変換**してからコンパイルする
2. 手書きの C 関数を Lean から呼び出せる
3. C 側で Lean のオブジェクト (文字列、配列など) を操作する API がある

これは Go の cgo よりも低レベルで、Python の C Extension に近い。

### 4.2 Lean ↔ C の型マッピング

| Lean の型 | C の型 | 説明 |
|---|---|---|
| `lean_obj_arg` | — | Lean オブジェクトへの参照 (所有権あり) |
| `b_lean_obj_arg` | — | Lean オブジェクトへの参照 (借用、`@&` に対応) |
| `lean_obj_res` | — | Lean オブジェクトの戻り値 |
| `UInt32` | `uint32_t` | 値渡し |
| `UInt16` | `uint16_t` | 値渡し |
| `String` | `b_lean_obj_arg` | `lean_string_cstr()` で C文字列に変換 |
| `IO T` | `T + world` | 最後の引数に `lean_obj_arg world` が追加される |
| `Unit` | `lean_box(0)` | 空のタプル |
| `Nat` (小さい値) | `lean_box(n)` | タグ付きポインタとして格納 |
| `Array T` | `lean_obj_arg` | `lean_array_size()`, `lean_array_cptr()` で操作 |

### 4.3 IO 関数の変換ルール

Lean の `IO T` 型の関数は、C 側で **最後の引数に `lean_obj_arg world` が追加**される:

```lean
-- Lean 側
opaque pgConnect : @& String → IO PgConn
```

```c
// C 側 (world 引数が追加されている)
lean_obj_res lean_pg_connect(b_lean_obj_arg conn_str, lean_obj_arg world)
```

`world` は「現実世界の状態」を表すトークンで、IO 操作の順序を保証するためのもの。C 側では使わないが引数としては必要。

戻り値は `lean_io_result_mk_ok(value)` (成功) または `lean_io_result_mk_error(error)` (失敗) で返す。

### 4.4 外部オブジェクト (PgConn の仕組み)

C のポインタを Lean に持ち込むための仕組み:

```c
// 1. ファイナライザ (GC がオブジェクトを回収するときに呼ばれる)
static void pg_conn_finalize(void *ptr) {
    PGconn *conn = (PGconn *)ptr;
    if (conn) PQfinish(conn);     // コネクションを閉じる
}

// 2. external class を登録
static lean_external_class *g_pg_conn_class = NULL;
lean_register_external_class(pg_conn_finalize, pg_conn_foreach);

// 3. 外部オブジェクトを作成
lean_obj_res obj = lean_alloc_external(get_pg_conn_class(), (void *)conn);
return lean_io_result_mk_ok(obj);
```

**ポイント:**

- `lean_alloc_external` で C のポインタを Lean オブジェクトにラップ
- GC がこのオブジェクトを回収するとき、`pg_conn_finalize` が呼ばれて `PQfinish` でコネクションが閉じられる
- Go の `runtime.SetFinalizer()` と同じ仕組み

### 4.5 配列の操作

C 側で Lean の配列を操作する方法:

```c
// 読み取り (Lean Array → C)
size_t nParams = lean_array_size(params_obj);         // 配列の長さ
lean_obj_arg elem = lean_array_cptr(params_obj)[i];   // i番目の要素
const char *str = lean_string_cstr(elem);              // 文字列に変換

// 構築 (C → Lean Array)
lean_obj_res outer = lean_mk_empty_array();                           // []
row = lean_array_push(row, lean_mk_string("hello"));                  // ["hello"]
outer = lean_array_push(outer, row);                                  // [["hello"]]
```

### 4.6 pgQuery の実装解説

`pgQuery` は最も複雑な FFI 関数。全体像:

```c
LEAN_EXPORT lean_obj_res lean_pg_query(
    b_lean_obj_arg conn_obj,    // PgConn (借用)
    b_lean_obj_arg sql_obj,     // SQL文字列 (借用)
    b_lean_obj_arg params_obj,  // パラメータ配列 (借用)
    lean_obj_arg world          // IO トークン
) {
    // 1. Lean オブジェクト → C の値に変換
    PGconn *conn = pg_conn_of(conn_obj);
    const char *sql = lean_string_cstr(sql_obj);

    // 2. Lean Array String → const char** に変換
    size_t nParams = lean_array_size(params_obj);
    const char **paramValues = malloc(nParams * sizeof(char *));
    for (size_t i = 0; i < nParams; i++) {
        paramValues[i] = lean_string_cstr(lean_array_cptr(params_obj)[i]);
    }

    // 3. libpq でクエリ実行
    PGresult *res = PQexecParams(conn, sql, nParams, NULL, paramValues, ...);

    // 4. 結果を Lean Array (Array String) に変換
    lean_obj_res outer = lean_mk_empty_array();
    for (int r = 0; r < PQntuples(res); r++) {
        lean_obj_res row = lean_mk_empty_array();
        for (int c = 0; c < PQnfields(res); c++) {
            row = lean_array_push(row, lean_mk_string(PQgetvalue(res, r, c)));
        }
        outer = lean_array_push(outer, row);
    }

    // 5. 成功結果として返す
    return lean_io_result_mk_ok(outer);
}
```

---

## 5. リクエストライフサイクル

`curl -X POST localhost:8080/todos -d '{"title":"Buy milk"}'` を例に、処理の全流れを追う。

### Step 1: TCP 接続の確立

```
Server.lean: serve
  │
  │  repeat do
  │    let clientFd ← tcpAccept serverFd   ← ここでブロック、接続を待つ
  │    handleClient clientFd conn
  ▼

ffi.c: lean_tcp_accept
  → accept() システムコール
  → 新しい fd を返す
```

### Step 2: リクエストの受信とパース

```
Server.lean: handleClient
  │
  │  let raw ← tcpRecv clientFd
  │  -- raw = "POST /todos HTTP/1.1\r\nHost: localhost:8080\r\n\r\n{\"title\":\"Buy milk\"}"
  │
  │  match parseRequest raw with
  │  | some req => ...
  ▼

Http.lean: parseRequest
  → method = .POST
  → path = "/todos"
  → body = "{\"title\":\"Buy milk\"}"
  → HttpRequest を返す
```

### Step 3: ルーティングとビジネスロジック

```
Server.lean: handleRequest req conn
  │
  │  match req.path, req.method with
  │  | "/todos", .POST => ...
  ▼

Router.lean: POST /todos ハンドラ
  │
  │  parseJsonBody req.body
  │  → some (some "Buy milk", none)
  │
  │  let todo ← dbAdd conn "Buy milk"
  ▼

Db.lean: dbAdd
  │
  │  pgQuery conn "INSERT INTO todos (title) VALUES ($1) RETURNING ..." #["Buy milk"]
  ▼

ffi.c: lean_pg_query
  → PQexecParams(conn, "INSERT ...", 1, ..., ["Buy milk"], ...)
  → PostgreSQL にクエリ送信
  → 結果: [["1", "Buy milk", "f"]]
  → Lean Array (Array String) に変換して返す

Db.lean: rowToTodo
  → { id := 1, title := "Buy milk", completed := false }
```

### Step 4: レスポンスの構築と送信

```
Router.lean:
  │  return created todo.toJson
  │  -- created は status=201 の HttpResponse を作る
  ▼

Json.lean: Todo.toJson
  → "{\"id\":1,\"title\":\"Buy milk\",\"completed\":false}"

Http.lean: HttpResponse.serialize
  → "HTTP/1.1 201 Created\r\nContent-Type: application/json\r\n..."

Server.lean:
  │  tcpSend clientFd response.serialize
  │  tcpClose clientFd    (finally ブロック)
  ▼

ffi.c: lean_tcp_send → write() システムコール
ffi.c: lean_tcp_close → close() システムコール
```

### シーケンス図

```
Client          Server.lean      Router.lean     Db.lean        ffi.c          PostgreSQL
  │                 │                │              │              │               │
  │─── TCP ────────▶│                │              │              │               │
  │                 │ tcpRecv        │              │              │               │
  │                 │───────────────────────────────────────────▶│               │
  │                 │               parseRequest    │              │               │
  │                 │──────────────▶│                │              │               │
  │                 │               │ handleRequest  │              │               │
  │                 │               │──────────────▶│              │               │
  │                 │               │               │  pgQuery     │               │
  │                 │               │               │─────────────▶│  PQexecParams │
  │                 │               │               │              │──────────────▶│
  │                 │               │               │              │◀──────────────│
  │                 │               │               │◀─────────────│               │
  │                 │               │◀──────────────│              │               │
  │                 │◀──────────────│               │              │               │
  │                 │ tcpSend       │               │              │               │
  │◀────────────────│               │              │              │               │
  │                 │ tcpClose      │               │              │               │
```

---

## 6. よくある疑問

### Q: `!` は何?

```lean
parts.head!        -- head? ではなく head!
tokens[0]!         -- tokens[0]? ではなく tokens[0]!
```

`!` 付きの操作は「値が必ず存在する」と仮定して直接アクセスする。存在しない場合はパニック (クラッシュ)。`?` 付きは `Option` を返す安全な版。

| バリアント | 戻り値 | 値がない場合 |
|---|---|---|
| `arr[i]!` | `T` | パニック |
| `arr[i]?` | `Option T` | `none` |

Go の `map[key]` (パニック) vs `val, ok := map[key]` (安全) に近い。

### Q: `pure` と `return` の違いは?

```lean
| none => pure (badRequest "...")     -- pure
| some req => return ok todo.toJson  -- return
```

実質的に同じ。どちらも「この値を IO 結果として返す」。`return` は `do` ブロック内の糖衣構文。

### Q: なぜ JSON パーサーを手書きしている?

Lean 4 のエコシステムはまだ若く、広く使われる JSON ライブラリが確立していない。このプロジェクトは外部依存ゼロを目指しているため手書きしている。実運用では [lean4-json](https://github.com/leanprover-community/lean4-json) などのライブラリを使う方が良い。

### Q: なぜシングルスレッド?

Lean 4 の `Task` (軽量スレッド) を使えば並行処理は可能だが、このプロジェクトではシンプルさを優先している。高負荷対応が必要な場合は、`IO.asTask` で各クライアント処理を別タスクにオフロードする設計になる。

### Q: `opaque` は何のために?

```lean
opaque tcpListen (port : UInt16) : IO UInt32
```

`opaque` は「この関数の実装はLeanの中にはない (外部に存在する)」ことを宣言する。Go の `//go:linkname` や TypeScript の `declare function` に相当。コンパイラは型情報だけを信じて、実際の実装は C リンカが解決する。

### Q: `s!"..."` は何?

```lean
IO.println s!"Server listening on http://localhost:{port}"
```

文字列補間 (string interpolation)。`{port}` の部分が変数の値に置き換わる。TypeScript のテンプレートリテラル `` `Server listening on port ${port}` `` と同じ。

### Q: `filterMap` は何?

```lean
rows.filterMap rowToTodo
```

`map` + `filter` の合体版。各要素に関数を適用し、`some` の結果だけを集めて `none` は除外する。

```typescript
// TypeScript 相当
rows.map(rowToTodo).filter(x => x !== undefined)
```

### Q: `←` が2箇所で違う意味に見える

```lean
-- IO の do ブロック内
let conn ← pgConnect connStr      -- IO 操作を実行して結果を取り出す

-- Option の do ブロック内
let id ← row[0]?.bind (·.toNat?)  -- Option を展開、none なら即終了
```

`←` は「コンテキスト (IO や Option) から値を取り出す」という汎用的な操作。コンテキストが IO なら副作用を実行し、Option なら none チェックを行う。TypeScript の `await` は IO のケースだけだが、Lean の `←` はあらゆるモナドで使える。
