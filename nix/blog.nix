{ fetchPnpmDeps
, lib
, nodejs-slim_24
, pnpm_12
, pnpmConfigHook
, stdenvNoCC
}:

let
  fs = lib.fileset;
  pnpm = pnpm_12;
in
stdenvNoCC.mkDerivation (finalAttrs: {
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
    (pnpmConfigHook.override { inherit pnpm; })
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 4;
    hash = "sha256-PBOiGCDUFPMA34YM893wZSFtXXFqFTK+SOJtCLqy66o=";
  };

  env.ASTRO_TELEMETRY_DISABLED = "1";

  buildPhase = ''
    runHook preBuild
    pnpm build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp -r dist "$out"
    runHook postInstall
  '';

  dontFixup = true;
  allowedReferences = [];
})
