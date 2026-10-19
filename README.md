# Hexstead

A building and trading game for 2 to 6 players on GameNight. The TV shows a
new hex island in 3D every round; each player's cards and choices are on
their own phone, through GameNight's phone screens. Godot 4.5 (CI pins 4.5.2), MIT licensed.

Everything you see is built from code: fields, trees, sheep, windmills,
mountains, houses and the card pictures are low-poly meshes made by
`src/world/art.gd`, so every round gets a fresh island at no asset cost.

## How it plays

- Each field produces one resource: Timber (forest), Clay (clay pit),
  Wool (pasture), Grain (farm) or Ore (mountain). The lake produces nothing
  and is where the storm starts.
- Everyone places a hamlet and a road, then again in reverse order. The
  second hamlet pays out one card per field it touches.
- On your turn you roll two dice. Every field with that number pays each
  hamlet next to it one card, and each town two.
- Build with what you hold:

  | Build | Cost | Points |
  | --- | --- | --- |
  | Road | Timber, Clay | |
  | Hamlet | Timber, Clay, Wool, Grain | 1 |
  | Town (upgrades a hamlet) | 2 Grain, 3 Ore | 2 |
  | Festival (twice per game) | Wool, Grain, Ore | 1 |

- Hamlets need a free corner with no neighbouring hamlet, reached by your road.
- The bank trades 4 of a kind for 1. Each round the market favours one
  resource, which then trades 2 for 1.
- A 7 brings the storm: anyone holding more than 9 cards loses half, and the
  roller moves the storm to a field. That field stops producing, and the
  roller takes a random card from a player next to it.
- First to 8 points wins. A new island rises 12 seconds later.

## The TV and the phones

The TV is for everyone to watch; all choices are made on phones. It shows
the island, the settlers' scoreboard, the market card, whose turn it is with
the dice, a price list of what each build costs, and cards flying from fields
to whoever they pay. The storm is a thundercloud raining on its field. When a
phone player has to pick a corner, side or field, the TV shows the choices
glowing so the table can follow along.

The game declares `phone/` as its phone screen (`declare_companion`), copied
to the user folder first because GameNight serves it from disk. The phone
shows your hand as illustrated cards, a tappable board that highlights where
you may build, dice, the bank and the scoreboard. The game checks every move;
the page only draws the view it is sent.

AI seats are played by bots. A player without a phone gets 15 seconds on
their turn, then a bot plays that turn so the table never stalls. With fewer
than three players, bots fill up to three.

## Code

| Path | What |
| --- | --- |
| `src/rules.gd` | The rules, no nodes; ids are 1-based to match the phone page |
| `src/bot.gd` | The bot |
| `src/main.gd` | GameNight session, phones, bots, screenshot mode |
| `src/world/` | `mesh_kit.gd` (low-poly builder), `art.gd` (everything on the island), `island.gd` (scene, camera, animations), `water.gdshader` |
| `src/hud/` | Scoreboard, market card, price list, dice |
| `phone/` | The phone page; `phone/art/*.png` are rendered by `tools/card_art.gd` |

## Run and test

```sh
godot --path .                                   # four bots, to watch
godot --headless --script tests/rules_test.gd    # 60 boards, 25 bot games
python3 tests/lifecycle.py                       # fake GameNight host + phone (SDK fake_host.py)
tools/shot.sh out.png --moves 60 --seed 5        # render the TV (xvfb + Vulkan, lavapipe works)
xvfb-run -a godot --rendering-driver vulkan --path . --script tools/card_art.gd   # re-render card art
```

Under GameNight (`GAMENIGHT=1`) the SDK reads the launch environment, the
game prepares hidden, shows on Start and reports `finished` when someone wins.
`HEXSTEAD_BOT_STEP` sets seconds per bot move (default 0.9).

The GameNight addon in `addons/gamenight` is a copy of the SDK. Update it from
a gamenight checkout with `python sdk/godot/sync.py path/to/hexstead`; CI
fails when it drifts.

Fonts: Alegreya and Alegreya SC by Huerta Tipográfica, SIL Open Font License
(`assets/fonts/OFL.txt`).
