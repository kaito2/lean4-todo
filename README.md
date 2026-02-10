# lean-todo

Lean 4 で書かれた TODO REST API サーバー。HTTP パーサー・TCP ソケット・PostgreSQL 接続をすべて C FFI で実装しており、外部の Lean ライブラリに依存しない。

## 技術スタック

| レイヤー | 実装 |
|---|---|
| 言語 | Lean 4 (v4.27.0) |
| ビルド | Lake |
| HTTP | 自前パーサー (ffi.c / Http.lean) |
| TCP | BSD ソケット via C FFI |
| DB | PostgreSQL — libpq via C FFI |
| コンテナ | Docker + Docker Compose |

## クイックスタート (Docker Compose)

```bash
docker compose up --build -d
```

PostgreSQL と API サーバーが起動し、`http://localhost:8080` で利用可能になる。

```bash
# 停止
docker compose down

# データボリュームも削除する場合
docker compose down -v
```

## ローカル開発

### 前提条件

- [elan](https://github.com/leanprover/elan) (Lean ツールチェーンは `lean-toolchain` で自動管理)
- PostgreSQL + libpq

```bash
# macOS
brew install libpq
brew install postgresql@16   # または既存の PostgreSQL

# DB 作成
createdb todo_api
```

### ビルド & 実行

```bash
lake build
DATABASE_URL="host=localhost dbname=todo_api" .lake/build/bin/todo_api
```

ポートはデフォルト 8080。引数で変更可能:

```bash
.lake/build/bin/todo_api 3000
```

## API

すべてのエンドポイントは `application/json` で応答する。

### `GET /todos`

全 TODO を取得する。

```bash
curl localhost:8080/todos
```

```json
[
  {"id": 1, "title": "Buy milk", "completed": false}
]
```

### `POST /todos`

TODO を追加する。

```bash
curl -X POST localhost:8080/todos -d '{"title": "Buy milk"}'
```

```json
{"id": 1, "title": "Buy milk", "completed": false}
```

### `PUT /todos/:id`

TODO の完了状態を更新する。

```bash
curl -X PUT localhost:8080/todos/1 -d '{"completed": true}'
```

```json
{"id": 1, "title": "Buy milk", "completed": true}
```

### `DELETE /todos/:id`

TODO を削除する。成功時は `204 No Content` を返す。

```bash
curl -X DELETE localhost:8080/todos/1
```

## プロジェクト構成

```
.
├── Main.lean              # エントリーポイント (ポート解析 → serve)
├── TodoApi.lean           # モジュール re-export
├── TodoApi/
│   ├── Types.lean         # Todo 構造体
│   ├── Http.lean          # HttpRequest / HttpResponse / パーサー
│   ├── Json.lean          # JSON シリアライズ / デシリアライズ
│   ├── Db.lean            # PgConn opaque 型 + DB 操作 (FFI 宣言)
│   ├── Router.lean        # ルーティング (パスマッチ → DB 操作 → レスポンス)
│   └── Server.lean        # TCP サーバーループ + DB 接続管理
├── ffi/
│   └── ffi.c              # C FFI (TCP ソケット + libpq)
├── lakefile.lean           # ビルド設定
├── Dockerfile              # マルチステージビルド
└── docker-compose.yml      # PostgreSQL + API サーバー
```

## 環境変数

| 変数 | デフォルト | 説明 |
|---|---|---|
| `DATABASE_URL` | `host=localhost dbname=todo_api` | libpq 接続文字列 |

## アーキテクチャ

### C FFI

`ffi/ffi.c` に以下の FFI 関数を実装している:

**TCP** — `lean_tcp_listen`, `lean_tcp_accept`, `lean_tcp_recv`, `lean_tcp_send`, `lean_tcp_close`

**PostgreSQL** — `lean_pg_connect`, `lean_pg_exec`, `lean_pg_query`

- `PgConn` は `lean_external_class` で管理され、GC の finalizer で `PQfinish` が呼ばれる
- 全クエリは `PQexecParams` を使用し、SQLインジェクションを防止

### リクエストの流れ

```
クライアント
  │
  ▼
TCP accept (ffi.c)
  │
  ▼
parseRequest (Http.lean)    ← 生バイト列 → HttpRequest
  │
  ▼
handleRequest (Router.lean) ← パスマッチ → DB 操作 → HttpResponse
  │
  ▼
TCP send (ffi.c)            ← HttpResponse.serialize → 生バイト列
```

### Docker ビルド

マルチステージビルドを採用:

1. **Build stage** — Ubuntu 24.04 + elan + Lean ツールチェーン + libpq-dev でコンパイル
2. **Runtime stage** — Ubuntu 24.04 + libpq5 のみ。ビルド済みバイナリをコピー

Lean ツールチェーンの bundled linker は `--sysroot` を使うため、libpq を toolchain の lib ディレクトリにシンボリックリンクしている。
