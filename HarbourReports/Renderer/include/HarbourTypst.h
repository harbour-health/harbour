#include <stdint.h>
#include <stddef.h>
int32_t harbour_typst_compile(const uint8_t *source, size_t source_len, const uint8_t *json, size_t json_len, uint8_t **output, size_t *output_len);
void harbour_typst_free(uint8_t *bytes, size_t len);
