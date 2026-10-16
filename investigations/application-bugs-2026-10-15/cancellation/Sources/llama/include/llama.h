#ifndef HARBOUR_CANCELLATION_TEST_LLAMA_H
#define HARBOUR_CANCELLATION_TEST_LLAMA_H
#include <stdbool.h>
#include <stdint.h>

// Cancellation-only ABI double. It does not load weights or implement inference.
typedef int32_t llama_token;
struct llama_model;
struct llama_context;
struct llama_vocab;
struct llama_memory;
struct llama_sampler;
struct llama_model_params { int32_t n_gpu_layers; bool use_extra_bufts; };
struct llama_context_params { uint32_t n_ctx; uint32_t n_batch; int32_t n_threads; int32_t n_threads_batch; };
struct llama_sampler_chain_params { bool no_perf; };
struct llama_batch {
    int32_t n_tokens;
    llama_token *token;
    int32_t *pos;
    int32_t *n_seq_id;
    int32_t **seq_id;
    int8_t *logits;
};
void llama_backend_init(void);
struct llama_model_params llama_model_default_params(void);
struct llama_context_params llama_context_default_params(void);
struct llama_model *llama_model_load_from_file(const char *, struct llama_model_params);
struct llama_context *llama_init_from_model(struct llama_model *, struct llama_context_params);
void llama_free(struct llama_context *);
void llama_model_free(struct llama_model *);
const struct llama_vocab *llama_model_get_vocab(const struct llama_model *);
int32_t llama_tokenize(const struct llama_vocab *, const char *, int32_t, llama_token *, int32_t, bool, bool);
struct llama_memory *llama_get_memory(struct llama_context *);
void llama_memory_clear(struct llama_memory *, bool);
struct llama_sampler_chain_params llama_sampler_chain_default_params(void);
struct llama_sampler *llama_sampler_chain_init(struct llama_sampler_chain_params);
void llama_sampler_free(struct llama_sampler *);
struct llama_sampler *llama_sampler_init_grammar(const struct llama_vocab *, const char *, const char *);
void llama_sampler_chain_add(struct llama_sampler *, struct llama_sampler *);
struct llama_sampler *llama_sampler_init_greedy(void);
struct llama_batch llama_batch_init(int32_t, int32_t, int32_t);
void llama_batch_free(struct llama_batch);
int32_t llama_decode(struct llama_context *, struct llama_batch);
llama_token llama_sampler_sample(struct llama_sampler *, struct llama_context *, int32_t);
bool llama_vocab_is_eog(const struct llama_vocab *, llama_token);
int32_t llama_token_to_piece(const struct llama_vocab *, llama_token, char *, int32_t, int32_t, bool);

// Hold inside the C call, not at an async Swift suspension point.
void llama_test_arm_decode_barrier(void);
bool llama_test_wait_decode_entered(int32_t timeout_milliseconds);
void llama_test_release_decode(void);
int32_t llama_test_decode_calls(void);
#endif
