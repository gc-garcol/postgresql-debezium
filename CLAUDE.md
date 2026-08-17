# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A demo/reference project for Change Data Capture (CDC) from PostgreSQL into Kafka using Debezium. It has two parallel setups sharing the same Postgres schema:

- **JSON setup** (`compose.yaml`): Debezium Connect emits plain JSON to Kafka (Redpanda), no schema registry.
- **Avro setup** (`compose.avro.yaml`): Debezium Connect emits Avro, serialized/deserialized via an Apicurio schema registry. A Spring Boot consumer (`kafka-consumer-avro/`) reads and logs these Avro CDC events.

Only one stack should run at a time (both bind the same host ports).

## Running the stacks

JSON stack:
```shell
docker compose up -d
```

Avro stack (always recreate volumes when switching from the JSON stack, since Redpanda topic data is stack-specific):
```shell
docker compose -f compose.avro.yaml down -v
docker compose -f compose.avro.yaml up -d
```

Postgres is seeded via `initdb/` (mounted at `/docker-entrypoint-initdb.d`), which sets `wal_level = logical` and creates the `public.customers` table. Postgres requires a restart after `wal_level` changes on first init.

## Registering the Debezium connector

The connector is not created automatically — after the stack is up, POST it to Kafka Connect's REST API (port 8083). See `readme.md` for the JSON connector payload and `readme.avro.md` for the Avro connector payload (there are two Avro variants: native Apicurio and Confluent-compatibility mode via `apicurio.registry.as-confluent`/`use-id: contentId`).

```shell
curl -X POST http://localhost:8083/connectors -H "Content-Type: application/json" -d '{...}'
curl http://localhost:8083/connectors/pg-connector/status   # check status
curl -X DELETE http://localhost:8083/connectors/pg-connector # tear down
```

Key connector config points:
- `plugin.name: pgoutput`, `publication.autocreate.mode: filtered`, `table.include.list: public.customers`
- `topic.prefix: debezium-cdc` → CDC events land on topic `debezium-cdc.public.customers`

To generate CDC events, insert into `public.customers` directly in Postgres (see `readme.md` for the exact statement), then observe events either in the Redpanda Console (JSON stack, port 8082) or via the `kafka-consumer-avro` app logs (Avro stack).

## kafka-consumer-avro (Spring Boot / Java 25)

Located at `kafka-consumer-avro/`. Consumes the Avro CDC topic and logs insert/update/delete/snapshot events.

Build/run/test (from `kafka-consumer-avro/`):
```shell
./mvnw clean package
./mvnw spring-boot:run
./mvnw test                                  # run all tests
./mvnw test -Dtest=ClassName#methodName       # run a single test
```

Architecture notes:
- `CustomerCdcConsumer` (`@KafkaListener` on topic `debezium-cdc.public.customers`) receives `ConsumerRecord<GenericRecord, GenericRecord>` — both key and value are Avro `GenericRecord`, deserialized via `AvroKafkaDeserializer` against the Apicurio registry (configured in `application.yaml`, group id `kafka-consumer-avro`).
- Debezium envelope handling: the consumer reads `value.get("op")` to branch on change type — `c` (create/insert), `u` (update, has both `before`/`after`), `d` (delete, uses `before`), `r` (initial snapshot read, uses `after`). This op-code convention is central to interpreting any Debezium payload in this repo, JSON or Avro.
- App listens on port 9000 (`server.port`); Kafka bootstrap and Apicurio registry URLs are set in `application.yaml` for local (host-mapped) ports — `localhost:19092` for Kafka, `localhost:8080` for the registry — since the app runs outside Docker while pointing at the compose stack.
- If adding new listeners for other tables, follow the same `op`-switch pattern and register the corresponding table in `table.include.list` on the connector.

## Schema registry

Apicurio Registry (Confluent-API-compatible) is used, not Confluent Schema Registry. Its UI is at `http://localhost:8080/ui` in the Avro stack. `readme.schema-registry.md` explains the general produce/consume-time schema resolution flow (schema ID lookup/registration on produce, ID-based schema fetch on consume) — read it before changing converter/serde config.
