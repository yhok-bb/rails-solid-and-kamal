# ChronosHub 学習ロードマップ

Rails 8 × Kamal 2 × Solid系 を軸に、「旧インフラ構成の体感 → Rails 8への移行 → 本番デプロイ → 負荷検証」までを一貫して経験するためのプロジェクト。

---

## アーキテクチャ概要（最終構成）

```
[ブラウザ]
    │ HTTPS
    ▼
[Cloudflare]  ← DNS / CDN / WAF
    │
    ▼
[VPS (Ubuntu)]
    └── [Docker]
           ├── Kamal Proxy  ← ポート80/443、SSL終端、コンテナルーティング
           │       ▼
           ├── Thruster     ← 静的アセット圧縮・キャッシュ（Nginxの代替）
           │       ▼
           ├── Puma (Rails 8)
           │       ▼
           └── PostgreSQL
                  ├── Solid Queue  ← 非同期ジョブ（Sidekiq/Redisの代替）
                  └── Solid Cache  ← キャッシュ（Redisの代替）
```

**Cloudflare R2**（オプション、Step 7）：ファイルストレージ。Presigned URLでブラウザから直接アップロード。

---

## ロードマップ（全8ステップ）

### フェーズ1：ローカルでの新旧比較と概念理解

| Step | テーマ | 目的 | 達成基準 | 状態 |
|------|--------|------|----------|------|
| 1 | 旧・王道構成の構築 | 役割分散型インフラの構造を体感する | Nginx / Redis / Sidekiq / PostgreSQL を別コンテナで起動し、タスクCRUDが動く | ✅ 完了 |
| 2 | Redisの挙動監視 | 「なぜRedisが必要だったか」とそのボトルネックを理解する | `redis-cli monitor` とSidekiqダッシュボードでジョブの流れを目視確認 | ✅ 完了 |
| 3 | Solid系への移行 | Rails 8「RDB一元管理」思想へのリプレイスを経験する | Redis/Sidekiqを削除し、`solid_queue_jobs` テーブルにジョブが記録・処理される挙動を確認 | ✅ 完了 |
| 4 | Thruster化 | リバースプロキシをアプリ層に統合するメリットを学ぶ | Nginxコンテナを削除し、レスポンスヘッダで `Content-Encoding: gzip` を確認 | 🔜 次 |

### フェーズ2：本番環境への進出と最新デプロイ

| Step | テーマ | 目的 | 達成基準 | 状態 |
|------|--------|------|----------|------|
| 5 | Kamal 2 によるVPS構築 | コンテナベースのデプロイ自動化を学ぶ | `kamal setup` 一発でVPSにデプロイし、ブラウザからHTTPアクセスできる | - |
| 6 | Cloudflareによる本番防御とSSL | DNS / CDN / WAFの境界を理解する | Cloudflare → Kamal Proxy 間のHTTPS通信が成立し、CDNキャッシュが確認できる | - |

### フェーズ3：実務レベルへの肉付け（寄り道歓迎）

| Step | テーマ | 目的 | 達成基準 | 状態 |
|------|--------|------|----------|------|
| 7 | Cloudflare R2 へのダイレクトアップロード | サーバー帯域・メモリを使わないアーキテクチャを体験する | Presigned URL 経由で、ブラウザから直接R2に画像を保存・表示できる | - |
| 8 | 負荷試験とメトリクス | 組んだインフラのボトルネックを数値で把握する | ApacheBench / Locust で負荷をかけ、CPU/メモリ/DBコネクション/Solid Queueの遅延を観測する | - |

---

## 完了済みの主な作業（Step 1〜3）

- Docker Compose で Nginx / Rails / PostgreSQL / Redis / Sidekiq の5コンテナ構成を構築
- Task の CRUD を Scaffold で実装
- コントローラーに同期的な重い処理（sleep 5）を入れてレスポンス遅延を体感
- `ProcessTaskWorker` を実装し `perform_async` で非同期化、即時レスポンスに改善
- Sidekiqの並行処理を観察（5並行 vs 25並行で処理時間の差を確認）
- `redis-cli monitor` で `lpush` によるジョブ投入と `brpop` による待ち受けを目視確認
- Redis / Sidekiq を削除し、Solid Queue に移行
- `solid_queue_jobs` テーブルで `finished_at` の埋まり方を確認し、ジョブのライフサイクルを観察

---

## 技術選定の背景

| 旧構成 | 新構成（Rails 8） | 理由 |
|--------|------------------|------|
| Nginx | Thruster | Rails標準の軽量プロキシ。GzipやBrotli圧縮をPumaの前段で処理。インフラのコンテナ数を削減できる |
| Redis + Sidekiq | Solid Queue | NVMe/SSD前提ではRDBへの読み書きが十分速い。Redisサーバーの運用・課金が不要になる |
| Redis（キャッシュ用途） | Solid Cache | 同上。DBに同居させることでインフラのシンプルさを維持する |
| 手動デプロイ | Kamal 2 | Docker前提のデプロイ自動化ツール。SSHでVPSに接続し、イメージビルド→転送→起動→マイグレーションを一括実行 |
