#include "llama.h"
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <time.h>

struct llama_model { int marker; };
struct llama_context { int marker; };
struct llama_vocab { int marker; };
struct llama_memory { int marker; };
struct llama_sampler { int marker; };
static struct llama_vocab vocab;
static struct llama_memory memory;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static bool armed, entered, released;
static int32_t calls;
void llama_test_arm_decode_barrier(void) {
    pthread_mutex_lock(&lock); armed = true; entered = false; released = false; calls = 0; pthread_mutex_unlock(&lock);
}
bool llama_test_wait_decode_entered(int32_t ms) {
    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_sec += ms / 1000; deadline.tv_nsec += (ms % 1000) * 1000000L;
    if (deadline.tv_nsec >= 1000000000L) { deadline.tv_sec++; deadline.tv_nsec -= 1000000000L; }
    pthread_mutex_lock(&lock);
    while (!entered) { if (pthread_cond_timedwait(&changed, &lock, &deadline) != 0) break; }
    bool result = entered; pthread_mutex_unlock(&lock); return result;
}
void llama_test_release_decode(void) {
    pthread_mutex_lock(&lock); released = true; pthread_cond_broadcast(&changed); pthread_mutex_unlock(&lock);
}
int32_t llama_test_decode_calls(void) {
    pthread_mutex_lock(&lock); int32_t n = calls; pthread_mutex_unlock(&lock); return n;
}
void llama_backend_init(void) {}
struct llama_model_params llama_model_default_params(void) { return (struct llama_model_params){0}; }
struct llama_context_params llama_context_default_params(void) { return (struct llama_context_params){0}; }
struct llama_model *llama_model_load_from_file(const char *p, struct llama_model_params x) { (void)p; (void)x; return calloc(1, sizeof(struct llama_model)); }
struct llama_context *llama_init_from_model(struct llama_model *m, struct llama_context_params p) { (void)m; (void)p; return calloc(1, sizeof(struct llama_context)); }
void llama_free(struct llama_context *p) { free(p); }
void llama_model_free(struct llama_model *p) { free(p); }
const struct llama_vocab *llama_model_get_vocab(const struct llama_model *p) { (void)p; return &vocab; }
int32_t llama_tokenize(const struct llama_vocab *v, const char *text, int32_t len, llama_token *out, int32_t capacity, bool special, bool parse) {
    (void)v; (void)text; (void)len; (void)special; (void)parse;
    if (capacity < 1) return -1; out[0] = 1; return 1;
}
struct llama_memory *llama_get_memory(struct llama_context *p) { (void)p; return &memory; }
void llama_memory_clear(struct llama_memory *p, bool reset) { (void)p; (void)reset; }
struct llama_sampler_chain_params llama_sampler_chain_default_params(void) { return (struct llama_sampler_chain_params){0}; }
struct llama_sampler *llama_sampler_chain_init(struct llama_sampler_chain_params p) { (void)p; return calloc(1, sizeof(struct llama_sampler)); }
void llama_sampler_free(struct llama_sampler *p) { free(p); }
struct llama_sampler *llama_sampler_init_grammar(const struct llama_vocab *v, const char *g, const char *r) { (void)v; (void)g; (void)r; return calloc(1, sizeof(struct llama_sampler)); }
void llama_sampler_chain_add(struct llama_sampler *chain, struct llama_sampler *child) { (void)chain; free(child); }
struct llama_sampler *llama_sampler_init_greedy(void) { return calloc(1, sizeof(struct llama_sampler)); }
struct llama_batch llama_batch_init(int32_t n, int32_t embedding, int32_t sequences) {
    (void)embedding; (void)sequences; struct llama_batch b = {0};
    b.token = calloc(n, sizeof(llama_token)); b.pos = calloc(n, sizeof(int32_t)); b.n_seq_id = calloc(n, sizeof(int32_t));
    b.seq_id = calloc(n, sizeof(int32_t *)); b.logits = calloc(n, sizeof(int8_t));
    for (int i = 0; i < n; i++) b.seq_id[i] = calloc(1, sizeof(int32_t));
    // LocalModel always requests512; record capacity privately in the unused last slot is unnecessary.
    return b;
}
void llama_batch_free(struct llama_batch b) {
    for (int i = 0; i < 512; i++) free(b.seq_id[i]);
    free(b.token); free(b.pos); free(b.n_seq_id); free(b.seq_id); free(b.logits);
}
int32_t llama_decode(struct llama_context *p, struct llama_batch b) {
    (void)p; (void)b; pthread_mutex_lock(&lock); calls++;
    if (armed) { armed = false; entered = true; pthread_cond_broadcast(&changed); while (!released) pthread_cond_wait(&changed, &lock); }
    pthread_mutex_unlock(&lock); return 0;
}
llama_token llama_sampler_sample(struct llama_sampler *s, struct llama_context *c, int32_t i) { (void)s; (void)c; (void)i; return 2; }
bool llama_vocab_is_eog(const struct llama_vocab *v, llama_token t) { (void)v; (void)t; return false; }
int32_t llama_token_to_piece(const struct llama_vocab *v, llama_token t, char *buf, int32_t capacity, int32_t strip, bool special) {
    (void)v; (void)t; (void)strip; (void)special;
    const char *out = "{\"tool\":\"list_medications\",\"arg\":\"\"}";
    int32_t n = (int32_t)strlen(out); if (capacity < n) return -n; memcpy(buf, out, n); return n;
}
