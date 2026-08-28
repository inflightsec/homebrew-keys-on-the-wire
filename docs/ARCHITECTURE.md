# AVP for Mac — Architecture

`agent-vault-proxy` ships on macOS as a Homebrew formula at `inflightsec/homebrew-avp/agent-vault-proxy`. The formula installs the PyPI wheel into an isolated virtualenv inside the brew prefix using `Language::Python::Virtualenv` — every transitive Python dependency is SHA256-pinned via brew's `resource` blocks.

The user runs `sudo kow setup` once. That command:

- Creates the `_kow` system user via `dscl` (no shell, no home, hidden from login UI).
- Lays out `/usr/local/etc/kow/` (0750 root:_kow) and `/usr/local/var/{lib,log}/agent-vault-proxy/` (0750 _kow:_kow).
- Creates the audit log with the append-only flag set (`chflags sappnd`).
- Prompts for the Bitwarden Secrets Manager machine-account token (or, with `--static`, writes a static-secrets file instead).
- Writes a starter `bindings.yaml` with `organization_id: "REPLACE-WITH-YOUR-BWS-ORG-UUID"` — the user edits this.
- Generates the mitmproxy CA at `/usr/local/etc/kow/ca.pem`. The CA is never added to the macOS Trust Store — apps that need to trust it read it via `NODE_EXTRA_CA_CERTS` / `SSL_CERT_FILE`.
- Installs and loads the LaunchDaemon at `/Library/LaunchDaemons/io.inflightsec.kow.plist`, running the daemon as `_kow`.

Bindings live in BWS — each secret's `notes` field carries a structured YAML blob describing its binding policy. A file-based binding path is retained as an escape hatch for Ansible-driven fleets, air-gapped environments, and GitOps workflows. The `--static` flag on `kow setup` provisions with that file backend instead of BWS.

For filesystem and user isolation of the agent (recommended on dedicated Mac Minis), AVP composes with [webcoyote/sandvault](https://github.com/webcoyote/sandvault). The two tools are installed independently and paired by adding the AVP env block to SandVault's per-user shell config dir (`/Users/Shared/sv-${USER}/user/.zshenv`).

## ADRs

| ADR | Decision |
|---|---|
| ADR-0011 | Homebrew formula + virtualenv, not cask + signed/notarized .pkg. Supply-chain integrity > one-fewer-click UX. |
| ADR-0012 | Headless-compatible sudo posture. Privileged ops re-prompt every invocation. |
| ADR-0013 | AVP scope is AVP only. Compose with `webcoyote/sandvault` for user/filesystem isolation. |
| ADR-0014 | No separate bindings update channel. BWS is the channel; file path is the escape hatch. |
| ADR-0015 | Separate tap repo at `inflightsec/homebrew-avp`. Homebrew-core is a later ambition. |
| ADR-0016 | Borrow `dscl`-based user-creation patterns from `webcoyote/sandvault`. Apache 2.0 attribution. |
| ADR-0017 | Comprehensive lockdown surface — `NODE_USE_ENV_PROXY`, MCP env injection, LaunchAgent, `pf` enforcement layer, type-to-confirm gates. Future work; today the install steps cover the env-var coverage manually. |

## Process model

| UID | Identity | Owns | Sudo? |
|---|---|---|---|
| the user (e.g., `alex`) | GUI / SSH session | `/Users/alex/` | yes (default macOS) |
| `_kow` | the AVP daemon | `/usr/local/etc/kow/` (0750), `/usr/local/var/lib/kow/` (0750), `/usr/local/var/log/kow/` (0750), BWS token (0440 root:_kow), CA private key (0600 _kow:_kow) | NO — shell `/usr/bin/false`, no home, hidden |
| `sandvault-$USER` (if composed) | the agent inside the sandbox | `/Users/sandvault-$USER/`, isolated by sandbox-exec | NO |

The user's GUI account cannot read `_kow`'s files (mode 0750 / 0440 / 0600). Real credentials enter the agent's address space only via TLS-MITM substitution on the outbound socket inside the AVP daemon process.

## Network and trust model

```
agent (claude-code, etc.) — env holds placeholders only
       │  HTTPS_PROXY=http://127.0.0.1:14322
       │  NODE_EXTRA_CA_CERTS=/usr/local/etc/kow/ca.pem
       │  SSL_CERT_FILE=/usr/local/etc/kow/ca.pem
       │  NODE_USE_ENV_PROXY=1
       ▼
[ 127.0.0.1:14322 — AVP daemon as _kow ]
       │ reads BWS token (0440 root:_kow), fetches secret + binding metadata
       │ outbound TLS with real secret injected via binding.inject_format
       ▼
   api.openai.com / api.anthropic.com / api.github.com / …
```

**Narrow-trust CA.** A CA that can mint a cert for any host should not be trusted system-wide. The AVP CA lives only at `/usr/local/etc/kow/ca.pem` and is trusted by individual clients via per-app env vars. `kow doctor` checks the CA is not in any scanned flat-file trust-store path; the macOS keychain inspection is not yet implemented — operator discipline is to never `security add-trusted-cert` the AVP CA.

## Sudo posture

`kow setup` requires sudo once. The daemon then runs as `_kow` via launchd. The user's agent has no way to run privileged AVP operations because there are no other privileged `avp` subcommands — updates flow through `brew upgrade keys-on-the-wire` (its own sudo prompt) and `sudo launchctl kickstart -k system/io.inflightsec.kow`. Bindings are edited in Bitwarden's UI (no AVP CLI involvement), or by `sudo $EDITOR` of the file-backend escape hatch.

ADR-0012's full posture (sudoers drop-in with `timestamp_timeout=0`, type-to-confirm phrases for state-changing ops, `sudo -k` wrapper) lands when state-changing `avp` subcommands exist to gate.

## What does NOT ship in the brew formula

- A `_claude` system user managed by AVP — that's SandVault's job, separate brew package.
- sandbox-exec profiles — SandVault's job.
- Homebrew-core submission — formulas creating system users and installing LaunchDaemons don't pass Core's policy. Custom tap is the right home.
- A signed/notarized `.pkg` — see ADR-0011. Forks the supply chain.
- Auto-update — both `brew upgrade` and the launchctl restart require an interactive sudo password.
- Migration of pre-existing plaintext credentials in the user's home — SandVault's domain.

## macOS launchd is not a sandbox

launchd is service supervision, not kernel confinement. There is no equivalent to systemd's `ProtectSystem`, `RestrictAddressFamilies`, or syscall filter. The `_kow` UID gives isolated-user privilege separation; if your host is a credible target, run `agent-vault-proxy` inside Docker or a Linux VM instead.
