# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this gem does

SidekiqAlive is a Kubernetes liveness probe for Sidekiq. It starts an HTTP server (default port `7433`) that returns `200 Alive!` only while a per-host liveness key exists in Redis. A dedicated Sidekiq worker rewrites that key on an interval and re-enqueues itself; if Sidekiq stops processing jobs the key expires (Redis TTL) and the HTTP endpoint starts failing, signalling Kubernetes to restart the pod.

Everything is scoped **per host** via `SIDEKIQ_ALIVE_HOSTNAME` / `HOSTNAME` (set per replica by Kubernetes), so each pod has its own queue, liveness key, and registry entry.

## Commands

Always use the project binstubs — never `bundle exec` or a globally installed gem.

- `bin/rspec` — run the full test suite
- `bin/rspec spec/sidekiq_alive/server_spec.rb` — run one file
- `bin/rspec spec/sidekiq_alive/server_spec.rb:42` — run one example by line
- `bin/rubocop` — lint (config in `.rubocop.yml`, TargetRuby 3.2)
- `bin/rake` — default task, runs `spec`

**Tests require a live Redis** on `localhost:6379`: `spec/spec_helper.rb` calls `Sidekiq.redis(&:flushall)` before every example and resets config via `SidekiqAlive.config.set_defaults`. There is no mocked Redis.

## Architecture

The entrypoint `lib/sidekiq_alive.rb` auto-runs `SidekiqAlive.start` on require, unless `DISABLE_SIDEKIQ_ALIVE=true`. Loading uses Zeitwerk (`Zeitwerk::Loader.for_gem`), so file paths must match constant names.

`SidekiqAlive.start` registers callbacks inside `Sidekiq.configure_server` — the gem only activates in a Sidekiq **server** process, not in web/client processes:

- **`on(:startup)`** — sets the worker's queue to `sidekiq-alive-<hostname>`, creates a dedicated Sidekiq capsule (`CAPSULE_NAME = "sidekiq-alive"`, concurrency 2) so the probe has its own thread pool, writes the first liveness key, enqueues the worker, and **forks** `SidekiqAlive::Server.run!` into a child process (`@server_pid`).
- **`on(:quiet)` / `on(:shutdown)`** — unregister the instance, purge pending probe jobs, and (on shutdown) `TERM` + `wait` the forked HTTP server.

The three moving parts:

- **`Worker`** (`worker.rb`) — a `Sidekiq::Worker` with `retry: false`. On `perform` it checks `config.custom_liveness_probe`, rewrites the liveness key (`store_alive_key`), refreshes the instance registration, runs `config.callback`, then re-schedules itself at `time_to_live / 2`. This self-requeue loop is what keeps the key alive.
- **`Server`** (`server.rb`) — a Rack app served by Rackup (`webrick` by default, `puma` configurable via `SIDEKIQ_ALIVE_SERVER`). `call` returns 200 only when the request path matches `config.path` **and** `SidekiqAlive.alive?` (Redis TTL check). Optional TLS via `tls_cert_file` / `tls_key_file` (webrick only).
- **`Redis` adapter** (`redis.rb` + `redis/`) — `Redis.adapter` returns a `RedisClientGem` instance (the `redis-client` gem used by Sidekiq 7+). `Base` defines the interface; `RedisGem` is the legacy `redis`-gem wrapper. All Redis access goes through the capsule's connection pool (`(@capsule || Sidekiq).redis`). Add new Redis operations to `Base` and both adapters.

**Two Redis key structures:**
- Liveness keys: `SIDEKIQ::LIVENESS_PROBE_TIMESTAMP::<hostname>`, a plain key with `EX = time_to_live`.
- Instance registry: `HOSTNAME_REGISTRY = "sidekiq-alive-hostnames"`, a **sorted set** scored by expiry timestamp. `expire_old_keys` prunes entries whose score is in the past; `registration_ttl` defaults to `time_to_live * 3`.

**`Config`** (`config.rb`) is a `Singleton`. Users configure via `SidekiqAlive.setup { |c| ... }`. Defaults come from `set_defaults`, several read from `SIDEKIQ_ALIVE_*` env vars. When adding a config option, add the `attr_accessor` **and** initialize it in `set_defaults` (tests rely on `set_defaults` resetting all state).

## Conventions

- Ruby `>= 3.2` (`required_ruby_version`); RuboCop `TargetRubyVersion: 3.2`, line length 150, trailing commas required on multiline literals, explicit block forwarding.
- Runtime deps: `rack`, `rackup`, `sidekiq >= 7 < 9`, `webrick`, `zeitwerk`. Keep the gemspec dependency bounds in sync when touching Sidekiq/Redis integration.
- Public entrypoints for external callers: `SidekiqAlive.setup`, `SidekiqAlive.start`, and the `SIDEKIQ_ALIVE_*` / `DISABLE_SIDEKIQ_ALIVE` env vars — treat these as the stable API.
