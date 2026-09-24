- feat(ebpf): :fire: 集成eBPF透明代理支持并新增相关管理功能
---
- feat(restore): :sparkles: #34 添加代理配置备份与还原功能
- 新增 RestoreCubit 管理还原状态，还原后自动刷新代理配置列表
- ProxyConfigData 新增 toBytes/fromBytes 方法，支持配置文件读写
- 设置页面新增备份/还原按钮，使用 file_picker 保存与读取配置文件
- 备份失败、还原成功/失败均显示对应提示信息
- 中英文国际化资源补充备份与还原相关文案
- 事件目录按 language/theme/restore 模块拆分，规范代码结构
- feat(ui): :sparkles: 根据操作切换代理配置页面标题
- 添加代理时显示"添加代理"，修改配置时显示"修改配置"
- fix(ui): :bug: 修正UI相关的问题和优化初始化数据逻辑
- chore(android): :arrow_up: 优化仓库镜像与升级依赖版本
- 构建脚本新增阿里云/华为云 Maven 镜像，解决 Maven Central 403 问题
- connectivity_plus 升级至 7.3.1，flutter_lints 升级至 6.0.0
- com.android.application 插件升级至 9.3.3
- docs(readme): :memo: 更新开发章节，添加继续开发提示
---
- feat(appproxy): :sparkles: 应用安装/卸载时自动刷新配置列表
- chore(deps): 升级依赖版本
- device_info_plus 升级至 13.2.0
- package_info_plus 升级至 10.2.1
- app_settings 升级至 9.0.0
- build(android): 升级构建工具链并清理打包警告
- AGP 升级至 9.3.2，KGP 升级至 2.4.10，迁移至 Built-in Kotlin
- Gradle 升级至 9.7.1
- tun2socks 同步上游最新代码，gomobile 编译新增 -ldflags="-s -w" 剥离调试符号
- 更新应用版本号至 0.2.8+28
---
- fix(vpn): :bug: #46 修复 VPN 中断后无法抢占接口
- chore(android): 升级依赖版本及优化构建配置
- 将 ktor 依赖库版本从 3.4.1 升级至 3.4.2
- 将 kotlin-sdk-server 版本从 0.9.0 升级至 0.11.1
- 禁用 android.enableJetifier 以优化构建性能
- 启用 Gradle 守护进程、并行构建、按需配置及缓存提升构建速度
- 开启 Kotlin 增量编译
- 在启动 VPN 逻辑中添加权限检查调用
- 更新应用版本号至 0.2.7+27
---
- feat(android): :ambulance: 启动申请通知和 vpn 权限不再走用时申请逻辑
- fix(McpServer): :fire: 修复 McpServer 后台无法访问
- fix(mcpserver): 修改用户名密码长度校验限制
- 将用户名密码长度限制从10修改为30
---
- feat(appproxy): #43 支持 MCP 服务远程调用
- 在配置文件中新增 MCP 服务支持远程调用
- 增加 mcpServers 配置示例，支持 HTTP 流式访问并带有授权头
- 更新 pubspec.yaml 描述，注明支持 MCP 调用
- README 增加 MCP 远程调用使用说明和示例配置
- 补充相关截图，展示 MCP 功能界面
- **必须先授权VPN启动权限**
- 修复更新代理配置校验错误
```shell
{
  "mcpServers": {
    "appproxy-mcp": {
      "type": "http",
      "url": "http://192.168.0.10:12345/mcp",
      "headers": {
        "Authorization": "Bearer appproxy"
      }
    }
  }
}
```