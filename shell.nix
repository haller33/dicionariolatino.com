{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  buildInputs = [
    (pkgs.lua5_2.withPackages (luaPkgs: [
      luaPkgs.luasql-sqlite3
    ]))
  ];
}
