"""Ask Tala gateway: sits between LibreChat and the external model.

It adds the knowledge base from S3, reads the model key from Parameter Store,
stops personal data leaving the account, and logs one JSON line per request.
"""
import asyncio
import hashlib
import json
import os
import re
import secrets
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import boto3
import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse

BASE_URL = os.environ.get("MODEL_BASE_URL", "").rstrip("/")
MODEL = os.environ.get("MODEL_NAME", "")
VERSION = os.environ.get("APP_VERSION", "dev")
TOKEN = os.environ.get("GATEWAY_TOKEN", "")
CONTENT_DIR = os.environ.get("CONTENT_DIR", "")
KB_BUCKET = os.environ.get("KB_BUCKET", "")
KB_PREFIX = os.environ.get("KB_PREFIX", "content/")
KEY_PARAM = os.environ.get("MODEL_KEY_PARAM", "")
CACHE_SECONDS = 300
MAX_TOKENS = 600
PROMPT = Path(__file__).with_name("system_prompt.txt").read_text()

PII_PATTERNS = [
    re.compile(r"[\w.+-]+@(?![\w-]+\.example\b)[\w-]+\.[\w.-]+"),
    re.compile(r"(?<!\d)(?:\+?63|0)9\d{2}[\s-]?\d{3}[\s-]?\d{4}(?!\d)"),
    re.compile(r"(?<!\d)\d{10,}(?!\d)"),
]
PII_REPLY = (
    "Please don't share personal details such as email addresses, phone numbers or ID "
    "numbers here. Ask your question without them."
)
NO_KB_REPLY = "The helpdesk information is unavailable right now. Please try again later."

app = FastAPI()
client = httpx.AsyncClient(timeout=httpx.Timeout(55.0, connect=5.0))
_key = {"value": "", "at": 0.0}
_kb = {"text": "", "version": "none", "at": 0.0}


def log(**fields):
    stamp = datetime.now(timezone.utc).isoformat(timespec="milliseconds")
    print(json.dumps({"ts": stamp, **fields}, ensure_ascii=False), flush=True)


def fetch_key():
    if os.environ.get("MODEL_API_KEY"):
        return os.environ["MODEL_API_KEY"]
    if time.time() - _key["at"] > CACHE_SECONDS or not _key["value"]:
        ssm = boto3.client("ssm")
        result = ssm.get_parameter(Name=KEY_PARAM, WithDecryption=True)
        _key.update(value=result["Parameter"]["Value"], at=time.time())
    return _key["value"]


def read_documents():
    if CONTENT_DIR:
        return {p.name: p.read_text() for p in sorted(Path(CONTENT_DIR).glob("*.md"))}
    s3 = boto3.client("s3")
    listing = s3.list_objects_v2(Bucket=KB_BUCKET, Prefix=KB_PREFIX)
    docs = {}
    for item in sorted(listing.get("Contents", []), key=lambda i: i["Key"]):
        if item["Key"].endswith(".md"):
            body = s3.get_object(Bucket=KB_BUCKET, Key=item["Key"])["Body"].read()
            docs[item["Key"]] = body.decode("utf-8")
    return docs


def refresh_kb():
    if time.time() - _kb["at"] < CACHE_SECONDS and _kb["text"]:
        return
    try:
        docs = read_documents()
    except Exception as exc:  # keep serving the last good copy
        log(event="kb_error", error=type(exc).__name__)
        _kb["at"] = time.time() - CACHE_SECONDS + 30
        return
    text = "\n\n".join(f"## {name}\n{body}" for name, body in docs.items())
    version = hashlib.sha256(text.encode()).hexdigest()[:10] if text else "none"
    if version != _kb["version"]:
        log(event="kb_loaded", kb_version=version, documents=len(docs))
    _kb.update(text=text, version=version, at=time.time())


def as_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(p.get("text", "") for p in content if isinstance(p, dict))
    return ""


def has_pii(text):
    return any(p.search(text) for p in PII_PATTERNS)


def scrub(text):
    for pattern in PII_PATTERNS:
        text = pattern.sub("[removed]", text)
    return text


