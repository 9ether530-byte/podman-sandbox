#!/usr/bin/env bash
# install.sh: install Podman (Ubuntu/Debian, apt) and restore the
# restricted-sandbox workaround config. Idempotent; also the boot-guard
# rebuild script: run it again after a VM replacement and it restores
# everything that lives outside the persistent home directory.
#
# It never prints environment variables: proxy URLs can embed credentials.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [ -n "${PODMAN_SANDBOX_DATA:-}" ]; then
  DATA_DIR="$PODMAN_SANDBOX_DATA"
elif [ -d "$HOME/workspace" ]; then
  DATA_DIR="$HOME/workspace/podman-data"
else
  DATA_DIR="$HOME/.local/share/podman-sandbox-data"
fi
mkdir -p "$DATA_DIR/graphroot" "$DATA_DIR/runroot"

# Sandbox-specific apt optimisation, only when that mirror list is present:
# the stock Ubuntu sources on this VM listed two mirrors and fetching both
# made `apt update` crawl for minutes; Azure alone finished in ~12s.
APT_SOURCES="/etc/apt/sources.list.d/ubuntu.sources"
if [ -f "$APT_SOURCES" ] && grep -q "mirror.cogentco.com" "$APT_SOURCES"; then
  cp "$APT_SOURCES" /tmp/ubuntu.sources.bak
  sed -i 's|URIs: http://azure.archive.ubuntu.com/ubuntu http://mirror.cogentco.com/pub/linux/ubuntu|URIs: http://azure.archive.ubuntu.com/ubuntu|' "$APT_SOURCES"
  echo "apt sources: trimmed to Azure mirror only"
fi

if command -v podman >/dev/null 2>&1; then
  echo "podman already installed: $(podman --version)"
else
  echo "podman missing, installing via apt..."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y podman
  echo "podman installed: $(podman --version)"
fi

# Podman also needs its network helpers, even for --network=none/host:
# without netavark, `podman info` fails with "could not find netavark".
# A VM replacement can restore podman without them (e.g. a
# --no-install-recommends replay), so install them explicitly if missing.
if [ ! -x /usr/lib/podman/netavark ] || [ ! -x /usr/lib/podman/aardvark-dns ]; then
  echo "network helpers missing, installing netavark + aardvark-dns via apt..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y netavark aardvark-dns
fi

# Rootful Podman reads /etc/containers/*.conf, not ~/.config/containers/*.
# Render the templates with the real data dir and install them (root only;
# the wrapper in ./podman-sandbox works without this step, via flags).
if [ "$(id -u)" = "0" ]; then
  sed -e "s|__DATA_DIR__|$DATA_DIR|g" configs/storage.conf > /tmp/podman-sandbox-storage.conf
  install -m 644 /tmp/podman-sandbox-storage.conf /etc/containers/storage.conf
  install -m 644 configs/containers.conf /etc/containers/containers.conf
  echo "restored /etc/containers/storage.conf (vfs) and containers.conf (cgroups disabled)"
  # Also make the wrapper available on PATH when possible.
  if [ -w /usr/local/bin ]; then
    install -m 755 podman-sandbox /usr/local/bin/podman-sandbox
    install -m 755 check.sh /usr/local/bin/podman-sandbox-check
    echo "installed podman-sandbox to /usr/local/bin"
  fi
else
  echo "not root: skipping /etc config install; use ./podman-sandbox, which passes the same flags explicitly"
fi

GRAPH_DRIVER="$(podman info --format '{{.Store.GraphDriverName}}' 2>/dev/null || true)"
echo "podman graph driver (system config): $GRAPH_DRIVER"
echo "wrapper data dir: $DATA_DIR"
echo "Use: ./podman-sandbox run --rm docker.io/library/hello-world"
echo "Known-good networks: --network=none, --network=host. Isolated bridge networking is blocked in this sandbox."
