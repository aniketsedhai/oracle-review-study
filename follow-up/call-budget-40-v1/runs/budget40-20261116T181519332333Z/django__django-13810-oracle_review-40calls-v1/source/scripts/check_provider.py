"""Check model availability and remaining credit without displaying credentials."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key-file", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    key = os.environ.get("DEEPSEEK_API_KEY", "")
    if args.key_file:
        from dotenv import dotenv_values
        key = dotenv_values(args.key_file).get("DEEPSEEK_API_KEY", "")
    if not key:
        raise SystemExit("No API key supplied")

    def fetch(path):
        request = urllib.request.Request("https://api.deepseek.com/" + path,
                                         headers={"Authorization": "Bearer " + key})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except Exception as error:
            raise SystemExit(f"Provider check failed ({type(error).__name__}); response withheld") from None

    models, balance = fetch("models"), fetch("user/balance")
    report = {"checked_utc": datetime.now(timezone.utc).isoformat(),
              "models": sorted(item["id"] for item in models.get("data", [])),
              "credit_available": bool(balance.get("is_available")),
              "balances": [{key: item.get(key) for key in ("currency", "total_balance")}
                           for item in balance.get("balance_infos", [])]}
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    if "deepseek-flash" not in report["models"] or not report["credit_available"]:
        raise SystemExit("Required model or credit unavailable")


if __name__ == "__main__":
    main()
