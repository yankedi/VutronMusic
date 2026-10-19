# Electron 37.10.3 —— 与 yarn.lock 中 `electron@^37.6.0` 的解析结果保持一致。
#
# nixpkgs 只保留最近几个大版本（当前为 39+），这里按 nixpkgs 的做法自行固定版本，
# 保证「开发环境 / nix 打包 / 官方发布」使用完全相同的 Electron。
#
# 结构改编自 nixpkgs: pkgs/development/tools/electron/binary/generic.nix（MIT）
#
# 升级方式：
#   1. 修改 package.json 的 electron 版本并更新 yarn.lock
#   2. 修改下方 version
#   3. 用 `nix-prefetch-url <url>` 更新 zip / headers 哈希（build 时会报出正确值）
{
  lib,
  stdenv,
  fetchurl,
  fetchzip,
  makeWrapper,
  wrapGAppsHook3,
  unzip,
  alsa-lib,
  at-spi2-atk,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  gtk4,
  nss,
  nspr,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  libxkbfile,
  pango,
  pciutils,
  systemd,
  libnotify,
  pipewire,
  libsecret,
  libpulseaudio,
  speechd-minimal,
  libdrm,
  libgbm,
  libxkbcommon,
  libxshmfence,
  libGL,
  vulkan-loader,
}:

let
  version = "37.10.3";

  sources = {
    x86_64-linux = {
      tag = "linux-x64";
      zip = "sha256-wLTt1r2YWM2kz3qymeaaLT7NLl/Mp4UHvAhRujVhRmA=";
    };
    aarch64-linux = {
      tag = "linux-arm64";
      zip = "sha256-N6IoghGEE2+oaocnvsGatABSTdfUvKeJN95dUHBFktE=";
    };
  };

  system = stdenv.hostPlatform.system;
  source = sources.${system} or (throw "electron ${version}: 不支持的系统 ${system}");

  electronLibPath = lib.makeLibraryPath [
    alsa-lib
    at-spi2-atk
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    gtk4
    nss
    nspr
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxkbfile
    pango
    pciutils
    stdenv.cc.cc
    systemd
    libnotify
    pipewire
    libsecret
    libpulseaudio
    speechd-minimal
    libdrm
    libgbm
    libxkbcommon
    libxshmfence
    libGL
    vulkan-loader
  ];

  headers = fetchzip {
    name = "electron-${version}-headers";
    url = "https://artifacts.electronjs.org/headers/dist/v${version}/node-v${version}-headers.tar.gz";
    hash = "sha256-hWqdibcq1IZvUylD0Q7M1tCC+Xx27yThFktCgRBvjFM=";
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "electron";
  inherit version;

  src = fetchurl {
    url = "https://github.com/electron/electron/releases/download/v${version}/electron-v${version}-${source.tag}.zip";
    hash = source.zip;
  };

  nativeBuildInputs = [
    unzip
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    glib
    gtk3
    gtk4
  ];

  # 用于给原生模块（better-sqlite3 等）编译 Electron ABI 的头文件
  passthru.headers = headers;
  passthru.dist = finalAttrs.finalPackage + "/libexec/electron";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec/electron
    unzip -d $out/libexec/electron $src
    chmod u-x $out/libexec/electron/*.so*

    runHook postInstall
  '';

  # 手动包装，避免把整个 $out/libexec 内容加入 GDK/GSettings 环境探测
  dontWrapGApps = true;

  preFixup = ''
    makeWrapper "$out/libexec/electron/electron" $out/bin/electron \
      "''${gappsWrapperArgs[@]}"
  '';

  postFixup = ''
    patchelf \
      --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
      --set-rpath "${electronLibPath}:$out/libexec/electron" \
      $out/libexec/electron/electron \
      $out/libexec/electron/chrome_crashpad_handler

    # 使用 nixpkgs 的 vulkan-loader 替换捆绑版本
    rm "$out/libexec/electron/libvulkan.so.1"
    ln -s -t "$out/libexec/electron" "${lib.getLib vulkan-loader}/lib/libvulkan.so.1"

    # patch ANGLE（Electron 44 之前需要）
    patchelf \
      --set-rpath "${lib.makeLibraryPath [ libGL pciutils vulkan-loader ]}" \
      $out/libexec/electron/lib*GL*
  '';

  meta = {
    description = "Cross platform desktop application shell (VutronMusic 固定版本)";
    homepage = "https://github.com/electron/electron";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "electron";
  };
})
