// Fixture for the recommended pattern: set process.exitCode and return
// instead of calling process.exit, so stdout has a chance to drain. The
// bundle phase MUST succeed.
//
// See amarbel-llc/bun#7.
process.stdout.write("done\n");
process.exitCode = 0;
