---
category: Content
---

# CurrencyPill

The 54px currency chip in the HUD's top strip — dark row gradient, pill radius,
the currency icon overhanging the left end.

```jsx
<CurrencyPill currency="coin" value="12.4K" />
<CurrencyPill currency="gem" value="318" />
```

`value` is rendered as given — the HUD abbreviates large amounts ("1.28M") rather
than printing every digit, so format before passing it in.
