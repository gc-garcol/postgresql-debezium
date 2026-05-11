package gc.garcol.kafkaconsumeravro;

import lombok.extern.slf4j.Slf4j;
import org.apache.avro.generic.GenericRecord;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

@Slf4j
@Component
public class CustomerCdcConsumer {

    @KafkaListener(topics = "debezium-cdc.public.customers", groupId = "${consumer.group-id.customers}")
    public void consume(ConsumerRecord<GenericRecord, GenericRecord> record) {
        GenericRecord key = record.key();
        GenericRecord value = record.value();

        log.info("[RECEIVE] key: {} | value: {}", key, value);

        if (value == null) {
            return;
        }

        String op = String.valueOf(value.get("op"));
        GenericRecord after = (GenericRecord) value.get("after");
        GenericRecord before = (GenericRecord) value.get("before");

        switch (op) {
            case "c" -> log.info("[INSERT] customer: {}", toCustomerLog(after));
            case "u" -> log.info("[UPDATE] before: {} | after: {}", toCustomerLog(before), toCustomerLog(after));
            case "d" -> log.info("[DELETE] customer: {}", toCustomerLog(before));
            case "r" -> log.info("[SNAPSHOT] customer: {}", toCustomerLog(after));
            default  -> log.warn("[UNKNOWN op={}] value: {}", op, value);
        }
    }

    private String toCustomerLog(GenericRecord r) {
        if (r == null) return "null";
        return "id=%s firstName=%s lastName=%s email=%s".formatted(
            r.get("id"), r.get("first_name"), r.get("last_name"), r.get("email")
        );
    }
}
