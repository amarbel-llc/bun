// Fixture for the build-time eslint pass: calls process.exit() after a
// write. Without disableLint, the bundle phase MUST fail with an
// n/no-process-exit diagnostic. Used as the inner derivation for the
// pkgs.testers.testBuildFailure assertion in flake.nix.
//
// See amarbel-llc/bun#7.
process.stdout.write("about to exit\n");
process.exit(0);
