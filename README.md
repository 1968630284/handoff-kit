# handoff-kit · 交接包

[![CI](https://github.com/1968630284/handoff-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/1968630284/handoff-kit/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/1968630284/handoff-kit?display_name=tag)](https://github.com/1968630284/handoff-kit/releases/latest)
[![License](https://img.shields.io/github/license/1968630284/handoff-kit)](LICENSE)

[English](README.en.md) | **简体中文**

> 换 agent、换会话，最贵的不是重新写代码，是重新解释一遍「做到哪了、什么不能动」。
> 一条命令把事实和停点打包，再给下一个 agent 一段可以直接粘贴的恢复语。

## 它解决什么

多轮 agent 协作里，上下文一丢，接手的人只能从零开始问：做到哪了？下一步干什么？哪些文件不许碰？
口头交接靠自觉，文档交接靠维护，最后都会过期。

这个工具把交接拆成两半：

- **事实自动采集**：git 分支 / HEAD / 未提交改动、顶层结构、时间、环境
- **人只写三句话**：停点、待办、约束（写在 `.handoff/notes.md`）

`pack` 一次生成一包，包含：

| 文件 | 用途 |
| --- | --- |
| `BOOT.md` | 恢复语，直接粘给下一个 agent |
| `HANDOFF.md` | 给人看的完整交接（事实 + 笔记） |
| `facts.json` | 机器可读的事实快照 |
| `notes.md` | 你写的交接笔记副本 |
| `manifest.json` | 包清单（id、时间、git、文件大小） |

`check` 会拦下两种情况：包里缺文件、笔记里混进了疑似密钥。

## 30 秒上手

```powershell
.\handoff.ps1 init
# 编辑 .handoff\notes.md：停点 / 待办 / 约束，各写一行也行

.\handoff.ps1 pack -Note "48 号核心层做完，等验收"
.\handoff.ps1 boot          # 复制输出，粘给下一个 agent
```

`boot` 输出长这样：

```
# 恢复语（直接粘给接手的 agent）

你在接手项目「demo」。先读同目录下的 HANDOFF.md，再按下面的停点继续。

- 路径：D:\work\demo
- 版本：分支 `main`，HEAD `abc1234 修掉状态机空转`，脏文件 2 个
- 生成时间：2026-11-15 20:10:00

## 上次停点
改到 40_app.ps1 的状态机，下一步跑回归。

## 硬约束
- 不要改总线协议

## 规矩
1. 先复述你读到的「停点 / 待办 / 约束」，确认无误再动手。
2. 不确定的事先问，不要猜着改。
3. 每完成一步就更新 .handoff\notes.md，下次交接靠它。
```

## 命令

| 命令 | 作用 |
| --- | --- |
| `init` | 初始化 `.handoff/` 与笔记模板 |
| `pack [-Note 一句话]` | 采集事实 + 合入笔记，生成交接包 |
| `boot [-Json]` | 打印最新包的恢复语 |
| `list` | 列出所有交接包（时间、体积、备注） |
| `check` | 检查最新包是否完整、有无疑似密钥 |

公共参数：`-Root <项目目录>`，默认当前目录。

## 为什么不是再写一份文档

文档依赖人持续维护，交接时往往已经过期。这里把能机器采集的部分自动采掉，人只需要写三个小标题；每包是独立快照，不覆盖历史，也不需要同步服务。

## 设计取舍

- **无服务端、无依赖**：`.handoff/` 跟着项目走，复制目录就带走了交接记录
- **不总结对话**：只固化「可验证的事实 + 人的三句话」，避免生成一段看似合理实则过期的小结
- **git 可选**：没有仓库也能打包，只是少版本信息
- **不做加密**：`check` 只做最低限度的密钥模式扫描，真正的密钥仍应放在环境变量里
- **不自动清理**：包按时间戳存放，删不删由你决定

## 边界

- 需要 Windows PowerShell 5.1+ 或 PowerShell 7
- 不解析源码，不生成项目摘要
- 恢复语是给 agent 的提示，不保证任何模型一定遵守

## 目录

```
handoff.ps1             命令行入口
tests/Handoff.Tests.ps1 Pester 用例（9 例）
```

## License

MIT
