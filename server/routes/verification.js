const express = require('express');
const { store, redactPhone, redactCode } = require('../store');
const channelTimer = require('../channelTimer');

const router = express.Router();

let verifyClient;

function setVerifyClient(client) {
  verifyClient = client;
}

function requireFields(obj, fields) {
  for (const field of fields) {
    if (!obj || obj[field] == null || obj[field] === '') {
      return field;
    }
  }
  return null;
}

router.get('/health', (req, res) => {
  res.json({ ok: true });
});

router.post('/verification', async (req, res) => {
  try {
    const missing = requireFields(req.body, ['phone']);
    if (missing) {
      return res.status(400).json({
        error: `Field '${missing}' is required.`
      });
    }

    const { phone } = req.body;

    // TODO: add rate limiting before production use

    // +990 numbers route to the Network Registry Playground virtual operator,
    // which only accepts silent_auth — SMS/voice channels cause a 422.
    const isPlayground = phone.startsWith('+990');
    const workflow = isPlayground
      ? [{ channel: 'silent_auth', to: phone }]
      : [
          { channel: 'silent_auth', to: phone },
          { channel: 'sms', to: phone },
          { channel: 'voice', to: phone }
        ];

    // Explicit channel timeout (seconds). Vonage advances to the next channel
    // this long after a channel starts — and sends no webhook when it does, so
    // the server mirrors this clock with its own timers (see channelTimer.js).
    // Short default keeps the demo's fallbacks snappy. Vonage allows 15–900.
    const channelTimeout = parseInt(process.env.CHANNEL_TIMEOUT_SECONDS, 10) || 60;

    const result = await verifyClient.newRequest({
      brand: 'SilentAuthDemo',
      workflow,
      channelTimeout
    });

    const record = store.create(result.requestId, phone);
    // Remember the actual channel order so webhook events can advance the
    // active channel when Vonage moves on (e.g. SMS expires → voice).
    store.setWorkflow(result.requestId, workflow.map((w) => w.channel));
    store.setChannelTimeout(result.requestId, channelTimeout);
    store.setCheckUrl(result.requestId, result.checkUrl || null);
    // Start mirroring Vonage's channel-timeout clock from the first channel.
    channelTimer.arm(result.requestId);

    res.json({
      request_id: result.requestId,
      check_url: result.checkUrl || null
    });
  } catch (error) {
    const status = error?.response?.status || 500;
    let details = error?.message;
    try {
      if (error?.response) {
        const body = await error.response.json().catch(() => null)
                  || await error.response.text().catch(() => null);
        details = body ?? details;
        console.error('Vonage error body:', JSON.stringify(body, null, 2));
      }
    } catch (_) {}

    console.error('Error /verification:', details);
    return res.status(status).json({
      error: 'Failed to start verification',
      details: typeof details === 'string' ? details : undefined
    });
  }
});

router.post('/check-code', async (req, res) => {
  try {
    const missing = requireFields(req.body, ['request_id', 'code']);
    if (missing) {
      return res.status(400).json({
        error: `Field '${missing}' is required.`
      });
    }

    const { request_id, code } = req.body;
    const record = store.get(request_id);

    if (!record) {
      return res.status(404).json({
        error: 'Unknown request_id'
      });
    }

    const total = store.pathTotal(request_id);
    const isSilent = record.channel === 'silent_auth';

    store.addLog(request_id, {
      source: 'server',
      label: 'verification:checkCode',
      step: `${total - 1}/${total}`,
      note: isSilent
        ? 'Exchanging the code the device obtained from the carrier. The user never saw it — that is what makes this "silent".'
        : 'Exchanging the code the user typed in. Vonage compares it against the one it sent.',
      detail: { code: redactCode(code) }
    });

    const result = await verifyClient.checkCode(request_id, code);
    const verified = result === 'completed';

    if (verified) {
      store.setStatus(request_id, 'completed');
      channelTimer.clear(request_id);
      store.addLog(request_id, {
        source: 'server',
        label: 'verification:completed',
        step: `${total}/${total}`,
        note: `Vonage returned status "completed" — the phone number is verified via the ${record.channel} channel.`,
        detail: { status: result, channel: record.channel }
      });
    } else {
      store.addLog(request_id, {
        source: 'server',
        label: 'verification:codeFailed',
        note: 'Vonage rejected the code. Three wrong attempts and the whole request is user_rejected.',
        detail: { status: result }
      });
    }

    res.json({
      verified,
      status: result || record.status
    });
  } catch (error) {
    const status = error?.response?.status || 500;
    const details = error?.response?.data || error?.message;

    console.error('Error /check-code:', details);

    if (status === 400 || status === 404) {
      return res.json({
        verified: false,
        error: typeof details === 'string' ? details : 'Invalid code'
      });
    }

    return res.status(status).json({
      error: 'Failed to check code',
      details: typeof details === 'string' ? details : undefined
    });
  }
});

router.post('/next', async (req, res) => {
  try {
    const missing = requireFields(req.body, ['request_id']);
    if (missing) {
      return res.status(400).json({
        error: `Field '${missing}' is required.`
      });
    }

    const { request_id } = req.body;
    const record = store.get(request_id);

    if (!record) {
      return res.status(404).json({
        error: 'Unknown request_id'
      });
    }

    // Advance the tracked channel so subsequent log events are numbered
    // against the right path total (sms stays a 5-step story, voice grows to 6).
    const prevChannel = record.channel;
    const nextChannel = prevChannel === 'silent_auth' ? 'sms' : 'voice';
    store.setChannel(request_id, nextChannel);
    const total = store.pathTotal(request_id);

    store.addLog(request_id, {
      source: 'server',
      label: 'verification:next',
      step: nextChannel === 'sms' ? '2/5' : '4/6',
      note: nextChannel === 'sms'
        ? 'Skipping Silent Auth — telling Vonage to advance the workflow to the SMS channel instead of waiting for the silent_auth timeout.'
        : 'Skipping SMS — the path just grew from 5 steps to 6. Vonage advances to the voice channel and will call the user with a spoken code.',
      detail: { from: prevChannel, to: nextChannel, pathTotal: total }
    });

    const result = await verifyClient.nextWorkflow(request_id);

    store.addLog(request_id, {
      source: 'server',
      label: 'vonage:nextWorkflow',
      note: `Vonage confirmed the workflow advanced to ${nextChannel}.`,
      detail: { result }
    });

    // The new channel's timeout clock starts now.
    channelTimer.arm(request_id);

    res.json({ ok: true });
  } catch (error) {
    const status = error?.response?.status || 500;
    const details = error?.response?.data || error?.message;

    console.error('Error /next:', details);
    return res.status(status).json({
      error: 'Failed to move workflow',
      details: typeof details === 'string' ? details : undefined
    });
  }
});

module.exports = { router, setVerifyClient };
