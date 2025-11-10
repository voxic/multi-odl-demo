package com.odl.agreementprofile.kafka;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.odl.agreementprofile.model.CustomerAgreementProfile;
import com.odl.agreementprofile.service.AgreementProfileService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.Acknowledgment;
import org.springframework.kafka.support.KafkaHeaders;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.stereotype.Component;

@Slf4j
@Component
public class KafkaConsumer {

    @Autowired
    private AgreementProfileService agreementProfileService;

    @Autowired
    private KafkaTemplate<String, String> kafkaTemplate;

    @Value("${kafka.topic.output}")
    private String outputTopic;

    private final ObjectMapper objectMapper = new ObjectMapper();

    @KafkaListener(topics = "${kafka.topic.input}", groupId = "${spring.kafka.consumer.group-id}")
    public void consume(@Payload String message,
                       @Header(KafkaHeaders.RECEIVED_KEY) String key,
                       Acknowledgment acknowledgment) {
        try {
            log.info("Received message from Kafka - Key: {}, Message: {}", key, message);

            // Parse the message
            JsonNode jsonNode = objectMapper.readTree(message);
            
            // Extract customer ID from the event
            Long customerId = extractCustomerId(jsonNode);
            
            if (customerId == null) {
                log.warn("Could not extract customer ID from message: {}", message);
                acknowledgment.acknowledge();
                return;
            }

            log.info("Processing agreement profile for customer: {}", customerId);

            // Build the customer agreement profile
            CustomerAgreementProfile profile = agreementProfileService.buildCustomerAgreementProfile(customerId);

            if (profile == null) {
                log.warn("Could not build profile for customer: {}", customerId);
                acknowledgment.acknowledge();
                return;
            }

            // Convert profile to JSON
            String profileJson = objectMapper.writeValueAsString(profile);

            // Publish to output topic
            String outputKey = String.valueOf(customerId);
            kafkaTemplate.send(outputTopic, outputKey, profileJson);

            log.info("Successfully published agreement profile for customer {} to topic {}", customerId, outputTopic);

            // Acknowledge the message
            acknowledgment.acknowledge();

        } catch (Exception e) {
            log.error("Error processing Kafka message: {}", e.getMessage(), e);
            // In production, you might want to implement retry logic or dead letter queue
            // For now, we'll acknowledge to prevent blocking
            acknowledgment.acknowledge();
        }
    }

    private Long extractCustomerId(JsonNode jsonNode) {
        // Try different possible structures
        if (jsonNode.has("customer_id")) {
            return jsonNode.get("customer_id").asLong();
        }
        if (jsonNode.has("after") && jsonNode.get("after").has("customer_id")) {
            return jsonNode.get("after").get("customer_id").asLong();
        }
        if (jsonNode.has("fullDocument") && jsonNode.get("fullDocument").has("customer_id")) {
            return jsonNode.get("fullDocument").get("customer_id").asLong();
        }
        // Try to get from agreement document
        if (jsonNode.has("after") && jsonNode.get("after").has("customer_id")) {
            return jsonNode.get("after").get("customer_id").asLong();
        }
        return null;
    }
}

