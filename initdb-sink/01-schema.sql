-- Target database for the ETL sink connector (see readme.etl.md).
--
-- Only the schema is created here: `be-sink-connector` runs with
-- `schema.evolution: basic`, so it creates `be.users` / `be.trades` itself from
-- the Kafka record schemas. Deliberately NOT reusing `initdb/` — pre-created
-- tables would carry the foreign keys and check constraints from the source
-- DDL, which the sink cannot honour (topics are applied independently, so a
-- trade can be flushed before the user it references).
CREATE SCHEMA IF NOT EXISTS be;
