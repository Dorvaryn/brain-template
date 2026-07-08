// UPSTREAM SOURCE: adapted from @modelcontextprotocol/server-filesystem v2026.1.14
// Security envelope and tool set preserved faithfully.
// Search for "BRAIN PATCH" to find intentional divergences from upstream.

import { promises as fs } from 'fs';
import { createReadStream } from 'fs';
import path from 'path';
import os from 'os';
import { createPatch } from 'diff';
import { minimatch } from 'minimatch';
import { z } from 'zod';

function expandHome(filepath) {
  if (filepath.startsWith('~/') || filepath === '~') {
    return path.join(os.homedir(), filepath.slice(1));
  }
  return filepath;
}

async function validatePath(requestedPath, allowedDir) {
  const expanded = expandHome(requestedPath);
  const resolved = path.resolve(expanded);
  const normalizedAllowed = allowedDir.endsWith(path.sep) ? allowedDir : allowedDir + path.sep;
  if (!resolved.startsWith(normalizedAllowed) && resolved !== allowedDir) {
    throw new Error(`Access denied: ${requestedPath} is outside allowed directory`);
  }
  try {
    const real = await fs.realpath(resolved);
    if (!real.startsWith(normalizedAllowed) && real !== allowedDir) {
      throw new Error(`Access denied: symlink target is outside allowed directory`);
    }
    return real;
  } catch (err) {
    if (err.code === 'ENOENT') {
      // Path doesn't exist yet (new file write) — validate parent instead
      const parent = path.dirname(resolved);
      try {
        const realParent = await fs.realpath(parent);
        if (!realParent.startsWith(normalizedAllowed) && realParent !== allowedDir) {
          throw new Error(`Access denied: parent directory is outside allowed directory`);
        }
      } catch (parentErr) {
        if (parentErr.code !== 'ENOENT') throw parentErr;
      }
      return resolved;
    }
    throw err;
  }
}

async function writeFileContent(filePath, content) {
  const tmpPath = `${filePath}.tmp.${process.pid}`;
  try {
    await fs.writeFile(tmpPath, content, 'utf8');
    await fs.rename(tmpPath, filePath);
  } catch (err) {
    try { await fs.unlink(tmpPath); } catch {}
    throw err;
  }
}

async function applyFileEdits(filePath, edits, dryRun = false) {
  const original = await fs.readFile(filePath, 'utf8');
  let content = original;
  for (const edit of edits) {
    if (!content.includes(edit.oldText)) {
      throw new Error(`Text not found: ${JSON.stringify(edit.oldText.slice(0, 80))}`);
    }
    content = content.split(edit.oldText).join(edit.newText);
  }
  const patch = createPatch(path.basename(filePath), original, content, '', '');
  if (!dryRun) {
    await writeFileContent(filePath, content);
  }
  return patch;
}

function formatSize(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

async function readFileAsBase64(filePath) {
  return new Promise((resolve, reject) => {
    const stream = createReadStream(filePath);
    const chunks = [];
    stream.on('data', chunk => chunks.push(chunk));
    stream.on('end', () => resolve(Buffer.concat(chunks).toString('base64')));
    stream.on('error', reject);
  });
}

async function searchFilesRecursive(dir, pattern, excludePatterns, allowedDir, results) {
  try {
    const entries = await fs.readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name);
      const relPath = path.relative(dir, fullPath);
      const excluded = excludePatterns.some(p =>
        minimatch(entry.name, p, { dot: true }) ||
        minimatch(relPath, p, { dot: true })
      );
      if (excluded) continue;
      try { await validatePath(fullPath, allowedDir); } catch { continue; }
      if (entry.isDirectory()) {
        await searchFilesRecursive(fullPath, pattern, excludePatterns, allowedDir, results);
      }
      if (minimatch(entry.name, pattern, { dot: true }) ||
          minimatch(fullPath, pattern, { dot: true })) {
        results.push(fullPath);
      }
    }
  } catch {}
}

