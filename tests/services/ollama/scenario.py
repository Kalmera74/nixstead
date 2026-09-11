machine.wait_for_unit("ollama.service")
machine.wait_until_succeeds(
    "curl -fsS http://127.0.0.1:21434/api/version | jq -e .version"
)
machine.succeed("ss -ltn | grep -F '127.0.0.1:21434'")
