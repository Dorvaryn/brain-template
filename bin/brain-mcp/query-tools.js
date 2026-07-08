import fg from 'fast-glob';
import yaml from 'js-yaml';
import { promises as fs } from 'fs';
import path from 'path';
import { z } from 'zod';

async function parseWikiFile(filePath, wikiDir) {
  const content = await fs.readFile(filePath, 'utf8');
  const slug = path.relative(wikiDir, filePath).replace(/\.md$/, '');
  let frontmatter = {};
  let summary = '';
  const fmMatch = content.match(/^---\n([\s\S]*?)\n---/);
  if (fmMatch) {
    try { frontmatter = yaml.load(fmMatch[1]) || {}; } catch {}
  }
  const summaryMatch = content.match(/## Summary\n([\s\S]*?)(?=\n##|$)/);
  if (summaryMatch) summary = summaryMatch[1].trim();
  return { slug, frontmatter, summary, content };
}

function matchesStatus(fileStatus, filterStatus) {
  if (fileStatus == null) return false;
  if (typeof fileStatus === 'string') return fileStatus === filterStatus;
  if (typeof fileStatus === 'object') return Object.values(fileStatus).includes(filterStatus);
  return false;
}

export function registerQueryTools(server, brainDir, wrap = (_, h) => h) {
  const wikiDir = path.join(brainDir, 'wiki');

  server.registerTool('list_wiki', {
    title: 'List Wiki Pages',
    description: 'List wiki pages with optional filtering by type, status, team, or platform. ' +
      'Returns slug, type, status, team, and first sentence of the Summary for each match. ' +
      'Use this instead of reading index.md to find wiki page slugs.',
    inputSchema: {
      type: z.string().optional().describe(
        'Filter by entity type: project, decision, question, architecture, team, person, theatre, knowledge, week-note'
      ),
      status: z.string().optional().describe(
        'Filter by status value (e.g. open, active, resolved, complete). Handles both string and dict status fields.'
      ),
      team: z.string().optional().describe('Filter by team field (exact match)'),
      platform: z.string().optional().describe('Filter by platform field (case-insensitive substring match)'),
      project_type: z.string().optional().describe(
        'Filter projects by project_type: platform, cross-cutting, evaluation, roadmap, devex, personal'
      )
    },
    annotations: { readOnlyHint: true }
  }, wrap('list_wiki', async (args) => {
    const files = await fg('**/*.md', { cwd: wikiDir, absolute: true, followSymbolicLinks: false });
    const results = [];
    for (const file of files) {
      try {
        const { slug, frontmatter, summary } = await parseWikiFile(file, wikiDir);
        if (args.type && frontmatter.type !== args.type) continue;
        if (args.status && !matchesStatus(frontmatter.status, args.status)) continue;
        if (args.team && frontmatter.team !== args.team) continue;
        if (args.platform) {
          const platforms = Array.isArray(frontmatter.platforms)
            ? frontmatter.platforms
            : [frontmatter.platform];
          if (!platforms.some(p => p && p.toLowerCase().includes(args.platform.toLowerCase()))) continue;
        }
        if (args.project_type && frontmatter.project_type !== args.project_type) continue;
        const firstLine = summary.split('\n')[0].slice(0, 200);
        results.push({
          slug,
          type: frontmatter.type,
          status: frontmatter.status,
          team: frontmatter.team,
          project_type: frontmatter.project_type,
          summary: firstLine
        });
      } catch {}
    }
    results.sort((a, b) => a.slug.localeCompare(b.slug));
    const text = JSON.stringify(results, null, 2);
    return { content: [{ type: 'text', text }], structuredContent: { content: text } };
  }));

  server.registerTool('get_summaries', {
    title: 'Get Wiki Summaries',
    description: 'Fetch the full Summary section and frontmatter for specific wiki pages by slug. ' +
      'Use after list_wiki to get more detail on pages of interest.',
    inputSchema: {
      slugs: z.array(z.string()).min(1).describe(
        'Wiki slugs to fetch (e.g. ["decisions/apple-pay-zonal-ssl-expiry", "projects/artemis/catalogue"])'
      )
    },
    annotations: { readOnlyHint: true }
  }, wrap('get_summaries', async (args) => {
    const results = await Promise.all(args.slugs.map(async slug => {
      const filePath = path.join(wikiDir, `${slug}.md`);
      try {
        const { frontmatter, summary } = await parseWikiFile(filePath, wikiDir);
        return { slug, frontmatter, summary };
      } catch (err) {
        return { slug, error: err.message };
      }
    }));
    const text = JSON.stringify(results, null, 2);
    return { content: [{ type: 'text', text }], structuredContent: { content: text } };
  }));

  server.registerTool('search_frontmatter', {
    title: 'Search Wiki Frontmatter',
    description: 'Find wiki pages by frontmatter field value (case-insensitive substring match). ' +
      'Useful for finding pages by owner, jira_epics, project, source, etc.',
    inputSchema: {
      field: z.string().describe('Frontmatter field name (e.g. owner, team, jira_epics, project)'),
      value: z.string().describe('Value to search for (case-insensitive substring)')
    },
    annotations: { readOnlyHint: true }
  }, wrap('search_frontmatter', async (args) => {
    const files = await fg('**/*.md', { cwd: wikiDir, absolute: true, followSymbolicLinks: false });
    const results = [];
    for (const file of files) {
      try {
        const { slug, frontmatter } = await parseWikiFile(file, wikiDir);
        const fieldValue = frontmatter[args.field];
        if (fieldValue == null) continue;
        const strValue = Array.isArray(fieldValue) ? fieldValue.join(' ') : String(fieldValue);
        if (strValue.toLowerCase().includes(args.value.toLowerCase())) {
          results.push({ slug, matched_value: fieldValue, type: frontmatter.type, status: frontmatter.status });
        }
      } catch {}
    }
    const text = JSON.stringify(results, null, 2);
    return { content: [{ type: 'text', text }], structuredContent: { content: text } };
  }));

  server.registerTool('list_recent', {
    title: 'List Recent Wiki Activity',
    description: 'Return wiki page activity from the last N days, parsed from log.md. ' +
      'More reliable than hot.md for finding recently touched pages.',
    inputSchema: {
      days: z.number().min(1).max(90).default(7).describe('Number of days to look back (default 7)')
    },
    annotations: { readOnlyHint: true }
  }, wrap('list_recent', async (args) => {
    const logPath = path.join(brainDir, 'log.md');
    let logContent;
    try {
      logContent = await fs.readFile(logPath, 'utf8');
    } catch {
      return { content: [{ type: 'text', text: '[]' }], structuredContent: { content: '[]' } };
    }
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - args.days);
    const entries = [];
    const linePattern = /^## \[(\d{4}-\d{2}-\d{2}T[\d:Z]+)\] (\S+) \| (.+)$/;
    for (const line of logContent.split('\n')) {
      const match = line.match(linePattern);
      if (!match) continue;
      const [, timestamp, operation, description] = match;
      if (new Date(timestamp) < cutoff) continue;
      // Extract wiki page slugs referenced in the description
      const slugMatches = [...description.matchAll(/wiki\/([^\s,]+?)(?:\.md)?(?:\s|,|$)/g)];
      const slugs = slugMatches.map(m => m[1]);
      entries.push({ timestamp, operation, description, slugs });
    }
    const text = JSON.stringify(entries, null, 2);
    return { content: [{ type: 'text', text }], structuredContent: { content: text } };
  }));

  server.registerTool('find_links', {
    title: 'Find Wiki Backlinks',
    description: 'Find all wiki pages that contain a [[wikilink]] pointing to a given slug. ' +
      'Useful for impact analysis — e.g. which pages reference a decision before changing it.',
    inputSchema: {
      slug: z.string().describe(
        'Wiki slug to find backlinks for (e.g. "decisions/apple-pay-zonal-ssl-expiry")'
      )
    },
    annotations: { readOnlyHint: true }
  }, wrap('find_links', async (args) => {
    const files = await fg('**/*.md', { cwd: wikiDir, absolute: true, followSymbolicLinks: false });
    const basename = path.basename(args.slug);
    const results = [];
    for (const file of files) {
      try {
        const content = await fs.readFile(file, 'utf8');
        if (content.includes(`[[${basename}]]`) || content.includes(`[[${args.slug}]]`)) {
          const slug = path.relative(wikiDir, file).replace(/\.md$/, '');
          if (slug !== args.slug) results.push(slug);
        }
      } catch {}
    }
    const text = JSON.stringify(results, null, 2);
    return { content: [{ type: 'text', text }], structuredContent: { content: text } };
  }));

  server.registerTool('get_open_questions', {
    title: 'Get Open Questions',
    description: 'List all open decisions and questions from the wiki, optionally filtered by owner. ' +
      'Equivalent to list_wiki({type:"question", status:"open"}) but also catches type:"decision" status:"open".',
    inputSchema: {
      owner: z.string().optional().describe('Filter by owner frontmatter field (exact match)')
    },
    annotations: { readOnlyHint: true }
  }, wrap('get_open_questions', async (args) => {
    const files = await fg('**/*.md', { cwd: wikiDir, absolute: true, followSymbolicLinks: false });
    const results = [];
    for (const file of files) {
      try {
        const { slug, frontmatter, summary } = await parseWikiFile(file, wikiDir);
        if (frontmatter.type !== 'question' && frontmatter.type !== 'decision') continue;
        if (frontmatter.status !== 'open') continue;
        if (args.owner && frontmatter.owner !== args.owner) continue;
        results.push({
          slug,
          type: frontmatter.type,
          owner: frontmatter.owner,
          raised: frontmatter.raised,
          team: frontmatter.team,
          summary: summary.split('\n')[0].slice(0, 200)
        });
      } catch {}
    }
    results.sort((a, b) => (String(a.raised || '')).localeCompare(String(b.raised || '')));
    const text = JSON.stringify(results, null, 2);
    return { content: [{ type: 'text', text }], structuredContent: { content: text } };
  }));

  server.registerTool('search_wiki_content', {
    title: 'Search Wiki Page Content',
    description: 'Full-text search across all wiki page bodies (not just frontmatter). ' +
      'Returns slug, matched lines with surrounding context, and the page type. ' +
      'Use when you need to find pages that mention a concept, person, or term ' +
      'that does not appear in frontmatter fields.',
    inputSchema: {
      query: z.string().describe('Search string (case-insensitive substring match)'),
      type: z.string().optional().describe('Optionally restrict search to a specific entity type'),
      context_lines: z.number().min(0).max(5).default(1).describe('Lines of context around each match (default 1)')
    },
    annotations: { readOnlyHint: true }
  }, wrap('search_wiki_content', async (args) => {
    const files = await fg('**/*.md', { cwd: wikiDir, absolute: true, followSymbolicLinks: false });
    const queryLower = args.query.toLowerCase();
    const results = [];
    for (const file of files) {
      try {
        const { slug, frontmatter, content } = await parseWikiFile(file, wikiDir);
        if (args.type && frontmatter.type !== args.type) continue;
        const lines = content.split('\n');
        const matches = [];
        for (let i = 0; i < lines.length; i++) {
          if (lines[i].toLowerCase().includes(queryLower)) {
            const start = Math.max(0, i - args.context_lines);
            const end = Math.min(lines.length - 1, i + args.context_lines);
            matches.push({
              line: i + 1,
              excerpt: lines.slice(start, end + 1).join('\n')
            });
          }
        }
        if (matches.length > 0) {
          results.push({ slug, type: frontmatter.type, match_count: matches.length, matches });
        }
      } catch {}
    }
    results.sort((a, b) => b.match_count - a.match_count);
    const text = JSON.stringify(results, null, 2);
    return { content: [{ type: 'text', text }], structuredContent: { content: text } };
  }));

  server.registerTool('get_outbound_links', {
    title: 'Get Outbound Wiki Links',
    description: 'Return all [[wikilinks]] from the ## Links section of a wiki page. ' +
      'Complements find_links (inbound) — together they enable full graph traversal. ' +
      'Use to find what a page depends on or references.',
    inputSchema: {
      slug: z.string().describe('Wiki slug to read outbound links from (e.g. "decisions/apple-pay-zonal-ssl-expiry")')
    },
    annotations: { readOnlyHint: true }
  }, wrap('get_outbound_links', async (args) => {
    const filePath = path.join(wikiDir, `${args.slug}.md`);
    let content;
    try {
      content = await fs.readFile(filePath, 'utf8');
    } catch (err) {
      return {
        content: [{ type: 'text', text: JSON.stringify({ error: err.message }) }],
        structuredContent: { content: JSON.stringify({ error: err.message }) }
      };
    }
    // Extract ## Links section
    const linksMatch = content.match(/## Links\n([\s\S]*?)(?=\n##|$)/);
    const links = [];
    if (linksMatch) {
      const wikilinkPattern = /\[\[([^\]]+)\]\]/g;
      let m;
      while ((m = wikilinkPattern.exec(linksMatch[1])) !== null) {
        links.push(m[1]);
      }
    }
    const text = JSON.stringify(links, null, 2);
    return { content: [{ type: 'text', text }], structuredContent: { content: text } };
  }));
}
