## RouterOS Setup

Full manual from original creator available on [habr.ru](https://habr.com/ru/articles/838452/) and [web.archive.org](https://web.archive.org/web/*/https://habr.com/ru/articles/838452/).

---

```routeros
/interface/bridge add name=byedpi-bridge port-cost-mode=short
/ip/address add address=192.168.254.1/24 interface=byedpi-bridge network=192.168.254.0
/interface/veth add address=192.168.254.2/24 gateway=192.168.254.1 name=byedpi-tunnel
/interface/bridge/port add bridge=byedpi-bridge interface=byedpi-tunnel
```

### Docker Registry & Container

**Change path `/usb1` to your actual path!**

Also, I highly recommend to find best for your case run command (`cmd`), I use for this mobile [ByeByeDPI](https://github.com/romanvht/ByeByeDPI) application, its scanner is one of the best for scanning DPI restrictions that I have found.

```routeros
/container/config set registry-url=https://ghcr.io tmpdir=/usb1/docker/pull
/container/add remote-image=ghcr.io/unknown-gd/byedpi-hev-socks5-tunnel:latest interface=byedpi-tunnel cmd="--disorder 1 --auto=torst --tlsrec 1+s" root-dir=/usb1/docker/byedpi-tunnel start-on-boot=yes
```

### Routing Table

````routeros
/routing/table add disabled=no fib name=bdpit-mark
/ip/route add disabled=no distance=1 dst-address=0.0.0.0/0 gateway=192.168.254.2%byedpi-bridge routing-table=bdpit-mark scope=30 target-scope=10 comment="ByeDPI Tunnel"
```

### Route address list over ByeDPI Tunnel

```routeros
/ip firewall mangle add action=mark-routing chain=prerouting comment="List DNS FWD route to ByeDPI Tunnel" dst-address-list=blocked-addresses in-interface-list=LAN new-routing-mark=bdpit-mark passthrough=no
````

### Run container and enjoy, good luck!

```routeros
/container start [find interface=byedpi-tunnel]
```
