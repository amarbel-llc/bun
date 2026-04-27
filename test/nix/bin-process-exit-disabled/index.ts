// Fixture for the per-line escape hatch: same process.exit pattern as
// bin-process-exit-fail, but with the documented eslint-disable comment.
// The bundle phase MUST succeed.
//
// See amarbel-llc/bun#7.
process.stdout.write("about to exit\n");
// eslint-disable-next-line n/no-process-exit
process.exit(0);
