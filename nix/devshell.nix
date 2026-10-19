# VutronMusic 开发环境：`nix develop` 进入
#
# 目标：在 NixOS 上无需手工安装 node/yarn/python，也不依赖 electron 的二进制下载，
# 直接获得可运行 `yarn dev` 的环境。
{
  lib,
  mkShell,
  nodejs_22,
  yarn,
  python3,
  node-gyp,
  writeShellApplication,
  stdenv,
  electron,
}:

let
  nodejs = nodejs_22;

  # node-gyp 在 Python 3.12+ 下需要 setuptools 提供的 distutils 兼容层
  python = python3.withPackages (ps: [ ps.setuptools ]);

  # 一键初始化：安装依赖 + patch taglib-wasm + 按 Electron ABI 重建 better-sqlite3
  setup = writeShellApplication {
    name = "vutron-setup";
    runtimeInputs = [
      nodejs
      yarn
      python
      node-gyp
    ];
    runtimeEnv = {
      # 原生模块（better-sqlite3）编译所用的 Electron 头文件
      npm_config_nodedir = "${electron.headers}";
      npm_config_build_from_source = "true";
    };
    text = ''
      if [ ! -f package.json ]; then
        echo "❌ 请在 VutronMusic 仓库根目录运行（当前目录：$PWD）" >&2
        exit 1
      fi

      echo "==> [1/3] 安装依赖（跳过 install scripts，sandbox/rebuild 由本脚本接管）"
      yarn install --ignore-scripts --frozen-lockfile --no-progress

      echo "==> [2/3] 修补 taglib-wasm（动态 import 需要 \"type\": \"module\"）"
      node fix-taglib-wasm.js

      echo "==> [3/3] 为 Electron 重建 better-sqlite3 原生模块"
      gyp=node-gyp
      if [ -x ./node_modules/.bin/node-gyp ]; then
        gyp=./node_modules/.bin/node-gyp
      fi
      # 显式传 --nodedir：nixpkgs 的 node-gyp 包装脚本会覆盖 npm_config_nodedir
      "$gyp" rebuild --nodedir="$npm_config_nodedir" --directory=node_modules/better-sqlite3

      echo ""
      echo "✅ 初始化完成，运行 yarn dev 启动开发模式"
    '';
  };
in
mkShell {
  name = "vutronmusic-dev";

  packages = [
    nodejs
    yarn
    python
    node-gyp
    setup
    electron
    # sharp 使用官方预编译产物（@img/*），只缺 libstdc++
    stdenv.cc.cc.lib
  ];

  env = {
    # 让 `require('electron')`（vite-plugin-electron 启动时使用）指向 nix 提供的 Electron，
    # 而不是去下载 electron npm 包自带的二进制
    ELECTRON_OVERRIDE_DIST_PATH = "${electron}/bin";
    # 原生模块按 Electron ABI 编译
    npm_config_nodedir = "${electron.headers}";
    npm_config_build_from_source = "true";
    # 避免任何情况下 electron 的 postinstall 触发二进制下载
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
  };

  shellHook = ''
    # sharp 预编译产物依赖 libstdc++，确保运行时可被找到
    export LD_LIBRARY_PATH="${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    echo ""
    echo "  VutronMusic nix 开发环境（electron ${electron.version}）"
    echo "  -------------------------------------------------------"
    if [ ! -d node_modules ]; then
      echo "  首次使用：运行 vutron-setup 安装依赖并编译原生模块"
    else
      echo "  依赖已就绪，直接运行 yarn dev 启动开发模式"
      echo "  依赖有变动时重新运行 vutron-setup"
    fi
    echo ""
  '';
}
