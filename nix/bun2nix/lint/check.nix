# Drift guard: assert that the committed bun.nix matches what bun2nix
# would generate from the committed bun.lock. Fails the check if they
# disagree, with a one-line fix instruction.
#
# This is the pure half of the bootstrap. It runs in the sandbox, no
# network, and only needs bun.lock + bun2nix to do its job. It does NOT
# detect package.json → bun.lock drift; that's caught by `nix run .#regen-lint-stack`.
#
# See:
#   - amarbel-llc/bun#7
#   - regen.nix (the impure regenerator)
{
  pkgs,
  bun2nix,
  lintDir,
}:

pkgs.runCommand "lint-stack-up-to-date"
  {
    nativeBuildInputs = [ bun2nix ];
    src = lintDir;
  }
  ''
    cp -r $src/* .
    chmod -R u+w .

    if [ ! -f bun.lock ]; then
      cat >&2 <<EOF
    lint-stack-up-to-date: bun.lock is missing from nix/bun2nix/lint/.

    Bootstrap the lint stack with:

      nix run .#regen-lint-stack

    Then commit bun.lock and bun.nix.
    EOF
      exit 1
    fi

    if [ ! -f bun.nix ]; then
      cat >&2 <<EOF
    lint-stack-up-to-date: bun.nix is missing from nix/bun2nix/lint/.

    Run:

      nix run .#regen-lint-stack

    to regenerate it from bun.lock, then commit it.
    EOF
      exit 1
    fi

    bun2nix --lock-file=./bun.lock --output-file=./bun.nix.regenerated

    if ! diff -u bun.nix bun.nix.regenerated; then
      cat >&2 <<EOF

    lint-stack-up-to-date: nix/bun2nix/lint/bun.nix is out of date relative to bun.lock.

    Fix: run \`nix run .#regen-lint-stack\` and commit the updated bun.nix.
    EOF
      exit 1
    fi

    touch $out
  ''
