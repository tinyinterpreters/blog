{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    deploy = {
      url = "github:dwayne/deploy";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, deploy }:
    flake-utils.lib.eachDefaultSystem(system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        blog = pkgs.callPackage ./nix/blog.nix {};

        deployBlog = pkgs.writeShellScript "deploy-blog" ''
          ${deploy.packages.${system}.default}/bin/deploy "$@" ${blog} release/prod
        '';
      in
      {
        devShells.default = pkgs.mkShell {
          name = "blog";

          packages = [
            pkgs.nodejs-slim_24
            pkgs.pnpm
          ];

          shellHook = ''
            export PROJECT_ROOT="$(git rev-parse --show-toplevel)"
            export PS1="($name)\n$PS1"
            export PATH="$PROJECT_ROOT/node_modules/.bin:$PATH"

            if [ ! -d "$PROJECT_ROOT/node_modules" ]; then
              pnpm install --silent
            fi

            alias d='pnpm dev'
            alias b='pnpm build'
            alias p='pnpm preview'

            clean () {
              rm -rf "$PROJECT_ROOT/"{.astro,dist,node_modules,public/pagefind,result}
            }
            alias c='clean'

            deploy-prod () {
              nix run .#deploy
            }
          '';
        };

        packages = {
          inherit blog;
          default = blog;
        };

        apps = {
          deploy = {
            type = "app";
            program = "${deployBlog}";
            meta.description = "Deploy the blog";
          };
        };

        checks = {
          inherit blog deployBlog;
        };
      }
    );
}
