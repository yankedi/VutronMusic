# VutronMusic —— 从源码构建的 Nix 包
#
# 与官方 electron-builder 产物等价，区别在于：
#   - 使用 nix 固定版本的 Electron（见 nix/electron.nix，与 yarn.lock 一致）
#   - better-sqlite3 按 Electron ABI 现场编译
#   - sharp 使用官方预编译产物（@img/*），由 autoPatchelfHook 补齐 libstdc++ 依赖
#
# 产物：
#   $out/bin/vutronmusic                        启动器（包装 Electron）
#   $out/share/vutronmusic/{dist,node_modules}  应用本体
#   $out/share/applications/vutronmusic.desktop
#   $out/share/icons/hicolor/{512x512,1024x1024}/apps/vutronmusic.png
{
  lib,
  stdenv,
  fetchYarnDeps,
  yarnConfigHook,
  nodejs_22,
  python3,
  electron,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  autoPatchelfHook,
  src,
}:

let
  nodejs = nodejs_22;

  # node-gyp 在 Python 3.12+ 下需要 setuptools 提供的 distutils 兼容层
  python = python3.withPackages (ps: [ ps.setuptools ]);

  packageJson = lib.importJSON "${src}/package.json";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "vutronmusic";
  version = packageJson.version;

  inherit src;

  # yarn.lock 对应的离线依赖缓存（更新 yarn.lock 后需同步更新 hash）
  offlineCache = fetchYarnDeps {
    yarnLock = "${src}/yarn.lock";
    hash = "sha256-hNyS9fHdf+PyfKKyNrdoCfPrmX8BX7mWp2Y2LU2rlNg=";
  };

  nativeBuildInputs = [
    nodejs
    python
    yarnConfigHook
    autoPatchelfHook
    makeWrapper
    copyDesktopItems
  ];

  buildInputs = [
    # sharp 预编译产物（@img/*）需要 libstdc++
    stdenv.cc.cc.lib
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "vutronmusic";
      desktopName = "VutronMusic";
      exec = "vutronmusic %U";
      icon = "vutronmusic";
      type = "Application";
      categories = [
        "AudioVideo"
        "Audio"
        "Player"
      ];
      comment = "多数据源桌面音乐播放器";
      # Electron 的 WM_CLASS 为 app.name（class 字段），见 nix/README.md
      startupWMClass = "VutronMusic";
    })
  ];

  env = {
    # 原生模块按 Electron ABI 编译（node-gyp 读取）
    npm_config_nodedir = "${electron.headers}";
    npm_config_build_from_source = "true";
    # electron npm 包不做二进制下载（运行时使用 nix 提供的 Electron）
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
  };

  autoPatchelfIgnoreMissingDeps = [
    # 随依赖安装的 musl 版 sharp 预编译产物（glibc 系统不会加载）
    "libc.musl-*.so.*"
  ];

  buildPhase = ''
    runHook preBuild

    echo "==> vite build（renderer / main / preload / workers）"
    yarn vite build

    # 注意：yarn 的裁剪会重装被修改过的包，因此修补/重编译必须放在裁剪之后
    echo "==> 裁剪 devDependencies（仅保留运行时依赖）"
    yarn install \
      --production=true --ignore-scripts --frozen-lockfile \
      --offline --ignore-engines --ignore-platform --no-progress

    echo "==> 修补 taglib-wasm（worker 内动态 import 需要 \"type\": \"module\"）"
    node fix-taglib-wasm.js

    # better-sqlite3 必须按 Electron ABI 编译：
    # 使用仓库自带的 node-gyp（与官方构建一致，读取 env.npm_config_nodedir）；
    # 不能用 nixpkgs 的 node-gyp —— 它的包装脚本会覆盖 npm_config_nodedir
    echo "==> 为 Electron ${electron.version} 重建 better-sqlite3"
    if [ ! -f node_modules/node-gyp/bin/node-gyp.js ]; then
      echo "错误：node_modules/node-gyp 不存在（依赖树可能已变化）" >&2
      exit 1
    fi
    node node_modules/node-gyp/bin/node-gyp.js rebuild --directory=node_modules/better-sqlite3

    # 功能自检：用 Electron 自身的 ABI 加载 better-sqlite3 并执行一次 SQL
    echo "==> 自检 better-sqlite3（Electron ABI）"
    ELECTRON_RUN_AS_NODE=1 ${lib.getExe electron} -e "
      const Database = require('better-sqlite3');
      const db = new Database(':memory:');
      db.exec('CREATE TABLE t (a)');
      if (db.prepare('SELECT 1 AS x').get().x !== 1) throw new Error('sqlite 自检失败');
      console.log('better-sqlite3 自检通过');
    "

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    appdir=$out/share/vutronmusic
    mkdir -p $appdir
    cp -r dist package.json node_modules $appdir/

    # esbuild 的依赖树里带有各平台的二进制（含 Solaris 等），
    # 只保留当前平台，避免 autoPatchelfHook 处理外来 ELF
    esbuild_dir=$appdir/node_modules/@esbuild
    if [ -d "$esbuild_dir" ]; then
      current="${stdenv.hostPlatform.node.platform}-${stdenv.hostPlatform.node.arch}"
      find "$esbuild_dir" -mindepth 1 -maxdepth 1 -type d ! -name "$current" -exec rm -rf {} +
    fi

    # 仓库自带图标：icon.png 1024x1024，icon-1.png 512x512
    install -Dm644 buildAssets/icons/icon.png \
      $out/share/icons/hicolor/1024x1024/apps/vutronmusic.png
    install -Dm644 buildAssets/icons/icon-1.png \
      $out/share/icons/hicolor/512x512/apps/vutronmusic.png

    makeWrapper ${lib.getExe electron} $out/bin/vutronmusic \
      --add-flags "$appdir" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}" \
      --inherit-argv0

    runHook postInstall
  '';

  meta = {
    description = "多数据源桌面音乐播放器（Electron + Vue3）";
    homepage = "https://github.com/stark81/VutronMusic";
    license = lib.licenses.mit;
    platforms = electron.meta.platforms;
    mainProgram = "vutronmusic";
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
  };
})
