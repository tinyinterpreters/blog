{ fetchPnpmDeps
, lib
, nodejs-slim_24
, pnpm
, pnpmConfigHook
, stdenv
}:

let
  fs = lib.fileset;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "blog";
  version = "1.0.0";

  src = fs.toSource {
    root = ../.;
    fileset = fs.unions [
      ../public
      ../src
      ../astro-paper.config.ts
      ../astro.config.ts
      ../package.json
      ../pnpm-lock.yaml
      ../pnpm-workspace.yaml
      ../tsconfig.json
    ];
  };

  nativeBuildInputs = [
    nodejs-slim_24
    pnpm
    pnpmConfigHook
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 4;
    hash = "sha256-5MHOyfzZpuc7apZOd7bA93GKuGJ/nE2lgxin3xEHO1M=";
  };

  buildPhase = ''
    runHook preBuild

    pnpm build
    cp -R dist/ "$out/"

    runHook postBuild
  '';
})
