# docs/ — Birchboard site

Static site sources for the Birchboard landing page. Served by GitHub Pages
straight out of this folder on the `main` branch.

## Enabling GitHub Pages (one-time)

1. GitHub → repo → **Settings → Pages**.
2. *Build and deployment* → Source: **Deploy from a branch**.
3. Branch: **main**, folder: **/docs**. Save.

The site goes live at
`https://birchsport.github.io/clipboard-manager/` within a minute or two.
Pushing further commits to `main` that touch `docs/` redeploys automatically.

A custom domain (e.g. `birchboard.birchsport.net`) is configurable on the
same Pages settings page — Pages will generate a CNAME file inside `docs/`
when you set one.

## Structure

```
docs/
├── .nojekyll          # tell Pages to serve files verbatim (skip Jekyll)
├── index.html         # landing page
└── assets/
    └── style.css      # styles (dark-first, light-mode media query)
```

## Adding screenshots / videos

Drop image or video files into `assets/` and reference them from
`index.html`. There's a `.screenshot.placeholder` block near the top of the
page ready to be replaced — swap the inner div for:

```html
<img src="assets/panel.png" alt="Birchboard panel showing clipboard history" />
```

Keep screenshots as compressed PNG or JPEG under ~1 MB each to stay inside
GitHub Pages' soft bandwidth limits.
