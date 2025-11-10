package com.odl.agreementprofile.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.odl.agreementprofile.model.CustomerAgreementProfile;
import com.odl.agreementprofile.service.AgreementProfileService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@Slf4j
@RestController
@RequestMapping("/api")
public class AgreementProfileController {

    @Autowired
    private AgreementProfileService agreementProfileService;

    private final ObjectMapper objectMapper = new ObjectMapper();

    @GetMapping("/health")
    public ResponseEntity<?> health() {
        return ResponseEntity.ok().body(Map.of("status", "healthy", "service", "agreement-profile-service"));
    }

    @GetMapping("/profile/{customerId}")
    public ResponseEntity<?> getProfile(@PathVariable Long customerId) {
        try {
            CustomerAgreementProfile profile = agreementProfileService.buildCustomerAgreementProfile(customerId);
            if (profile == null) {
                return ResponseEntity.notFound().build();
            }
            return ResponseEntity.ok(profile);
        } catch (Exception e) {
            log.error("Error getting profile for customer {}: {}", customerId, e.getMessage(), e);
            return ResponseEntity.internalServerError().body(Map.of("error", e.getMessage()));
        }
    }
}

