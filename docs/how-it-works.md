# How the weather works

The weather is not random and not fetched from anywhere. All of it is computed in
[`Core.lua`](../Core.lua) from three inputs:

1. **The zone** you are in (`GetRealZoneText()`), which picks a *climate*.
2. **The realm's clock** (`GetServerTime()` for the date, `GetGameTime()` for the hour).
3. **Whether you are under a roof or in an instance** (`IsIndoors()`, `IsInInstance()`).

Because nothing else goes in, the result is **deterministic**:

- Every player running the addon in the same zone at the same time sees the same weather.
- `/reload`, logging out or switching characters never re-rolls the sky.
- Nothing is saved or synced between players, so there is no network traffic.

The display recalculates every 5 seconds and immediately when you change zone or go indoors.

## Smooth noise: why it changes slowly

Weather needs to look random but change gradually. The addon uses *smooth value noise*:

- A hash of the zone name plus a time slot gives a repeatable pseudo-random number between 0 and 1.
- One new number is picked per time slot (for example every 6 hours), and the value glides
  between neighbouring numbers with an S-curve. It never jumps.
- Each quantity uses its own key (`"Duskwood:t"`, `"Duskwood:w"`...), so temperature, wind and
  rain drift independently, and two zones never share the same pattern.

Each zone also gets small **permanent quirks** from its name: up to ±2 °C and ±5 % humidity.
Zones that are not in the climate table still feel slightly different from each other.

## Climates

Each zone maps to a climate in [`Data.lua`](../Data.lua). A climate defines:

| Field | Meaning |
|---|---|
| `temp` | Yearly mean temperature (°C) |
| `swing` | Difference between the warmest afternoon and the coldest pre-dawn hour |
| `season` | How far summer and winter move away from the mean |
| `hum` | Mean relative humidity (%) |
| `wind` | Mean wind speed (km/h) |
| `dir` | Prevailing wind direction in degrees, where the wind blows *from* |
| `sky` | A ladder of sky conditions from fairest to foulest, each with a weight |
| `indoor` | No sky and no wind (Ironforge, Undercity, every instance) |

Built-in climates: `temperate`, `gloom`, `undead`, `alpine`, `highland`, `coast`, `plains`, `arid`,
`desert`, `jungle`, `swamp`, `elven`, `volcanic`, `blight`, `wastes`, and the indoor `forge`, `crypt` and
`underground`. Unlisted zones use `temperate`. Instances use `underground`.

## Time of day

| From | Phase |
|---|---|
| 00:00 | Dead of Night |
| 04:00 | Before Dawn |
| 05:30 | Dawn (twilight) |
| 07:00 | Morning |
| 11:00 | Midday |
| 14:00 | Afternoon |
| 18:00 | Evening |
| 19:30 | Dusk (twilight) |
| 21:00 | Night |

It is **night** from 21:00 to 05:30: the orb shows the moon. `/imw time local` switches from
realm time to your PC clock.

The orb shows the hour at a glance:

- **The sky colour follows the clock**, blending smoothly between keyframes: violet before dawn,
  a pink-orange horizon at dawn, pale blue in the early morning, deep blue at midday, golden in the evening,
  red-violet at dusk and deep navy at night. Bad weather greys or darkens the same sky.
- **The sun crosses the orb from 05:30 to 21:00**: it rises low on the left, is highest around 13:00 and
  sets low on the right, glowing orange near the horizon. The **moon** makes the same journey through
  the night, highest around 01:00, with stars around it when the sky is clear.

The **moon phase** follows the real lunar cycle (29.53 days, counted from a known new moon in
January 2000), rounded to one of eight phases.

## Sky condition

Each zone has a **wetness** value between 0 (fairest) and 1 (foulest):

- 80 % of it drifts over 6-hour slots and 20 % over 1.5-hour slots, so big weather systems
  come and go over a few hours with smaller wobbles on top.
- The value is stretched away from the middle, so both fine days and real storms happen.

Wetness picks a rung on the climate's `sky` ladder. The weights decide how much of the time
each rung gets. Duskwood (`gloom`), for example, spends most of its time in mist and fog and
only sometimes clears to overcast.

Precipitation reacts to temperature:

- Below -1 °C, drizzle becomes flurries, rain becomes snow and a storm becomes a blizzard.
- Above 3 °C, they turn back.

Available conditions: clear, fair, overcast, mist, fog, drizzle, rain, storm, flurries, snow, blizzard,
haze, sandstorm, ashfall, miasma, and "under stone" for indoor climates.

## Temperature

