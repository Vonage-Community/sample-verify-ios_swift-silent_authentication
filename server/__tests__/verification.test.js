const request = require('supertest');

// Factory mocks avoid loading the real ESM-dependent Vonage packages
jest.mock('@vonage/auth', () => ({ Auth: jest.fn() }));
jest.mock('@vonage/verify2', () => ({ Verify2: jest.fn() }));

let app;
let mockVerifyClient;

beforeEach(() => {
  jest.resetModules();
  jest.clearAllMocks();

  process.env.NODE_ENV = 'test';

  mockVerifyClient = {
    newRequest: jest.fn(),
    checkCode: jest.fn(),
    nextWorkflow: jest.fn()
  };

  // Re-require after resetModules so the factory mock is fresh
  jest.mock('@vonage/auth', () => ({ Auth: jest.fn() }));
  jest.mock('@vonage/verify2', () => ({ Verify2: jest.fn() }));

  const { setVerifyClient } = require('../routes/verification');
  setVerifyClient(mockVerifyClient);

  const { store } = require('../store');
  store.clear();

  app = require('../server');
});

describe('GET /health', () => {
  test('returns ok', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });
});

describe('POST /verification', () => {
  test('returns request_id and check_url on success', async () => {
    mockVerifyClient.newRequest.mockResolvedValue({
      requestId: 'req-abc',
      checkUrl: 'https://api.nexmo.com/v2/verify/req-abc/silent-auth/redirect'
    });

    const res = await request(app)
      .post('/verification')
      .send({ phone: '+14155551234' });

    expect(res.status).toBe(200);
    expect(res.body.request_id).toBe('req-abc');
    expect(res.body.check_url).toBe('https://api.nexmo.com/v2/verify/req-abc/silent-auth/redirect');
    expect(mockVerifyClient.newRequest).toHaveBeenCalledWith(
      expect.objectContaining({
        channelTimeout: expect.any(Number),
        workflow: expect.arrayContaining([
          expect.objectContaining({ channel: 'silent_auth' }),
          expect.objectContaining({ channel: 'sms' }),
          expect.objectContaining({ channel: 'voice' })
        ])
      })
    );
  });

  test('returns null check_url when silent auth not available', async () => {
    mockVerifyClient.newRequest.mockResolvedValue({
      requestId: 'req-def',
      checkUrl: undefined
    });

    const res = await request(app)
      .post('/verification')
      .send({ phone: '+14155551234' });

    expect(res.status).toBe(200);
    expect(res.body.check_url).toBeNull();
  });

  test('returns 400 when phone is missing', async () => {
    const res = await request(app)
      .post('/verification')
      .send({});

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/phone/);
  });

  test('propagates Vonage API error status', async () => {
    const err = new Error('Vonage error');
    err.response = { status: 422, data: { title: 'Unprocessable' } };
    mockVerifyClient.newRequest.mockRejectedValue(err);

    const res = await request(app)
      .post('/verification')
      .send({ phone: '+14155551234' });

    expect(res.status).toBe(422);
  });
});

