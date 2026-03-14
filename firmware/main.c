#include "sentry_ai.h"
#include <stdio.h>

void irq_handler() {
    uint32_t anomaly_type = SENTRY_INFERENCE_RES;
    uint32_t raw_spikes   = SENTRY_SPIKE_STATUS; // Reading this auto-clears the interrupt!
    
    printf("URGENT: Sentry-AI Interrupt Fired! Class: %d (Mask: 0x%02X)\n", anomaly_type, raw_spikes);
    
    if (anomaly_type == 7) {
        printf("ACTION: Critical High-Frequency Failure! Shutting down motor.\n");
    }
}

void main() {
    printf("Initializing Sentry-AI Edge Accelerator...\n");

    // 0. Clean Startup Sequence
    SENTRY_ENABLE_MASK = 0x00; // Disable all neurons during config
    uint32_t clear_dummy = SENTRY_SPIKE_STATUS; // Clear residual hardware flags
    
    // 1. Configure Temporal Integration & Thresholds
    SENTRY_GLOBAL_THRESH = 5000; 
    SENTRY_LEAK_RATE = 2;        
    SENTRY_TICK_LIMIT = 100000; // 1 millisecond temporal window at 100MHz

    // 2. Configure Feature Extractors (Shift-Add Weights)
    SENTRY_WEIGHT_0 = 0; // 1x multiplier (Baseline rumble)
    SENTRY_WEIGHT_7 = 5; // 32x multiplier (High-freq anomaly)

    // 3. Arm the System
    SENTRY_ENABLE_MASK = 0x81; // Enable Neurons 0 and 7
    printf("Sentry-AI armed. CPU entering deep sleep...\n");
    
    // 4. Power Saving
    while(1) { asm("wfi"); /* Wait For Interrupt */ }
}