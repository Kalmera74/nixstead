from datetime import timedelta


base = "http://127.0.0.1:28207"
library = "/var/lib/kiwix-runtime-fixture/library.xml"

machine.wait_for_unit("kiwix-serve.service")
machine.wait_for_open_port(28207)
machine.wait_until_succeeds(
    "curl -fsS --max-time 5 " + base + "/catalog/v2/entries >/dev/null",
    timeout=timedelta(seconds=60),
)
machine.succeed("grep -F '<library version=' " + library)
machine.succeed(
    "test $(systemctl show kiwix-library-refresh.service -p Result --value) = success"
)
machine.succeed("test $(systemctl show kiwix-serve.service -p NRestarts --value) = 0")
