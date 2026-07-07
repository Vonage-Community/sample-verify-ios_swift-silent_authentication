const express = require('express');
const { store } = require('../store');
const channelTimer = require('../channelTimer');

const router = express.Router();

// Skip JWT validation in test environment
function verifyWebhookSignature(req) {
  if (process.env.NODE_ENV === 'test') return true;

  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    console.warn('Webhook missing Authorization header');
    return false;
  }

  // @vonage/jwt does not expose a standalone verifySignature in all versions;
  // the application private key is the shared secret for webhook JWTs.
  // In production you'd verify the JWT signature here using the application
  // public key. For this tutorial demo we log the warning and proceed.
  console.warn('Webhook JWT validation not yet implemented — accept in demo only');
  return true;
}

// Maps a per-channel event webhook to a step number and a plain-English note
// for the Dev Mode timeline. `total` is the current path length (5 or 6).
function describeEvent(channel, status, total) {
  const key = `${channel}:${status}`;
  const map = {
    'silent_auth:action_pending': {
      step: '2/5',
      note: 'Vonage issued the check_url and is waiting for the device to fetch it over cellular. Nothing happens until the device acts.'
    },
    'silent_auth:completed': {
      step: '5/5',
      note: 'The carrier confirmed the SIM matches the phone number — no code was ever shown to the user.'
    },
    'silent_auth:failed': {
      step: '2/5',
      note: 'Carrier pre-checks failed (unsupported operator or network error). Vonage falls through to the next channel in the workflow.'
    },
    'silent_auth:user_rejected': {
      step: '2/5',
      note: 'The carrier rejected the authentication for this SIM.'
    },
    'sms:pending': {
      step: '3/5',
      note: 'SMS with a one-time code dispatched to the handset. Compare this with Silent Auth: the user now has to read and retype a code.'
    },
    'sms:completed': {
      step: `${total}/${total}`,
      note: 'The SMS code was entered correctly.'
    },
    'voice:pending': {
      step: '5/6',
      note: 'Vonage is placing a phone call that reads the code aloud — the slowest but most accessible channel.'
    },
    'voice:completed': {
      step: '6/6',
      note: 'The voice code was entered correctly.'
    }
  };
  return map[key] || {
    note: `Channel "${channel}" reported status "${status}".`
  };
}

// POST /callback — Vonage sends both event and summary payloads here
router.post('/callback', (req, res) => {
  // Acknowledge immediately — Vonage expects 200/204 fast; delivery is at-least-once
  res.status(200).json({ ok: true });

  const { request_id, type } = req.body || {};

  verifyWebhookSignature(req);

  if (!request_id) return;

  const record = store.get(request_id);
  if (!record) {
    // Unknown request_id — log and ignore (idempotent)
    console.warn('Webhook for unknown request_id:', request_id);
    return;
  }

  if (type === 'event') {
    const { channel, status, action } = req.body;

    // Vonage may auto-advance on channel timeout without the app calling /next.
    // The signal is the CURRENT channel finishing with a non-completing status
    // (e.g. SMS `expired`) — there is no explicit "voice started" event — which
    // means Vonage is now driving the next channel in the workflow.
    const advancedTo = store.advanceOnChannelFinished(request_id, channel, status);
    if (advancedTo) {
      store.addLog(request_id, {
        source: 'server',
        label: 'workflow:channel_advanced',
        note: `The ${channel} channel ended (${status}) and Vonage advanced the workflow to ${advancedTo} on its own — the app never called /next.`,
        detail: { from: channel, to: advancedTo }
      });
      // Restart the timeout mirror for the channel Vonage just moved to.
      channelTimer.arm(request_id);
    }

    const { step, note } = describeEvent(channel, status, store.pathTotal(request_id));
    store.addLog(request_id, {
      source: 'server',
      label: `webhook:${channel}:${status}`,
      ...(step ? { step } : {}),
      ...(note ? { note } : {}),
      detail: { channel, status, ...(action ? { action } : {}) }
    });
  } else if (type === 'summary') {
    const { status, workflow } = req.body;

    // Idempotent — only update if not already in a terminal state
    if (record.status !== 'completed') {
      store.setStatus(request_id, status);
    }
    // The request is over either way — stop mirroring the channel clock.
    channelTimer.clear(request_id);

    const channels = Array.isArray(workflow)
      ? workflow.map(({ channel, status: s }) => ({ channel, status: s }))
      : [];
    const tally = channels.map((c) => `${c.channel}: ${c.status}`).join(', ');
    const total = store.pathTotal(request_id);

    store.addLog(request_id, {
      source: 'server',
      label: 'webhook:summary',
      step: status === 'completed' ? `${total}/${total}` : undefined,
      note: `Final tally from Vonage — ${tally || 'no workflow data'}. Channels marked "unused" were never needed; that gap is the whole point of Silent Auth.`,
      detail: { status, workflow: channels }
    });
  }
});

// GET /logs/:request_id — iOS polls this every 1.5s to merge server logs into Dev Mode timeline
router.get('/logs/:request_id', (req, res) => {
  const { request_id } = req.params;
  const record = store.get(request_id);

  if (!record) {
    return res.status(404).json({ error: 'Unknown request_id' });
  }

  // `channel` lets the client reconcile its local state when Vonage
  // auto-advanced a channel that the app didn't initiate.
  res.json({ logs: record.logs, channel: record.channel });
});

module.exports = { router };
