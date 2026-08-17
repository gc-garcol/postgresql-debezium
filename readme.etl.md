# Sync data

## Docs
- source connector: https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-example-configuration
- sink connector: https://debezium.io/documentation/reference/stable/connectors/jdbc.html#jdbc-connector-configuration

## Architecture

Replicates `public.users` and `public.trades` from the source Postgres (`postgres`, host port
`5432`) into the sink Postgres (`postgres-sink`, host port `5433`) through Kafka:

```
postgres:5432 --> be-source-connector --> be.public.users
                                          be.public.trades --> be-sink-connector --> postgres-sink:5432 (host 5433)
```

The source tables live in `public` (created by `initdb/`); the replicated copies land in the `be`
schema of the sink database — `initdb-sink/` creates only that schema, the tables are created by the
sink connector itself.

## Usage

### Setup source connector

source-connector.json
```json
{
  "name": "be-source-connector",
  "config": {
      "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
      "database.hostname": "postgres",
      "database.port": "5432",
      "database.dbname": "debezium",
      "database.user": "username",
      "database.password": "password",
      "topic.prefix": "be",
      "table.include.list": "public.users,public.trades",
      "plugin.name": "pgoutput",
      "slot.name": "debezium_slot",
      "publication.autocreate.mode": "filtered"
  }
}
```

Create connector
```shell
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @etl/source-connector.json
```

Check status
```shell
curl http://localhost:8083/connectors/be-source-connector/status
```

Delete connector
```shell
curl -X DELETE http://localhost:8083/connectors/be-source-connector
```

### Setup sink connector

The `be` schema is created on first boot by `initdb-sink/01-schema.sql` (mounted into
`postgres-sink`); the sink connector creates the tables inside it. If you dropped the schema by
hand, recreate it with `CREATE SCHEMA IF NOT EXISTS be;`.

Consumes the topics written by `be-source-connector` and applies them to `postgres-sink` with the
Debezium JDBC sink connector (bundled in the `quay.io/debezium/connect` image).

sink-connector.json
```json
{
  "name": "be-sink-connector",
  "config": {
    "connector.class": "io.debezium.connector.jdbc.JdbcSinkConnector",
    "tasks.max": "1",
    "topics": "be.public.users,be.public.trades",
    "connection.url": "jdbc:postgresql://postgres-sink:5432/debezium",
    "connection.username": "username",
    "connection.password": "password",
    "insert.mode": "upsert",
    "primary.key.mode": "record_key",
    "primary.key.fields": "id",
    "delete.enabled": "true",
    "schema.evolution": "basic",
    "table.name.format": "be.${topic}",
    "transforms": "route",
    "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
    "transforms.route.regex": "be\\.public\\.(.*)",
    "transforms.route.replacement": "$1"
  }
}
```

Config notes:
- `connection.url` uses `postgres-sink:5432` because Kafka Connect runs inside the compose network.
  `5433` is only the host-side mapping of that container — use it from your machine
  (`psql -h localhost -p 5433 -U username debezium`), not from the connector.
- The `route` RegexRouter strips the `be.public.` topic prefix, so `be.public.users` → `be.users`
  via `table.name.format`. Without it the sink would try to create a table literally named
  `be.public.users`. The `be` schema must already exist — the sink creates tables, not schemas.
- `insert.mode: upsert` + `primary.key.mode: record_key` makes the sink idempotent: the Debezium
  message key (`id`) becomes the conflict target, so replays and snapshot re-reads update in place.
- `delete.enabled: true` applies `d` events (and consumes the tombstones) as `DELETE`s. It requires
  `primary.key.mode: record_key`.
- `schema.evolution: basic` lets the sink create the tables in `be` and add missing columns as the
  source schema grows — set it to `none` if the sink schema must stay frozen.

Create connector
```shell
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @etl/sink-connector.json
```

Check status
```shell
curl http://localhost:8083/connectors/be-sink-connector/status
```

Delete connector
```shell
curl -X DELETE http://localhost:8083/connectors/be-sink-connector
```

## Verify the sync

