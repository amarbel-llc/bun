default: check

build:
  bun bd

test *args:
  bun bd test {{args}}

fmt:
  nix fmt

check:
  nix flake check

clean:
  nix-store --gc
