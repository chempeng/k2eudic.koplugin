# K2Eudic · KOReader to 欧路生词本

[English](README.en.md) | 简体中文

**长按英文单词，点击「添加至欧路生词本」，保存到你指定的生词本。**

支持单词和短语，使用欧路官方 API，阅读器上无需安装欧路 App。

界面跟随 KOReader 的语言设置：中文环境显示简体中文，其他语言环境显示英文。更改语言后重启 KOReader 即可。

<p>
  <img src="images/select-word.png" width="340" alt="长按选词后，菜单中出现添加至欧路生词本按钮">
  <img src="images/word-added.png" width="340" alt="单词已提交至 kindle 生词本">
</p>

## 1. 安装并填写授权

下载并解压插件，确保文件夹名为 **`k2eudic.koplugin`**。

在电脑上登录[欧路授权页面](https://my.eudic.net/OpenAPI/Authorization)，复制个人授权信息。在插件文件夹内新建名为 **`KEY`** 的 UTF-8 纯文本文件，与 `main.lua` 同级，只写一行：

```text
NIS 你的授权令牌
```

只填写令牌也可以。文件名必须是大写 `KEY`，**没有 `.txt` 扩展名**。

将整个插件文件夹放入设备的 KOReader `plugins/` 目录，然后重启 KOReader。正确路径为：

```text
koreader/plugins/k2eudic.koplugin/main.lua
koreader/plugins/k2eudic.koplugin/KEY
```

Kindle 通常为 `koreader/plugins/`，Kobo 为 `.adds/koreader/plugins/`。首次启动会自动导入 `KEY`；如插件未出现，请在工具菜单的「插件管理」（部分版本位于「更多工具」下）中启用「欧路生词本 (K2Eudic)」并重启。

**也可手动输入：**不创建 `KEY`，安装后在「欧路生词本 → 授权信息」中填写即可。

## 2. 选择生词本

设备联网后，打开工具菜单中的 **「欧路生词本」**（部分版本位于「更多工具」下），点击 **「目标生词本」**，从列表中选一个英语生词本。

如需新建生词本，请先在欧路中创建，再回来获取列表。

## 3. 长按添加

打开英文书，在阅读设置的 **「长按文本」** 中：

- 选择 **「弹出菜单 / Ask with popup dialog」**。
- 取消 **「选择单个词时查词典 / Dictionary on single word selection」**。

长按单词，点击 **「添加至欧路生词本」**。出现「已提交」后，可在欧路中同步查看；已有单词会自动跳过。

## 常用功能

- **添加前编辑单词**：手动调整选词，例如把 `running` 改为 `run`。
- **手动添加单词**：直接输入单词或短语。
- **重试上次失败的添加**：网络失败后手动重试，仅保留当前会话的最近一次失败记录。

## 授权文件说明

`KEY` 适合在电脑上配置后整体复制到阅读器。**已有授权时不会自动覆盖**；更换 `KEY` 后，点击「从 KEY 导入授权」即可主动更新。更换授权后需重新选择生词本。

导入后授权会保存在 KOReader 设置中，**可以删除设备上的 `KEY`**。点击「清除已保存的授权」后，即使 `KEY` 仍在，重启也不会自动重新导入；需要时可再次手动导入。

请勿分享或上传自己的 `KEY`、`settings/k2eudic.lua` 及其备份。仓库已忽略 `KEY`，但手动压缩分享前仍应移除它。

需要网络和可选中文字的书籍；无文字层的扫描 PDF 不能直接选词。已在 KOReader v2026.07.1 桌面版完成真实欧路账号加词验证。

代码：[GPL-3.0-or-later](LICENSE)；随附 CA 证书：[MPL-2.0](certs/MPL-2.0.txt)。
