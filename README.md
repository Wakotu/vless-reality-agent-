# A Script to Generate sing-box config

config generation command

```bash
./gen-singbox-vless-reality.sh \
  --server-address <public_ip> \
  --local-port 21807 \
  --public-port <public_port> \
  --server-name tesla.com
```

sing-box run command:

```bash
nohup sing-box run -c config.json >/tmp/sing-box.log 2>&1 &
```

