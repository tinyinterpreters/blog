{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flake-deploy = {
      url = "github:dwayne/deploy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, flake-deploy }:
    flake-utils.lib.eachDefaultSystem(system:
      let
        lib = nixpkgs.lib;
        pkgs = nixpkgs.legacyPackages.${system};
        deploy = flake-deploy.lib.mkDeploy pkgs;

        blog = pkgs.callPackage ./nix/blog.nix {};

        deployBlog = pkgs.writeShellApplication {
          name = "deploy-blog";
          runtimeInputs = [ deploy ];
          text = ''
            exec deploy "$@" "${blog}" "release/prod"
          '';
        };
      in
      {
        devShells.default = pkgs.mkShell {
          name = "blog";

          packages = [
            pkgs.just
            pkgs.nodejs-slim_24
            pkgs.pnpm
          ];

          shellHook = ''
            export PROJECT_ROOT="$PWD"
            export PATH="$PROJECT_ROOT/node_modules/.bin:$PATH"

            if [ ! -d "$PROJECT_ROOT/node_modules" ]; then
              pnpm install --silent
            fi
          '';
        };

        packages = {
          inherit blog deployBlog;
          default = blog;
        };

        apps = {
          deploy = {
            type = "app";
            program = lib.getExe deployBlog;
            meta.description = "Deploy the blog";
          };
        };

        checks = {
          inherit blog deployBlog;
        };
      }
    );
}
