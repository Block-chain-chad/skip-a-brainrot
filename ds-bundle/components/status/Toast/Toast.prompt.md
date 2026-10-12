Toast from @skip-a-brainrot/ui. Use via `window.SkipABrainrotUI.Toast` (bundle loaded from the root `_ds_bundle.js`).

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

## Props

```ts
interface ToastProps {
  tone?: "neutral" | "success" | "warn" | "error";
  /** Optional leading icon. */
  icon?: "bag" | "coin" | "daily" | "eggs" | "gem" | "goals" | "index" | "pass" | "plot" | "settings" | "shops" | "skip";
  children?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
}
```
