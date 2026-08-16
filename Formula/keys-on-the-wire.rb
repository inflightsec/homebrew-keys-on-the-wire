# Homebrew formula for keys-on-the-wire (formerly agent-vault-proxy). Installs
# the daemon from PyPI into an isolated virtualenv under the brew prefix.
# Privileged setup (`_kow` user, install layout, CA, LaunchDaemon) is handled
# by the `kow setup` command that ships INSIDE the package, not by this formula.

class KeysOnTheWire < Formula
  include Language::Python::Virtualenv

  desc "Credential broker for AI agents; real keys never enter process env"
  homepage "https://github.com/inflightsec/keys-on-the-wire"

  # url + sha256 point at the published PyPI sdist and are maintained by the
  # auto-bump bot (see .github/workflows/bump.yml) after each PyPI release.
  # The sdist ships the daemon's hash-pinned `requirements.lock`, so `def
  # install` pins every dependency from it; no `resource` stanzas are needed.
  url "https://files.pythonhosted.org/packages/ee/91/c80b82e76d766882a3780894fc7b2cf27fb7ca4f7741ac85cc73e0f8cce2/keys_on_the_wire-1.0.0.tar.gz"
  sha256 "76cf362a50a45cf4fedd4100b0e04429751b8ed388171ae89c45b5bbdd4efe07"
  license "Apache-2.0"

  # Renamed from agent-vault-proxy in 1.0.0. Existing installs migrate via
  # tap_migrations.json at the tap root (Homebrew derives the old name there);
  # no formula-level oldname/oldnames, which this tap's brew doesn't provide.

  head "https://github.com/inflightsec/keys-on-the-wire.git", branch: "main"

  depends_on "python@3.13"

  # No `resource` stanzas: dependencies are pinned from the daemon's in-tree
  # `requirements.lock` (uv-generated, --generate-hashes, universal), which
  # ships in both the PyPI sdist and the git HEAD tree. This keeps the brew
  # install byte-identical to the daemon's own supply-chain-audited lockfile.

  def install
    virtualenv_create(libexec, "python3.13")

    # Homebrew 6.0.1 on macOS 26 (Tahoe) does not reliably bootstrap pip into
    # the venv after virtualenv_create: the bundled-pip step exits silently
    # and leaves libexec/bin/pip missing. Force it explicitly via ensurepip.
    system libexec/"bin/python", "-m", "ensurepip", "--upgrade"

    # Both the PyPI sdist (stable) and the git HEAD tree ship the daemon's
    # hash-pinned universal lockfile at the buildpath root. Install every
    # dependency from it (--require-hashes for supply-chain integrity), then
    # the package itself with --no-deps to skip PyPI re-resolution.
    system libexec/"bin/python", "-m", "pip", "install",
           "--require-hashes", "--only-binary=:all:",
           "-r", buildpath/"requirements.lock"
    system libexec/"bin/python", "-m", "pip", "install", "--no-deps", buildpath

    # `kow` is the canonical CLI; `avp` stays as a deprecated alias (dropped in 2.0.0).
    bin.install_symlink libexec/"bin/kow"
    bin.install_symlink libexec/"bin/avp"
  end

  def caveats
    <<~EOS
      One-time setup (creates _kow user, install layout, CA, LaunchDaemon):

        sudo kow setup
        # add `--static` for a local file backend instead of Bitwarden

      Add to ~/.zshenv so all shells (including non-interactive) inherit:

        export HTTPS_PROXY="http://127.0.0.1:14322"
        export NODE_EXTRA_CA_CERTS="/usr/local/etc/kow/ca.pem"
        export SSL_CERT_FILE="/usr/local/etc/kow/ca.pem"
        export NODE_USE_ENV_PROXY=1  # Node 22.21+/24.5+ ignores HTTPS_PROXY without this

      Then:  kow env  (writes ~/.config/kow/env with placeholder exports; source it)
             kow doctor  (verify install)

      Add API keys later; your real key never enters the agent. Run the
      generator and paste what it prints into your vault:

        kow binding new --host api.stripe.com --name STRIPE_API_KEY

      In Claude Code, skip the flags and just say "route my Stripe key through
      kow". Install the skill ONCE by typing these as slash-commands in the
      Claude Code chat (NOT terminal commands):

        /plugin marketplace add inflightsec/keys-on-the-wire
        /plugin install kow@keys-on-the-wire

      Codex or another agent? No plugin store, just run the command above.
    EOS
  end

  test do
    assert_match "kow", shell_output("#{bin}/kow --help")
    system bin/"kow", "doctor", "--help"
    system bin/"kow", "setup", "--help"
    system bin/"kow", "secret", "--help"
    system bin/"kow", "run", "--help"
    # deprecated alias still resolves
    system bin/"avp", "--help"
  end
end
