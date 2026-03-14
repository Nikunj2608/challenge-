#ifndef NEURON_H
#define NEURON_H

#include <stdint.h>

// The base address for user projects in Caravel is 0x30000000
#define USER_PROJ_BASE 0x30000000

// Register Offsets
#define REG_THRESHOLD  (*(volatile uint32_t*)(USER_PROJ_BASE + 0x00))
#define REG_STATUS     (*(volatile uint32_t*)(USER_PROJ_BASE + 0x04))
#define REG_WEIGHT     (*(volatile uint32_t*)(USER_PROJ_BASE + 0x08))

// Helper Functions
inline void set_neuron_threshold(uint32_t val) { REG_THRESHOLD = val; }
inline uint32_t check_neuron_spike() { return REG_STATUS & 0x1; }

#endif