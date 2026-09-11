base = "http://127.0.0.1:23100"

machine.wait_for_unit("loki.service")
machine.wait_until_succeeds(
    "curl --fail --silent --max-time 10 " + base + "/ready", timeout=180
)
machine.succeed("ss -ltn | grep -F '127.0.0.1:23100'")
