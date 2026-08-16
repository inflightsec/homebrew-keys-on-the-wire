# keys-on-the-wire for Mac

**Keep your AI agent's API keys out of its environment.** Two commands, runs as its own user, real keys stay in Bitwarden.

Your AI agent's environment holds **placeholder** strings like `sk-PLACEHOLDER-...` instead of real API keys. When the agent calls OpenAI / GitHub / Anthropic / etc., the request goes through a local proxy running as a dedicated `_kow` system user. The proxy fetches the real key from [Bitwarden Secrets Manager](https://bitwarden.com/products/secrets-manager/) and substitutes it on the wire. The agent never sees the real bytes.

If the agent gets prompt-injected, or one of its npm/pip packages turns out to be malicious, the only thing that escapes is a placeholder worth nothing.

## Try it. 10 seconds.

```bash
$ brew install inflightsec/keys-on-the-wire/keys-on-the-wire
$ sudo kow setup --static
$ sudo kow secret add STRIPE_API_KEY
Value:                                       # nothing echoes while you type
✓ added secret 'STRIPE_API_KEY'
$ kow run claude                             # claude routed via kow; real key never enters its env
                                             # add `--sandvault` for an extra macOS sandbox layer
```

No Bitwarden account? `--static` keeps secrets in a local YAML file owned by `_kow` at 0600. Upgrade to Bitwarden later by re-running `sudo kow setup` without `--static`.

## Hardened install

The block above is the demo. For the full setup (`kow run` as the recommended launcher, `~/.zshenv` patching as the fallback, MCP-server `env` blocks, `bindings.yaml`, `kow env` / `kow doctor`, update + remove) see [docs/INSTALL.md](docs/INSTALL.md).

For maximum isolation, compose with [SandVault](https://github.com/webcoyote/sandvault): keys-on-the-wire brokers credentials, SandVault sandboxes the filesystem. Recipe in [docs/INSTALL.md](docs/INSTALL.md#compose-with-sandvault-for-full-isolation).

## Docs

- **[INSTALL](docs/INSTALL.md)** — full install / update / remove walkthrough
- **[ARCHITECTURE](docs/ARCHITECTURE.md)** — process model, network and trust, sudo posture, ADRs
- **[SECURITY-AUDIT](docs/SECURITY-AUDIT.md)** — threat model and per-finding mitigations
- **[WORM-DEFENSE](docs/WORM-DEFENSE.md)** — defenses against Shai-Hulud-class supply-chain worms
- **[CONTEXT](docs/CONTEXT.md)** — domain glossary
- **[CONTRIBUTING](CONTRIBUTING.md)** · **[SECURITY](SECURITY.md)** · **[CREDITS](CREDITS.md)**

## License

MIT. Adapted user-creation patterns from [`webcoyote/sandvault`](https://github.com/webcoyote/sandvault) under Apache 2.0 — see `NOTICE` and `CREDITS.md`.
