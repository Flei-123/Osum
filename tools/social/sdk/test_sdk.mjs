import assert from 'node:assert/strict';
import { createSocial } from '../../../sdk/social/orient-social.mjs';

const social = createSocial({ act: process.env.ORIENT_ACT });

assert.equal(await social.setActivity('Minecraft', { party: 'mc://h:1' }), true);
assert.equal(await social.setActivity('Pong', { joinable: true }), true);
assert.equal(await social.setActivity('Solo'), true);
assert.equal(await social.setActivity(''), false);
assert.equal(await social.setActivity('bad\nname'), false);
assert.equal(await social.clearActivity(), true);
assert.equal(await social.invite('local:peter', { name: 'Chess' }), true);
assert.equal(await social.invite('local:peter'), true);
assert.equal(await social.askToJoin('local:peter'), true);
const got = await social.takeJoin({ name: 'Chess' });
assert.deepEqual(got, { target: 'game://lobby/7', name: 'Chess', kind: 'invite', from: 'local:peter' });
assert.equal((await social.takeJoin()).target, 'game://lobby/7');

const calls = [];
const injected = createSocial({ run: async (argv) => { calls.push(argv); return { code: 0, stdout: 'ok\nfound=false\n' }; } });
assert.equal(await injected.takeJoin(), null);
assert.deepEqual(calls[0], ['call', 'social.party.take']);

const failing = createSocial({ run: async () => ({ code: 1, stdout: '' }) });
assert.equal(await failing.setActivity('X'), false);
assert.equal(await failing.takeJoin(), null);
console.log('js-ok');
