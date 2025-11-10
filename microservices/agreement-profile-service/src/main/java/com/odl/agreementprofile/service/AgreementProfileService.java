package com.odl.agreementprofile.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.mongodb.client.MongoCollection;
import com.mongodb.client.MongoDatabase;
import com.odl.agreementprofile.model.CustomerAgreementProfile;
import lombok.extern.slf4j.Slf4j;
import org.bson.Document;
import org.bson.types.ObjectId;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.*;
import java.util.stream.Collectors;

@Slf4j
@Service
public class AgreementProfileService {

    @Autowired
    @Qualifier("mongoDatabase")
    private MongoDatabase mongoDatabase;

    private final ObjectMapper objectMapper = new ObjectMapper();

    public CustomerAgreementProfile buildCustomerAgreementProfile(Long customerId) {
        log.info("Building agreement profile for customer: {}", customerId);

        try {
            // Get customer information
            Document customer = getCustomerDocument(customerId);
            if (customer == null) {
                log.warn("Customer {} not found", customerId);
                return null;
            }

            // Get all agreements for the customer
            List<Document> agreements = getAgreementDocuments(customerId);

            // Build customer info
            CustomerAgreementProfile.CustomerInfo customerInfo = buildCustomerInfo(customer);

            // Build agreement details
            List<CustomerAgreementProfile.AgreementDetail> agreementDetails = agreements.stream()
                    .map(this::buildAgreementDetail)
                    .collect(Collectors.toList());

            // Build agreement summary
            CustomerAgreementProfile.AgreementSummary summary = buildAgreementSummary(agreements);

            // Create profile
            CustomerAgreementProfile profile = new CustomerAgreementProfile();
            profile.setCustomerId(customerId);
            profile.setCustomerInfo(customerInfo);
            profile.setAgreements(agreementDetails);
            profile.setAgreementSummary(summary);
            profile.setComputedAt(Instant.now());

            log.info("Successfully built agreement profile for customer: {}", customerId);
            return profile;

        } catch (Exception e) {
            log.error("Error building agreement profile for customer {}: {}", customerId, e.getMessage(), e);
            return null;
        }
    }

    private Document getCustomerDocument(Long customerId) {
        MongoCollection<Document> customersCollection = mongoDatabase.getCollection("customers");

        // Try to find customer - handle both CDC format and regular format
        Document customer = customersCollection.find(
                new Document("$or", Arrays.asList(
                        new Document("customer_id", customerId),
                        new Document("after.customer_id", customerId)
                ))
        ).sort(new Document("ts_ms", -1)).first();

        if (customer == null) {
            return null;
        }

        // Extract actual customer data from CDC format if needed
        if (customer.containsKey("after")) {
            return (Document) customer.get("after");
        }

        return customer;
    }

    private List<Document> getAgreementDocuments(Long customerId) {
        MongoCollection<Document> agreementsCollection = mongoDatabase.getCollection("agreements");

        List<Document> agreements = agreementsCollection.find(
                new Document("$or", Arrays.asList(
                        new Document("customer_id", customerId),
                        new Document("after.customer_id", customerId)
                ))
        ).into(new ArrayList<>());

        // Extract actual agreement data from CDC format if needed
        return agreements.stream()
                .map(doc -> {
                    if (doc.containsKey("after")) {
                        return (Document) doc.get("after");
                    }
                    return doc;
                })
                .collect(Collectors.toList());
    }

    private CustomerAgreementProfile.CustomerInfo buildCustomerInfo(Document customer) {
        CustomerAgreementProfile.CustomerInfo info = new CustomerAgreementProfile.CustomerInfo();
        
        // Handle nested personal_info structure or flat structure
        if (customer.containsKey("personal_info")) {
            Document personalInfo = (Document) customer.get("personal_info");
            info.setFirstName(getString(personalInfo, "first_name"));
            info.setLastName(getString(personalInfo, "last_name"));
            info.setEmail(getString(personalInfo, "email"));
            info.setPhone(getString(personalInfo, "phone"));
        } else {
            info.setFirstName(getString(customer, "first_name"));
            info.setLastName(getString(customer, "last_name"));
            info.setEmail(getString(customer, "email"));
            info.setPhone(getString(customer, "phone"));
        }

        // Handle nested address structure or flat structure
        if (customer.containsKey("address")) {
            Document address = (Document) customer.get("address");
            info.setAddress(getString(address, "line1") + " " + getString(address, "line2"));
            info.setCity(getString(address, "city"));
            info.setState(getString(address, "state"));
            info.setPostalCode(getString(address, "postal_code"));
            info.setCountry(getString(address, "country"));
        } else {
            info.setAddress(getString(customer, "address_line1") + " " + getString(customer, "address_line2"));
            info.setCity(getString(customer, "city"));
            info.setState(getString(customer, "state"));
            info.setPostalCode(getString(customer, "postal_code"));
            info.setCountry(getString(customer, "country"));
        }

        info.setStatus(getString(customer, "customer_status") != null ? 
                      getString(customer, "customer_status") : 
                      getString(customer, "status"));

        return info;
    }

