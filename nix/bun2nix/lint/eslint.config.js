// Flat eslint config used by the nix-build-time lint pass for
// buildBunBinary / buildBunBinaries / buildZxScript / buildZxScriptFromFile.
//
// Single-purpose: forbid raw process.exit() in entrypoints. The bug this
// catches is a kernel-pipe-drain race —
// `process.stdout.write(big); process.exit(0);` truncates output when the
// consumer is not draining. Use `process.exitCode = N; return;` or a
// flush-aware helper instead.
//
// See:
//   - amarbel-llc/bun#7 (this lint's home issue)
//   - amarbel-llc/bun#8 (follow-up to expand the rule set)
//   - amarbel-llc/nixpkgs#11 (root-cause triage)
//   - docs/decisions/0001-vendor-eslint-stack-for-buildbunbinary-lint.md
//
// Per-line escape hatch:
//   // eslint-disable-next-line n/no-process-exit
//   process.exit(1);
//
// Coverage notes:
//   `n/no-process-exit` only matches the literal AST shape
//   `process.exit(...)` — it does not catch `const p = process; p.exit()`,
//   `require('process').exit()`, or destructured imports
//   (`import { exit } from "node:process"`). The two extra rules below
//   close those holes.

import n from "eslint-plugin-n";
import tsParser from "@typescript-eslint/parser";

export default [
  {
    files: ["**/*.{ts,tsx,mts,cts,js,mjs,cjs}"],
    languageOptions: {
      parser: tsParser,
      sourceType: "module",
      ecmaVersion: "latest",
    },
    plugins: { n },
    rules: {
      // Catches `process.exit(N)` by direct AST shape.
      "n/no-process-exit": "error",

      // Catches `import { exit } from "process"` /
      // `import { exit } from "node:process"` (then `exit(N)` later).
      "no-restricted-imports": [
        "error",
        {
          paths: [
            {
              name: "process",
              importNames: ["exit"],
              message:
                "Don't import `exit` — set `process.exitCode = N; return;` instead so stdout/stderr can drain (see amarbel-llc/bun#7).",
            },
            {
              name: "node:process",
              importNames: ["exit"],
              message:
                "Don't import `exit` — set `process.exitCode = N; return;` instead so stdout/stderr can drain (see amarbel-llc/bun#7).",
            },
          ],
        },
      ],

      // Catches `require('process').exit(...)` and `require('node:process').exit(...)`.
      // n/no-process-exit doesn't see these because the AST root isn't the
      // bare identifier `process`.
      "no-restricted-syntax": [
        "error",
        {
          selector:
            "CallExpression[callee.type='MemberExpression'][callee.property.name='exit'][callee.object.type='CallExpression'][callee.object.callee.name='require'][callee.object.arguments.0.value=/^(node:)?process$/]",
          message:
            "Don't call `require('process').exit()` — set `process.exitCode = N; return;` instead so stdout/stderr can drain (see amarbel-llc/bun#7).",
        },
      ],
    },
  },
];