```
temperature = climate mean
            + zone quirk          (±2 °C, permanent)
            + season              (coldest mid-January, warmest mid-July, ±season)
            + time of day         (warmest at 15:00, coldest at 03:00, total range = swing)
            + drift               (±3 °C over 6-hour slots)
            + sky                 (rain, snow and fog cool; haze and ashfall warm)
```

- The season follows the **real calendar date** of the realm clock.
- A clear or hazy sky warms the day but **cools the night**, like real radiative cooling.
- **Under a roof** in an outdoor zone, the wind drops to zero and the orb still shows the sky outside.
  The tooltip also shows the temperature outside. Two kinds of roof:
  - **Heated**: inns, taverns and city buildings, anywhere the game lets you rest (`IsResting()`).
    A fire in the hearth keeps it near 19 °C: -10 °C outside is about 16 °C inside. The air is drier,
    pulled toward 45 % humidity, and the readout says *By the hearth*.
  - **Sheltered**: caves, barns, ruins and other roofs without a fire. The temperature moves 45 % of
    the way toward 12 °C: milder than outside, but a winter cave in Dun Morogh is still cold.

### Fires and forges

WoW doesn't tell addons about nearby fires, so the addon **learns where they are**, then warms you
automatically whenever you come within about 8 yards of one:

- **By crafting**: cooking only works next to a fire and smelting only next to a forge, so a successful
  cook or smelt remembers that spot.
- **By telling it**: `/imw fire` or `/imw forge` warms you right away and remembers the spot too.
  `/imw forget` removes a remembered spot where you stand.
- **Shared spots**: `ns.FireSpots` in `Data.lua` lists fires everyone feels. `/imw spots` prints yours
  in that format, ready to send upstream.
- **Known warm places**: `ns.WarmPlaces` in `Data.lua` maps a building's subzone name (shown above the
  minimap) to a heat source. It counts while you're under a roof there.

| Heat source | Pulls the air toward | Strength | Readout says |
|---|---|---|---|
| Forge | 30 °C, dry (25 %) | 90 % | By the forge |
| Fire under a roof | 24 °C (40 %) | 85 % | By the fire |
| Fire in the open (campfire) | 22 °C (50 %) | 55 % | By the campfire (the wind still blows) |

On a -13 °C night in Dun Morogh: about -2 °C in an unheated building, 15 °C in an inn, 20 °C by a fire,
27 °C at a forge and 6 °C at a campfire in the open. The tooltip shows the warmth and the temperature outside.

### Feels like

- At 10 °C or below with wind over 5 km/h: the standard wind-chill formula.
- At 27 °C or above: humid air feels hotter, by 0.1 °C per percent of humidity over 40 %.
- Otherwise it equals the temperature.

### Badge and colour

The badge next to the temperature uses the **feels-like** value. The text colour uses the actual temperature.

| Feels like | Badge |
|---|---|
| 0 °C or below | Snowflake |
| up to 10 °C | Blue thermometer (cold) |
| up to 21 °C | Green thermometer (mild) |
| up to 28 °C | Orange thermometer (warm) |
| above 28 °C | Red thermometer (hot) |

## Humidity

```
humidity = climate mean
         + zone quirk             (±5 %, permanent)
         + sky                    (rain and fog add, clear and haze subtract)
         + time of day            (higher at night, lower in the afternoon)
         + drift                  (±6 % over 4-hour slots)
```

Fog forces at least 94 % and mist at least 85 %. The result is kept between 3 % and 100 %.

## Wind

```
speed = climate wind × gustiness (0.4× to 1.7×, over 1.5-hour slots) × sky multiplier + sky gusts
```

- Storms, blizzards and sandstorms add strong gusts. Mist and fog calm the air.
- The **direction** swings up to ±100° around the climate's prevailing wind over 5-hour slots,
  shown as one of eight compass points.
- Indoor climates and anywhere under a roof have no wind.

| Speed | Tooltip description |
|---|---|
| under 2 km/h | Calm |
| under 12 | Light breeze |
| under 29 | Steady breeze |
| under 50 | Strong wind |
| under 75 | Gale |
| 75 and over | Storm winds |

## Barometer

Pressure is tied directly to wetness:

```
pressure ≈ 1034 hPa − wetness × 48 hPa   (± a small permanent zone offset)
```

Fair weather reads around 1030 hPa and a full storm sits near 986 hPa.

The **trend** in the tooltip compares wetness now with wetness one hour ahead. A *falling*
barometer means the weather is about to get worse, and a *rising* one means it is clearing,
so characters can read the sky the way real sailors do.

## Outlook

The tooltip's **Outlook** line runs the same simulation three hours ahead and shows the sky it finds.
