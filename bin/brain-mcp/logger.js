import { appendFile, mkdir } from 'fs/promises';
import path from 'path';

function sanitizeArgs(toolName, args) {
  if (!args || typeof args !== 'object') return args;
  const safe = { ...args };
  if (toolName === 'write_file' && typeof safe.content === 'string') {
    safe.content = `[${safe.content.length} chars]`;
  }
  if (toolName === 'edit_file' && Array.isArray(safe.edits)) {
    safe.edits = `[${safe.edits.length} edits]`;
  }
  if (toolName === 'read_multiple_files' && Array.isArray(safe.paths)) {
    safe.paths = `[${safe.paths.length} paths]`;
  }
  return safe;
}

export function createLogger(logDir) {
  // Ensure log directory exists (best-effort at startup)
  mkdir(logDir, { recursive: true }).catch(() => {});

  function logCall(entry) {
    // Fire-and-forget — never block tool execution
    const date = new Date().toISOString().slice(0, 10);
    const logFile = path.join(logDir, `${date}.jsonl`);
    const line = JSON.stringify({ ts: new Date().toISOString(), ...entry }) + '\n';
    appendFile(logFile, line, 'utf8').catch(() => {});
  }

  function wrap(toolName, handler) {
    return async (args) => {
      const start = Date.now();
      try {
        const result = await handler(args);
        logCall({
          tool: toolName,
          args: sanitizeArgs(toolName, args),
          duration_ms: Date.now() - start,
          success: true
        });
        return result;
      } catch (err) {
        logCall({
          tool: toolName,
          args: sanitizeArgs(toolName, args),
          duration_ms: Date.now() - start,
          success: false,
          error: err.message
        });
        throw err;
      }
    };
  }

  return { wrap };
}
