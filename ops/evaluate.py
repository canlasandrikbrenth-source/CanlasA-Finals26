#!/usr/bin/env python3
"""Runs the labelled test questions, records a pass rate and emails the result."""
import json
import os
import subprocess
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(os.environ.get("ASKTALA_ROOT", "/opt/asktala"))
URL = os.environ.get("GATEWAY_URL", "http://127.0.0.1:8080/v1/chat/completions")
DELAY = float(os.environ.get("EVAL_DELAY", "3"))
RUNTIME_ENV = Path("/run/asktala/app.env")


def settings():
    values = {}
    for path in (Path("/etc/asktala.env"), RUNTIME_ENV):
        if path.exists():
            for line in path.read_text().splitlines():
                name, _, value = line.partition("=")
                values[name] = value
    values.update({k: v for k, v in os.environ.items() if k in ("GATEWAY_TOKEN", "BUCKET", "AWS_REGION", "TOPIC_ARN")})
    return values


def ask(question, token):
    body = json.dumps({"messages": [{"role": "user", "content": question}], "stream": False}).encode()
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json", "X-Source": "eval"}
    request = urllib.request.Request(URL, data=body, headers=headers)
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)["choices"][0]["message"]["content"] or ""


def normalise(text):
    return text.lower().replace("’", "'")


def score(item, answer):
    return any(normalise(option) in normalise(answer) for option in item["pass_any"])


def aws(*args):
    subprocess.run(["aws", *args], check=True, stdout=subprocess.DEVNULL)


def main():
    env = settings()
    items = json.loads((ROOT / "tests/questions.json").read_text())
    results = []
    for item in items:
        try:
            answer = ask(item["question"], env["GATEWAY_TOKEN"])
            passed = score(item, answer)
        except Exception as exc:
            answer, passed = f"ERROR: {type(exc).__name__}", False
        results.append({**item, "answer": answer, "passed": passed})
        time.sleep(DELAY)

    passed = sum(r["passed"] for r in results)
    rate = round(100 * passed / len(results), 1)
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    trigger = "systemd-timer" if os.environ.get("INVOCATION_ID") else "manual"
    misses = [r["id"] for r in results if not r["passed"]]
    print(f"{stamp} eval trigger={trigger} passed={passed}/{len(results)} rate={rate} misses={','.join(misses) or 'none'}", flush=True)

    if not env.get("BUCKET"):
        print(json.dumps(results, indent=1))
        return
    region = env["AWS_REGION"]
    report = {"timestamp": stamp, "trigger": trigger, "passed": passed, "total": len(results), "rate": rate, "results": results}
    path = Path("/tmp/asktala-eval.json")
    path.write_text(json.dumps(report, indent=1))
    aws("s3", "cp", "--region", region, str(path), f"s3://{env['BUCKET']}/evaluations/{stamp}.json")
    aws("cloudwatch", "put-metric-data", "--region", region, "--namespace", "AskTala", "--metric-name", "TestPassRate", "--unit", "Percent", "--value", str(rate))
    message = f"Ask Tala scheduled test at {stamp}: {passed}/{len(results)} passed ({rate}%). Missed: {', '.join(misses) or 'none'}."
    aws("sns", "publish", "--region", region, "--topic-arn", env["TOPIC_ARN"], "--subject", f"Ask Tala test pass rate {rate}%", "--message", message)


if __name__ == "__main__":
    main()
