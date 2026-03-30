#!/usr/bin/env node
/**
 * Claude Code hook: Stop
 * Fired when Claude Code finishes a response.
 * Signals the daemon to return to "ready" state (green lightbar).
 */
import { createConnection } from 'net';

const SOCKET = '/tmp/plaude-code.sock';
const event = { type: 'Stop', sessionId: process.env.CLAUDE_SESSION_ID };

const client = createConnection(SOCKET, () => {
  client.write(JSON.stringify(event) + '\n', () => client.end());
});
client.setTimeout(300);
client.on('timeout', () => client.destroy());
client.on('error', () => {});
