package com.odl.agreementprofile.model;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.Data;

import java.time.Instant;
import java.util.List;
import java.util.Map;

@Data
@JsonInclude(JsonInclude.Include.NON_NULL)
public class CustomerAgreementProfile {
    private Long customerId;
    private CustomerInfo customerInfo;
    private List<AgreementDetail> agreements;
    private AgreementSummary agreementSummary;
    private Instant computedAt;

    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class CustomerInfo {
        private String firstName;
        private String lastName;
        private String email;
        private String phone;
        private String status;
        private String address;
        private String city;
        private String state;
        private String postalCode;
        private String country;
    }

    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class AgreementDetail {
        private Long agreementId;
        private String agreementNumber;
        private String agreementType;
        private Long accountId;
        private Double principalAmount;
        private Double currentBalance;
        private Double interestRate;
        private Integer termMonths;
        private Double paymentAmount;
        private String paymentFrequency;
        private String startDate;
        private String endDate;
        private String status;
        private Map<String, Object> metadata;
    }

    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class AgreementSummary {
        private Integer totalAgreements;
        private Integer activeAgreements;
        private Integer completedAgreements;
        private Integer defaultedAgreements;
        private Double totalPrincipalAmount;
        private Double totalCurrentBalance;
        private Double totalOutstandingBalance;
        private Double averageInterestRate;
        private List<String> agreementTypes;
    }
}

