#!/usr/bin/env python3
"""Telegram API helper for webloc-preview.

Usage:
    tg_preview.py auth                 # Interactive: phone → code → session saved
    tg_preview.py fetch <url>          # One-shot fetch (for testing)
    tg_preview.py check                # Check if session is valid
    tg_preview.py daemon               # Long-running: reads URLs from stdin, writes JSON to stdout
"""

import sys, json, os, asyncio, tempfile

CONFIG_DIR = os.path.expanduser("~/.webloc-preview")
SESSION_PATH = os.path.join(CONFIG_DIR, "tg_session")
CONFIG_PATH = os.path.join(CONFIG_DIR, "tg_config.json")


def load_config():
    if not os.path.exists(CONFIG_PATH):
        return None
    with open(CONFIG_PATH) as f:
        return json.load(f)


def save_config(api_id, api_hash):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(CONFIG_PATH, "w") as f:
        json.dump({"api_id": api_id, "api_hash": api_hash}, f)


def clean_url(url):
    """Strip tracking query params that break Telegram preview resolution."""
    from urllib.parse import urlparse, urlunparse
    parsed = urlparse(url)
    return urlunparse((parsed.scheme, parsed.netloc, parsed.path, "", "", ""))


def respond(data):
    """Write JSON line to stdout and flush."""
    sys.stdout.write(json.dumps(data, ensure_ascii=False) + "\n")
    sys.stdout.flush()


async def auth():
    """Interactive auth flow."""
    config = load_config()
    if config:
        api_id = config["api_id"]
        api_hash = config["api_hash"]
    else:
        api_id = input("api_id: ").strip()
        api_hash = input("api_hash: ").strip()
        save_config(int(api_id), api_hash)

    from telethon import TelegramClient
    client = TelegramClient(SESSION_PATH, int(api_id), api_hash)
    await client.start()
    me = await client.get_me()
    print(f"Authenticated as {me.first_name} ({me.phone})")
    await client.disconnect()


async def check():
    """Check if session is valid."""
    config = load_config()
    if not config:
        print(json.dumps({"ok": False, "error": "not_configured"}))
        return
    from telethon import TelegramClient
    client = TelegramClient(SESSION_PATH, config["api_id"], config["api_hash"])
    await client.connect()
    ok = await client.is_user_authorized()
    if ok:
        me = await client.get_me()
        print(json.dumps({"ok": True, "user": me.first_name}))
    else:
        print(json.dumps({"ok": False, "error": "not_authorized"}))
    await client.disconnect()


async def fetch_preview(client, url):
    """Fetch web page preview. Returns dict with result or error."""
    from telethon.tl.functions.messages import GetWebPagePreviewRequest
    from telethon.errors import FloodWaitError

    # Try original URL first, then without query params
    clean = clean_url(url)
    urls_to_try = [url, clean] if clean != url else [url]

    try:
        wp = None
        for try_url in urls_to_try:
            try:
                result = await client(GetWebPagePreviewRequest(message=try_url))
            except FloodWaitError as e:
                # Telethon's auto-sleep didn't handle it (> threshold)
                return {"error": "flood_wait", "seconds": e.seconds}

            if hasattr(result, "media") and hasattr(result.media, "webpage"):
                wp = result.media.webpage
            elif hasattr(result, "webpage"):
                wp = result.webpage
            if wp and hasattr(wp, "title") and wp.title:
                break
            wp = None

        if not wp or not hasattr(wp, "title") or not wp.title:
            return {"error": "no_preview"}

        data = {
            "title": wp.title or "",
            "description": wp.description or "",
            "site_name": wp.site_name or "",
        }

        # Download photo to temp file
        if hasattr(wp, "photo") and wp.photo:
            try:
                photo_bytes = await client.download_media(wp.photo, bytes)
                if photo_bytes:
                    tmp = os.path.join(tempfile.gettempdir(), "webloc_tg_img.jpg")
                    with open(tmp, "wb") as f:
                        f.write(photo_bytes)
                    data["image_path"] = tmp
            except Exception:
                pass

        return data

    except Exception as e:
        return {"error": str(e)}


async def daemon():
    """Long-running daemon: reads URLs from stdin, writes JSON to stdout.
    Keeps one persistent Telegram connection — Telethon handles FloodWait
    automatically for waits up to flood_sleep_threshold seconds."""
    config = load_config()
    if not config:
        respond({"error": "not_configured"})
        return

    from telethon import TelegramClient

    client = TelegramClient(
        SESSION_PATH, config["api_id"], config["api_hash"],
        flood_sleep_threshold=120  # auto-wait up to 2 min on rate limits
    )
    await client.connect()

    if not await client.is_user_authorized():
        respond({"error": "not_authorized"})
        await client.disconnect()
        return

    # Signal ready
    respond({"status": "ready"})

    # Read URLs from stdin asynchronously
    loop = asyncio.get_event_loop()
    reader = asyncio.StreamReader()
    protocol = asyncio.StreamReaderProtocol(reader)
    await loop.connect_read_pipe(lambda: protocol, sys.stdin)

    while True:
        line = await reader.readline()
        if not line:
            break
        url = line.decode().strip()
        if not url:
            continue

        result = await fetch_preview(client, url)
        respond(result)

    await client.disconnect()


async def fetch_oneshot(url):
    """One-shot fetch (for testing). Creates and destroys connection."""
    config = load_config()
    if not config:
        print(json.dumps({"error": "not_configured"}))
        return
    from telethon import TelegramClient
    client = TelegramClient(
        SESSION_PATH, config["api_id"], config["api_hash"],
        flood_sleep_threshold=120
    )
    await client.connect()
    if not await client.is_user_authorized():
        print(json.dumps({"error": "not_authorized"}))
        await client.disconnect()
        return
    result = await fetch_preview(client, url)
    print(json.dumps(result, ensure_ascii=False))
    await client.disconnect()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "auth":
        asyncio.run(auth())
    elif cmd == "check":
        asyncio.run(check())
    elif cmd == "fetch":
        if len(sys.argv) < 3:
            print(json.dumps({"error": "usage: tg_preview.py fetch <url>"}))
            sys.exit(1)
        asyncio.run(fetch_oneshot(sys.argv[2]))
    elif cmd == "daemon":
        asyncio.run(daemon())
    else:
        print(json.dumps({"error": f"unknown command: {cmd}"}))
        sys.exit(1)
