#!/usr/bin/env node
/**
 * Claude Code hook: Notification
 * Fired when Claude Code sends a notification (error, warning, info, etc.).
 * Reads JSON from stdin (Claude Code hook payload).
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
    type: 'Notification',
    message: payload.message ?? '',
    sessionId: process.env.CLAUDE_SESSION_ID,
  };

  const client = createConnection(SOCKET, () => {
    client.write(JSON.stringify(event) + '\n', () => client.end());
  });
  client.setTimeout(300);
  client.on('timeout', () => client.destroy());
  client.on('error', () => {});
});
