---
category: Status
---

# Toast

The transient message that flies into the top of the HUD — a reward landing, a
purchase confirming, an error.

| Tone | Gradient |
|---|---|
| `neutral` (default) | dark row |
| `success` | green |
| `warn` | small gold |
| `error` | red |

```jsx
<Toast tone="success" icon="coin">+2,500 Coins</Toast>
```

Keep copy to one short line — these sit at `zIndex.toast` (80), above everything
including panels, and are on screen for about two seconds.
