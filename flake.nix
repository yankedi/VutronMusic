{
  description = "VutronMusic —— 多数据源桌面音乐播放器（Nix/NixOS 集成）";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # 各系统共用的构造：固定版本的 Electron（与 yarn.lock 一致）
      mkContext =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          electron = pkgs.callPackage ./nix/electron.nix { };
        in
        {
          inherit pkgs electron;
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          ctx = mkContext system;
          vutronmusic = ctx.pkgs.callPackage ./nix/package.nix {
            inherit (ctx) electron;
            src = self;
          };
        in
        {
          inherit vutronmusic;
          default = vutronmusic;
        }
      );

      overlays.default = final: prev: {
        vutronmusic = final.callPackage ./nix/package.nix {
          electron = final.callPackage ./nix/electron.nix { };
          src = self;
        };
      };

      nixosModules = {
        default = import ./nix/module.nix { inherit self; };
        vutronmusic = self.nixosModules.default;
      };

      devShells = forAllSystems (
        system:
        let
          ctx = mkContext system;
        in
        {
          default = ctx.pkgs.callPackage ./nix/devshell.nix { inherit (ctx) electron; };
        }
      );
    };
}
