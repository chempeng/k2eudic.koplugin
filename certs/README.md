# CA 证书包

插件使用此证书包验证欧路 API 服务器的 HTTPS 证书链，并另外校验域名。随插件提供统一的信任根，使设备无需另行配置系统证书路径。这些是公开证书，可以随项目发布；当前实现依赖此文件，请保留整个 `certs/` 目录。

`cacert.pem` 来自 [curl 的 Mozilla CA Extract](https://curl.se/docs/caextract.html)，下载地址为 <https://curl.se/ca/cacert.pem>。数据快照日期为 2026-09-25；文件头保留了来源与生成信息。

Mozilla CA 数据采用 MPL-2.0，许可证全文见 `MPL-2.0.txt`。原始数据位于 [Mozilla NSS certdata.txt](https://raw.githubusercontent.com/mozilla-firefox/firefox/refs/heads/release/security/nss/lib/ckfw/builtins/certdata.txt)。此目录的数据许可证与插件 Lua 代码的 GPL-3.0-or-later 分开适用。

维护者可从上述 HTTPS 来源更新证书包，并同步更新此日期。不要把服务器叶证书或自签名证书随意加入此文件。
