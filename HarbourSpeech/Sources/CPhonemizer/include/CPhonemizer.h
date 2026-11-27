#ifndef HARBOUR_PHONEMIZER_H
#define HARBOUR_PHONEMIZER_H
int harbour_phonemizer_initialize(const char *data_parent);
char *harbour_phonemize(const char *text, const char *language);
void harbour_phonemizer_free(char *value);
#endif
