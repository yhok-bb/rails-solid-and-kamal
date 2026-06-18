# VPC導入の経緯と技術メモ

## なぜVPCが必要になったか

2台構成のKamalデプロイを試みた際、DBへの接続で詰まったことがきっかけ。

### 前提構成

- サーバー1（167.179.103.252）：RailsアプリとPostgreSQLを同居
- サーバー2（108.61.126.182）：Railsアプリのみ
- `deploy.yml` の `DB_HOST` でサーバー1のPostgreSQLを両サーバーから参照する構成

---

## 問題の連鎖

### 試み1：パブリックIPで接続

```yaml
DB_HOST: 167.179.103.252
```

**結果：タイムアウト**

サーバー1のDockerコンテナがホストのパブリックIPに接続しようとすると、Dockerのiptablesルールがこれをブロックする。コンテナからホスト自身のパブリックIPへのループバック的な通信が通らない。

---

### 試み2：VPCプライベートIPで接続

VultrのVPCネットワークを作成し、プライベートIPを使う方針に切り替えた。

```
VPCサブネット: 10.25.96.0/20（約4096台分）
サーバー1のVPC IP: 10.25.96.3
サーバー2のVPC IP: 10.25.96.4
```

```yaml
DB_HOST: 10.25.96.3
```

**サーバー2 → サーバー1のDB：成功**（VPC経由でping 0.5ms、`nc -zv 10.25.96.3 5432` 成功）

**サーバー1 → 自分自身のDB：タイムアウト**

---

### 問題の本質

サーバー1のDockerコンテナ（ブリッジネットワーク `172.18.0.0/16`）からVPC IP（`10.25.96.3`）経由でPostgreSQLに接続しようとすると、Linuxのiptablesが「外部から来た通信」として扱いブロックする。

```
[Railsコンテナ] 172.18.0.x
      ↓ 10.25.96.3:5432 に接続
[ホストOS] 10.25.96.3
      ↓ INPUT chainでブロック ← ここが詰まり
[PostgreSQLコンテナ]
```

---

### 解決策：iptablesルールの追加

サーバー1で以下を実行：

```bash
iptables -I INPUT -s 172.18.0.0/16 -p tcp --dport 5432 -j ACCEPT
```

| オプション | 意味 |
|---|---|
| `-I INPUT` | 受信ルールの先頭に挿入（既存ルールより優先） |
| `-s 172.18.0.0/16` | 送信元がDockerブリッジネットワーク |
| `-p tcp --dport 5432` | PostgreSQLへのTCP |
| `-j ACCEPT` | 許可 |

これでDockerコンテナがホスト自身のVPC IPを経由してPostgreSQLに接続できるようになった。

---

## VPCを使う意義（セキュリティ観点）

VPC導入前はDBポートがインターネットに公開された状態だった。VPC導入後：

- サーバー間の通信はプライベートネットワーク内で完結
- 5432ポートをインターネットに公開しなくてよい
- より本番環境に近い構成になる（AWS RDSもVPC内に置くのが標準）

---

## Kamalの設定変化

```yaml
# deploy.yml 抜粋（VPC導入後）
servers:
  web:
    hosts:
      - 167.179.103.252
      - 108.61.126.182
    env:
      clear:
        DB_HOST: 10.25.96.3  # VPCプライベートIP
```

---

## post-deployフックの工夫

db:migrateをサーバー1でのみ実行するように制限。両台でmigrate実行するとサーバー2からの接続タイミング次第でエラーが出るため。

```sh
#!/bin/sh
kamal app exec --hosts=167.179.103.252 'bin/rails db:migrate'
```

---

## 学んだこと

- DockerはホストのiptablesルールをDOCKER-USER chainで管理している。自分で追加するルールはINPUT chainに-Iで先頭挿入する
- VPCのプライベートIPへの通信もホストOSのiptablesを通る。「同じサーバー内だから」とはならない
- VPCはセキュリティだけでなく、本番相当の構成を体験する上でも重要なステップ

---

## 落ち着いたDocker構成

### ローカル（docker-compose.yml）

3サービス構成：

```
web      ← Thruster + Rails (Puma) ポート80
postgres ← PostgreSQL 16-alpine
jobs     ← Solid Queue ワーカー（bin/jobs）
```

```yaml
# webサービスの起動コマンド
command: sh -c "rm -f tmp/pids/server.pid && bin/rails tailwindcss:watch & bundle exec thrust bin/rails server -b 0.0.0.0"
```

ポイント：
- tailwindcssウォッチとThrusterを同一コンテナで並列起動
- `depends_on: condition: service_healthy` でPostgreSQLの起動を待ってからRails起動
- Solid QueueのワーカーをJobsコンテナとして分離（Sidekiqと役割は同じだがRedis不要）

### 本番（Kamal）

```
[Cloudflare] ← DNS / SSL / CDN / WAF
     ↓
[Kamal Proxy] ← ポート80/443、SSL終端
     ↓
[Thruster] ← 静的アセット圧縮・キャッシュ（Nginxの代替）
     ↓
[Puma (Rails 8)]
     ↓
[PostgreSQL] ← Kamal accessoryとしてサーバー1で管理
```

### Dockerfile（本番用）

```dockerfile
FROM ruby:3.3-slim

RUN apt-get install build-essential git libpq-dev libvips libyaml-dev pkg-config

# アセットはビルド時にコンパイル（実行時のSECRET_KEY_BASE不要）
RUN RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile

EXPOSE 80
CMD ["bundle", "exec", "thrust", "bin/rails", "server", "-b", "0.0.0.0"]
```

ポイント：
- `SECRET_KEY_BASE_DUMMY=1` でビルド時にシークレット不要にする（Rails 7.1以降）
- `EXPOSE 80` はThrusterのポート。KamalがこのポートをProxyにルーティングする
- Nginxは使わない。Thrusterが静的アセットのgzip/zstd圧縮とキャッシュヘッダー付与を担当

### 旧構成との対比

| 役割 | 旧構成（Step 1-2） | 新構成（Step 3-6） |
|---|---|---|
| リバースプロキシ | Nginx | Thruster |
| 非同期ジョブ | Sidekiq | Solid Queue |
| キャッシュバックエンド | Redis | Solid Cache（PostgreSQL） |
| デプロイ | docker compose | Kamal 2 |

Solid系の思想：**ミドルウェアを増やさず、PostgreSQLに寄せる**。Redisを別途運用しなくてよい。
