## 1. Fleet Integration

- [x] 1.1 Add and pin the `nix-index-database` flake input, import its NixOS module for every host, and verify all host configurations evaluate.
- [x] 1.2 Enable `programs.nix-index-database.comma` in `modules/profiles/shell-profile.nix` and verify the fleet configuration evaluates with the shared profile.

## 2. Validation

- [x] 2.1 Run the scoped formatter check and `openspec validate --strict` successfully.
