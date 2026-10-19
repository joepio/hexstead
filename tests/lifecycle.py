#!/usr/bin/env python3
"""Plays a fake GameNight host against Hexstead, headless.

Checks the session lifecycle and the phone screens: the game declares its
phone page, prepares and reports ready, sends a phone its view when it opens,
accepts a move from that phone, refuses a bad one, and plays a bot seat.

    python3 tests/lifecycle.py [--godot path/to/godot] [--pack game.pck]

The host is the GameNight SDK's addons/gamenight/fake_host.py (standard
library only).
"""
import argparse
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "addons" / "gamenight"))
from fake_host import FakeHost  # noqa: E402


def run(godot: str, pack: str = "") -> None:
    with FakeHost(godot, "hexstead", path=ROOT, pack=pack, timeout=20,
                  env={"HEXSTEAD_BOT_STEP": "0.05"}) as host:
        # FakeHost already checked the hello's game id and launch token.
        host.welcome()
        page = host.expect("declare_companion")
        root = Path(page["root"])
        assert (root / page["entry"]).is_file(), page
        assert (root / "art" / "timber.png").is_file(), "card art is copied for the phone"
        print("ok: phone page declared at", root)

        seats = [
            {"index": 0, "occupant": {"kind": "player", "player_id": "joep"}},
            {"index": 1, "occupant": {"kind": "ai"}},
        ]
        players = [{"id": "joep", "name": "Joep", "color": "#3d8fe0"}]
        host.prepare(seats, players, session="s1")
        host.start()
        print("ok: prepared and ready")

        host.phone("joep", connected=True)
        view = host.expect("companion_message", lambda m: m.get("player_id") == "joep")["data"]
        assert view["t"] == "view" and view["you"]["name"] == "Joep", view["you"]
        assert len(view["players"]) == 3, "bots fill up to three"
        assert view["you"]["turn"] and view["phase"] == "setup_hamlet"
        print("ok: phone gets its view")

        host.phone("joep", {"a": "roll"})
        err = host.expect("companion_message", lambda m: m["data"].get("t") == "error")
        print("ok: refused:", err["data"]["text"])

        # Pointing at spots while picking only moves the hint on the TV.
        for aim in [view["legal"]["hamlet"][1], 99999, view["legal"]["hamlet"][0]]:
            host.phone("joep", {"a": "aim", "kind": "hamlet", "id": aim})
        host.phone("joep", {"a": "aim", "kind": "storm", "id": 1})
        print("ok: aiming is quiet")

        spot = view["legal"]["hamlet"][0]
        host.phone("joep", {"a": "hamlet", "id": spot})
        view = host.expect("companion_message", lambda m: m["data"].get("phase") == "setup_road")["data"]
        road = view["legal"]["road"][0]
        host.phone("joep", {"a": "road", "id": road})
        # The bots take their opening turns, then it comes back to Joep.
        view = host.expect("companion_message",
                           lambda m: m["data"].get("t") == "view" and m["data"]["you"]["turn"]
                           and m["data"]["phase"] == "setup_hamlet")["data"]
        owners = {v.get("owner") for v in view["verts"] if v.get("owner")}
        assert owners == {1, 2, 3}, owners
        print("ok: moves from the phone, bots play their seats")

        host.pause()
        host.resume()
        host.dispose()
        time.sleep(0.5)
        assert host.process.poll() is None, "the game keeps running between sessions"
        print("ok: pause, resume, dispose")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    ap.add_argument("--pack", default="", help="test an exported .pck instead of the project")
    args = ap.parse_args()
    try:
        run(args.godot, args.pack)
    except AssertionError as e:
        print("FAIL:", e)
        sys.exit(1)
    print("hexstead lifecycle passed")


if __name__ == "__main__":
    main()
