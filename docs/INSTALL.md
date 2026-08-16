# AVP for Mac — Install / Setup / Remove

The README's "Try it. 10 seconds." block is the demo. This page is the full hardened install — env-var setup, MCP-server config, adding a secret, updating, removing.

## Install

```bash
brew install inflightsec/avp/agent-vault-proxy
sudo kow setup
```

`sudo kow setup` creates the `_kow` system user, lays out `/usr/local/etc/kow/` and `/usr/local/var/{lib,log}/agent-vault-proxy/`, prompts for your Bitwarden machine-account token, generates the mitmproxy CA, and installs the LaunchDaemon at `/Library/LaunchDaemons/io.inflightsec.kow.plist`.

Add `--static` to skip the BWS prompt and use a local file backend (development / testing).

## Point your agent at the proxy

The simplest path — **recommended** — is to launch every agent via `kow run`. It sets the four AVP env vars on the spawned process tree only, and auto-loads `~/.config/kow/env` (the placeholder file written by `kow env`). Your host shell stays free of both proxy vars and placeholder strings; only `kow run`-wrapped processes route through AVP.

```bash
sudo $EDITOR /usr/local/etc/kow/bindings.yaml   # set organization_id, api_url
kow env                                                       # write placeholders to ~/.config/kow/env
kow doctor                                                    # verify
kow run claude                                                # launch claude via AVP
```

### Alternative: shell-rc patching (only if you can't wrap every launch)

If you have processes that aren't launched via `kow run` (cron jobs, IDE-integrated tools that ignore wrappers, etc.), put the four vars in `~/.zshenv` (NOT `~/.zshrc` — non-interactive shells must inherit too):

```bash
export HTTPS_PROXY="http://127.0.0.1:14322"
export NODE_EXTRA_CA_CERTS="/usr/local/etc/kow/ca.pem"
export SSL_CERT_FILE="/usr/local/etc/kow/ca.pem"
export NODE_USE_ENV_PROXY=1                # Node 22.21+/24.5+ ignores HTTPS_PROXY otherwise
```

Plus `source ~/.config/kow/env` if you want placeholders in your shell too. For MCP servers (`~/.claude.json`, project `.mcp.json`), add the same four env vars to each server's `env` block — stdio MCP servers don't inherit shell env reliably.

## Adding a secret

1. Create a secret in Bitwarden Secrets Manager. Name it like your agent already knows it (`OPENAI_API_KEY`, `GITHUB_PAT`, etc.).
2. In the Notes field, set the destination — minimum is `host: api.openai.com`. Override the default Bearer auth with `header:` / `format:` / `methods:` / `paths:` if needed (see the daemon's [`bindings.example.yaml`](https://github.com/inflightsec/agent-vault-proxy/blob/main/bindings.example.yaml)).
3. Delete the real key from your `.zshrc` / `.env`.
4. Re-run `kow env` to refresh `~/.config/kow/env`. If you launch via `kow run`, you're done — no re-source needed. If you've patched `~/.zshenv` instead, re-source it.

## Update

```bash
brew upgrade keys-on-the-wire
sudo launchctl kickstart -k system/io.inflightsec.kow
```

Both prompt for your sudo password — on purpose. The password is the gate that stops the agent from updating the proxy on its own.

## Remove

```bash
sudo launchctl bootout system /Library/LaunchDaemons/io.inflightsec.kow.plist 2>/dev/null || \
  sudo launchctl unload /Library/LaunchDaemons/io.inflightsec.kow.plist
sudo rm /Library/LaunchDaemons/io.inflightsec.kow.plist
sudo chflags nosappnd /usr/local/var/log/kow/audit.jsonl 2>/dev/null
sudo rm -rf /usr/local/etc/kow \
            /usr/local/var/lib/kow \
            /usr/local/var/log/kow
sudo dscl . -delete /Users/_kow
sudo dscl . -delete /Groups/_kow
brew uninstall agent-vault-proxy
brew untap inflightsec/avp
```

Bitwarden secrets are left alone.

## CA trust model

The mitmproxy CA AVP generates is **never** added to the macOS Trust Store. It lives at `/usr/local/etc/kow/ca.pem` and is trusted per-app via `NODE_EXTRA_CA_CERTS` / `SSL_CERT_FILE`. A CA that can mint a cert for any host should not be trusted system-wide.

`kow doctor` checks that the CA is NOT in any flat-file trust-store directory and that the CA private key is `_kow`-owned mode 0600. (It does not yet inspect the macOS keychain — discipline: don't `security add-trusted-cert` the AVP CA.)

## Compose with SandVault for full isolation

```bash
brew install sandvault
brew install inflightsec/avp/agent-vault-proxy
sudo kow setup
# Pick one path:
#  (a) Wrap every launch: `sandvault` then `kow run claude` — no env-var setup at all.
#  (b) Patch the sandbox shell once: add the four AVP env vars to
#      /Users/Shared/sv-$USER/user/.zshenv. After that, just `sandvault`
#      and every later session inherits them — no per-session ritual.
sandvault
```

SandVault stops the agent from reading your other files; AVP keeps real API keys out of the agent's environment. Use both. Full worm-defense composition: [WORM-DEFENSE.md](WORM-DEFENSE.md).
