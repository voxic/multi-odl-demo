package com.odl.agreementprofile.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;

import java.util.Map;

@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class CustomerAgreementEvent {
    private String operation;
    private Map<String, Object> after;
    private Map<String, Object> before;
    private Long customerId;
    private Long agreementId;
}

