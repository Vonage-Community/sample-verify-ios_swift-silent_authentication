const request = require('supertest');

jest.mock('@vonage/auth', () => ({ Auth: jest.fn() }));
jest.mock('@vonage/verify2', () => ({ Verify2: jest.fn() }));

let app;

beforeEach(() => {
  jest.resetModules();
  process.env.NODE_ENV = 'test';

  jest.mock('@vonage/auth', () => ({ Auth: jest.fn() }));
  jest.mock('@vonage/verify2', () => ({ Verify2: jest.fn() }));

  const mockVerifyClient = { newRequest: jest.fn(), checkCode: jest.fn(), nextWorkflow: jest.fn() };

  const { setVerifyClient } = require('../routes/verification');
  setVerifyClient(mockVerifyClient);

  const { store } = require('../store');
  store.clear();
  store.create('req-webhook', '+14155551234');

  app = require('../server');
});

describe('POST /callback — event type', () => {
  test('returns 200 and logs the event', async () => {
    const res = await request(app)
      .post('/callback')
      .send({
        request_id: 'req-webhook',
        type: 'event',
        channel: 'silent_auth',
        status: 'action_pending'
      });

    expect(res.status).toBe(200);

    const { store } = require('../store');
    const logs = store.getLogs('req-webhook');
    const eventLog = logs.find(l => l.label === 'webhook:silent_auth:action_pending');
    expect(eventLog).toBeDefined();
    expect(eventLog.detail.channel).toBe('silent_auth');
    expect(eventLog.detail.status).toBe('action_pending');
    expect(eventLog.step).toBe('2/5');
    expect(eventLog.note).toContain('check_url');
  });

  test('includes action field when present', async () => {
    const action = { type: 'check', check_url: 'https://api.nexmo.com/v2/verify/req-webhook/silent-auth/redirect' };

    await request(app)
      .post('/callback')
      .send({
        request_id: 'req-webhook',
        type: 'event',
        channel: 'silent_auth',
        status: 'action_pending',
        action
      });

    const { store } = require('../store');
    const logs = store.getLogs('req-webhook');
    const eventLog = logs.find(l => l.label === 'webhook:silent_auth:action_pending');
    expect(eventLog.detail.action).toEqual(action);
  });
});

describe('POST /callback — summary type', () => {
  test('updates status and logs summary', async () => {
    const workflow = [
      { channel: 'silent_auth', status: 'expired' },
      { channel: 'sms', status: 'completed' },
      { channel: 'voice', status: 'unused' }
    ];

    const res = await request(app)
      .post('/callback')
      .send({
        request_id: 'req-webhook',
        type: 'summary',
        status: 'completed',
        workflow
      });

    expect(res.status).toBe(200);

    const { store } = require('../store');
    expect(store.get('req-webhook').status).toBe('completed');

    const logs = store.getLogs('req-webhook');
    const summaryLog = logs.find(l => l.label === 'webhook:summary');
    expect(summaryLog).toBeDefined();
    expect(summaryLog.detail.status).toBe('completed');
    expect(summaryLog.detail.workflow).toHaveLength(3);
    expect(summaryLog.note).toContain('silent_auth: expired, sms: completed, voice: unused');
  });

  test('summary on the silent_auth path gets a 5/5 step', async () => {
    await request(app)
      .post('/callback')
      .send({
        request_id: 'req-webhook',
        type: 'summary',
        status: 'completed',
        workflow: [
          { channel: 'silent_auth', status: 'completed' },
          { channel: 'sms', status: 'unused' },
          { channel: 'voice', status: 'unused' }
        ]
      });

    const { store } = require('../store');
    const summaryLog = store.getLogs('req-webhook').find(l => l.label === 'webhook:summary');
    expect(summaryLog.step).toBe('5/5');
  });

  test('summary on the voice path gets a 6/6 step', async () => {
    const { store } = require('../store');
    store.setChannel('req-webhook', 'voice');

    await request(app)
      .post('/callback')
      .send({
        request_id: 'req-webhook',
        type: 'summary',
        status: 'completed',
        workflow: [
          { channel: 'silent_auth', status: 'failed' },
          { channel: 'sms', status: 'expired' },
          { channel: 'voice', status: 'completed' }
        ]
      });

    const summaryLog = store.getLogs('req-webhook').find(l => l.label === 'webhook:summary');
    expect(summaryLog.step).toBe('6/6');
  });

  test('does not downgrade a completed status (idempotent)', async () => {
    const { store } = require('../store');
    store.setStatus('req-webhook', 'completed');

    await request(app)
      .post('/callback')
      .send({
        request_id: 'req-webhook',
        type: 'summary',
        status: 'expired',
        workflow: []
      });

    expect(store.get('req-webhook').status).toBe('completed');
  });
});

