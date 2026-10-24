// SPDX-License-Identifier: GPL-2.0-only
import { execFile } from 'node:child_process';

const FAIL_CODE = -1;

function defaultRun(actPath) {
  return (argv) => new Promise((resolve) => {
    execFile(actPath, argv, { encoding: 'utf8', timeout: 8000 }, (error, stdout) => {
      resolve({ code: error ? (typeof error.code === 'number' ? error.code : FAIL_CODE) : 0, stdout: stdout || '' });
    });
  });
}

function parseReply(stdout) {
  const fields = {};
  for (const line of stdout.split('\n')) {
    const at = line.indexOf('=');
    if (at > 0) fields[line.slice(0, at)] = line.slice(at + 1);
  }
  return fields;
}

function valid(value) {
  return typeof value === 'string' && value.length > 0 && !value.includes('\n');
}

export function createSocial({ act = process.env.ORIENT_ACT || '/bin/act', run = defaultRun(act) } = {}) {
  async function call(action, args = {}) {
    const argv = ['call', action];
    for (const [key, value] of Object.entries(args)) {
      if (value === undefined || value === null || value === false) continue;
      const text = value === true ? 'true' : String(value);
      if (!valid(text)) return { ok: false, fields: {} };
      argv.push(`${key}=${text}`);
    }
    const { code, stdout } = await run(argv);
    return { ok: code === 0, fields: parseReply(stdout) };
  }

  async function setActivity(name, { joinable = false, party } = {}) {
    if (!valid(name)) return false;
    const join = joinable || valid(party);
    return (await call('social.activity.set', { name, join, party })).ok;
  }

  async function clearActivity() {
    return (await call('social.activity.clear')).ok;
  }

  async function invite(friend, { name } = {}) {
    return (await call('social.invites.send', { id: friend, kind: 'invite', name })).ok;
  }

  async function askToJoin(friend) {
    return (await call('social.invites.send', { id: friend, kind: 'join' })).ok;
  }

  async function takeJoin({ name } = {}) {
    const { ok, fields } = await call('social.party.take', { name });
    if (!ok || fields.found !== 'true' || !fields.target) return null;
    return { target: fields.target, name: fields.name, kind: fields.kind, from: fields.from };
  }

  return { setActivity, clearActivity, invite, askToJoin, takeJoin };
}
