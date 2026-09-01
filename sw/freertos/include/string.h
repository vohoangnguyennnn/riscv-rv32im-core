#ifndef RV32IM_FREERTOS_STRING_H
#define RV32IM_FREERTOS_STRING_H

#include <stddef.h>

/* Freestanding implementations are provided by freertos/platform.c. */
void *memcpy(void *destination, const void *source, size_t length);
void *memset(void *destination, int value, size_t length);
int memcmp(const void *lhs, const void *rhs, size_t length);
size_t strlen(const char *text);

#endif
