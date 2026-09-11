import shlex


start_all()
peer.wait_for_unit("dnsmasq.service")
peer.wait_for_open_port(8000)

# Build disposable private configuration inside the guests. Only public keys
# cross the test driver while the runtime files exercise the actual module.
client.succeed("umask 077; wg genkey > /run/app.key; wg genkey > /run/work.key")
peer.succeed("umask 077; wg genkey > /run/peer.key")
app_public = client.succeed("wg pubkey < /run/app.key").strip()
work_public = client.succeed("wg pubkey < /run/work.key").strip()
peer_public = peer.succeed("wg pubkey < /run/peer.key").strip()

peer.succeed(
    "ip link add wg0 type wireguard; ip addr add 10.77.0.1/24 dev wg0; ip addr add 10.88.0.1/24 dev wg0; ip -6 addr add fd77::1/64 dev wg0; ip -6 addr add fd88::1/64 dev wg0"
)
peer.succeed(
    f"wg set wg0 private-key /run/peer.key listen-port 51820 peer {app_public} allowed-ips 10.77.0.2/32,fd77::2/128 peer {work_public} allowed-ips 10.88.0.2/32,fd88::2/128; ip link set wg0 up"
)

for name, address, allowed in [
    ("apps", "10.77.0.2/24,fd77::2/64", "0.0.0.0/0,::/0"),
    ("work", "10.88.0.2/24,fd88::2/64", "10.88.0.0/24,fd88::/64"),
]:
    key_file = "app" if name == "apps" else "work"
    dns = "DNS=10.77.0.1\n" if name == "apps" else ""
    contents = f"Address={address}\n{dns}[Peer]\nPublicKey={peer_public}\nEndpoint=192.168.1.2:51820\nAllowedIPs={allowed}\nPersistentKeepalive=5\n"
    client.succeed(
        "umask 077; { printf '[Interface]\\nPrivateKey='; "
        + f"cat /run/{key_file}.key; printf %s "
        + shlex.quote(contents)
        + f"; }} > /run/{name}.generated.conf"
    )

client.succeed("python /etc/wireguard-credentials.py install-source")
client.succeed("/run/current-system/bin/switch-to-configuration test >/dev/null")
client.succeed("systemctl start wg-quick-work.service vpn-probe.service")
client.wait_for_unit("wg-quick-work.service")
client.wait_for_unit("vpn-probe.service")
client.wait_until_succeeds("curl -fsS --max-time 3 http://10.88.0.1:8000/ > /dev/null")
pid = client.succeed("systemctl show vpn-probe.service -p MainPID --value").strip()
probe = f"nsenter -t {pid} -n -m "
client.wait_until_succeeds(
    probe + "curl -fsS --max-time 3 http://fixture.test:8000/ > /dev/null"
)
client.succeed(probe + "dig +tcp +short fixture.test @10.77.0.1 | grep -F 10.77.0.1")
assert client.succeed("wg show work public-key").strip() == work_public
assert (
    client.succeed("ip netns exec apps wg show apps0 public-key").strip() == app_public
)
