#include "CPhonemizer.h"
#include <EspeakNG/speak_lib.h>
#include <stdlib.h>
#include <string.h>

int harbour_phonemizer_initialize(const char *path) {
    return espeak_Initialize(AUDIO_OUTPUT_SYNCHRONOUS, 0, path, espeakINITIALIZE_DONT_EXIT);
}

// eSpeak has process-global state. The Swift shared actor serializes all calls.
char *harbour_phonemize(const char *text, const char *language) {
    espeak_VOICE selector = {0};
    selector.languages = (char *)language;
    int status = espeak_SetVoiceByProperties(&selector);
    if (status != EE_OK) return NULL;
    size_t capacity = strlen(text) * 32 + 1024;
    char *result = calloc(capacity, 1);
    if (!result) return NULL;
    const void *cursor = text;
    size_t used = 0;
    while (cursor && *(const char *)cursor) {
        const void *previous = cursor;
        const char *phonemes = espeak_TextToPhonemes(&cursor, espeakCHARS_UTF8, espeakPHONEMES_IPA);
        if (!phonemes || cursor == previous) { free(result); return NULL; }
        size_t size = strlen(phonemes);
        if (used + size + 2 >= capacity) { free(result); return NULL; }
        if (used && size) result[used++] = ' ';
        memcpy(result + used, phonemes, size); used += size;
    }
    return result;
}
void harbour_phonemizer_free(char *value) { free(value); }
