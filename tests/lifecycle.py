#!/usr/bin/env python3
"""Plays a fake GameNight host against Hexstead, headless.

Checks the session lifecycle and the phone screens: the game declares its
phone page, prepares and reports ready, sends a phone its view when it opens,
accepts a move from that phone, refuses a bad one, and plays a bot seat.

    python3 tests/lifecycle.py [--godot path/to/godot]   (needs `websockets`)
"""
import argparse
import asyncio
import json
import os
import subprocess
import sys
from pathlib import Path

import websockets

ROOT = Path(__file__).resolve().parents[1]
PORT = 7931


async def run(godot: str) -> None:
    inbox: asyncio.Queue = asyncio.Queue()
    conn = {}

    async def handler(ws):
        conn["ws"] = ws
        try:
            async for text in ws:
                await inbox.put(json.loads(text))
        except websockets.ConnectionClosed:
            pass

    async def expect(kind, check=lambda m: True, timeout=20.0):
        loop = asyncio.get_running_loop()
        end = loop.time() + timeout
        while True:
            left = end - loop.time()
            if left <= 0:
                raise AssertionError(f"timed out waiting for {kind}")
            m = await asyncio.wait_for(inbox.get(), left)
            if m.get("type") == kind and check(m):
                return m

    async def send(msg):
        await conn["ws"].send(json.dumps(msg))

    async with websockets.serve(handler, "127.0.0.1", PORT):
        env = dict(os.environ, GAMENIGHT="1", GAMENIGHT_ADDR=f"127.0.0.1:{PORT}",
                   GAMENIGHT_GAME_ID="hexstead", GAMENIGHT_TOKEN="t", HEXSTEAD_BOT_STEP="0.05")
        proc = subprocess.Popen([godot, "--headless", "--path", str(ROOT)], env=env,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            hello = await expect("hello")
            assert hello["game"] == "hexstead" and hello.get("token") == "t", hello
            await send({"type": "welcome", "party": {}})
            page = await expect("declare_companion")
            root = Path(page["root"])
            assert (root / page["entry"]).is_file(), page
            assert (root / "art" / "timber.png").is_file(), "card art is copied for the phone"
            print("ok: phone page declared at", root)

            seats = [
                {"index": 0, "occupant": {"kind": "player", "player_id": "joep"}},
                {"index": 1, "occupant": {"kind": "ai"}},
            ]
            players = [{"id": "joep", "name": "Joep", "color": "#3d8fe0"}]
            await send({"type": "prepare", "game": "hexstead", "session": "s1", "seats": seats, "players": players})
            await expect("ready", lambda m: m.get("session") == "s1")
            await send({"type": "start", "session": "s1"})
            print("ok: prepared and ready")

            await send({"type": "companion_presence", "player_id": "joep", "connected": True})
            view = (await expect("companion_message", lambda m: m.get("player_id") == "joep"))["data"]
            assert view["t"] == "view" and view["you"]["name"] == "Joep", view["you"]
            assert len(view["players"]) == 3, "bots fill up to three"
            assert view["you"]["turn"] and view["phase"] == "setup_hamlet"
            print("ok: phone gets its view")

            await send({"type": "companion_message", "player_id": "joep", "data": {"a": "roll"}})
            err = await expect("companion_message", lambda m: m["data"].get("t") == "error")
            print("ok: refused:", err["data"]["text"])

            spot = view["legal"]["hamlet"][0]
            await send({"type": "companion_message", "player_id": "joep", "data": {"a": "hamlet", "id": spot}})
            view = (await expect("companion_message", lambda m: m["data"].get("phase") == "setup_road"))["data"]
            road = view["legal"]["road"][0]
            await send({"type": "companion_message", "player_id": "joep", "data": {"a": "road", "id": road}})
            # The bots take their opening turns, then it comes back to Joep.
            view = (await expect("companion_message",
                                 lambda m: m["data"].get("t") == "view" and m["data"]["you"]["turn"]
                                 and m["data"]["phase"] == "setup_hamlet"))["data"]
            owners = {v.get("owner") for v in view["verts"] if v.get("owner")}
            assert owners == {1, 2, 3}, owners
            print("ok: moves from the phone, bots play their seats")

            await send({"type": "pause", "session": "s1"})
            await send({"type": "resume", "session": "s1"})
            await send({"type": "dispose", "session": "s1"})
            await asyncio.sleep(0.5)
            assert proc.poll() is None, "the game keeps running between sessions"
            print("ok: pause, resume, dispose")
        finally:
            proc.terminate()
            proc.wait(timeout=10)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    args = ap.parse_args()
    try:
        asyncio.run(run(args.godot))
    except AssertionError as e:
        print("FAIL:", e)
        sys.exit(1)
    print("hexstead lifecycle passed")


if __name__ == "__main__":
    main()
