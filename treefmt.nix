{
  projectRootFile = "flake.nix";

  programs.nixfmt.enable = true;
  programs.prettier.enable = true;
  programs.shfmt.enable = true;
  programs.rustfmt.enable = true;

  settings.excludes = [
    "secrets.yaml"
    "*.md"
    "flake.lock"
  ];

  programs.prettier.excludes = [
    "secrets.yaml"
    "*.md"
  ];
}
