# Siri 与快捷指令

Nexora 提供五个 App Intents：连接、断开连接、启用 TUN、停用 TUN、选择代理节点。

## 中文示例

- “连接 Nexora”或“打开 Nexora”。
- “断开 Nexora”或“关闭 Nexora”。
- “启用 Nexora 的 TUN”。
- “停用 Nexora 的 TUN”。
- “切换 Nexora 的节点”，随后选择节点。
- “将 Nexora 的节点切换为 [完整节点名]”。

这些短语也有英文版本。在 macOS 的“快捷指令”App 中搜索 Nexora，可以把操作加入自己的快捷指令；给快捷指令起一个好记的名字后，也可对 Siri 说这个名字。

## 行为

- 所有动作使用应用界面的同一个 AppStore、核心与串行切换队列。动作会打开 Nexora；连接开关是幂等设置，重复要求开启不会反而断开。
- TUN 首次启用仍由 macOS 请求管理员授权，Siri 不绕过授权。断开连接时，TUN 动作只设置下一次连接的偏好，回复会明确说明。
- 节点列表来自当前选中配置的手动选择器。同名节点会显示所属代理组供选择；AppEntity 查询不启动核心、不申请 TUN 权限，也不启用系统代理。
- 首次安装后需连接或刷新节点一次，以填充节点目录。随后即使应用重启，也可离线读取该配置的目录。目录只保存配置 ID、代理组和节点名称，不保存节点密码或服务器配置。
- 旧快捷指令的节点 ID 绑定原配置和代理组。换配置、删除节点后不会猜测一个同名替代节点，需重新选择。
- 选择节点不会主动连接 VPN。断开时若 TUN 偏好已启用，需要先连接再切节点，以避免仅为切节点而暗中启动特权隧道。
- Siri 能否直接识别某个口语表达由系统语言、Siri 状态与识别结果决定。预置短语与快捷指令中的可选节点是明确入口。

## 构建与发现

SwiftPM 编译后，打包流程还需要提取 App Intents 常量元数据、生成 `Metadata.appintents`、复制中英文主包资源，再签名。普通 `swift build` 本身不能证明 Siri 已经发现动作。

应用启动与节点目录变化时会调用 `updateAppShortcutParameters()` 更新系统参数建议。

参考：[App Intents](https://developer.apple.com/documentation/appintents/appintent)、[AppEntity](https://developer.apple.com/documentation/appintents/appentity)、[EntityQuery](https://developer.apple.com/documentation/appintents/entityquery)。

## 本次验证（2026-11-01）

- 临时用户目录中的完整 `swift test`：264 项通过，其中新增 14 项自动化回归。
- 显式 `swift build` 与 Release 打包通过。
- 安装包提取出 5 个动作、5 个 App Shortcuts 和节点实体；中英文短语训练通过。
- 本机“快捷指令”实际发现全部五个 Nexora 动作，并成功提供当前配置的动态节点列表。
- `shortcuts run` 实际执行连接与选择当前节点均退出 0；节点验证沿用原节点。
- 保留一个只有连接动作的“连接 Nexora”快捷指令，移除验证时追加的节点切换动作。
- 已安装到 `/Applications/Nexora.app`，主程序与 staged 版本 SHA-256 一致，深层严格签名检查通过。
- 未使用麦克风进行语音识别测试；TUN 授权成功/拒绝及实际设置语义由隔离回归覆盖，本次未主动开启用户的真实 TUN。
