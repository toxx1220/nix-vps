{
  projectRootFile = "flake.nix";

  programs.nixfmt.enable = true;
  programs.prettier.enable = true;
  programs.shfmt.enable = true;
  programs.rustfmt.enable = true;

  settings.excludes = [
    "settings.json"
    "secrets.yaml"
    ".sops.yaml"
    "*.md"
    "flake.lock"
    "*.sql"
  ];

  programs.prettier.excludes = [
    "settings.json"
    "secrets.yaml"
    ".sops.yaml"
    "*.md"
    "*.sql"
  ];
}
