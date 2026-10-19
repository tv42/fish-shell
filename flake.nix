{
  description = "fish - the friendly interactive shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
    }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      mkFish =
        pkgs:
        let
          craneLib = crane.mkLib pkgs;

          # Source including Cargo/Rust files plus extra directories needed for build
          src = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [
              (craneLib.fileset.commonCargoSources ./.)
              ./share
              ./doc_src
              ./build_tools
              ./localization
            ];
          };

          # Common arguments for crane builds
          commonArgs = {
            inherit src;

            nativeBuildInputs = [
              pkgs.pkg-config
              pkgs.cmake
              pkgs.sphinx
              pkgs.gettext
            ];

            buildInputs = [
              pkgs.pcre2
              pkgs.libiconv
            ];

            # Environment variables for pcre2
            PCRE2_LIB_DIR = "${pkgs.pcre2.out}/lib";
            PCRE2_INCLUDE_DIR = "${pkgs.pcre2.dev}/include";
          };

          # Build just the cargo dependencies for caching
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        in
        # Build the fish package
        craneLib.buildPackage (
          commonArgs
          // {
            inherit cargoArtifacts;

            # Skip tests that require filesystem access not available in sandbox
            doCheck = false;

            # Install shell scripts, completions, and other data files
            postInstall = ''
              # Install fish functions and completions
              mkdir -p $out/share/fish
              cp -r share/functions $out/share/fish/
              cp -r share/completions $out/share/fish/
              cp -r share/tools $out/share/fish/ 2>/dev/null || true

              # Install man pages if they exist
              if [ -d share/man ]; then
                mkdir -p $out/share/man
                cp -r share/man/* $out/share/man/
              fi
            '';

            meta = with pkgs.lib; {
              description = "Smart and user-friendly command line shell";
              homepage = "https://fishshell.com";
              license = licenses.gpl2Only;
              platforms = platforms.unix;
              mainProgram = "fish";
            };

            passthru = {
              shellPath = "/bin/fish";
            };
          }
        );
    in
    {
      overlays.default = final: prev: {
        fish = mkFish final;
      };

      packages = forAllSystems (
        system:
        let
          fish = mkFish nixpkgs.legacyPackages.${system};
        in
        {
          default = fish;
          inherit fish;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          craneLib = crane.mkLib pkgs;
        in
        {
          default = craneLib.devShell {
            # Inherit inputs from the main package
            inputsFrom = [ self.packages.${system}.fish ];

            # Extra tools for development
            packages = with pkgs; [
              cargo
              rustc
              rust-analyzer
              clippy
              rustfmt

              # Testing dependencies
              (python3.withPackages (
                ps: with ps; [
                  pexpect
                ]
              ))
              tmux
            ];
          };
        }
      );
    };
}
