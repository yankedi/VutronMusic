# NixOS 模块：声明式启用 VutronMusic
#
# 用法（在系统 flake 中）：
#   inputs.vutronmusic.url = "github:stark81/VutronMusic";
#
#   modules = [
#     inputs.vutronmusic.nixosModules.default
#     { programs.vutronmusic.enable = true; }
#   ];
#
# 目前仅提供 enable（安装 + 桌面集成），包本身由 flake 的 packages 输出提供。
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.vutronmusic;
in
{
  options.programs.vutronmusic = {
    enable = lib.mkEnableOption "VutronMusic 多数据源桌面音乐播放器";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.vutronmusic;
      defaultText = lib.literalMD "`inputs.vutronmusic.packages.\${system}.vutronmusic`";
      description = "要安装的 VutronMusic 包。";
      example = lib.literalExpression "pkgs.vutronmusic";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