def canned(reply, stream):
    rid = f"chatcmpl-{uuid.uuid4().hex}"
    if not stream:
        message = {"role": "assistant", "content": reply}
        choice = {"index": 0, "message": message, "finish_reason": "stop"}
        return JSONResponse({"id": rid, "object": "chat.completion", "model": MODEL, "choices": [choice]})

    def chunk(delta, finish=None):
        body = {
            "id": rid,
            "object": "chat.completion.chunk",
            "model": MODEL,
            "choices": [{"index": 0, "delta": delta, "finish_reason": finish}],
        }
        return f"data: {json.dumps(body)}\n\n"

    async def events():
        yield chunk({"role": "assistant", "content": reply})
        yield chunk({}, "stop")
        yield "data: [DONE]\n\n"

    return StreamingResponse(events(), media_type="text/event-stream")


def failure(status, detail="model_error"):
    return JSONResponse({"error": {"message": detail, "type": "gateway_error"}}, status_code=status)


@app.get("/health")
async def health():
    return {"status": "ok", "version": VERSION, "kb_version": _kb["version"]}


@app.get("/v1/models")
async def models():
    return {"object": "list", "data": [{"id": "tala-helpdesk", "object": "model"}]}


@app.post("/v1/chat/completions")
async def chat(request: Request):
    started = time.perf_counter()
    supplied = request.headers.get("authorization", "").removeprefix("Bearer ").strip()
    if not TOKEN or not secrets.compare_digest(supplied, TOKEN):
        return failure(401, "unauthorized")

    payload = await request.json()
    stream = bool(payload.get("stream"))
    source = request.headers.get("x-source", "chat")
    turns = [
        {"role": m.get("role"), "content": as_text(m.get("content"))}
        for m in payload.get("messages", [])
        if m.get("role") in ("user", "assistant")
    ]
    question = next((t["content"] for t in reversed(turns) if t["role"] == "user"), "")

    def record(status, http_status=200, chars=0, first_ms=None, question_text=question):
        log(
            event="request", request_id=uuid.uuid4().hex[:12], source=source,
            question=question_text[:500], status=status, http_status=http_status,
            duration_ms=round((time.perf_counter() - started) * 1000),
            first_token_ms=first_ms, answer_chars=chars, model=MODEL,
            app_version=VERSION, kb_version=_kb["version"],
        )

    if has_pii(question):
        record("blocked_pii", question_text="[removed: personal data]")
        return canned(PII_REPLY, stream)

    await asyncio.to_thread(refresh_kb)
    if not _kb["text"]:
        record("empty")
        return canned(NO_KB_REPLY, stream)

    for turn in turns:
        turn["content"] = scrub(turn["content"])
    system = {"role": "system", "content": PROMPT.replace("{kb}", _kb["text"])}
    requested = payload.get("max_tokens") or MAX_TOKENS
    body = {
        "model": MODEL,
        "messages": [system, *turns],
        "stream": stream,
        "temperature": 0.2,
        "max_tokens": min(int(requested), MAX_TOKENS),
    }

    try:
        api_key = await asyncio.to_thread(fetch_key)
        upstream = client.build_request(
            "POST", f"{BASE_URL}/chat/completions", json=body,
            headers={"Authorization": f"Bearer {api_key}"},
        )
        response = await client.send(upstream, stream=True)
    except Exception as exc:
        log(event="upstream_error", error=type(exc).__name__)
        record("error", 502)
        return failure(502)

    if response.status_code >= 400:
        detail = (await response.aread())[:300].decode("utf-8", "replace")
        await response.aclose()
        log(event="upstream_error", http_status=response.status_code, detail=detail)
        record("error", response.status_code)
        return failure(response.status_code)

    if not stream:
        data = json.loads(await response.aread())
        await response.aclose()
        answer = data["choices"][0]["message"].get("content") or ""
        record("ok" if answer.strip() else "empty", chars=len(answer))
        return JSONResponse(data)

    async def relay():
        chars, first_ms, status = 0, None, "ok"
        try:
            async for line in response.aiter_lines():
                if line.startswith("data:") and "[DONE]" not in line:
                    try:
                        parsed = json.loads(line[5:])
                        piece = parsed["choices"][0]["delta"].get("content") or ""
                    except (ValueError, KeyError, IndexError):
                        piece = ""
                    if piece and first_ms is None:
                        first_ms = round((time.perf_counter() - started) * 1000)
                    chars += len(piece)
                yield line + "\n"
            if chars == 0:
                status = "empty"
        except asyncio.CancelledError:
            status = "cancelled"
            raise
        except Exception as exc:
            status = "error"
            log(event="upstream_error", error=type(exc).__name__)
        finally:
            await response.aclose()
            record(status, chars=chars, first_ms=first_ms)

    return StreamingResponse(relay(), media_type="text/event-stream")
