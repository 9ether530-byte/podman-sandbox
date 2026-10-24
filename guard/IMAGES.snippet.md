# Heartbeat snippet (optional, add to HEARTBEAT.md only if you want it)

- Podman business images: run `./podman-sandbox/check.sh` (or
  `podman-sandbox check`) and look for the `image:` lines. If
  `factory-sandbox` or `critique-sandbox` is MISSING, report it —
  do NOT rebuild automatically (factory rebuild is ~1 minute,
  critique rebuild is ~9 minutes, and a rebuild is a deliberate
  step, not a silent tick). Stay silent when both images are
  present. This check is separate from the Podman boot-guard,
  which only restores Podman itself, not the images.
