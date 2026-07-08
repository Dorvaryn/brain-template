import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import path from 'path';
import os from 'os';
import { registerFsTools } from './fs-tools.js';
import { registerQueryTools } from './query-tools.js';
import { createLogger } from './logger.js';

function expandHome(p) {
  return (p.startsWith('~/') || p === '~') ? path.join(os.homedir(), p.slice(1)) : p;
}

// BRAIN PATCH: take allowed root from CLI arg; BRAIN_DIR env var supplies wiki query root.
// Upstream uses dynamic MCP roots protocol — we don't need that complexity.
const arg = process.argv[2];
if (!arg) {
  console.error('Usage: node index.js <allowed-directory>');
  process.exit(1);
}
const allowedDir = path.resolve(expandHome(arg));
const brainDir = process.env.BRAIN_DIR
  ? path.resolve(expandHome(process.env.BRAIN_DIR))
  : allowedDir;

const logDir = path.join(brainDir, 'bin/brain-mcp/logs');
const { wrap } = createLogger(logDir);

const server = new McpServer({
  name: 'brain-mcp-server',
  version: '1.0.0'
});

registerFsTools(server, allowedDir, wrap);
registerQueryTools(server, brainDir, wrap);

const transport = new StdioServerTransport();
await server.connect(transport);
