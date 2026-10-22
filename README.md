# PortLens

macOS 菜单栏 USB-C / Thunderbolt 端口与充电诊断工具。原生 Swift + SwiftUI + IOKit，无第三方依赖，数据全部读取自本机 IORegistry，不联网、不上传。

> 定位：覆盖端口枚举、PD 协商、e-marker 线缆识别与显示链路诊断，并补齐更细致的端口归属与协商诊断。
> 仅支持 Apple Silicon（arm64），最低 macOS 13.0。

## 功能

**端口面板**
- 按真实物理端口逐一列出：USB-C 1/2/3、MagSafe、Thunderbolt 等
- 每口显示：连接状态、协商功率（PDO 档位）、实测电压/电流、e-marker 线缆身份
- 严格按物理口归属数据，不做跨口 fallback（空口不会被误报为"已接充电器"）

**线缆识别**
- e-marker 解析：厂商、型号、VID/PID、线缆能力（电流/速率/是否 240W EPR）
- USB-IF 认证库比对（内置 XID 数据库）
- 线缆指纹历史：插过的线缆自动建档，可回看

**协商诊断**
- 逐口分析供电合约是否达成、为何限流（线缆能力 / 适配器能力 / 端口上限）
- 扩展坞场景区分：坞自带 PD 输入口 vs 坞对外供电口

**显示诊断**
- 显示器链路：分辨率、刷新率、色深、HDR、DSC、带宽占用与瓶颈判断

**菜单栏**
- 三档图标模式：simple（纯电池）/ dynamic（电池 + 状态符号）/ wideBar（宽体色块）
- 状态符号按实际情况切换：插头（已接电源未充电）、闪电（充电中）、纯电池（放电）
- Widget Extension：桌面小组件同步展示端口与电量

## 构建

要求：macOS 13+，Swift 工具链（Xcode 或 Command Line Tools 均可），无需 Apple 开发者账户。

```bash
git clone <this-repo>
cd PortLens
./build.sh
```

产物默认输出到 `~/Desktop/PortLens.app`，可用环境变量改路径：

```bash
OUT_DIR=~/Applications ./build.sh
```

构建脚本会自动：编译主程序 → 编译 CLI 辅助程序 → 编译 Widget Extension → 生成图标 → 组装 .app → ad-hoc 签名。

版本号统一在 `build.sh` 顶部的 `APP_VERSION` 修改。

### 首次打开

应用未经 Apple 公证（ad-hoc 签名），首次启动请右键点击 → 打开，或在终端执行：

```bash
xattr -dr com.apple.quarantine ~/Desktop/PortLens.app
```

## CLI

```bash
~/Desktop/PortLens.app/Contents/Helpers/portlens
```

以纯文本输出当前所有端口的诊断结果，便于脚本化或远程排查。

## 项目结构

```
Sources/
  Models.swift             数据模型
  USBMonitor.swift         IORegistry 采集与端口发现
  Diagnostics.swift        端口诊断主逻辑
  ProModels.swift          Pro 层模型
  ProDataSources.swift     e-marker / PD / 供电数据源
  ProLogic.swift           协商诊断、线缆指纹、历史
  CableVendorDB.swift      线缆厂商库
  USBIFXIDDB.swift         USB-IF XID 认证库
  ThunderboltFabric.swift  Thunderbolt 拓扑
  DeviceIdentity.swift     设备名称推断
  DisplayDiagnostics.swift 显示链路诊断
  Views.swift              主界面
  ProViews.swift           Pro 面板
  ProIntegration.swift     Pro 与主界面桥接
  SettingsView.swift       设置
  CLI.swift                命令行入口
WidgetExtension/           桌面小组件
gen_icon.swift             图标生成
build.sh                   一键构建
```

## 免责声明

本项目为个人独立开发的非官方工具，与 Apple Inc. 无任何关联，未获其背书。所有硬件信息均来自系统公开接口（IOKit / IORegistry），不涉及任何私有 API 或逆向。诊断结果为工程参考，不构成硬件质保依据。

## License

**源码公开，非商业使用免费；商业使用需授权。**

- 许可协议：[PolyForm Noncommercial License 1.0.0](LICENSE)
- 允许（免费）：个人学习、研究、实验、测试、业余项目与兴趣开发；慈善组织、教育机构、公共科研机构、公共安全与卫生机构、环保组织、政府机构的使用
- 需授权（付费）：任何商业目的使用，包括收费产品集成、企业内部生产环境部署、对外提供付费服务或托管服务
- 商业授权请联系：**chengong2664@icloud.com**

> 说明：本许可限制使用领域，属于 **source-available（源码公开）**，并非 OSI 定义的开源许可。条款以 [LICENSE](LICENSE) 中的英文原文为准，中文表述仅为便于理解。
