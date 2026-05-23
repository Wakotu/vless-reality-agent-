# AGENTS.md

## DDNS 系统关键对象与关系

### 对象

| 对象 | 角色 |
|------|------|
| **Domain** | 对外暴露的固定名称，用户/客户端通过它访问服务 |
| **Dynamic IP** | Host 的公网地址，会随时间/重拨号变化 |
| **Host** | 运行服务的机器（VPS/路由器），持有动态 IP |
| **DDNS Client** | 运行在 Host 上的客户端进程，检测 IP 变化，调用 Provider API 更新 DNS 记录 |
| **DDNS Provider** | 提供 DNS 托管和 API 的服务商，接受更新请求，修改 A/AAAA 记录 |

### 关系

- **Host** 持有 **Dynamic IP**（1:1）
- **Domain** 通过 A 记录绑定到 **Dynamic IP**（1:1）
- **DDNS Client** 运行在 **Host** 上，检测到 Dynamic IP 变化时调用 **DDNS Provider** API，将 Domain 的 A 记录更新为新的 Dynamic IP
- **DDNS Provider** 收到请求后修改 DNS 记录，实现 **Domain → 新 IP** 的重新绑定

### 数据流

```
Host(Dynamic IP) → DDNS Client → DDNS Provider API → DNS Record(Domain → IP)
                                                              ↓
                                                          Client 解析 Domain → 最新 IP
```
