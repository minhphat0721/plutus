{ pkgs, plutus, rootSshKeys, extraImports ? [ ] }:
# mkMachine :: { config : Path, name : String } -> NixOS machine
# Takes a machine specific configuration and a hostname to set and
# applies generic settings:
# - aws machine settings from ./profiles/std.nix
# - configures root ssh keys for
# - adds plutus specific packages through an overlay
{ config, name }: {
  imports = extraImports ++ [
    config
    ({ lib, config, ... }:
      {
        networking.hostName = name;
        users.extraUsers.root.openssh.authorizedKeys.keys = rootSshKeys;
        nixpkgs = {
          inherit pkgs;
          overlays = [
            (self: super: {
              plutus-pab = plutus.plutus-pab;
              marlowe-app = plutus.marlowe-app;
              marlowe-companion-app = plutus.marlowe-companion-app;
              marlowe-dashboard = plutus.marlowe-dashboard;
              marlowe-playground = plutus.marlowe-playground;
              plutus-playground = plutus.plutus-playground;
              web-ghc = plutus.web-ghc;
              plutus-docs = plutus.docs;
            })
          ];
        };
      })
  ];
}
