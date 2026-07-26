# Homebrew formula for agent-vault-proxy. Installs the daemon from PyPI
# into an isolated virtualenv under the brew prefix. Privileged setup
# (`_avp` user, install layout, CA, LaunchDaemon) is handled by the
# `avp setup` command that ships INSIDE the package, not by this formula.

class AgentVaultProxy < Formula
  include Language::Python::Virtualenv

  desc "Credential broker for AI agents — real keys never enter process env"
  homepage "https://github.com/inflightsec/agent-vault-proxy"

  # url + sha256 point at the published PyPI sdist and are maintained by the
  # auto-bump bot (see .github/workflows/bump.yml) after each PyPI release.
  # The sdist ships the daemon's hash-pinned `requirements.lock`, so `def
  # install` pins every dependency from it — no `resource` stanzas needed.
  url "https://files.pythonhosted.org/packages/08/1a/f520a4fb017c213e2990b025931bc2a4482ea1e3dc8e4cd6ea0655ad3e26/agent_vault_proxy-0.9.0.tar.gz"
  sha256 "374773fede47a4bbb9c458456dd4d8f71cec5bcb0fc6507605de12d88c0cabc5"
  license "MIT"

  head "https://github.com/inflightsec/agent-vault-proxy.git", branch: "main"

  depends_on "python@3.13"

  # No `resource` stanzas: dependencies are pinned from the daemon's in-tree
  # `requirements.lock` (uv-generated, --generate-hashes, universal), which
  # ships in both the PyPI sdist and the git HEAD tree. This keeps the brew
  # install byte-identical to the daemon's own supply-chain-audited lockfile.

  def install
    virtualenv_create(libexec, "python3.13")

    # Homebrew 6.0.1 on macOS 26 (Tahoe) does not reliably bootstrap pip into
    # the venv after virtualenv_create — the bundled-pip step exits silently
    # and leaves libexec/bin/pip missing. Force it explicitly via ensurepip.
    # ensurepip on Python 3.13 creates pip3 and pip3.13 but NOT bare `pip`,
    # so invoke pip as a module (`python -m pip`) which works regardless.
    system libexec/"bin/python", "-m", "ensurepip", "--upgrade"

    # Both the PyPI sdist (stable) and the git HEAD tree ship the daemon's
    # hash-pinned universal lockfile at the buildpath root. Install every
    # dependency from it (--require-hashes for supply-chain integrity), then
    # the package itself with --no-deps to skip PyPI re-resolution.
    system libexec/"bin/python", "-m", "pip", "install",
           "--require-hashes", "--only-binary=:all:",
           "-r", buildpath/"requirements.lock"
    system libexec/"bin/python", "-m", "pip", "install", "--no-deps", buildpath

    bin.install_symlink libexec/"bin/avp"
  end

  def caveats
    <<~EOS
      One-time setup (creates _avp user, install layout, CA, LaunchDaemon):

        sudo avp setup
        # add `--static` for a local file backend instead of Bitwarden

      Add to ~/.zshenv so all shells (including non-interactive) inherit:

        export HTTPS_PROXY="http://127.0.0.1:14322"
        export NODE_EXTRA_CA_CERTS="/usr/local/etc/agent-vault-proxy/ca.pem"
        export SSL_CERT_FILE="/usr/local/etc/agent-vault-proxy/ca.pem"
        export NODE_USE_ENV_PROXY=1  # Node 22.21+/24.5+ ignores HTTPS_PROXY without this

      Then:  avp env  (writes ~/.config/avp/env with placeholder exports — source it)
             avp doctor  (verify install)

      Add API keys later — your real key never enters the agent. Run the
      generator and paste what it prints into your vault:

        avp binding new --host api.stripe.com --name STRIPE_API_KEY

      In Claude Code, skip the flags and just say "route my Stripe key through
      avp". Install the skill ONCE by typing these as slash-commands in the
      Claude Code chat (NOT terminal commands):

        /plugin marketplace add inflightsec/agent-vault-proxy
        /plugin install avp@agent-vault-proxy

      Codex or another agent? No plugin store — just run the command above.
    EOS
  end

  test do
    assert_match "avp", shell_output("#{bin}/avp --help")
    system bin/"avp", "doctor", "--help"
    system bin/"avp", "setup", "--help"
    system bin/"avp", "secret", "--help"
    system bin/"avp", "run", "--help"
  end
end
