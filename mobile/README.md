# RunLah — mobile app (Flutter)

Live race tracking for runners and the people cheering them, plus **Race Insights** after the finish.
One Flutter codebase for **Android, iOS and web**. Built from *Runner Live Tracking App — PRD, ERD & API Contract (v2)* in the repo root.

> **Demo mode.** There's no backend yet. A built-in race simulator stands in for the Laravel API + Reverb:
> a half marathon around KL with **11,760 runners**, so every screen has live data. "You" are **Arep, bib 34144**, and the
> simulator reproduces his real KLSCM 2026 result: net 1:36:15, gun 1:36:54, start delay 0:39, **172nd of 11,664 (Top 1.5%)**,
> ahead of 99.7% of women, quarters 13.2 / 13.8 / 12.9 / 12.8 km/h.

---

## Run it

Flutter is installed at `~/development/flutter` (3.47.7), Android SDK at `~/development/android-sdk`, JDK 17 at `~/development/jdk-17`.

```bash
export PATH=~/development/flutter/bin:$PATH
cd mobile
flutter pub get

flutter run -d chrome          # quickest: runs in the browser
flutter run                    # Android phone plugged in (USB debugging on)
flutter build apk --release    # APK to send to an Android phone: build/app/outputs/flutter-apk/app-release.apk
```

**iPhone** needs a Mac with Xcode: `cd ios && pod install && cd .. && flutter run` (set your Apple team under Runner → Signing & Capabilities the first time).
Everything iOS needs is already configured: location "Always" + background location, camera, photos, notifications, iOS 15.5 (required by ML Kit).

---

## 5-minute demo (showing someone how it works)

The navy pill at the **bottom-right** is the **Demo director**. It's the race clock: fire the gun, change the speed (1× – 120×), and jump to moments.

1. **Home.** Race-day countdown, bib card with QR, live heat alert (real KL weather from Open-Meteo), and the **3D course flyover**.
2. **Demo director → Fire the gun** (or Organizer → GUN). Set **30×**.
3. **Run tab.** Arep's live run: pace, place on the road, projected finish against the target, overtakes counting up, cheers from Qirah and Hafiz read aloud, and SOS (hold 2 s).
4. **Cheer tab.** Following Qirah (GPS) and Hafiz (no GPS, so a hollow "estimated" ring). Open the **live map** and **Cheer spots** ("Qirah reaches KLCC in 6:12, leave now"). Send a cheer.
5. **Demo director → Jump to "You finish".** Confetti. Tap **See Race Insights**:
   - **Finish:** place line crowd, Net/Gun toggle, 172nd · Top 1.5% · ahead of 99.7% of women, ghost runners.
   - **Speed:** quarter bars, passed 1,135 before halfway, place by checkpoint, who's who.
   - **Where:** where were you when the male winner finished (about KM 14, same as RunPix).
   - **Compare** and the **share card** (Instagram story size).
6. **3D:** Drone view at the finish arch, and the full 3D race replay over KL (Twin Towers, KL Tower, Merdeka 118).
7. **Organizer** (Home → Organizer, or the Demo director): field stats, congestion **heatmap**, **SOS queue**, **bib camera (OCR)**, import the timing CSV, then **Publish official results**.
8. **Me:** race passport, new PB, badges unlocking, **Race Wrapped 2026**, selfie frame, and switch to **Bahasa Malaysia**.

**Demo director → Reset demo** starts everything again.

---

## What's built (PRD v2 feature IDs)

| Area | Features |
|---|---|
| Runner | F06 join with bib + code · F07 background GPS run · F08 free run + share link · F09 offline queue + battery saver · F10 privacy · F11 SOS · F17 splits & pace · voice coach · target-time alerts · glance mode |
| Cheer | F13 add runner (search, QR, link) · F14 live map + ETA · F15 notifications · F16 live ranking · F30 cheer messages · Cheer spots + "leave now" · meet-me-after · live overtake counter |
| Race Insights | F18 finish card (net/gun, start delay, places, Top %, gender compare) · F19 who's who · F20 section speed · F21 overtakes + place by checkpoint · F23 where were you · F24 ghost runners · F25 comparer · F26 share card · F33 e-certificate |
| 3D (three.js) | F28 drone view · F29 full race replay · course flyover |
| Organizer | F05 gun · live field stats · course heatmap · SOS queue · F31 bib camera (ML Kit OCR + review queue) · F27 timing CSV import · F33 publish official |
| Me | race passport · PBs · 14 badges · Race Wrapped · F34 selfie frames · my QR · settings · PDPA export / delete |
| Everywhere | F36 English + Bahasa Malaysia · light + dark mode · km / miles |

---

## How the code is organised

```
lib/
  main.dart, app.dart          wiring (providers), theme, language
  core/                        theme + shared widgets, formatting, geo (route maths), tr() translations, nav, CourseMap
  data/
    models.dart                mirrors the ERD (PRD §14)
    demo/                      KL course + 11,760-runner field generator
    sim/race_sim.dart          the simulator: race clock, runner positions, events (stands in for API + Reverb)
    insights/insights_engine.dart   Race Insights maths (PRD §6.2), O(N log N), tested against brute force
    app_state.dart             settings, follows, live insights snapshot, tabs
    activity_store.dart        saved runs + offline points queue
    achievements.dart          passport, PBs, badges, Wrapped
  services/                    GPS tracking, points upload (demo + API sink), voice, notifications, weather
  features/
    shell/                     bottom nav, notification banners, demo director
    home/ run/ cheer/ insights/ organizer/ profile/ three/
assets/three/race3d.html       the bundled three.js scenes (built from three_src/)
three_src/                     three.js source + esbuild script
test/                          widget + unit tests
```

**Translations:** write UI text in English as `tr('Start run')` and add the BM text to the matching `lib/core/l10n/bm_<feature>.dart`. A missing key falls back to English.

**3D scenes:** edit `three_src/src/`, then `cd three_src && npm install && npm run build`. That writes one self-contained `assets/three/race3d.html`. The app loads it in a WebView on phones and an iframe on web.

---

## Connecting the real backend (next step)

- **Track points already upload to the API contract.** Run with `--dart-define=API_BASE_URL=https://api.example.com` (optionally `API_TOKEN=…`) and free-run points go to `POST /api/v1/activities/{id}/points` in batches of up to 500, from the offline queue.
- **Everything else still reads from `RaceSim`.** To go live, put an API + Reverb data source behind the same interface: the screens use its kinematics/events and `InsightsSnapshot`, so they don't need to change. Race Insights maths moves to the Laravel results job (same algorithm as `insights_engine.dart`).
- **Push notifications** currently use local notifications. Add Firebase (FCM) config files to switch to server push.

---

## Tests

```bash
flutter analyze
flutter test --concurrency=1      # one file at a time keeps memory low (~0.5 GB)
```

---

## Known limits (honest list)

- Race day follows the simulated runner. Real GPS is used for free runs and the pre-race GPS check.
- **Not run on real hardware yet:**
  - The bib camera (ML Kit OCR).
  - QR scanning.
  - The background-GPS foreground service.
  - The iOS build (needs a Mac).
- Map tiles come from CARTO / OpenStreetMap: free for a demo, but production needs a tile plan or self-hosted tiles.
- Demo history races, staff and upcoming events are fictional.
