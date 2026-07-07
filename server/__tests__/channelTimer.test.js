// The server mirrors Vonage's channel_timeout clock with local timers because
// Vonage sends no webhook when a channel times out mid-flow (see channelTimer.js).

let store;
let channelTimer;

beforeEach(() => {
  jest.resetModules();
  jest.useFakeTimers();

  ({ store } = require('../store'));
  channelTimer = require('../channelTimer');

  store.clear();
  const record = store.create('req-timer', '+14155551234');
  store.setWorkflow('req-timer', ['silent_auth', 'sms', 'voice']);
  store.setChannelTimeout('req-timer', 60);
});

afterEach(() => {
  channelTimer.clear('req-timer');
  jest.useRealTimers();
});

test('advances sms → voice when the channel timeout elapses', () => {
  store.setChannel('req-timer', 'sms');
  channelTimer.arm('req-timer');

  jest.advanceTimersByTime(60 * 1000 + 5000);

  expect(store.get('req-timer').channel).toBe('voice');
  const log = store.getLogs('req-timer').find(l => l.label === 'workflow:channel_advanced');
  expect(log).toBeDefined();
  expect(log.detail).toEqual({ from: 'sms', to: 'voice', reason: 'channel_timeout' });
});

test('does not fire before the timeout + grace has elapsed', () => {
  store.setChannel('req-timer', 'sms');
  channelTimer.arm('req-timer');

  jest.advanceTimersByTime(60 * 1000); // timeout reached, grace not yet

  expect(store.get('req-timer').channel).toBe('sms');
});

test('a completed request is not advanced', () => {
  store.setChannel('req-timer', 'sms');
  channelTimer.arm('req-timer');

  store.setStatus('req-timer', 'completed');
  jest.advanceTimersByTime(60 * 1000 + 5000);

  expect(store.get('req-timer').channel).toBe('sms');
  expect(store.getLogs('req-timer').some(l => l.label === 'workflow:channel_advanced')).toBe(false);
});

test('clear() disarms the timer', () => {
  store.setChannel('req-timer', 'sms');
  channelTimer.arm('req-timer');
  channelTimer.clear('req-timer');

  jest.advanceTimersByTime(60 * 1000 + 5000);

  expect(store.get('req-timer').channel).toBe('sms');
});

test('does not advance if something else already moved the channel', () => {
  store.setChannel('req-timer', 'sms');
  channelTimer.arm('req-timer');

  // e.g. an explicit /next moved to voice before the timer fired
  store.setChannel('req-timer', 'voice');
  jest.advanceTimersByTime(60 * 1000 + 5000);

  expect(store.get('req-timer').channel).toBe('voice');
  expect(store.getLogs('req-timer').some(l => l.label === 'workflow:channel_advanced')).toBe(false);
});

test('the last channel (voice) is never advanced', () => {
  store.setChannel('req-timer', 'voice');
  channelTimer.arm('req-timer');

  jest.advanceTimersByTime(60 * 1000 + 5000);

  expect(store.get('req-timer').channel).toBe('voice');
});

test('re-arms along the chain: silent_auth → sms → voice over two timeouts', () => {
  channelTimer.arm('req-timer'); // channel is silent_auth

  jest.advanceTimersByTime(60 * 1000 + 5000);
  expect(store.get('req-timer').channel).toBe('sms');

  jest.advanceTimersByTime(60 * 1000 + 5000);
  expect(store.get('req-timer').channel).toBe('voice');

  const advances = store.getLogs('req-timer').filter(l => l.label === 'workflow:channel_advanced');
  expect(advances.map(l => l.detail.to)).toEqual(['sms', 'voice']);
});