describe('POST /callback — channel auto-advance', () => {
  test('an SMS `expired` event advances the workflow sms → voice', async () => {
    const { store } = require('../store');
    store.setChannel('req-webhook', 'sms');

    await request(app)
      .post('/callback')
      .send({
        request_id: 'req-webhook',
        type: 'event',
        channel: 'sms',
        status: 'expired'
      });

    expect(store.get('req-webhook').channel).toBe('voice');
    const advanceLog = store.getLogs('req-webhook').find(l => l.label === 'workflow:channel_advanced');
    expect(advanceLog).toBeDefined();
    expect(advanceLog.detail).toEqual({ from: 'sms', to: 'voice' });
  });

  test('an SMS `completed` event does NOT advance (the request is done)', async () => {
    const { store } = require('../store');
    store.setChannel('req-webhook', 'sms');

    await request(app)
      .post('/callback')
      .send({
        request_id: 'req-webhook',
        type: 'event',
        channel: 'sms',
        status: 'completed'
      });

    expect(store.get('req-webhook').channel).toBe('sms');
    expect(store.getLogs('req-webhook').some(l => l.label === 'workflow:channel_advanced')).toBe(false);
  });

  test('a stale event for an already-passed channel does not move backward', async () => {
    const { store } = require('../store');
    store.setChannel('req-webhook', 'voice');

    // A late silent_auth `failed` arrives after we're already on voice
    await request(app)
      .post('/callback')
      .send({
        request_id: 'req-webhook',
        type: 'event',
        channel: 'silent_auth',
        status: 'failed'
      });

    expect(store.get('req-webhook').channel).toBe('voice');
    expect(store.getLogs('req-webhook').some(l => l.label === 'workflow:channel_advanced')).toBe(false);
  });

  test('a voice `expired` event on the last channel does not advance', async () => {
    const { store } = require('../store');
    store.setChannel('req-webhook', 'voice');

    await request(app)
      .post('/callback')
      .send({
        request_id: 'req-webhook',
        type: 'event',
        channel: 'voice',
        status: 'expired'
      });

    expect(store.get('req-webhook').channel).toBe('voice');
    expect(store.getLogs('req-webhook').some(l => l.label === 'workflow:channel_advanced')).toBe(false);
  });

  test('after auto-advance, a voice completion is numbered against the 6-step total', async () => {
    const { store } = require('../store');
    store.setChannel('req-webhook', 'sms');

    // SMS expires → advance to voice
    await request(app).post('/callback').send({
      request_id: 'req-webhook', type: 'event', channel: 'sms', status: 'expired'
    });
    // Voice completes
    await request(app).post('/callback').send({
      request_id: 'req-webhook', type: 'event', channel: 'voice', status: 'completed'
    });

    const voiceLog = store.getLogs('req-webhook').find(l => l.label === 'webhook:voice:completed');
    expect(voiceLog.step).toBe('6/6');
  });
});

describe('GET /logs/:request_id — channel', () => {
  test('includes the current channel in the response', async () => {
    const { store } = require('../store');
    store.setChannel('req-webhook', 'voice');

    const res = await request(app).get('/logs/req-webhook');
    expect(res.status).toBe(200);
    expect(res.body.channel).toBe('voice');
  });
});

describe('POST /callback — unknown request_id', () => {
  test('returns 200 even for unknown request_id', async () => {
    const res = await request(app)
      .post('/callback')
      .send({
        request_id: 'no-such-id',
        type: 'event',
        channel: 'sms',
        status: 'completed'
      });

    expect(res.status).toBe(200);
  });

  test('returns 200 when request_id is missing entirely', async () => {
    const res = await request(app)
      .post('/callback')
      .send({ type: 'event' });

    expect(res.status).toBe(200);
  });
});

describe('GET /logs/:request_id', () => {
  test('returns logs array for known request', async () => {
    const res = await request(app).get('/logs/req-webhook');

    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.logs)).toBe(true);
    expect(res.body.logs.length).toBeGreaterThan(0);
  });

  test('returns 404 for unknown request_id', async () => {
    const res = await request(app).get('/logs/no-such-id');
    expect(res.status).toBe(404);
  });
});
