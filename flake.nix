{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    foundry = {
      url = "github:shazow/foundry.nix/monthly"; # Use monthly branch for permanent releases
      inputs.nixpkgs.follows = "nixpkgs";
    };
    solc = {
      url = "github:hellwolf/solc.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, utils, devenv, foundry, solc } @ inputs:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ foundry.overlay solc.overlay ];
        };
      in
      {
        devShell = devenv.lib.mkShell {
          inherit inputs pkgs;
          modules = [
            ({ pkgs, ... }: {
              packages = with pkgs; [
                foundry-bin
                solc_0_8_20
                (solc.mkDefault pkgs solc_0_8_20)
                slither-analyzer
                lcov
              ];
              languages.javascript.enable = true;
              languages.javascript.package = pkgs.nodejs_20;
              enterShell = ''
                set -a; source .env; set +a
                npm i
                forge install
              '';
            })
          ];
        };
      });
}
