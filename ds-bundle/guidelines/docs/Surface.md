---
category: Surfaces
---

# Surface

The base card every other component is built on — a port of `UI.surface`. It
composes the four effects the whole kit is made of: a vertical gradient, a thick
near-black outer stroke, optionally a hard offset shadow, and optionally the
top gloss strip with its bottom shade.

## Kinds

| Kind | Gradient | Used for |
|---|---|---|
| `panel` | #D6D6D6 → #A9A9A9 | the window body |
| `subPanel` | #C4C4C4 → #9C9C9C | a section inside a window |
| `row` | #4A4A4A → #363636 | list rows |
| `slot` | #4A4A4A → #363636 | inventory slots (8px radius) |
| `tab` | #BEBEBE → #9C9C9C | unselected segments |
| `track` | #2E2E2E → #3A3A3A | recessed bar backgrounds |

Light text sits on `row`/`slot`/`track`; dark `--sb-text-on-window` sits on
`panel`/`subPanel`/`tab`.

```jsx
<Surface kind="subPanel" shadowed keyline style={{ width: 320, height: 120 }} />
```

Reach for `Panel` instead when you want the full window with its header.
