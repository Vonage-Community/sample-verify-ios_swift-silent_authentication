const { store } = require('./store');

// Vonage does NOT send a webhook when a channel times out mid-flow and the
// workflow advances (only Silent Auth / WhatsApp Codeless get mid-flow events;
// SMS/voice outcomes show up in the final summary). But the timeout itself is
// a request parameter we set, so the server mirrors Vonage's clock: arm a
// timer when a channel starts, and when it fires with the request still
// pending on that channel, advance to the next one — same move Vonage just
// made on its side.
//
// GRACE_MS makes our clock fire slightly AFTER Vonage's, so we never advance
// the UI ahead of reality.
const GRACE_MS = 5000;

const timers = new Map();

function clear(requestId) {
  const timer = timers.get(requestId);
  if (timer) {
    clearTimeout(timer);
    timers.delete(requestId);
  }
}

// Arm (or re-arm) the timeout mirror for the record's current channel.
// No-op if the request is finished or the channel has no successor.
function arm(requestId) {
  clear(requestId);

  const record = store.get(requestId);
  if (!record || record.status !== 'pending') return;

  const workflow = record.workflow || [];
  const idx = workflow.indexOf(record.channel);
  if (idx < 0 || idx >= workflow.length - 1) return; // last channel — nothing follows

  const channelWhenArmed = record.channel;
  const timeoutSeconds = record.channelTimeout || 300;

  const timer = setTimeout(() => {
    timers.delete(requestId);

    const current = store.get(requestId);
    // Only advance if nothing else moved the request along in the meantime.
    if (!current || current.status !== 'pending' || current.channel !== channelWhenArmed) return;

    const nextChannel = workflow[idx + 1];
    store.setChannel(requestId, nextChannel);
    store.addLog(requestId, {
      source: 'server',
      label: 'workflow:channel_advanced',
      note: `The ${channelWhenArmed} channel hit its ${timeoutSeconds}s timeout without completing, so Vonage advanced the workflow to ${nextChannel}. Vonage sends no webhook for this — the server mirrors the timeout clock itself.`,
      detail: { from: channelWhenArmed, to: nextChannel, reason: 'channel_timeout' }
    });

    arm(requestId); // the new channel may also have a successor
  }, timeoutSeconds * 1000 + GRACE_MS);

  // Don't hold the process open just for pending demo verifications
  if (typeof timer.unref === 'function') timer.unref();
  timers.set(requestId, timer);
}

module.exports = { arm, clear };
