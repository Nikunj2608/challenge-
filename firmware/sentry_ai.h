#ifndef SENTRY_AI_H
#define SENTRY_AI_H

#include <stdint.h>

#define USER_PROJ_BASE 0x30000000

#define SENTRY_GLOBAL_THRESH  (*(volatile uint32_t*)(USER_PROJ_BASE + 0x00))
#define SENTRY_LEAK_RATE      (*(volatile uint32_t*)(USER_PROJ_BASE + 0x04))
#define SENTRY_ENABLE_MASK    (*(volatile uint32_t*)(USER_PROJ_BASE + 0x08))
#define SENTRY_TICK_LIMIT     (*(volatile uint32_t*)(USER_PROJ_BASE + 0x0C)) // NEW

#define SENTRY_WEIGHT_0       (*(volatile uint32_t*)(USER_PROJ_BASE + 0x10))
#define SENTRY_WEIGHT_1       (*(volatile uint32_t*)(USER_PROJ_BASE + 0x14))
#define SENTRY_WEIGHT_7       (*(volatile uint32_t*)(USER_PROJ_BASE + 0x2C))

#define SENTRY_INFERENCE_RES  (*(volatile uint32_t*)(USER_PROJ_BASE + 0x30))
#define SENTRY_SPIKE_STATUS   (*(volatile uint32_t*)(USER_PROJ_BASE + 0x34))

#endif