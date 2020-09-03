let
  pkgs = import ./nix/ci-pkgs.nix;
  pre-commit-hooks = import ./nix/pre-commit.nix;
in
pkgs.smosPackages // {
  release = pkgs.smosRelease;
  pre-commit-check = pre-commit-hooks.run;
  inherit (pkgs) smosVersionInfo;
}
