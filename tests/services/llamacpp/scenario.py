machine.wait_for_unit("llama-cpp.service")
machine.wait_until_succeeds(
    "curl -fsS http://127.0.0.1:28084/health | jq -e '.status == \"ok\"'"
)
machine.succeed("ss -ltn | grep -F '127.0.0.1:28084'")
