# Liquidity Signal — PWA

## What's in here
- index.html — the app (API key screen + chart analyzer)
- manifest.json — makes it installable
- service-worker.js — lets it open instantly / mostly offline
- icons/ — app icons

## Deploy it (pick one, both are free, ~2 minutes)

### Option A: Netlify Drop (easiest)
1. Go to https://app.netlify.com/drop
2. Drag this whole folder onto the page
3. You'll get a live https:// URL instantly

### Option B: GitHub Pages
1. Create a new GitHub repo, upload these files
2. Repo Settings → Pages → set source to your main branch
3. Your URL will be https://<yourname>.github.io/<repo>

## Install it on your Android phone
1. Open the https:// URL from above in Chrome on your phone
2. Tap the ⋮ menu → "Add to Home screen" / "Install app"
3. It now has its own icon and opens full-screen like a native app

## First launch
Paste your Anthropic API key (from console.anthropic.com/settings/keys) once.
It's saved only in the browser storage on your phone.
