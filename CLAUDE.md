# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## プロジェクト概要

**ChronosHub** — Rails 8 × Kamal 2 × Solid系 を使ったインフラ学習用タスク管理アプリ。

アプリの機能自体はシンプルなタスクCRUD。目的はアプリ機能ではなく、**Railsに近いレイヤーのインフラ・アーキテクチャを体系的に学ぶこと**。

- 旧構成（Nginx + Redis + Sidekiq）と新構成（Thruster + Solid Queue + Solid Cache）の比較
- Kamal 2 によるVPS本番デプロイ
- Cloudflare の CDN / SSL / WAF 構成
- 詳細なロードマップ → `docs/plan.md`

---

## オーナーのコンテキスト

- Rails実務経験5年。RailsのCRUD・規約・設計パターンは前提知識として省略してよい
- このプロジェクトの学習対象は **Rails 8の新機能** と **インフラ・デプロイ構成**
- 寄り道（メリデメ検証・旧構成の再現など）は積極的に歓迎する

---

## 最終アーキテクチャ

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
           ├── Thruster     ← 静的アセット圧縮・キャッシュ
           │       ▼
           ├── Puma (Rails 8)
           │       ▼
           └── PostgreSQL
                  ├── Solid Queue（非同期ジョブ）
                  └── Solid Cache（キャッシュ）
```

Nginx・Redis・Sidekiqは**学習のため意図的にStep 1〜2で構築し、Step 3〜4で排除する**。

---

## 開発コマンド（Railsアプリ作成後に更新）

> アプリ未作成のため、初期化後にこのセクションを更新すること。

```bash
# ローカル起動（フェーズ1）
docker compose up

# ジョブワーカー（Solid Queue）
bin/rails jobs:work

# デプロイ（フェーズ2以降）
kamal setup       # 初回のみ（DockerインストールからProxy起動まで）
kamal deploy      # 2回目以降
kamal app logs    # 本番ログ確認
```

---

## フェーズ別の構成差分

| フェーズ | DB | 非同期 | プロキシ | デプロイ |
|----------|-----|--------|----------|----------|
| Step 1〜2（旧構成） | PostgreSQL（コンテナ） | Redis + Sidekiq | Nginx | docker compose |
| Step 3〜4（Rails 8化） | PostgreSQL（コンテナ） | Solid Queue | Thruster | docker compose |
| Step 5〜6（本番） | PostgreSQL（VPS） | Solid Queue | Kamal Proxy + Thruster | Kamal 2 |

---

## 注意事項

- `config/deploy.yml`（Kamal設定）には秘匿情報を含めない。`.env` で管理する
- SQLiteではなくPostgreSQLを採用（Solid Queueのパフォーマンス検証に向いているため）
- Step移行時は**古い構成を完全に削除してから次に進む**（混在させない）
