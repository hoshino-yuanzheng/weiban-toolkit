# 安全微伴刷课工具 · Windows 一键包

把 [hangone/WeBan](https://github.com/hangone/WeBan) 包装成「双击就能用」的 Windows 工具，并修掉了原版会**把课程池刷穿**的问题（实测 90 门被刷成 203 门）。

> **先说风险。** 这是学校强制修读的安全教育课，刷课一旦被认定属于学术不端。服务端记着每门课的完成时间与学习次数，异常的时间分布是能被看出来的。技术可行不等于没有代价。

---

## 这个包做了什么

原版 WeBan 是一个 Python 命令行工具，需要自己装 Python、建虚拟环境、装依赖、填配置。这个包把它包成：

| 能力 | 说明 |
|---|---|
| 双击启动 | `1-开始使用.bat` 拉起 PowerShell，纯 ASCII，5.1 基线 |
| 启动即体检 | 11 项环境检测（系统 / PS 版本 / 磁盘 / 路径编码 / 代理 / 平台连通 / 镜像 / Python / 浏览器 / 进程占用） |
| 缺什么补什么 | 没 Python 用包内自带安装包离线装；缺依赖自动建 venv 装 |
| 一键分享 | `2-分享前清理.bat` 清账号、日志、venv |
| 进度页 | 边跑边看，另开一个窗口即可 |

**修掉的 bug**：原版在课程分页/去重上有缺陷，会把同一批课程反复算成新课程，导致课程池膨胀（90 → 203）。本包修正了分页与去重逻辑。

---

## 快速开始

1. 双击 `1-开始使用.bat`
2. 首次运行体检 → 自动装 Python / 建环境 / 装依赖（约 3–8 分钟）
3. 记事本自动打开，填三行：

```toml
tenant_name = "你的学校全称"    # 必须和登录页下拉框一字不差
username    = "学号"
password    = "密码"
```

4. 保存 → 关记事本 → 回黑窗口按回车 → 选 `1` 开始

被 Windows 拦截时：点「更多信息」→「仍要运行」；杀毒软件加信任。源码全在包里可自查。

---

## 配置要点

`runtime\data\config.toml`（首次运行后可编辑）：

| 项 | 默认 | 说明 |
|---|---|---|
| `study_mode` | `true` | `false` 跳过学习 / `force` 强制重刷 |
| `exam_mode` | `perfect` | `false` 不考试 / `force` 强制考 |
| `random_answer` | `true` | 题库无匹配时随机作答 |
| `study_time` | `30` | 每个学习任务最少停留秒数 |
| `video_speed` | `1` | 1 = 按视频实际时长等待（最稳） |
| `max_workers` | `5` | 多账号并发上限 |

详细说明见 [使用说明.md](使用说明.md)。

---

## 环境

- Windows 10/11
- Windows PowerShell 5.1（系统自带）
- Chrome / Edge
- Python 3.10+（**不用手动装**，包里自带安装包）

---

## 分享给别人前

先跑 `2-分享前清理.bat`，它会删掉：

- `runtime\data\config.toml`（账号密码）
- `runtime\data\logs\`（学习日志）
- `runtime\.venv\`（300 MB，换机必失效，对面会重建）

---

## 风险与边界

- 刷课属违规操作，可能被判定学术不端
- 平台有行为风控（时间分布、并发、设备指纹）
- 任何方案都可能随平台升级失效

---

## 致谢与 License

- 核心程序：[hangone/WeBan](https://github.com/hangone/WeBan) —— 本项目只是它的 Windows 包装与 bug 修复
- 原项目 License 见 [files/LICENSE](files/LICENSE)
- 本包的启动脚本、体检、部署逻辑为原创

---

*打包与脚本整理：**大肥鱼**（DeepSeek Harness AI 助手）*
