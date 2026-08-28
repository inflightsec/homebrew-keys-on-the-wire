# Glossary — AVP for Mac

> Domain vocabulary for the macOS distribution of `agent-vault-proxy`. Glossary, not spec.

## Terms

### Agent Vault Proxy (AVP)
The loopback HTTPS proxy that brokers credentials between a calling process and external APIs. Published on PyPI as `agent-vault-proxy` under the `inflightsec` GitHub org. Authoritative architecture doc: the upstream daemon repo's `docs/architecture.md`. Hard invariants: G1–G9.

### `_kow` (system user)
The unprivileged Unix user the daemon runs as on macOS (Linux uses `avp`). Auto-assigned UID via Directory Services. Shell `/usr/bin/false`, home `/var/empty`, hidden from the login UI, never in sudoers.

### Bindings
The policy that maps each placeholder to its substitution rule: which BWS secret, which destination host(s), optional method/path scope. Two storage backends:

- **BWS-notes (default):** binding policy stored as YAML in the BWS secret's `notes` field, fetched inline with the secret.
- **File-based (escape hatch):** `/usr/local/etc/kow/bindings.yaml`, owned `_kow:_kow` mode 0640. Used for Ansible deploys, air-gapped envs, GitOps. Selected by `kow setup --static` or by configuring the daemon's `binding_source`.

When both define a binding for the same placeholder, BWS-notes wins. If no binding matches, the daemon forwards the placeholder verbatim — the upstream's own auth-fail surfaces.

### BWS-notes binding format
YAML embedded in a BWS secret's notes field:

```yaml
binding:
  inject_header: Authorization
  inject_format: "Bearer {secret}"
  scope:
    - host: api.example.com
      methods: [GET, POST]    # optional
      paths: ["/v1/*"]        # optional
```

### Placeholder
The fake credential string in the agent's env. Public-knowledge constant derived from a salted hash; examples: `sk-PLACEHOLDER-...`, `ghp_PLACEHOLDER-...`. AVP swaps it for the real value at the wire.

### Real secret
The actual credential bytes in Bitwarden Secrets Manager. Fetched just-in-time, never enters the agent's address space.

### BWS / Bitwarden Secrets Manager
The secret backend. The daemon reads its own access token (NOT user secrets) from `0440 root:_kow` at `/usr/local/etc/kow/bws-token`, then uses that token to fetch per-host secrets at request time.

### `kow setup`
Privileged one-time install command. Creates `_kow`, lays out `/usr/local/etc/kow/` + `/usr/local/var/{lib,log}/agent-vault-proxy/`, prompts for the BWS token (or with `--static`, writes a static-secrets file), writes starter `bindings.yaml`, generates the install salt and the mitmproxy CA, installs and loads the LaunchDaemon plist.

### `kow env`
Projects the BWS project's secrets to a placeholder env file at `~/.config/kow/env`. Source it from the shell; agents see only placeholders.

### `kow doctor`
Read-only CA health check. Two checks: CA cert is not present in any scanned flat-file trust-store path (regression guard for the narrow-trust model), and CA private key is `0600 _kow:_kow` in a 0700 confdir. macOS keychain inspection is not yet implemented — discipline is to never `security add-trusted-cert` the AVP CA.

### Narrow-trust CA
The AVP CA is never added to the macOS Trust Store. It lives only at `/usr/local/etc/kow/ca.pem` and is read by individual HTTPS clients via per-app env vars (`NODE_EXTRA_CA_CERTS`, `SSL_CERT_FILE`). Rationale: a CA that can mint a cert for any host should not be trusted system-wide.

### Brew formula (vs cask)
**Formula:** Ruby DSL that runs `pip install` of dependencies into an isolated venv inside the brew prefix. AVP uses this. **Cask:** would install a frozen `.pkg` — forks the supply chain by bundling a frozen Python interpreter, bypassing PyPI's `--require-hashes` discipline. Rejected; see ADR-0011.

### LaunchDaemon
Per-machine service launched at boot by launchd, runs as a system user. AVP's daemon plist (`io.inflightsec.kow`) lives at `/Library/LaunchDaemons/`, runs as `_kow`.

### macOS launchd is not a sandbox
launchd is service supervision, not kernel confinement. There is no equivalent to systemd's `ProtectSystem`, `RestrictAddressFamilies`, or syscall filter. `_kow` UID gives privilege separation; for a credible target, run AVP inside Docker or a Linux VM.

### Fail-closed with diagnosis
A binding rejection must surface a precise, actionable reason. `kow doctor --secret <name>` (planned) will show the current notes content, what's missing, and the fix. Today the daemon logs the rejection to the audit log; reading it requires `sudo less /usr/local/var/log/kow/audit.jsonl`.

### SandVault
[`webcoyote/sandvault`](https://github.com/webcoyote/sandvault) — Apache-2.0 Mac-only Homebrew package that creates a `sandvault-$USER` Unix account and wraps the agent in `sandbox-exec`. The documented composition partner for AVP on dedicated Mac Mini installs. AVP brokers credentials; SandVault isolates filesystem reach. AVP does not bundle, reimplement, or take ownership of user/filesystem isolation.

### Composition model
AVP and SandVault are independent brew formulas that compose. Add the AVP env block to SandVault's per-user shell config dir (`/Users/Shared/sv-${USER}/user/.zshenv`) after running `kow setup`. Three valid postures: AVP-only (env-var protection, no fs isolation), SandVault-only (fs isolation, no credential brokerage), both (full model).

### NODE_USE_ENV_PROXY
Env var that switches Node 22.21+/24.5+ `fetch()` to respect `HTTPS_PROXY`. Without it, Node native fetch ignores `HTTPS_PROXY` entirely. Claude-code uses native fetch, so this env var being missing means AVP is structurally bypassed at the API hop. **Must be in `~/.zshenv` next to the other proxy env vars** — this is a real install step, not optional polish.

### MCP env injection
Stdio MCP servers do not inherit `HTTPS_PROXY` from the parent claude-code process reliably — Anthropic's MCP spec says env inheritance is platform-dependent and limited. Each MCP server's `env` block in `~/.claude.json` and project `.mcp.json` needs the four proxy env vars added manually. ADR-0017 captures an `kow setup` walk that would do this automatically; today it's manual.

### Minimum invariant
"As long as the agent cannot sudo and AVP runs on a separate user, credential isolation holds." Both halves are satisfied by default — the user's GUI account doesn't grant the agent sudo; `_kow` is a separate UID. Filesystem reach is out of scope; addressed by SandVault if composed.
