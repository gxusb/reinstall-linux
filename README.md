
# reinstall-linux

本仓库用于一键重装 Linux 系统（Debian/Ubuntu/CentOS）和管理 VPS 交换内存（Swap）。

## InstallNET.sh 用法

- 支持通过网络重装 Debian、Ubuntu、CentOS。
- 支持自定义 root 密码、镜像源、网络参数、架构等。

### 典型用法

```bash
bash <(wget -qO- 'https://raw.githubusercontent.com/gxusb/reinstall-linux/master/InstallNET.sh') -d 12 -p 'linux12345'
```

### 国内镜像示例

- 阿里云镜像源: <https://mirrors.aliyun.com/debian>
- `--ip-dns`: 223.5.5.5

```bash
bash <(wget -qO- 'https://git-proxy.gxusb.com/https://raw.githubusercontent.com/gxusb/reinstall-linux/master/InstallNET.sh') --mirror 'https://mirrors.aliyun.com/debian' --ip-dns '223.5.5.5' -d 12 -p 'linux12345'
```

### 关键参数

- `-d/--debian`、`-u/--ubuntu`、`-c/--centos` 选择发行版及版本
- `-p/--password` 设置 root 密码
- `--mirror` 指定镜像源
- `--ip-addr`/`--ip-mask`/`--ip-gate`/`--ip-dns` 配置静态网络
- 详见脚本内 Usage 输出

> 自动检测并处理 GRUB、磁盘、网络等环境差异。

---

## swap.sh 用法

- 一键添加、删除、查看 Swap，自动推荐大小，支持 OpenVZ 检测。
- 交互式菜单，需 root 权限。

```bash
bash <(curl -sSL 'https://raw.githubusercontent.com/gxusb/reinstall-linux/master/swap.sh')
```

### 国内加速

```bash
bash <(curl -sSL 'https://git-proxy.gxusb.com/https://raw.githubusercontent.com/gxusb/reinstall-linux/master/swap.sh')
```
