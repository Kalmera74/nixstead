from datetime import timedelta


base = "http://127.0.0.1:28208"

machine.wait_for_unit("stirling-pdf.service", timeout=timedelta(seconds=300))
machine.wait_until_succeeds(
    "curl -fsS --max-time 5 " + base + "/", timeout=timedelta(seconds=300)
)
machine.succeed("test $(systemctl show stirling-pdf.service -p NRestarts --value) = 0")
machine.succeed("ss -ltn | grep -F '127.0.0.1:28208'")
