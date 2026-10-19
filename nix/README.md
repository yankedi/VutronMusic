# Nix / NixOS 集成

本目录提供 VutronMusic 的 flake：既可以作为 NixOS 模块声明式安装，也提供 `nix develop` 开发环境。

## 安装（NixOS）

1. 添加 flake input：

   ```nix
   # flake.nix
   inputs.vutronmusic.url = "github:stark81/VutronMusic";
   # 本地路径也可以：inputs.vutronmusic.url = "path:/home/you/lib/VutronMusic";
   ```

2. 导入模块并启用：

   ```nix
   {
     imports = [ inputs.vutronmusic.nixosModules.default ];

     programs.vutronmusic.enable = true;
   }
   ```

模块选项：

| 选项                            | 说明                                                    |
| ------------------------------- | ------------------------------------------------------- |
| `programs.vutronmusic.enable`   | 安装 VutronMusic（含 `.desktop` 与图标）                |
| `programs.vutronmusic.package`  | 覆盖使用的包（默认使用 flake 自带的构建）               |

只使用 package / overlay 也可以：

```nix
nixpkgs.overlays = [ inputs.vutronmusic.overlays.default ];
environment.systemPackages = [ pkgs.vutronmusic ];
```

## 开发环境

```bash
nix develop     # 进入开发 shell（Node 22 / Yarn 1.22 / Python / Electron 37.10.3）
vutron-setup    # 首次使用：安装依赖 + patch taglib-wasm + 编译 better-sqlite3
yarn dev        # 启动开发模式
```

说明：

- shell 提供的 Electron 与 `yarn.lock` 中的版本一致（当前 37.10.3），通过
  `ELECTRON_OVERRIDE_DIST_PATH` 注入，不会下载 electron npm 包的二进制。
- 依赖安装在仓库的 `node_modules/`（`vutron-setup` 等价于
  `yarn install --ignore-scripts` + `fix-taglib-wasm` + 按 Electron ABI 重编译 better-sqlite3）。
- sharp 使用官方预编译产物（`@img/*`），仅需 shell 提供 `libstdc++`。

## 构建 / 打包

```bash
nix build .#vutronmusic   # 构建（结果在 result/）
nix run .#vutronmusic     # 构建并运行
```

打包流程与官方 electron-builder 产物等价，但完全由 Nix 构建：

1. `vite build`（renderer / main / preload / workers）
2. `fix-taglib-wasm`（worker 内动态 import 需要 `"type": "module"`）
3. 按 Electron ABI 重建 `better-sqlite3`
4. 裁剪 devDependencies，安装桌面文件与图标

## 文件说明

| 文件              | 说明                                                        |
| ----------------- | ----------------------------------------------------------- |
| `flake.nix`       | flake 输出：packages / overlays / nixosModules / devShells  |
| `nix/electron.nix`| 固定版本的 Electron（含 headers，供原生模块编译）           |
| `nix/package.nix` | 应用打包（从源码构建）                                      |
| `nix/module.nix`  | NixOS 模块（`programs.vutronmusic.enable`）                 |
| `nix/devshell.nix`| 开发环境（`nix develop`）                                   |

## 维护说明

- **Electron 版本固定**：`nix/electron.nix` 固定为与 `yarn.lock` 一致的版本（当前 37.10.3）。
  升级 `package.json` 中的 electron 后，同步更新该文件中的 `version` 与两个哈希
  （zip / headers，构建失败信息中会给出正确哈希）。
- **yarn 依赖哈希**：`nix/package.nix` 的 `offlineCache` 与 `yarn.lock` 绑定；更新依赖后
  把 hash 改成 `lib.fakeHash` 构建一次，即可从报错中获得新哈希。
- **原生模块 ABI**：`better-sqlite3` 必须按 Electron ABI 编译。打包脚本使用仓库自带的
  `node-gyp`（读取 `npm_config_nodedir`，指向 Electron headers），并在构建期用
  `ELECTRON_RUN_AS_NODE=1 electron` 实际加载一次做自检。
  注意：不要用 nixpkgs 的 `node-gyp` 编译原生模块——它的包装脚本会把
  `npm_config_nodedir` 覆盖为 nixpkgs 的 Node，导致 V8 符号不匹配
  （表现为应用启动后 `[db init error] ... undefined symbol`）。

## 已知行为

- Nix 打包版本未使用 asar 封装，`app.isPackaged` 为 `false`，因此自动更新检查不会启用
  （对 Nix 管理的软件包这是期望行为）。
- Linux 沙箱：NixOS 默认允许非特权 user namespace（`security.allowUserNamespaces = true`），
  Electron 沙箱可直接工作；排错时可用 `--no-sandbox` 启动。
- Wayland：设置 `NIXOS_OZONE_WL=1`（且处于 Wayland 会话）时，启动器会自动附加
  `--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true`。
- 桌面文件 `StartupWMClass=VutronMusic`（Electron 的 WM_CLASS class 字段即 `app.name`）。
