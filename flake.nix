{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    foundry = {
      url = "github:shazow/foundry.nix/monthly"; # Use monthly branch for permanent releases
      inputs.nixpkgs.follows = "nixpkgs";
    };
    solc = {
      url = "github:hellwolf/solc.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs = { self, nixpkgs, flake-utils, foundry, solc, rust }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ foundry.overlay solc.overlay rust.overlays.default ];
        };
        toolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
        stdenv = if pkgs.stdenv.isLinux then pkgs.stdenvAdapters.useMoldLinker pkgs.stdenv else pkgs.stdenv;
      in
      {
        devShells.default = pkgs.mkShell.override { inherit stdenv; } {
          nativeBuildInputs = with pkgs; [
            gnum4
          ];
          buildInputs = [
            pkgs.rust-analyzer-unwrapped
            toolchain
          ];
          packages = with pkgs; [
            nodejs_20
            typescript
            foundry-bin
            solc_0_8_26
            (solc.mkDefault pkgs solc_0_8_26)
            slither-analyzer
            lcov
          ];

          shellHook = ''
            set -a; source .env; set +a
            npm i
            forge install
          '';

          RUST_SRC_PATH = "${toolchain}/lib/rustlib/src/rust/library";
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.gnum4 ];
        };
      });
}