Seed / change some rows on the source:
```shell
# load the seed_users / seed_trades helpers once per fresh source database
docker exec -i postgres psql -U username -d debezium < etl/seed.sql

docker exec postgres psql -U username -d debezium \
  -c "SELECT seed_users(10); SELECT seed_trades(100);"
docker exec postgres psql -U username -d debezium \
  -c "UPDATE users SET email = 'updated@example.com' WHERE id = 1; DELETE FROM trades WHERE id = 100;"
```

Then compare on the sink:
```shell
docker exec postgres-sink psql -U username -d debezium \
  -c "SELECT count(*) FROM be.users; SELECT count(*) FROM be.trades;"
```

## Re-sync after dropping the target schema

Dropping `be` on the sink does not lose anything: the events are still in Kafka. What blocks the
replay is the sink's consumer offsets — the connector has already acknowledged those records, so it
would just sit idle. Reset the offsets and it replays every topic from the beginning; because
`insert.mode` is `upsert`, replaying is safe even when the schema was *not* dropped.

```shell
# 1. recreate the empty schema (the sink creates tables, never schemas)
docker exec postgres-sink psql -U username -d debezium \
  -c "DROP SCHEMA IF EXISTS be CASCADE; CREATE SCHEMA be;"

# 2. stop the connector — offsets can only be reset while it is STOPPED
curl -X PUT http://localhost:8083/connectors/be-sink-connector/stop

# 3. reset the consumer offsets (Connect >= 3.6; this cluster runs 3.7)
curl -X DELETE http://localhost:8083/connectors/be-sink-connector/offsets

# 4. resume — sink consumers default to auto.offset.reset=earliest, so it re-reads from offset 0
curl -X PUT http://localhost:8083/connectors/be-sink-connector/resume
```

Then check it caught up:
```shell
curl http://localhost:8083/connectors/be-sink-connector/status
docker exec postgres-sink psql -U username -d debezium \
  -c "\dt be.*" -c "SELECT count(*) FROM be.users; SELECT count(*) FROM be.trades;"
```

Notes:
- `schema.evolution: basic` recreates the tables, so the empty schema is enough. The generated DDL
  is not the DDL in `initdb/` — it keeps column types and the primary key, but `varchar(n)` becomes
  `text`, and check constraints, foreign keys and sequences are dropped.
- Deleting and re-POSTing the connector under the same name does **not** replay: the consumer group
  (`connect-be-sink-connector`) survives the connector. Either reset the offsets as above, or give
  the connector a new `name` so it gets a fresh consumer group.
- Deletes are replayed too, so the end state matches the source rather than the full history.
- The broker keeps CDC records forever (`--set redpanda.log_retention_ms=-1` in `compose.yaml`,
  overriding the 7-day default), so a replay always has the full history to work from. That
  property is only applied when the `kafka` volume is created — on an already-running cluster use
  `docker exec kafka rpk cluster config set log_retention_ms -1`.
- If the topics no longer hold the full history (retention was capped, or topics were deleted), reset
  the source instead so it takes a new snapshot: delete `be-source-connector`, drop its replication
  slot (`SELECT pg_drop_replication_slot('debezium_slot');` on `postgres`), delete the
  `be.public.*` topics, then recreate both connectors.

## Caveats

- `postgres-sink` mounts `initdb-sink/`, not `initdb/`, on purpose. Tables auto-created in `be` carry
  no foreign keys or check constraints, so cross-topic ordering between `users` and `trades` cannot
  break the load. If you pre-create the tables from the source DDL instead, the `trades → users` FKs
  can fire during the snapshot (a trade flushed before the user it references); drop them in that
  case:
  ```sql
  ALTER TABLE be.trades DROP CONSTRAINT trades_user_maker_id_fkey;
  ALTER TABLE be.trades DROP CONSTRAINT trades_user_taker_id_fkey;
  ```
- The sink writes `id` explicitly and creates no sequences, so `be` is replica-only — writing to it
  directly will collide with replicated ids.
- The messages must carry their Connect schema (`{"schema": ..., "payload": ...}`); the JDBC sink
  cannot infer column types otherwise. `compose.yaml` sets this explicitly on the worker with
  `CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE` / `CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE`. Note the
  `CONNECT_` prefix: the Debezium image only turns `CONNECT_*` variables into worker properties, so
  bare names like `VALUE_CONVERTER_SCHEMAS_ENABLE` are silently ignored.
