// Sources/CLibEdit/include/libedit_shim.h

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Readline-compatible API (libedit implements these)
char *le_readline(const char *prompt);                 // returns malloc'd string or NULL on EOF
void  le_add_history(const char *line);
int   le_read_history(const char *path);               // 0 on success, -1 on error
int   le_write_history(const char *path);              // 0 on success, -1 on error
void  le_clear_history(void);

int le_ding (void);

// Optional: initialize readline state (keymaps, etc.)
void  le_initialize(void);

// Completion hooks
typedef char *(*le_generator_t)(const char *text, int state);  // returns malloc'd match or NULL
void  le_set_completion(le_generator_t generator);

#ifdef __cplusplus
}
#endif
