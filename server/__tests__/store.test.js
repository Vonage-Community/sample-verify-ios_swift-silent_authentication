const { store, redactPhone, redactCode } = require('../store');

beforeEach(() => {
  store.clear();
});

describe('redactPhone', () => {
  test('redacts middle digits, keeps country code and last 4', () => {
    expect(redactPhone('+14155551234')).toBe('+14•••••1234');
  });

  test('handles short strings gracefully', () => {
    expect(redactPhone('+1')).toBe('+1');
    expect(redactPhone('')).toBe('');
    expect(redactPhone(null)).toBeNull();
  });
});

describe('redactCode', () => {
  test('returns only last 2 digits', () => {
    expect(redactCode('abc123')).toBe('23');
    expect(redactCode('si9sfG')).toBe('fG');
  });

  test('handles short codes', () => {
    expect(redactCode('a')).toBe('a');
    expect(redactCode(null)).toBeNull();
  });
});

describe('VerificationStore', () => {
  test('create stores a record with pending status and initial log', () => {
    const record = store.create('req-1', '+14155551234');
    expect(record.requestId).toBe('req-1');
    expect(record.status).toBe('pending');
    expect(record.logs).toHaveLength(1);
    expect(record.logs[0].label).toBe('verification:created');
    // phone in log is redacted
    expect(record.logs[0].detail.phone).not.toContain('555');
  });

  test('get returns stored record', () => {
    store.create('req-2', '+14155551234');
    const record = store.get('req-2');
    expect(record).toBeDefined();
    expect(record.requestId).toBe('req-2');
  });

  test('get returns undefined for unknown id', () => {
    expect(store.get('unknown')).toBeUndefined();
  });

  test('setCheckUrl updates checkUrl and appends log', () => {
    store.create('req-3', '+14155551234');
    store.setCheckUrl('req-3', 'https://api.nexmo.com/v2/verify/req-3/silent-auth/redirect');
    const record = store.get('req-3');
    expect(record.checkUrl).toBe('https://api.nexmo.com/v2/verify/req-3/silent-auth/redirect');
    const log = record.logs.find(l => l.label === 'silent_auth:coverage_passed');
    expect(log).toBeDefined();
    expect(log.step).toBe('2/5');
    expect(log.note).toContain('coverage check');
  });

  test('setCheckUrl with null records "none"', () => {
    store.create('req-4', '+14155551234');
    store.setCheckUrl('req-4', null);
    const record = store.get('req-4');
    expect(record.checkUrl).toBeNull();
    const log = record.logs.find(l => l.label === 'silent_auth:not_available');
    expect(log.detail.checkUrl).toBe('none');
    expect(log.step).toBe('2/5');
  });

  test('setStatus updates status idempotently', () => {
    store.create('req-5', '+14155551234');
    store.setStatus('req-5', 'completed');
    expect(store.get('req-5').status).toBe('completed');
    // calling again with same value is safe
    store.setStatus('req-5', 'completed');
    expect(store.get('req-5').status).toBe('completed');
  });

  test('addLog appends a log entry', () => {
    store.create('req-6', '+14155551234');
    store.addLog('req-6', { source: 'server', label: 'test:event', detail: { foo: 'bar' } });
    const logs = store.getLogs('req-6');
    const entry = logs.find(l => l.label === 'test:event');
    expect(entry).toBeDefined();
    expect(entry.source).toBe('server');
    expect(entry.detail.foo).toBe('bar');
  });

  test('addLog returns null for unknown requestId', () => {
    const result = store.addLog('no-such-id', { source: 'server', label: 'x', detail: {} });
    expect(result).toBeNull();
  });

  test('getLogs returns empty array for unknown requestId', () => {
    expect(store.getLogs('no-such-id')).toEqual([]);
  });

  test('clear empties the store', () => {
    store.create('req-7', '+14155551234');
    store.clear();
    expect(store.get('req-7')).toBeUndefined();
  });
});
