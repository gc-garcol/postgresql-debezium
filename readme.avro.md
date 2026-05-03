# Avro

- https://debezium.io/documentation/reference/stable/configuration/avro.html
- https://debezium.io/documentation/reference/stable/configuration/avro.html#deploying-confluent-schema-registry-with-debezium-containers

## Setup

### Setup Apicurio schema registry
- https://debezium.io/documentation/reference/stable/configuration/avro.html#overview-of-deploying-a-debezium-connector-that-uses-avro-serialization

### Or using "Deploying Confluent Schema Registry with Debezium containers"
- https://debezium.io/documentation/reference/stable/configuration/avro.html#deploying-with-debezium-containers

```shell
docker compose -f compose.avro.yaml down -v
docker compose -f compose.avro.yaml up -d
```

## Check wal_level

```sql
SHOW wal_level;
```

## Create connector

With Apicurio

```shell
key.converter=io.apicurio.registry.utils.converter.AvroConverter
key.converter.apicurio.registry.url=http://apicurio:8080/apis/registry/v2
key.converter.apicurio.registry.auto-register=true
key.converter.apicurio.registry.find-latest=true
value.converter=io.apicurio.registry.utils.converter.AvroConverter
value.converter.apicurio.registry.url=http://apicurio:8080/apis/registry/v2
value.converter.apicurio.registry.auto-register=true
value.converter.apicurio.registry.find-latest=true
schema.name.adjustment.mode=avro
```

```shell
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d '{
    "name": "pg-connector",
    "config": {
      "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
      "database.hostname": "postgres",
      "database.port": "5432",
      "database.user": "username",
      "database.password": "password",
      "database.dbname": "debezium",
      "topic.prefix": "debezium-cdc",
      "table.include.list": "public.customers",
      "plugin.name": "pgoutput",
      "slot.name": "debezium_slot",
      "publication.autocreate.mode": "filtered",
      
      "key.converter": "io.apicurio.registry.utils.converter.AvroConverter",
      "key.converter.apicurio.registry.url": "http://schema-registry:8080/apis/registry/v2",
      "key.converter.apicurio.registry.auto-register": "true",
      "key.converter.apicurio.registry.find-latest": "true",
      "value.converter": "io.apicurio.registry.utils.converter.AvroConverter",
      "value.converter.apicurio.registry.url": "http://schema-registry:8080/apis/registry/v2",
      "value.converter.apicurio.registry.auto-register": "true",
      "value.converter.apicurio.registry.find-latest": "true",
      "schema.name.adjustment.mode": "avro"
    }
  }'
```

or you can use the Confluent Compatibility mode as follows:

```shell
key.converter=io.apicurio.registry.utils.converter.AvroConverter
key.converter.apicurio.registry.url=http://schema-registry:8080/apis/registry/v2
key.converter.apicurio.registry.auto-register=true
key.converter.apicurio.registry.find-latest=true
key.converter.schemas.enable": "false"
key.converter.apicurio.registry.headers.enabled": "false"
key.converter.apicurio.registry.as-confluent": "true"
key.converter.apicurio.use-id: "contentId"
value.converter=io.apicurio.registry.utils.converter.AvroConverter
value.converter.apicurio.registry.url=http://schema-registry:8080/apis/registry/v2
value.converter.apicurio.registry.auto-register=true
value.converter.apicurio.registry.find-latest=true
value.converter.schemas.enable": "false"
value.converter.apicurio.registry.headers.enabled": "false"
value.converter.apicurio.registry.as-confluent": "true"
value.converter.apicurio.use-id: "contentId"
schema.name.adjustment.mode=avro
```

```shell
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d '{
    "name": "pg-connector",
    "config": {
      "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
      "database.hostname": "postgres",
      "database.port": "5432",
      "database.user": "username",
      "database.password": "password",
      "database.dbname": "debezium",
      "topic.prefix": "debezium-cdc",
      "table.include.list": "public.customers",
      "plugin.name": "pgoutput",
      "slot.name": "debezium_slot",
      "publication.autocreate.mode": "filtered",
      
      "key.converter": "io.apicurio.registry.utils.converter.AvroConverter",
      "key.converter.apicurio.registry.url": "http://schema-registry:8080/apis/registry/v2",
      "key.converter.apicurio.registry.auto-register": "true",
      "key.converter.apicurio.registry.find-latest": "true",
      "key.converter.schemas.enable": "false",
      "key.converter.apicurio.registry.headers.enabled": "false",
      "key.converter.apicurio.registry.as-confluent": "true",
      "key.converter.apicurio.use-id": "contentId",
    
      "value.converter": "io.apicurio.registry.utils.converter.AvroConverter",
      "value.converter.apicurio.registry.url": "http://schema-registry:8080/apis/registry/v2",
      "value.converter.apicurio.registry.auto-register": "true",
      "value.converter.apicurio.registry.find-latest": "true",
      "value.converter.schemas.enable": "false",
      "value.converter.apicurio.registry.headers.enabled": "false",
      "value.converter.apicurio.registry.as-confluent": "true",
      "value.converter.apicurio.use-id": "contentId",
    
      "schema.name.adjustment.mode": "avro"
    }
  }'
```

![alt text](./docs/connector.png)

## Check status

```shell
curl http://localhost:8083/connectors/pg-connector/status
```

## Insert data

Execute this command in postgresql
```sql
INSERT INTO public.customers
(id, first_name, last_name, email)
VALUES(nextval('customers_id_seq'::regclass), 'hihi', 'haaha', 'ok');
```

Then check the event in kafka
![alt text](./docs/event.png)

## Delete connector

```shell
curl -X DELETE http://localhost:8083/connectors/pg-connector
```
