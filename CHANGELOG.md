# Changelog

## 1.1.0 - 2026-11-15

- Addon-list icon in the shared ImmerseMe style.
- Renamed to **ImmerseMe: Weather** (previously *Immersive World*), the first module of the ImmerseMe suite.
- New sky orb in the style of the stock day/night icon: a heraldic gold sun, a lavender moon in its real phase, sparkle stars and a weather overlay for all 15 conditions, day and night.
- The orb shows the time of day: the sky colour follows the clock (dawn glow, midday blue, golden evening, red dusk, navy night) and the sun and moon travel across it in an arc.
- Replaced the weather panel with a compact readout that follows the curve of the minimap's left edge.
- The sky is drawn on the stock day/night icon, inside its own gold ring, instead of adding a second icon. `/imw stock` gives the orb its own spot instead.
- Inns, taverns and city buildings (anywhere you can rest) are heated: about 19 °C whatever the weather. Caves and other unheated roofs stay cold. The tooltip shows the temperature outside.
- Fires and forges warm you up. The addon learns where they are (when you cook or smelt next to one, or use `/imw fire` / `/imw forge` once) and warms you automatically every time you come back. Known warm buildings and shared spots work for everyone.
- The readout counts toward new values instead of jumping: walk into a tavern and watch the temperature climb.
- Added a warm / cold badge next to the temperature, based on the feels-like temperature.
- New commands: `/imw icon`, `/imw arc`, `/imw y`, `/imw gap`, `/imw font`. The slash commands are now `/imw` and `/weather`.
- Settings now live in `ImmerseMeWeatherDB`. Settings from *Immersive World* are not carried over.

## 1.0.0

- First release as *Immersive World*: a day/night orb on the minimap and a weather panel for every zone.
