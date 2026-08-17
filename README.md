# 卡片 —— iOS 原生背卡 app

自用的间隔重复卡片 app。SwiftUI 写的，不上 App Store，自己签名装。

功能：多个牌组、SM-2 间隔重复、四档评分、批量导入（Quizlet 那种复制粘贴也能吃）、
公式截图当卡面、整体导出/恢复成一个 json 文件。

---

## 为什么要绕 GitHub

iOS 的 app 只能在 **macOS 上用 Xcode 编译**。Windows 上没有任何办法把 `.swift` 变成 `.ipa`。

GitHub Actions 提供免费的 macOS 机器。把这些代码传上去，它替你在云端 Mac 上编一遍，
吐出一个没签名的 `.ipa`，你下载下来自己签。全程不用碰 Mac。

---

## 第一步：传到 GitHub，让它编译

1. 注册 / 登录 GitHub，点右上角 **＋ → New repository**。
   - 名字随便，比如 `flashcards`
   - **选 Public**（公开仓库的 macOS 构建分钟数是免费的；私有仓库会烧掉每月额度）
   - 不要勾 "Add a README"
2. 建好以后，页面上有 **uploading an existing file** 的链接，点它。
3. 把本文件夹里的东西**全部**拖进去：
   ```
   .github/workflows/ios.yml
   project.yml
   Sources/App.swift
   Sources/Models.swift
   Sources/Views.swift
   README.md
   ```
   注意 `.github` 这个文件夹要保持目录结构。网页拖拽有时候会吞掉以点开头的文件夹，
   如果传不上去，就在仓库里手动 **Add file → Create new file**，
   文件名直接填 `.github/workflows/ios.yml`，把内容粘进去，GitHub 会自动建目录。
4. 传完自动就开始编了。点仓库上方的 **Actions** 标签，能看见一条正在跑的记录。
   第一次大概 5～10 分钟。
5. 跑完变成绿勾，点进去，页面最下面 **Artifacts** 里有 `FlashCards-ipa`，下载。
   下下来是个 zip，解压出来就是 `FlashCards.ipa`。

**要是变成红叉**：点进去看哪一步报错，把报错信息整段发我，我改代码再传一次。
第一次编译不过是常事，我这边没有 Mac，测不了。

---

## 第二步：签名装到手机

Windows 上用 **Sideloadly**（免费）：

1. 先装 Apple 官方的 **Apple Devices**（或者老版 iTunes），Sideloadly 要靠它认设备。
2. 去 sideloadly.io 下载安装。
3. 数据线连手机，手机上点「信任这台电脑」。
4. 打开 Sideloadly：
   - `IPA` 那一栏拖进 `FlashCards.ipa`
   - `Apple ID` 填你自己的（普通 Apple ID 就行，不用开发者账号）
   - 点 **Start**，中途会让你输 Apple ID 密码，输
5. 装完手机上会多一个图标，但**点开会提示不受信任**。
   去 `设置 → 通用 → VPN与设备管理`，找到你的 Apple ID，点「信任」。
6. 打开就能用了。

### 关于 7 天

免费 Apple ID 签出来的 app **7 天到期**，到期后打不开。
重签方法：手机连电脑，Sideloadly 里同样的操作再来一遍就行，**数据不会丢**
（数据存在 app 的沙盒里，重签是覆盖安装）。

不放心的话，去 app 里「备份 / 恢复 → 导出备份文件」，存一份到「文件」里。

免费账号同时最多签 3 个 app，这一点注意。

---

## 怎么用

- **批量导入**：进牌组 → 批量导入。两种模式：
  - *一行一张*：`顶点横坐标 | x = −b/(2a)`，分隔符用 Tab、竖线、逗号、破折号都认
  - *空行分隔*：第一行正面，后面是背面，卡之间空一行。
    从网页上整段复制下来的内容一般用这个
- **公式**：别打字，直接截图，编辑卡片时「加图片」。图片会压到宽 900 存起来
- **四档评分**：按钮上直接写着按下去之后下次什么时候再出现
- **备份**：牌组列表最底下

---

## 文件说明

| 文件 | 干嘛的 |
|---|---|
| `Sources/App.swift` | 入口 |
| `Sources/Models.swift` | 数据结构、SM-2 算法、存取、导入解析、图片压缩 |
| `Sources/Views.swift` | 全部界面 |
| `project.yml` | XcodeGen 的配置，云端靠它生成 Xcode 工程 |
| `.github/workflows/ios.yml` | 云端 Mac 的编译脚本 |

改文案、改颜色、改算法参数都在 `Models.swift` 和 `Views.swift` 里。
改完重新传一遍，Actions 会自动再编一个新的 ipa。