    private CustomerAgreementProfile.AgreementDetail buildAgreementDetail(Document agreement) {
        CustomerAgreementProfile.AgreementDetail detail = new CustomerAgreementProfile.AgreementDetail();
        
        detail.setAgreementId(getLong(agreement, "agreement_id"));
        detail.setAgreementNumber(getString(agreement, "agreement_number"));
        detail.setAgreementType(getString(agreement, "agreement_type"));
        detail.setAccountId(getLong(agreement, "account_id"));
        detail.setPrincipalAmount(getDouble(agreement, "principal_amount"));
        detail.setCurrentBalance(getDouble(agreement, "current_balance"));
        detail.setInterestRate(getDouble(agreement, "interest_rate"));
        detail.setTermMonths(getInteger(agreement, "term_months"));
        detail.setPaymentAmount(getDouble(agreement, "payment_amount"));
        detail.setPaymentFrequency(getString(agreement, "payment_frequency"));
        detail.setStartDate(getString(agreement, "start_date"));
        detail.setEndDate(getString(agreement, "end_date"));
        detail.setStatus(getString(agreement, "status"));

        // Include metadata if present
        if (agreement.containsKey("metadata")) {
            detail.setMetadata((Map<String, Object>) agreement.get("metadata"));
        }

        return detail;
    }

    private CustomerAgreementProfile.AgreementSummary buildAgreementSummary(List<Document> agreements) {
        CustomerAgreementProfile.AgreementSummary summary = new CustomerAgreementProfile.AgreementSummary();
        
        summary.setTotalAgreements(agreements.size());
        
        long activeCount = agreements.stream()
                .filter(a -> "ACTIVE".equalsIgnoreCase(getString(a, "status")))
                .count();
        summary.setActiveAgreements((int) activeCount);

        long completedCount = agreements.stream()
                .filter(a -> "COMPLETED".equalsIgnoreCase(getString(a, "status")))
                .count();
        summary.setCompletedAgreements((int) completedCount);

        long defaultedCount = agreements.stream()
                .filter(a -> "DEFAULT".equalsIgnoreCase(getString(a, "status")))
                .count();
        summary.setDefaultedAgreements((int) defaultedCount);

        double totalPrincipal = agreements.stream()
                .mapToDouble(a -> getDouble(a, "principal_amount"))
                .sum();
        summary.setTotalPrincipalAmount(totalPrincipal);

        double totalCurrent = agreements.stream()
                .mapToDouble(a -> getDouble(a, "current_balance"))
                .sum();
        summary.setTotalCurrentBalance(totalCurrent);

        double totalOutstanding = totalPrincipal - totalCurrent;
        summary.setTotalOutstandingBalance(totalOutstanding);

        double avgInterest = agreements.stream()
                .mapToDouble(a -> getDouble(a, "interest_rate"))
                .average()
                .orElse(0.0);
        summary.setAverageInterestRate(avgInterest);

        List<String> types = agreements.stream()
                .map(a -> getString(a, "agreement_type"))
                .filter(Objects::nonNull)
                .distinct()
                .collect(Collectors.toList());
        summary.setAgreementTypes(types);

        return summary;
    }

    // Helper methods for safe extraction
    private String getString(Document doc, String key) {
        Object value = doc.get(key);
        return value != null ? value.toString() : null;
    }

    private Long getLong(Document doc, String key) {
        Object value = doc.get(key);
        if (value == null) return null;
        if (value instanceof Long) return (Long) value;
        if (value instanceof Integer) return ((Integer) value).longValue();
        if (value instanceof Number) return ((Number) value).longValue();
        try {
            return Long.parseLong(value.toString());
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private Double getDouble(Document doc, String key) {
        Object value = doc.get(key);
        if (value == null) return null;
        if (value instanceof Double) return (Double) value;
        if (value instanceof Number) return ((Number) value).doubleValue();
        try {
            return Double.parseDouble(value.toString());
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private Integer getInteger(Document doc, String key) {
        Object value = doc.get(key);
        if (value == null) return null;
        if (value instanceof Integer) return (Integer) value;
        if (value instanceof Long) return ((Long) value).intValue();
        if (value instanceof Number) return ((Number) value).intValue();
        try {
            return Integer.parseInt(value.toString());
        } catch (NumberFormatException e) {
            return null;
        }
    }
}

