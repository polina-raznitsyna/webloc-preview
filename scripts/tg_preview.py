#!/usr/bin/env python3
"""Telegram API helper for webloc-preview.

Usage:
    tg_preview.py auth                 # Interactive: phone → code → session saved
    tg_preview.py fetch <url>          # Non-interactive: returns JSON metadata
    tg_preview.py check                # Check if session is valid
"""

import sys, json, os, asyncio, tempfile, base64

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


async def auth():
    """Interactive auth flow — reads from stdin."""
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


async def fetch(url):
    """Fetch web page preview via Telegram API. Returns JSON."""
    config = load_config()
    if not config:
        print(json.dumps({"error": "not_configured"}))
        return

    from telethon import TelegramClient
    from telethon.tl.functions.messages import GetWebPagePreviewRequest

    client = TelegramClient(SESSION_PATH, config["api_id"], config["api_hash"])
    await client.connect()

    if not await client.is_user_authorized():
        print(json.dumps({"error": "not_authorized"}))
        await client.disconnect()
        return

    try:
        result = await client(GetWebPagePreviewRequest(message=url))

        # Navigate: result.media.webpage (WebPagePreview → MessageMediaWebPage → WebPage)
        wp = None
        if hasattr(result, "media") and hasattr(result.media, "webpage"):
            wp = result.media.webpage
        elif hasattr(result, "webpage"):
            wp = result.webpage

        if not wp or not hasattr(wp, "title"):
            print(json.dumps({"error": "no_preview"}))
            await client.disconnect()
            return

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

        print(json.dumps(data, ensure_ascii=False))

    except Exception as e:
        print(json.dumps({"error": str(e)}))

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
        asyncio.run(fetch(sys.argv[2]))
    else:
        print(json.dumps({"error": f"unknown command: {cmd}"}))
        sys.exit(1)
