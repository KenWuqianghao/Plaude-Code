#!/usr/bin/env node
/**
 * Claude Code hook: PreToolUse
 * Fired before Claude Code uses a tool.
 * Sends tool name + input so daemon can engage danger lock if needed.
 * MUST exit 0 quickly to not block Claude Code.
 */
import { createConnection } from 'net';

const SOCKET = '/tmp/plaude-code.sock';

let body = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  body += chunk;
});
process.stdin.on('end', () => {
  let payload = {};
  try {
    payload = JSON.parse(body);
  } catch {
    /* ignore */
  }

  const event = {
    type: 'PreToolUse',
    toolName: payload.tool_name ?? payload.toolName ?? '',
    toolInput: payload.tool_input ?? payload.toolInput ?? {},
    sessionId: process.env.CLAUDE_SESSION_ID,
  };

  const client = createConnection(SOCKET, () => {
    client.write(JSON.stringify(event) + '\n', () => client.end());
  });
  client.setTimeout(300);
  client.on('timeout', () => client.destroy());
  client.on('error', () => {});

  process.exit(0);
});

setTimeout(() => process.exit(0), 500);
