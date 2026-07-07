## Prompt

ok new error on the backend:

Error /verification: Request failed with status code 422
(node:63686) [https://github.com/node-fetch/node-fetch/issues/1000 (response)] DeprecationWarning: data doesn't exist, use json(), text(), arrayBuffer(), or body instead

[and separately, the app was hitting http://verification/ instead of http://localhost:4000/verification]

## Checklist

- [x] Diagnose and fix app hitting `http://verification/` instead of the real server URL
- [x] Add better Vonage error body logging to `/verification` route
- [x] Diagnose and fix 422 from Vonage for `+990` playground numbers
- [x] Archive with blog-worthy notes

## Blog-worthy Notes

### Bug 1: xcconfig `//` comment stripping silently breaks URLs

**What happened:** The app was constructing requests to `http://verification/` — the path segment was being treated as the hostname.

**Root cause:** Xcode `.xcconfig` files use `//` as the comment delimiter. The line:
```
BASE_URL = http://localhost:4000
```
gets parsed as `BASE_URL = http:` — everything after `//` is silently dropped as a comment. So `Configuration.baseURL` returned `"http:"`, and `"\(baseURL)/verification"` became `"http:/verification"`, which iOS URL parsing then interpreted as scheme=`http`, host=`verification`, path=`/`.

**Fix:** The standard xcconfig workaround — define a variable for `/` and use it to construct `://`:
```xcconfig
_SLASH = /
BASE_URL = http:$(_SLASH)/localhost:4000
```
`$(_SLASH)` expands to `/`, so the full value becomes `http://localhost:4000`. The same trick applies to `https://` ngrok URLs in `Config.local.xcconfig`.

**Why this is sharp:** There's no build warning. The app compiles and runs — it just silently uses the wrong URL. The `http://verification/` error message in the log is deeply confusing because it looks like a path-vs-host parsing bug rather than a build configuration issue.

---

### Bug 2: `+990` Network Registry Playground numbers reject SMS/voice workflow channels

**What happened:** Vonage returned 422 with:
```json
{
  "invalid_parameters": [
    { "name": "workflow", "reason": "`silent_auth` must be the only channel when virtual operator is used" },
    { "name": "workflow[1]", "reason": "`to` Phone number is invalid" },
    { "name": "workflow[2]", "reason": "`to` Phone number is invalid" }
  ]
}
```

**Root cause:** The `+990` prefix routes to a Vonage virtual operator in the Network Registry Playground. Virtual operators only support the `silent_auth` channel — SMS and voice channels are explicitly rejected, and `+990` numbers are not valid `to` values for those channels.

**Fix:** Detect playground numbers server-side and use a single-channel workflow:
```js
const isPlayground = phone.startsWith('+990');
const workflow = isPlayground
  ? [{ channel: 'silent_auth', to: phone }]
  : [
      { channel: 'silent_auth', to: phone },
      { channel: 'sms', to: phone },
      { channel: 'voice', to: phone }
    ];
```

**Why this matters for the blog:** This is not documented prominently in the Vonage docs — the AGENTS.md mentions that the outcome is controlled by the last digit (even = completed, odd = rejected, `99` = failed), but it doesn't mention the workflow restriction. Anyone trying to test fallback flows with `+990` numbers will hit this 422 and have no idea why. The fix is simple but the diagnosis requires reading the full error body, which the Vonage SDK's default error message (`Request failed with status code 422`) doesn't include.

**Implication for testing fallback:** Since playground numbers only support `silent_auth`, you can't use them to test SMS/voice fallback with real Vonage traffic. For fallback testing, use a real phone number on a device without Silent Auth coverage, or manually call `/next` from the Dev Mode console to force the workflow forward.
