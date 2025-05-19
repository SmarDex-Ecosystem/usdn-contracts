{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    foundry = {
      url = "github:shazow/foundry.nix/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs = { self, nixpkgs, flake-utils, foundry, rust }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ foundry.overlay rust.overlays.default ];
        };
        toolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
        stdenv = if pkgs.stdenv.isLinux then pkgs.stdenvAdapters.useMoldLinker pkgs.stdenv else pkgs.stdenv;
      in
      {
        devShells.default = pkgs.mkShell.override { inherit stdenv; } {
          nativeBuildInputs = with pkgs; [
            gnum4
            openssl
          ];
          buildInputs = [
            pkgs.rust-analyzer-unwrapped
            pkgs.pkg-config
            toolchain
          ];
          packages = with pkgs; [
            foundry-bin
            gyre-fonts
            just
            lcov
            lintspec
            mdbook
            nodejs_20
            trufflehog
            typescript
            typst
          ];

          shellHook = ''
            set -a; source .env; set +a
            npm i
            forge soldeer install
          '';

          RUST_SRC_PATH = "${toolchain}/lib/rustlib/src/rust/library";
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.gnum4 pkgs.openssl];
          TYPST_FONT_PATHS = "${pkgs.gyre-fonts}/share/fonts";
        };
      });
}
