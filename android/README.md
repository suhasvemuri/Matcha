# Matcha for Android

Native Android companion to the macOS Matcha menu-bar app — live football
(soccer) and cricket scores for your favorite teams and competitions, with
home-screen widgets, live-match notifications, where-to-watch streams, and a
Wear OS app.

Built to share the macOS app's data source: the public ESPN scoreboard API
(`site.api.espn.com`). No API keys, no backend.

## Modules

| Module  | What it is |
|---------|------------|
| `:app`  | Phone/tablet app (Jetpack Compose, AGP 9, Kotlin 2.3, Nav3) |
| `:wear` | Standalone Wear OS app (Wear Compose) |

## `:app` architecture

```
data/
  espn/EspnModels.kt      ESPN scoreboard JSON (serializable, subset)
  EspnApi.kt              HttpURLConnection fetch + parse, -3d..+5d window
  Leagues.kt              League catalog (ESPN slugs) — mirrors the Mac app
  MatchaModels.kt         Domain models (Match, MatchTeam, LeagueMatches)
  FavoritesStore.kt       Favorites via DataStore (leagues + team filters)
  MatchaRepository.kt     Parallel fetch of favorited leagues + team filter
  streaming/              Streamed (streamed.st) where-to-watch resolver
ui/main/                  Compose scores screen + ViewModel
widget/                   Glance home-screen widget + WorkManager refresh
notifications/            Foreground service + ongoing live-match notifications
```

Favorites default to **FIFA World Cup, Premier League, UEFA Champions League**
on first run. The macOS app's "favorite a competition" bug (favoriting didn't
enable the feed) is avoided here: the repository fetches exactly the favorited
leagues.

## Features

- **Scores** — football + **cricket**, grouped by league, live/upcoming/final
  states, team logos (Coil). Cricket scores ("161/5") parse through the same
  ESPN pipeline.
- **Favorites editor** — in-app screen (star button on the scores header) to
  toggle followed leagues by sport and add favorite-team text filters
- **Where to watch** — tap a match → bottom sheet of streams (Streamed provider)
- **Home-screen widget** — Glance widget of favorite live scores, refreshed by
  a 15-minute WorkManager job
- **Live notifications** — `LiveScoreService` foreground service polls live
  matches every 45s and posts/updates an ongoing notification per match
  (Android's analogue to iOS Live Activities), self-stopping when nothing is live
- **Wear OS** — standalone watch app + a Tile, showing live scores. Favorites
  sync from the phone over the Wearable Data Layer
  (`WearFavoritesPublisher` → `FavoritesSyncService`)

## Build & run

```bash
cd android
./gradlew :app:assembleDebug        # phone APK
./gradlew :wear:assembleDebug       # watch APK
./gradlew :app:testDebugUnitTest    # unit tests
```

Or via the project workflow: `android-dev build Matcha`.

## Known follow-ups

- Cricket feed (the macOS app uses a separate cricket source; Android currently
  covers ESPN soccer end-to-end)
- An in-app favorites/onboarding editor (defaults work; editing UI is pending)
- Wear: phone→watch favorites sync via the Wearable Data Layer, plus a Tile and
  complication (dependency is already wired)
