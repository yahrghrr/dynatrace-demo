package com.demo;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;

@SpringBootApplication
@RestController
public class DynatraceDemoApplication {

    private static final Logger logger = LoggerFactory.getLogger(DynatraceDemoApplication.class);

    public static void main(String[] args) {
        SpringApplication.run(DynatraceDemoApplication.class, args);
        LoggerFactory.getLogger(DynatraceDemoApplication.class)
            .info("Dynatrace Demo App started. Endpoints: /normal and /error");
    }

    /**
     * Normal transaction — returns a 200 OK with a simple message.
     * Dynatrace OneAgent will trace this as a successful service call.
     */
    @GetMapping("/normal")
    public ResponseEntity<Map<String, Object>> normalTransaction() {
        logger.info("[NORMAL] Transaction started at {}", LocalDateTime.now());

        // Simulate some processing
        int result = 100 * 42;

        Map<String, Object> response = new HashMap<>();
        response.put("status", "success");
        response.put("message", "Normal transaction completed successfully");
        response.put("result", result);
        response.put("timestamp", LocalDateTime.now().toString());

        logger.info("[NORMAL] Transaction completed successfully. result={}", result);
        return ResponseEntity.ok(response);
    }

    /**
     * Error transaction — deliberately triggers a divide-by-zero ArithmeticException.
     * Dynatrace OneAgent will:
     *   1. Capture the HTTP 500 error on this service call
     *   2. Record the ArithmeticException in the transaction trace
     *   3. Monitor the ERROR log entry written to the log file
     */
    @GetMapping("/error")
    public ResponseEntity<Map<String, Object>> errorTransaction() {
        logger.info("[ERROR] Error transaction started at {}", LocalDateTime.now());

        try {
            int zero = 0;
            // Deliberately trigger ArithmeticException: / by zero
            int result = 100 / zero;
            logger.info("[ERROR] This line will never be reached. result={}", result);
        } catch (ArithmeticException e) {
            // Log the error to the log file — Dynatrace Log Monitoring will pick this up
            logger.error("[ERROR] Divide by zero exception caught! Message: {} | Timestamp: {}",
                    e.getMessage(), LocalDateTime.now(), e);

            // Re-throw so Dynatrace OneAgent captures it as a failed transaction
            throw e;
        }

        // Unreachable
        return ResponseEntity.ok(new HashMap<>());
    }
}
