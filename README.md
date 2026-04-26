# A Script to Generate sing-box config

## Prerequisites

Our command depends on `jq` and `sing-box` to run.

In Alpine Linux, you can install them with the following command:

```bash
apk add sing-box --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community
apk add jq wget bash
```

## Usage

config generation command

```bash
 wget https://raw.githubusercontent.com/Wakotu/vless-reality-agent-/refs/heads/main/gen-singbox-vless-reality.sh
chmod +x gen-singbox-vless-reality.sh
./gen-singbox-vless-reality.sh \
  --server-address <public_ip> \
  --local-port 23907 \
  --public-port <public_port> \
  --server-name tesla.com
```

sing-box run command:

```bash
sing-box check -c config.json
nohup sing-box run -c config.json >/tmp/sing-box.log 2>&1 &
```

