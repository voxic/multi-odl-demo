package com.odl.agreementprofile.config;

import com.mongodb.client.MongoClient;
import com.mongodb.client.MongoClients;
import com.mongodb.client.MongoDatabase;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class MongoConfig {

    @Value("${mongodb.cluster1.uri}")
    private String cluster1Uri;

    @Value("${mongodb.cluster1.database}")
    private String cluster1Database;

    @Bean
    public MongoClient mongoClient() {
        return MongoClients.create(cluster1Uri);
    }

    @Bean
    public MongoDatabase mongoDatabase() {
        return mongoClient().getDatabase(cluster1Database);
    }
}

