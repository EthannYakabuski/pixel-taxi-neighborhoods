# Pixel Taxi Neighborhoods: Web hosting and embedding

Deployment target: [https://ethannyakabuski.github.io/pixel-taxi-neighborhoods/](https://ethannyakabuski.github.io/pixel-taxi-neighborhoods/). The website itself is not changed by this repository.

## Deployment contract

Pushes to `main` and manually dispatched main-branch runs execute the existing strict import, service/game tests, Web export and Android debug AAB checks. Only after that build job succeeds can `deploy` publish its `build/web` artifact using GitHub Pages Actions. Branch/environment protection stays in effect. A failing gate prevents a new deployment and does not prove the current public site is broken.

`build-info.json` contains only `source_commit` and `repository`. Compare its SHA with the exact successful Actions/deployment before attributing a page to a commit. The Pages upload contains only Web output and accompanying license notices, never source backups, genuine saves, SDK caches, private logs or signing material. Preserve `LICENSES/` with redistribution.

Workflow/configuration presence is not a completed deployment or browser test. Actual HTTP, browser and iframe verification must be recorded against the deployed SHA. Local historical exports and Android QA retain their original provenance.

## Embedding example for a later website update

```html
<iframe
  src="https://ethannyakabuski.github.io/pixel-taxi-neighborhoods/"
  title="Pixel Taxi Neighborhoods"
  width="540" height="960"
  style="max-width:100%;border:0"
  allow="autoplay; fullscreen"
  allowfullscreen>
</iframe>
```

This is an example only; no website files or policies are changed. Click/tap the game to focus keyboard input and unlock browser audio. Autoplay/fullscreen remain subject to browser policy. Keep a usable portrait frame; a tiny frame is not a verified touch layout. Parent-site CSP must permit the frame origin. Any additional iframe sandbox requires separate scripts/storage testing.

The Web preset is single-threaded with native extensions disabled. It does not require SharedArrayBuffer isolation headers. Browser WebGL support, memory and third-party iframe storage policies still apply. Saves are browser-local and may be partitioned or blocked in cross-site iframes; no cloud synchronization is implemented by this hosting update. Opening the game URL directly is a useful comparison when embedding behavior differs.

## Controls and platform limits

The drive pad combines steering and throttle for one-pointer operation; separate controls and keyboard combinations are also available. Human handling, a genuine completed fare and once-only payout remain separate acceptance checks.

Web services retain the existing non-Android fallback: no native AdMob/Play Games, no simulated earned-ad rewards, and no production-backend acceptance is asserted. Hosting is not a human balance, control-usability, native/device, audible-output or long-session certification. No gameplay rules or real saves are changed by the workflow.
