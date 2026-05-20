{
  description = "Bun - A fast all-in-one JavaScript runtime";

  # Uncomment this when you set up Cachix to enable automatic binary cache
  # nixConfig = {
  #   extra-substituters = [
  #     "https://bun-dev.cachix.org"
  #   ];
  #   extra-trusted-public-keys = [
  #     "bun-dev.cachix.org-1:REPLACE_WITH_YOUR_PUBLIC_KEY"
  #   ];
  # };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # nixpkgs-master is the SHA-pinned anchor that eng's update-nix-
    # repos recipe cascades. Unused in outputs — the actual build still
    # consumes `nixpkgs` above (nixos-unstable, Hydra-cached), which is
    # what keeps bun's compile-heavy build inputs in the public binary
    # cache. This input just lets the cascade see and update a pinned ref.
    nixpkgs-master.url = "github:NixOS/nixpkgs/d233902339c02a9c334e7e593de68855ad26c4cb";
    flake-utils.url = "github:numtide/flake-utils";

    # bun2nix — only used for the cacheEntryCreator Zig binary.
    # The Nix builder functions are vendored in nix/bun2nix/.
    bun2nix.url = "github:nix-community/bun2nix";
    bun2nix.inputs.nixpkgs.follows = "nixpkgs";

    # batman — bats wrapper with bundled support libraries.
    # Does NOT follow our nixpkgs: nokogiri (ronn dep) fails to build
    # against nixpkgs-unstable. See amarbel-llc/bob#100.
    bob.url = "github:amarbel-llc/bob";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      bun2nix,
      bob,
      ...
    }:
    {
      # Non-system-specific lib output.
      # Usage:
      #   let bunLib = bun.lib.mkBunLib { inherit pkgs; };
      #   in bunLib.buildBunBinary { pname = "my-app"; ... }
      #
      # Defaults to this fork's bun package (self.packages.${system}.bun).
      # Pass `bun` explicitly to override.
      lib.mkBunLib =
        {
          pkgs,
          bun ? self.packages.${pkgs.stdenv.hostPlatform.system}.bun,
        }:
        import ./nix/bun2nix {
          inherit pkgs bun;
          cacheEntryCreator = bun2nix.packages.${pkgs.stdenv.hostPlatform.system}.cacheEntryCreator;
        };
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
          };
        };

        # LLVM 21 - matching the bootstrap script (targets 21.1.8, actual version from nixpkgs-unstable)
        llvm = pkgs.llvm_21;
        clang = pkgs.clang_21;
        lld = pkgs.lld_21;

        # Node.js 24 - matching the bootstrap script (targets 24.3.0, actual version from nixpkgs-unstable)
        nodejs = pkgs.nodejs_24;

        # batman — bats wrapper with bundled support libraries
        batman = bob.packages.${system}.batman;

        # Build tools and dependencies
        packages = [
          # Core build tools
          pkgs.cmake # Expected: 3.30+ on nixos-unstable as of 2025-10
          pkgs.ninja
          pkgs.pkg-config
          pkgs.ccache

          # Compilers and toolchain - version pinned to LLVM 21
          clang
          llvm
          lld
          pkgs.gcc
          pkgs.rustc
          pkgs.cargo
          pkgs.go

          # Bun itself (for running build scripts via `bun bd`)
          pkgs.bun

          # Node.js - version pinned to 24
          nodejs

          # Python for build scripts
          pkgs.python3

          # Other build dependencies from bootstrap.sh
          pkgs.libtool
          pkgs.ruby
          pkgs.perl

          # Libraries
          pkgs.openssl
          pkgs.zlib
          pkgs.libxml2
          pkgs.libiconv

          # Development tools
          pkgs.git
          pkgs.curl
          pkgs.wget
          pkgs.unzip
          pkgs.xz

          # Testing
          batman

          # Additional dependencies for Linux
        ]
        ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
          pkgs.gdb # for debugging core dumps (from bootstrap.sh line 1535)

          # Chromium dependencies for Puppeteer testing (from bootstrap.sh lines 1397-1483)
          # X11 and graphics libraries
          pkgs.xorg.libX11
          pkgs.xorg.libxcb
          pkgs.xorg.libXcomposite
          pkgs.xorg.libXcursor
          pkgs.xorg.libXdamage
          pkgs.xorg.libXext
          pkgs.xorg.libXfixes
          pkgs.xorg.libXi
          pkgs.xorg.libXrandr
          pkgs.xorg.libXrender
          pkgs.xorg.libXScrnSaver
          pkgs.xorg.libXtst
          pkgs.libxkbcommon
          pkgs.mesa
          pkgs.nspr
          pkgs.nss
          pkgs.cups
          pkgs.dbus
          pkgs.expat
          pkgs.fontconfig
          pkgs.freetype
          pkgs.glib
          pkgs.gtk3
          pkgs.pango
          pkgs.cairo
          pkgs.alsa-lib
          pkgs.at-spi2-atk
          pkgs.at-spi2-core
          pkgs.libgbm # for hardware acceleration
          pkgs.liberation_ttf # fonts-liberation
          pkgs.atk
          pkgs.libdrm
          pkgs.xorg.libxshmfence
          pkgs.gdk-pixbuf
        ]
        ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
          # macOS specific dependencies (new unified SDK pattern, see nixos.org #354146)
          pkgs.apple-sdk
        ];

        bunLib = self.lib.mkBunLib { inherit pkgs; };

        # bun2nix CLI from the upstream flake. Used by the lint-stack
        # regen app and the lint-stack drift-guard check.
        bun2nixCli = bun2nix.packages.${system}.bun2nix;

        # Lint stack: vendored eslint + plugins under nix/bun2nix/lint/.
        # See amarbel-llc/bun#7 and
        # docs/decisions/0001-vendor-eslint-stack-for-buildbunbinary-lint.md.
        regenLintStack = import ./nix/bun2nix/lint/regen.nix {
          inherit pkgs;
          bun = pkgs.bun;
          bun2nix = bun2nixCli;
        };
        lintStackUpToDate = import ./nix/bun2nix/lint/check.nix {
          inherit pkgs;
          bun2nix = bun2nixCli;
          bunLock = ./nix/bun2nix/lint/bun.lock;
          bunNix = ./nix/bun2nix/lint/bun.nix;
        };

      in
      {
        # The fork's bun package. Re-exports nixpkgs bun until the fork
        # modifies the runtime source (issue #1).
        packages.bun = pkgs.bun;
        packages.default = pkgs.bun;

        # -- Lint stack regen app + drift-guard check --

        apps.regen-lint-stack = {
          type = "app";
          program = "${regenLintStack}/bin/regen-lint-stack";
        };

        checks.lint-stack-up-to-date = lintStackUpToDate;

        # -- buildZxScript test packages --

        # Tier 1: zero-config (just zx)
        packages.test-zx-basic = bunLib.buildZxScript {
          pname = "test-zx-basic";
          version = "0.0.1";
          src = ./test/nix/zx-basic;
        };

        # Tier 2: extra deps (zx + chalk)
        packages.test-zx-extra-deps = bunLib.buildZxScript {
          pname = "test-zx-extra-deps";
          version = "0.0.1";
          src = ./test/nix/zx-extra-deps;
          extraDeps = {
            "chalk@5.4.1" = pkgs.fetchurl {
              url = "https://registry.npmjs.org/chalk/-/chalk-5.4.1.tgz";
              hash = "sha512-zgVZuo2WcZgfUEmsn6eO3kINexW8RAE4maiQ8QNs8CtpPCSyMiYsULR3HQYkm3w8FIA3SberyMJMSldGsW+U3w==";
            };
          };
        };

        # Tier 4: file-based deps (///!dep directives in script)
        packages.test-zx-from-file = bunLib.buildZxScriptFromFile {
          pname = "test-zx-from-file";
          version = "0.0.1";
          script = ./test/nix/zx-from-file/index.ts;
        };

        # -- buildBunBinary lint test packages (amarbel-llc/bun#7) --

        # Recommended pattern: process.exitCode = N; return.
        # Lint runs (default) and the bundle builds.
        packages.test-bin-no-process-exit = bunLib.buildBunBinary {
          pname = "test-bin-no-process-exit";
          version = "0.0.1";
          src = ./test/nix/bin-no-process-exit;
        };

        # Per-line escape hatch: process.exit() is allowed because of an
        # eslint-disable-next-line comment. Lint runs and the bundle builds.
        packages.test-bin-process-exit-disabled = bunLib.buildBunBinary {
          pname = "test-bin-process-exit-disabled";
          version = "0.0.1";
          src = ./test/nix/bin-process-exit-disabled;
        };

        # Failure fixture: process.exit() with the lint on. We target
        # .passthru.bundle (not the wrapper) because testBuildFailure'
        # can only catch failures from the wrapped derivation's own
        # builder — wrapper-level dependency failures cascade past it.
        checks.lint-stack-rejects-process-exit = pkgs.testers.testBuildFailure' {
          drv = (bunLib.buildBunBinary {
            pname = "test-bin-process-exit-fail";
            version = "0.0.1";
            src = ./test/nix/bin-process-exit-fail;
          }).passthru.bundle;
          expectedBuilderLogEntries = [ "n/no-process-exit" ];
        };

        devShells.default =
          (pkgs.mkShell.override {
            stdenv = pkgs.clangStdenv;
          })
            {
              inherit packages;
              hardeningDisable = [ "fortify" ];

              shellHook =
                ''
                  # Set up build environment
                  export CC="${pkgs.lib.getExe clang}"
                  export CXX="${pkgs.lib.getExe' clang "clang++"}"
                  export AR="${llvm}/bin/llvm-ar"
                  export RANLIB="${llvm}/bin/llvm-ranlib"
                  export CMAKE_C_COMPILER="$CC"
                  export CMAKE_CXX_COMPILER="$CXX"
                  export CMAKE_AR="$AR"
                  export CMAKE_RANLIB="$RANLIB"
                  export CMAKE_SYSTEM_PROCESSOR="$(uname -m)"
                  export TMPDIR="''${TMPDIR:-/tmp}"
                ''
                + pkgs.lib.optionalString pkgs.stdenv.isLinux ''
                  export LD="${pkgs.lib.getExe' lld "ld.lld"}"
                  export NIX_CFLAGS_LINK="''${NIX_CFLAGS_LINK:+$NIX_CFLAGS_LINK }-fuse-ld=lld"
                  export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath packages}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
                ''
                + ''

                  # Print welcome message
                  echo "====================================="
                  echo "Bun Development Environment"
                  echo "====================================="
                  echo "Node.js: $(node --version 2>/dev/null || echo 'not found')"
                  echo "Bun: $(bun --version 2>/dev/null || echo 'not found')"
                  echo "Clang: $(clang --version 2>/dev/null | head -n1 || echo 'not found')"
                  echo "CMake: $(cmake --version 2>/dev/null | head -n1 || echo 'not found')"
                  echo "LLVM: ${llvm.version}"
                  echo ""
                  echo "Quick start:"
                  echo "  bun bd                    # Build debug binary"
                  echo "  bun bd test <test-file>   # Run tests"
                  echo "====================================="
                '';

              # Additional environment variables
              CMAKE_BUILD_TYPE = "Debug";
              ENABLE_CCACHE = "1";
            };
      }
    );
}
