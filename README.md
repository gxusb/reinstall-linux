# reinstall-linux

## 安装 debian 12
- 密码 `linux12345`

```bash
bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/gxusb/reinstall-linux/master/InstallNET.sh') -d 12 -p 'linux12345'
```
- 国内镜像
  - 阿里云镜像源: https://mirrors.aliyun.com/debian
  -  `--ip-dns`: 223.5.5.5
```bash
bash <(wget --no-check-certificate -qO- 'https://git-proxy.gxusb.com/https://raw.githubusercontent.com/gxusb/reinstall-linux/master/InstallNET.sh') --mirror 'https://mirrors.aliyun.com/debian' --ip-dns '223.5.5.5' -d 12 -p 'linux12345' 
```


## 设置交换内存

```bash
bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/gxusb/reinstall-linux/master/swap.sh')
```
- 国内
```bash
bash <(wget --no-check-certificate -qO- 'https://git-proxy.gxusb.com/https://raw.githubusercontent.com/gxusb/reinstall-linux/master/swap.sh')
```