export function registerFsTools(server, allowedDir, wrap = (_, h) => h) {
  const validate = p => validatePath(p, allowedDir);

  const readTextFileHandler = async (args) => {
    const validPath = await validate(args.path);
    if (args.head && args.tail) throw new Error('Cannot specify both head and tail');
    let content;
    if (args.tail) {
      const lines = (await fs.readFile(validPath, 'utf8')).split('\n');
      content = lines.slice(-args.tail).join('\n');
    } else if (args.head) {
      const lines = (await fs.readFile(validPath, 'utf8')).split('\n');
      content = lines.slice(0, args.head).join('\n');
    } else {
      content = await fs.readFile(validPath, 'utf8');
    }
    return { content: [{ type: 'text', text: content }], structuredContent: { content } };
  };

  server.registerTool('read_file', {
    title: 'Read File (Deprecated)',
    description: 'Read file contents as text. DEPRECATED: Use read_text_file instead.',
    inputSchema: { path: z.string(), tail: z.number().optional(), head: z.number().optional() },
    outputSchema: { content: z.string() },
    annotations: { readOnlyHint: true }
  }, wrap('read_file', readTextFileHandler));

  server.registerTool('read_text_file', {
    title: 'Read Text File',
    description: 'Read file contents as text. Use head or tail to limit to N lines. Only works within allowed directories.',
    inputSchema: {
      path: z.string(),
      tail: z.number().optional().describe('Return only the last N lines'),
      head: z.number().optional().describe('Return only the first N lines')
    },
    outputSchema: { content: z.string() },
    annotations: { readOnlyHint: true }
  }, wrap('read_text_file', readTextFileHandler));

  server.registerTool('read_media_file', {
    title: 'Read Media File',
    description: 'Read an image or audio file as base64. Only works within allowed directories.',
    inputSchema: { path: z.string() },
    outputSchema: { content: z.array(z.object({ type: z.string(), data: z.string(), mimeType: z.string() })) },
    annotations: { readOnlyHint: true }
  }, wrap('read_media_file', async (args) => {
    const validPath = await validate(args.path);
    const ext = path.extname(validPath).toLowerCase();
    const mimeTypes = {
      '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
      '.gif': 'image/gif', '.webp': 'image/webp', '.bmp': 'image/bmp',
      '.svg': 'image/svg+xml', '.mp3': 'audio/mpeg', '.wav': 'audio/wav',
      '.ogg': 'audio/ogg', '.flac': 'audio/flac'
    };
    const mimeType = mimeTypes[ext] || 'application/octet-stream';
    const data = await readFileAsBase64(validPath);
    const type = mimeType.startsWith('image/') ? 'image' : mimeType.startsWith('audio/') ? 'audio' : 'blob';
    const item = { type, data, mimeType };
    return { content: [item], structuredContent: { content: [item] } };
  }));

  server.registerTool('read_multiple_files', {
    title: 'Read Multiple Files',
    description: 'Read multiple files simultaneously. Each result includes the path as reference. Only works within allowed directories.',
    inputSchema: { paths: z.array(z.string()).min(1) },
    outputSchema: { content: z.string() },
    annotations: { readOnlyHint: true }
  }, wrap('read_multiple_files', async (args) => {
    const results = await Promise.all(args.paths.map(async p => {
      try {
        const validPath = await validate(p);
        const content = await fs.readFile(validPath, 'utf8');
        return `${p}:\n${content}\n`;
      } catch (err) {
        return `${p}: Error - ${err.message}`;
      }
    }));
    const text = results.join('\n---\n');
    return { content: [{ type: 'text', text }], structuredContent: { content: text } };
  }));

  server.registerTool('write_file', {
    title: 'Write File',
    description: 'Create or overwrite a file with atomic write (tmp + rename). Only works within allowed directories.',
    inputSchema: { path: z.string(), content: z.string() },
    outputSchema: { content: z.string() },
    annotations: { readOnlyHint: false, idempotentHint: true, destructiveHint: true }
  }, wrap('write_file', async (args) => {
    const validPath = await validate(args.path);
    await writeFileContent(validPath, args.content);
    const text = `Successfully wrote to ${args.path}`;
    return { content: [{ type: 'text', text }], structuredContent: { content: text } };
  }));

  server.registerTool('edit_file', {
    title: 'Edit File',
    description: 'Make exact string replacements in a file. Returns a unified diff. Use dryRun to preview. Only works within allowed directories.',
    inputSchema: {
      path: z.string(),
      edits: z.array(z.object({
        oldText: z.string().describe('Text to find — must match exactly'),
        newText: z.string().describe('Replacement text')
      })),
      dryRun: z.boolean().default(false).describe('Preview changes without writing')
    },
    outputSchema: { content: z.string() },
    annotations: { readOnlyHint: false, idempotentHint: false, destructiveHint: true }
  }, wrap('edit_file', async (args) => {
    const validPath = await validate(args.path);
    const result = await applyFileEdits(validPath, args.edits, args.dryRun);
    return { content: [{ type: 'text', text: result }], structuredContent: { content: result } };
  }));

  server.registerTool('create_directory', {
    title: 'Create Directory',
    description: 'Create a directory (mkdir -p). Succeeds silently if already exists. Only works within allowed directories.',
    inputSchema: { path: z.string() },
    outputSchema: { content: z.string() },
    annotations: { readOnlyHint: false, idempotentHint: true, destructiveHint: false }
  }, wrap('create_directory', async (args) => {
    const validPath = await validate(args.path);
    await fs.mkdir(validPath, { recursive: true });
    const text = `Successfully created directory ${args.path}`;
    return { content: [{ type: 'text', text }], structuredContent: { content: text } };
  }));

  server.registerTool('list_directory', {
    title: 'List Directory',
    description: 'List files and directories with [FILE]/[DIR] prefixes. Only works within allowed directories.',
    inputSchema: { path: z.string() },
    outputSchema: { content: z.string() },
    annotations: { readOnlyHint: true }
  }, wrap('list_directory', async (args) => {
    const validPath = await validate(args.path);
    const entries = await fs.readdir(validPath, { withFileTypes: true });
    const text = entries.map(e => `${e.isDirectory() ? '[DIR]' : '[FILE]'} ${e.name}`).join('\n');
    return { content: [{ type: 'text', text }], structuredContent: { content: text } };
  }));

  server.registerTool('list_directory_with_sizes', {
    title: 'List Directory with Sizes',
    description: 'List files and directories with sizes. Sort by name or size. Only works within allowed directories.',
    inputSchema: {
      path: z.string(),
      sortBy: z.enum(['name', 'size']).optional().default('name').describe('Sort by name or size')
    },
    outputSchema: { content: z.string() },
    annotations: { readOnlyHint: true }
  }, wrap('list_directory_with_sizes', async (args) => {
    const validPath = await validate(args.path);
    const entries = await fs.readdir(validPath, { withFileTypes: true });
    const detailed = await Promise.all(entries.map(async e => {
      const entryPath = path.join(validPath, e.name);
      try {
        const stats = await fs.stat(entryPath);
        return { name: e.name, isDirectory: e.isDirectory(), size: stats.size };
      } catch {
        return { name: e.name, isDirectory: e.isDirectory(), size: 0 };
      }
    }));
    const sorted = [...detailed].sort((a, b) =>
      args.sortBy === 'size' ? b.size - a.size : a.name.localeCompare(b.name)
    );
    const lines = sorted.map(e =>
      `${e.isDirectory ? '[DIR]' : '[FILE]'} ${e.name.padEnd(30)} ${e.isDirectory ? '' : formatSize(e.size).padStart(10)}`
    );
    const totalFiles = detailed.filter(e => !e.isDirectory).length;
    const totalDirs = detailed.filter(e => e.isDirectory).length;
    const totalSize = detailed.reduce((s, e) => s + (e.isDirectory ? 0 : e.size), 0);
    lines.push('', `Total: ${totalFiles} files, ${totalDirs} directories`, `Combined size: ${formatSize(totalSize)}`);
    const text = lines.join('\n');
    return { content: [{ type: 'text', text }], structuredContent: { content: text } };
  }));

  server.registerTool('directory_tree', {
    title: 'Directory Tree',
    description: 'Recursive JSON tree of files and directories. Only works within allowed directories.',
    inputSchema: {
      path: z.string(),
      excludePatterns: z.array(z.string()).optional().default([])
    },
    outputSchema: { content: z.string() },
    annotations: { readOnlyHint: true }
  }, wrap('directory_tree', async (args) => {
    async function buildTree(currentPath) {
      const validPath = await validate(currentPath);
      const entries = await fs.readdir(validPath, { withFileTypes: true });
      const result = [];
      for (const entry of entries) {
        const relPath = path.relative(args.path, path.join(currentPath, entry.name));
        const excluded = args.excludePatterns.some(p =>
          minimatch(relPath, p, { dot: true }) ||
          minimatch(relPath, `**/${p}`, { dot: true }) ||
          minimatch(relPath, `**/${p}/**`, { dot: true })
        );
        if (excluded) continue;
        const node = { name: entry.name, type: entry.isDirectory() ? 'directory' : 'file' };
        if (entry.isDirectory()) {
          node.children = await buildTree(path.join(currentPath, entry.name));
        }
        result.push(node);
      }
      return result;
    }
    const tree = await buildTree(args.path);
    const text = JSON.stringify(tree, null, 2);
    return { content: [{ type: 'text', text }], structuredContent: { content: text } };
  }));

  server.registerTool('move_file', {
    title: 'Move File',
    description: 'Move or rename a file or directory. Fails if destination exists. Both paths must be within allowed directories.',
    inputSchema: { source: z.string(), destination: z.string() },
    outputSchema: { content: z.string() },
    annotations: { readOnlyHint: false, idempotentHint: false, destructiveHint: false }
  }, wrap('move_file', async (args) => {
    const validSrc = await validate(args.source);
    const validDst = await validate(args.destination);
    await fs.rename(validSrc, validDst);
    const text = `Successfully moved ${args.source} to ${args.destination}`;
    return { content: [{ type: 'text', text }], structuredContent: { content: text } };
  }));

  server.registerTool('search_files', {
    title: 'Search Files',
    description: 'Recursively search for files/directories matching a glob pattern. Only searches within allowed directories.',
    inputSchema: {
      path: z.string(),
      pattern: z.string(),
      excludePatterns: z.array(z.string()).optional().default([])
    },
    outputSchema: { content: z.string() },
    annotations: { readOnlyHint: true }
  }, wrap('search_files', async (args) => {
    const validPath = await validate(args.path);
    const results = [];
    await searchFilesRecursive(validPath, args.pattern, args.excludePatterns, allowedDir, results);
    const text = results.length > 0 ? results.join('\n') : 'No matches found';
    return { content: [{ type: 'text', text }], structuredContent: { content: text } };
  }));

  server.registerTool('get_file_info', {
    title: 'Get File Info',
    description: 'Get metadata for a file or directory (size, type, permissions, timestamps). Only works within allowed directories.',
    inputSchema: { path: z.string() },
    outputSchema: { content: z.string() },
    annotations: { readOnlyHint: true }
  }, wrap('get_file_info', async (args) => {
    const validPath = await validate(args.path);
    const stats = await fs.stat(validPath);
    const info = {
      size: formatSize(stats.size),
      type: stats.isDirectory() ? 'directory' : stats.isFile() ? 'file' : 'other',
      created: stats.birthtime.toISOString(),
      modified: stats.mtime.toISOString(),
      accessed: stats.atime.toISOString(),
      permissions: `0${(stats.mode & 0o777).toString(8)}`
    };
    const text = Object.entries(info).map(([k, v]) => `${k}: ${v}`).join('\n');
    return { content: [{ type: 'text', text }], structuredContent: { content: text } };
  }));

  server.registerTool('list_allowed_directories', {
    title: 'List Allowed Directories',
    description: 'List the root directory this server can access.',
    inputSchema: {},
    outputSchema: { content: z.string() },
    annotations: { readOnlyHint: true }
  }, wrap('list_allowed_directories', async () => {
    const text = `Allowed directories:\n${allowedDir}`;
    return { content: [{ type: 'text', text }], structuredContent: { content: text } };
  }));
}
