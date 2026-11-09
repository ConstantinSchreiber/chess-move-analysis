// Minimal C interface to an in-process Stockfish (GPLv3, see ../Copying.txt).
#ifndef SFKIT_H
#define SFKIT_H

#ifdef __cplusplus
extern "C" {
#endif

/// Receives each complete UCI output line (no trailing newline). Called on engine threads.
typedef void (*sfkit_line_callback)(const char *line, void *context);

/// File name of the NNUE network this build expects (`EvalFileDefaultName` in evaluate.h).
const char *sfkit_default_net_name(void);

/// Boots the engine once per process on a dedicated 8 MB-stack thread and redirects
/// std::cin/std::cout to an in-memory queue / `callback`. The default network is looked up in the
/// directory of `argv0`, so pass "<netDirectory>/stockfish" to load it during boot.
/// Returns 1 if this call started the engine, 0 if it was already running (arguments ignored),
/// -1 if the thread could not be created.
int sfkit_start(const char *argv0, sfkit_line_callback callback, void *context);

/// Queues UCI command(s) for the engine; embedded newlines separate commands. Commands sent
/// before `sfkit_start` are kept and processed once the engine runs. Never send "quit".
void sfkit_send(const char *command);

#ifdef __cplusplus
}
#endif

#endif /* SFKIT_H */
