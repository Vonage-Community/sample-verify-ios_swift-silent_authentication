const store = new Map();

function redactPhone(e164) {
  if (!e164 || typeof e164 !== 'string') return e164;
  if (e164.length < 6) return e164;
  const countryPart = e164.slice(0, 3);
  const lastFour = e164.slice(-4);
  return `${countryPart}•••••${lastFour}`;
}

function redactCode(code) {
  if (!code || typeof code !== 'string') return code;
  if (code.length < 2) return code;
  return code.slice(-2);
}

// Each verification follows one of three paths, and the Dev Mode console
// enumerates steps against the path's total: silent_auth and sms are 5-step
// stories, voice (silent_auth → sms → voice) is 6. `record.channel` tracks
// which channel is currently active so log events can be numbered correctly.
const PATH_TOTALS = { silent_auth: 5, sms: 5, voice: 6 };

// Default workflow order, used when a record didn't capture its own. Vonage
// auto-advances on channel timeout (e.g. SMS expires → voice call placed)
// without the app calling /next, so webhook events are the real source of
// truth for which channel is live.
const DEFAULT_WORKFLOW = ['silent_auth', 'sms', 'voice'];

// Event statuses that mean a channel finished WITHOUT completing the request,
// so Vonage will move on to the next channel in the workflow. `completed`,
// `action_pending`, `cancelled`, and the user-rejection statuses are excluded:
// they either finish the request or don't imply a forward move.
const ADVANCING_STATUSES = new Set(['expired', 'failed', 'blocked']);

class VerificationStore {
  create(requestId, phone) {
    const now = new Date().toISOString();
    const record = {
      requestId,
      phone,
      status: 'pending',
      channel: 'silent_auth',
      workflow: DEFAULT_WORKFLOW,
      createdAt: now,
      updatedAt: now,
      checkUrl: null,
      logs: [
        {
          timestamp: now,
          source: 'server',
          requestId,
          label: 'verification:created',
          step: '1/5',
          note: 'Verification request accepted by Vonage. Workflow: silent_auth first, then SMS, then voice.',
          detail: { phone: redactPhone(phone) }
        }
      ]
    };
    store.set(requestId, record);
    return record;
  }

  get(requestId) {
    return store.get(requestId);
  }

  setCheckUrl(requestId, checkUrl) {
    const record = store.get(requestId);
    if (!record) return null;
    record.checkUrl = checkUrl;
    record.updatedAt = new Date().toISOString();
    record.logs.push({
      timestamp: record.updatedAt,
      source: 'server',
      requestId,
      label: checkUrl ? 'silent_auth:coverage_passed' : 'silent_auth:not_available',
      step: '2/5',
      note: checkUrl
        ? 'Vonage ran a synchronous carrier coverage check and it passed — a check_url was returned. The device must now fetch it over cellular data (never Wi-Fi).'
        : 'No check_url in the response — the carrier does not support Silent Auth for this number. Vonage moves to the SMS channel.',
      detail: { checkUrl: checkUrl ? 'present' : 'none' }
    });
    store.set(requestId, record);
    return record;
  }

  setStatus(requestId, status) {
    const record = store.get(requestId);
    if (!record) return null;
    record.status = status;
    record.updatedAt = new Date().toISOString();
    store.set(requestId, record);
    return record;
  }

  setChannel(requestId, channel) {
    const record = store.get(requestId);
    if (!record) return null;
    record.channel = channel;
    record.updatedAt = new Date().toISOString();
    store.set(requestId, record);
    return record;
  }

  setWorkflow(requestId, channels) {
    const record = store.get(requestId);
    if (!record) return null;
    if (Array.isArray(channels) && channels.length > 0) {
      record.workflow = channels;
      record.updatedAt = new Date().toISOString();
      store.set(requestId, record);
    }
    return record;
  }

  setChannelTimeout(requestId, seconds) {
    const record = store.get(requestId);
    if (!record) return null;
    record.channelTimeout = seconds;
    record.updatedAt = new Date().toISOString();
    store.set(requestId, record);
    return record;
  }

  // React to a per-channel event webhook. Vonage's event callbacks carry a
  // channel's *final* status — there is no "next channel started" event. So the
  // signal that the workflow moved on is the CURRENT channel reporting a
  // non-completing terminal status (e.g. SMS `expired` after its ~3min timeout):
  // that means Vonage is now driving the next channel in the workflow (voice).
  // Advances forward only, and only when the finished channel is the one we
  // think is active — a stale/out-of-order event for an older channel is
  // ignored. Returns the new channel if it moved, else null.
  advanceOnChannelFinished(requestId, finishedChannel, status) {
    const record = store.get(requestId);
    if (!record) return null;
    if (!ADVANCING_STATUSES.has(status)) return null;
    if (finishedChannel !== record.channel) return null;

    const workflow = record.workflow || DEFAULT_WORKFLOW;
    const idx = workflow.indexOf(record.channel);
    if (idx < 0 || idx >= workflow.length - 1) return null; // no next channel

    const nextChannel = workflow[idx + 1];
    record.channel = nextChannel;
    record.updatedAt = new Date().toISOString();
    store.set(requestId, record);
    return nextChannel;
  }

  pathTotal(requestId) {
    const record = store.get(requestId);
    return PATH_TOTALS[record?.channel] || 5;
  }

  addLog(requestId, { source, label, detail, step, note }) {
    const record = store.get(requestId);
    if (!record) return null;
    const logEntry = {
      timestamp: new Date().toISOString(),
      source,
      requestId,
      label,
      ...(step ? { step } : {}),
      ...(note ? { note } : {}),
      detail
    };
    record.logs.push(logEntry);
    record.updatedAt = logEntry.timestamp;
    store.set(requestId, record);
    return logEntry;
  }

  getLogs(requestId) {
    const record = store.get(requestId);
    return record ? record.logs : [];
  }

  clear() {
    store.clear();
  }
}

module.exports = {
  store: new VerificationStore(),
  redactPhone,
  redactCode
};
