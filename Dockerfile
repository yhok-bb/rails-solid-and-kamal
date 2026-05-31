# syntax=docker/dockerfile:1

# Step 4 Dev Dockerfile: Thruster経由でPuma起動。Nginxなし。
# Thrusterがポート80でリクエストを受け、Puma(3000)に転送する。

ARG RUBY_VERSION=3.3
FROM docker.io/library/ruby:$RUBY_VERSION-slim

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential git libpq-dev libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV BUNDLE_PATH="/usr/local/bundle"

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

# 本番用アセットをビルド時にコンパイル（SECRET_KEY_BASE_DUMMY=1でキー不要にする）
RUN RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile

EXPOSE 80
CMD ["bundle", "exec", "thrust", "bin/rails", "server", "-b", "0.0.0.0"]
