# Both units import `_purge.py` from this one store directory.
{ lib }:
lib.fileset.toSource {
  root = ./.;
  fileset = lib.fileset.fileFilter (file: file.hasExt "py") ./.;
}
