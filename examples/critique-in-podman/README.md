# Example: Micro-SaaS Critique Exchange inside Podman

The second real business app in Podman, same pattern as the factory:
build reproducibly, run isolated, no keys, no live data touched.

## What this is not

This example does **not** copy the critique code into this repo.
`build-image.sh` copies only `app/` and `requirements.txt` from a
critique checkout into an isolated `.build/` directory, and
`run-api.sh` mounts an isolated `.workload/data/` directory at
`/code/data` in the container. The live critique checkout's `data/`
is never touched.

## Run it

```bash
./build-image.sh ~/workspace/critique-exchange
# builds critique-sandbox:latest (about 7 minutes on the 2-core VM
# this was built on — chromadb, opencv and stellar-sdk are large)
./run-api.sh
curl http://localhost:8002/health
podman-sandbox stop critique-api; podman-sandbox rm critique-api
```

## Verified live on 2026-10-24

- Image `critique-sandbox:latest`, 994 MB (chromadb, opencv,
  onnxruntime, stellar-sdk and stripe dominate that size).
- API on port 8002: `/health` returned
  `{"ok":true,"escrow_mode":"mock","stripe_configured":false}` —
  no keys were passed in, so escrow is in local mock mode and
  Stripe is not configured, exactly as on the host without keys.
- `/templates/accessibility` worked (0 suggestions, CSS snippet
  written to the container data dir).
- `/payout/withdraw` with a nonexistent bounty returned
  404 bounty not found, before any Stripe check — expected, since
  no bounty exists without a capture first.
- `/capture` was not exercised: it needs a real MP4/WebM upload
  plus Screex/ffmpeg, which is a separate test, not an API smoke test.

## A real bug found, then fixed

`/trends` originally returned Internal Server Error in the
container, with `AttributeError: 'collections.defaultdict'
object has no attribute 'most_common'` in
`app/packaging/trends.py` line 59: `low_score_hits` was a
`defaultdict(int)`, and `.most_common` is a `Counter` method.
That code path fails on the host too — it was a bug in the
critique source, not something Podman introduced.

Fixed 2026-10-24 in the critique checkout itself (one line:
`low_score_hits` is now a `Counter`), tested standalone with
empty and populated critiques, then re-verified in Podman from
a rebuilt image: `/trends` now returns the empty trend object
instead of a 500, and `/health` still reports mock escrow with
Stripe not configured.

## Disk note

After this image, the graphroot grew to 3.3 GB. That is the vfs
tax from step 1 plus a 994 MB image: each build step is a full
copy, and intermediate layers stay on disk even after `podman rmi`
on them. Both final images still ran fine after intermediate
cleanup. Do not run `podman system reset` to reclaim this without
expecting to rebuild both images.

## Safety

Do NOT pass Stripe or Stellar keys into this container copy.
Live money movement stays a separate, key-gated step with the
owner's keys, on the live app, not in this sandbox example.