describe('POST /check-code', () => {
  beforeEach(() => {
    const { store } = require('../store');
    store.create('req-check', '+14155551234');
  });

  test('returns verified: true when code is correct', async () => {
    mockVerifyClient.checkCode.mockResolvedValue('completed');

    const res = await request(app)
      .post('/check-code')
      .send({ request_id: 'req-check', code: 'abc123' });

    expect(res.status).toBe(200);
    expect(res.body.verified).toBe(true);
    expect(res.body.status).toBe('completed');

    const { store } = require('../store');
    const logs = store.getLogs('req-check');
    const completedLog = logs.find(l => l.label === 'verification:completed');
    expect(completedLog.step).toBe('5/5');
    expect(completedLog.detail.channel).toBe('silent_auth');
    const checkLog = logs.find(l => l.label === 'verification:checkCode');
    expect(checkLog.step).toBe('4/5');
    expect(checkLog.detail.code).toBe('23'); // last 2 digits only
  });

  test('completed on the voice path logs step 6/6', async () => {
    mockVerifyClient.checkCode.mockResolvedValue('completed');
    const { store } = require('../store');
    store.setChannel('req-check', 'voice');

    await request(app)
      .post('/check-code')
      .send({ request_id: 'req-check', code: 'abc123' });

    const completedLog = store.getLogs('req-check').find(l => l.label === 'verification:completed');
    expect(completedLog.step).toBe('6/6');
    expect(completedLog.detail.channel).toBe('voice');
  });

  test('returns verified: false when code is wrong', async () => {
    mockVerifyClient.checkCode.mockResolvedValue('failed');

    const res = await request(app)
      .post('/check-code')
      .send({ request_id: 'req-check', code: 'wrong' });

    expect(res.status).toBe(200);
    expect(res.body.verified).toBe(false);
  });

  test('returns 400 when request_id is missing', async () => {
    const res = await request(app)
      .post('/check-code')
      .send({ code: '123456' });

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/request_id/);
  });

  test('returns 400 when code is missing', async () => {
    const res = await request(app)
      .post('/check-code')
      .send({ request_id: 'req-check' });

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/code/);
  });

  test('returns 404 for unknown request_id', async () => {
    const res = await request(app)
      .post('/check-code')
      .send({ request_id: 'no-such-id', code: '123456' });

    expect(res.status).toBe(404);
  });

  test('handles invalid code error from Vonage (400) as verified: false', async () => {
    const err = new Error('Bad code');
    err.response = { status: 400, data: 'Invalid code' };
    mockVerifyClient.checkCode.mockRejectedValue(err);

    const res = await request(app)
      .post('/check-code')
      .send({ request_id: 'req-check', code: 'bad' });

    expect(res.status).toBe(200);
    expect(res.body.verified).toBe(false);
  });
});

describe('POST /next', () => {
  beforeEach(() => {
    const { store } = require('../store');
    store.create('req-next', '+14155551234');
  });

  test('calls nextWorkflow and returns ok', async () => {
    mockVerifyClient.nextWorkflow.mockResolvedValue({});

    const res = await request(app)
      .post('/next')
      .send({ request_id: 'req-next' });

    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(mockVerifyClient.nextWorkflow).toHaveBeenCalledWith('req-next');
  });

  test('advances channel silent_auth → sms and logs step 2/5', async () => {
    mockVerifyClient.nextWorkflow.mockResolvedValue({});
    const { store } = require('../store');

    await request(app).post('/next').send({ request_id: 'req-next' });

    expect(store.get('req-next').channel).toBe('sms');
    const log = store.getLogs('req-next').find(l => l.label === 'verification:next');
    expect(log.step).toBe('2/5');
    expect(log.detail).toEqual({ from: 'silent_auth', to: 'sms', pathTotal: 5 });
  });

  test('advances channel sms → voice and logs step 4/6', async () => {
    mockVerifyClient.nextWorkflow.mockResolvedValue({});
    const { store } = require('../store');

    await request(app).post('/next').send({ request_id: 'req-next' });
    await request(app).post('/next').send({ request_id: 'req-next' });

    expect(store.get('req-next').channel).toBe('voice');
    const logs = store.getLogs('req-next').filter(l => l.label === 'verification:next');
    expect(logs[1].step).toBe('4/6');
    expect(logs[1].detail).toEqual({ from: 'sms', to: 'voice', pathTotal: 6 });
    expect(logs[1].note).toContain('voice');
  });

  test('returns 400 when request_id is missing', async () => {
    const res = await request(app)
      .post('/next')
      .send({});

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/request_id/);
  });

  test('returns 404 for unknown request_id', async () => {
    const res = await request(app)
      .post('/next')
      .send({ request_id: 'no-such-id' });

    expect(res.status).toBe(404);
  });
});
