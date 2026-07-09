{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nix-update-script,
  versionCheckHook,
}:

buildNpmPackage (finalAttrs: {
  pname = "eask-cli";
  version = "0.12.10";

  src = fetchFromGitHub {
    owner = "emacs-eask";
    repo = "cli";
    tag = finalAttrs.version;
    hash = "sha256-zGaVdKUWLmifzEbVE1hSTjo9UECcfX0QR/5wgeeVabM=";
  };

  npmDepsHash = "sha256-sC3Qja49zAqCVfJzm2Sk4Qoa6kIlutpbDtNkc5OEThc=";

  dontBuild = true;

  nativeInstallCheckInputs = [
    versionCheckHook
  ];

  doInstallCheck = true;

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--use-github-releases" ];
  };

  meta = {
    changelog = "https://github.com/emacs-eask/cli/blob/${finalAttrs.version}/CHANGELOG.md";
    description = "CLI for building, runing, testing, and managing your Emacs Lisp dependencies";
    homepage = "https://emacs-eask.github.io/";
    license = lib.licenses.gpl3Plus;
    mainProgram = "eask";
    maintainers = with lib.maintainers; [
      jcs090218
      piotrkwiecinski
    ];
  };
})
