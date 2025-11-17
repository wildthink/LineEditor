// Sources/CLibEdit/libedit_shim.c

#include <stdlib.h>
#include <editline/readline.h>   // libedit’s readline-compat headers

// Define a stable generator type matching readline/libedit's completion entry signature.
typedef char *(*le_generator_t)(const char *text, int state);

#ifndef rl_compentry_func_t
typedef char *rl_compentry_func_t(const char *text, int state);
#endif

// Forward declarations for readline/libedit types when headers vary across platforms.
#ifndef rl_completion_func_t
typedef char **rl_completion_func_t(const char *text, int start, int end);
#endif

// Some libedit symbols live behind macros; forward with stable names.

char *le_readline(const char *prompt) {
    return readline(prompt);
}

void le_add_history(const char *line) {
    if (line && *line) add_history(line);
}

int le_read_history(const char *path) {
    return read_history(path);
}

int le_write_history(const char *path) {
    return write_history(path);
}

void le_clear_history(void) {
    clear_history();
}

void le_initialize(void) {
    rl_initialize();
}

// Completion: supply a generator and let libedit build the match list.
static le_generator_t s_generator = NULL;

static char *le_generator_trampoline(const char *text, int state) {
    if (!s_generator) return NULL;
    return s_generator(text, state);
}

static char **attempted_completion(const char *text, int start, int end) {
    (void)start; (void)end;
    if (!s_generator) return NULL;
    // rl_completion_matches will call le_generator_trampoline with state = 0,1,2,...
    return rl_completion_matches(text, (rl_compentry_func_t *)le_generator_trampoline);
}

#ifndef HAVE_DECL_RL_ATTEMPTED_COMPLETION_FUNCTION
extern rl_completion_func_t *rl_attempted_completion_function;
#endif

void le_set_completion(le_generator_t generator) {
    s_generator = generator;
    rl_attempted_completion_function = (rl_completion_func_t *)attempted_completion;
}

