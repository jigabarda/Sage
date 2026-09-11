# Sage Project Guide

> **Name.** *Sage* — the muted green the app is themed in, and the older sense
> of the word: measured, unhurried counsel. Decided 2026-09-06.
>
> Android application id / namespace: `com.sage.mobile`, following Sellora’s
> `com.sellora.mobile` convention. Nothing is published, so it is not claimed
> anywhere and can still change.

## Purpose

A personal health companion for people who live with **migraine** and **acid
reflux**. It does two jobs, and the order matters:

1. **Log episodes and the things around them**, offline, in seconds, while in
   pain.
2. **Tell the person what their own record shows** — patterns they cannot see
   by remembering.

The AI assistant is the third job, not the first. It exists for the questions a
template cannot answer, and it is the only part of the app that needs a network.

## North Star

Build an app that is fully useful with the phone in airplane mode, and *better*
when it has signal.

Nothing safety-critical may depend on a network call or on a language model.
The record is the product; conversation is an interface on top of it.

## Non-Negotiables

1. **Red-flag triage is deterministic Dart, never a model.** It runs offline, it
   runs first, and it cannot be skipped. See Red-Flag Triage.
2. **Correlation findings are arithmetic, not inference.** Same rule as Sellora's
   insights engine: every finding states the numbers it came from, and every
   rule carries a minimum-evidence gate that fails closed.
3. **Core workflows work offline**: log an episode, view history, get in-attack
   guidance, see patterns, export the log.
4. **The local database is the source of truth.** No account, no cloud sync, no
   server-side copy of health data. If sync is ever added it layers on top; it
   does not replace.
5. **Health data leaves the device only on an explicit online chat turn**, and
   only the slice needed for that turn. See Privacy And Data.
6. **This app gives information, never a diagnosis and never a dose.** Wording
   throughout is "what people commonly do" and "what your log shows", not "you
   have" or "take 400mg".
7. **No hardcoded colours in `lib/features/**`.** Same rule as Sellora — tokens
   only, through `context.t`.
8. Use SQLite transactions for multi-step writes (an episode plus its symptoms,
   relievers, and trigger rows is one write).
9. Do not add a network dependency to anything outside `lib/data/assistant/`.
10. **The app ships with no `INTERNET` permission.** Phases 0–3 are entirely
    offline, so the manifest stays as clean as Sellora's. Adding
    `<uses-permission android:name="android.permission.INTERNET"/>` is a
    Phase 4 decision and nothing else — it is the single line that makes health
    data capable of leaving the device, so it does not get added speculatively,
    "for later", or as a side effect of pulling in a package. A build with no
    network permission cannot leak the log even if a dependency tries.

    **Verify against the *merged* release manifest, not the source one.** A
    dependency can inject a permission this project never declares, so the
    source file being clean proves nothing:

    ```
    flutter build apk --release
    grep -o 'uses-permission[^>]*' \
      build/app/intermediates/merged_manifest/release/*/AndroidManifest.xml
    ```

    As of Phase 5 the expected set is exactly:

    | Permission | Source |
    |---|---|
    | `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | Flutter internal, self-scoped, not a capability |
    | `POST_NOTIFICATIONS` | `flutter_local_notifications`, declared by the plugin |
    | `VIBRATE` | `flutter_local_notifications`, declared by the plugin |
    | `RECEIVE_BOOT_COMPLETED` | Declared by us, so schedules survive a reboot |

    Anything outside that table is new and wants explaining. `INTERNET` is
    never acceptable.

    **Debug builds legitimately carry `INTERNET`** and that is not a violation.
    Flutter ships `android/app/src/debug/AndroidManifest.xml` declaring it so
    the tool can attach for hot reload and breakpoints. It applies to the debug
    variant only and never reaches a release APK. Do not "clean it up" — that
    breaks hot reload — and do not check the debug merged manifest and conclude
    the rule is broken.

## Technology Direction

**Flutter, Android-first, sideloaded APK.** No Play Store, no Apple Developer
account, no store review.

Decided over Expo/React Native on where the actual depth is: `sellora_mobile`
is 71 Dart files of architected app, against a 9-file Expo project on SDK 46
(2022, long EOL). Sellora is a reference here rather than a code source, so the
argument is fluency and proven pipeline, not lines saved —
`flutter build apk --release` is the entire distribution story for an app that
is never published, and every Expo advantage (OTA updates, cloud iOS builds)
only pays off when publishing to a store.

| Concern | Choice |
|---|---|
| Language / UI | Flutter (Dart), Material 3 |
| Local database | **SQLite via `sqflite`** — MySQL cannot run on a device |
| State | Riverpod |
| Routing | `go_router` |
| Notifications | `flutter_local_notifications` — scheduled on-device, no FCM |
| Online assistant | **Deferred to Phase 4 — provider undecided** |
| Key storage (if Phase 4 happens) | `flutter_secure_storage` (Android Keystore) |
| Health data import | Deferred — see Open Questions |

### On the "on-device AI model" question

Rejected for v1, for the same reasons `docs/INSIGHTS_DESIGN.md` in Sellora
rejected it there, plus one specific to health:

- **Gemini Nano / ML Kit GenAI** exposes task-specific APIs (summarize,
  proofread, rewrite) — there is no general chat API — and requires a flagship
  device (Pixel 9+/Galaxy S25+; Nano 4 wants 12GB RAM). Most phones are out.
- **`flutter_gemma` / MediaPipe** is the real general-purpose route and does
  work, but costs a ~1–1.5GB model download, several GB of RAM, and delivers
  quality far below Haiku 4.5.
- **A 2B quantized model missing a red flag is a different class of bug than a
  2B model writing clumsy prose.** The offline path must be deterministic.

The offline answer to "I have a migraine right now, what do I do?" is a curated
template plus the person's own history. That is a lookup, not a generation —
0MB, instant, works on a 3GB budget phone, and says the same correct thing every
time. `flutter_gemma` can slot in later as an extra tier without changing
anything below it.

## Architecture — Four Tiers

Every user input passes through the tiers in order. A tier that answers stops
the chain.

```
INPUT (symptom entry, or a question typed into chat)
  │
  ├─ TIER 0  Red-flag triage          offline · deterministic Dart · ALWAYS FIRST
  │          Matches emergency patterns → stops advice, escalates. Never skipped.
  │
  ├─ TIER 1  Templated guidance       offline · deterministic
  │          Curated self-care steps + this person's own history
  │          "your last 3 episodes eased ~40 min after a dark room"
  │
  ├─ TIER 2  Correlation insights     offline · arithmetic over local rows
  │          Weekly + on demand. Sellora's insights engine, retargeted.
  │
  └─ TIER 3  Open conversation        ONLINE ONLY · DEFERRED, provider undecided
             Only reached when 0–2 do not cover the question.
             Receives Tier 2's already-computed findings as context.
             It explains and converses. It never discovers patterns.
```

**Tiers 0–2 are the app, and they cost nothing to build or run** — local Dart
and SQLite arithmetic, no API, no key, no account. Phases 0–3 ship a genuinely
useful app with no AI provider involved at all.

Tier 3 is an enhancement layered on afterwards, deliberately deferred to
Phase 4. By then there will be real usage showing whether the Tier 1 templates
already answer what gets asked mid-attack — and if they do, Tier 3 never has to
exist. `AssistantClient` is an interface precisely so this stays a late,
reversible decision rather than a foundation.

When offline, or when no provider is configured, Tier 3 degrades to "no signal —
here's what your log says" and hands back to Tier 1/2.

## What To Learn From Sellora

**Sellora is a reference, not a source tree.** Do not copy files across. Read
the listed file, understand the pattern and *why* it is shaped that way, then
write this app's own version against this app's own domain.

This costs more time than copying and is the right trade: Sellora's code is
threaded with `business_id`, users, accounts, money, and stock — none of which
exist here. Porting it means spending the saved time instead on unpicking
assumptions, and leaving dead concepts in the schema forever. The valuable part
was never the code; it is the decisions already paid for in bugs — the pragma
sequence, the evidence gates, the token discipline.

Two things may be lifted closer to verbatim, because they are domain-free and
their subtleties are the whole point: the **`openOptions()` pragma sequence**
and the **`_localDay` day-math helpers**. Everything else gets rewritten.

| Study in `sellora_mobile` | For |
|---|---|
| `lib/core/sellora_tokens.dart` | Token `ThemeExtension`, light + dark. Rename, retune palette. |
| `lib/core/sellora_theme.dart` | `ThemeData` builders |
| `lib/core/sellora_ui.dart` | Shared widget library (`IconTile`, etc.) |
| `lib/core/theme_controller.dart` | Light/dark persistence |
| `lib/core/dates.dart` | `_localDay`-style day math — critical for correlation |
| `lib/core/brand_palette.dart` | Accent palettes (trim the list) |
| `lib/data/db/sellora_database.dart` | **Schema + migration pattern, including the foreign-keys-OFF pragma sequence.** Read the Database Migrations section of the Sellora guide before touching it. |
| `lib/data/insights/insight.dart` | `Insight` model — maps 1:1 |
| `lib/data/insights/insights_service.dart` | Rule structure, evidence gates, `_maxPerRule` capping |
| `lib/data/backup/` + `lib/data/export/` | Export the log as a file for a doctor |
| `lib/features/**` layout, shell, router | App skeleton |

**Dropped from Sellora:** users, accounts, businesses, `business_id` scoping.
This app has one person on one device. Every table is device-global.

### Rule mapping — the insights engine retargets almost directly

| Sellora rule | Sage equivalent |
|---|---|
| Day-of-week sales pattern (`_minWeekdayOccurrences`, `_weekdayGapThreshold`) | Episodes cluster on a weekday |
| Customer rhythm / quiet customer (`_minPurchasesForRhythm`, `_quietMultiplier`) | Attack frequency shifted from this person's own baseline |
| Refund concentration (`_minSalesForRefundRate`) | Share of episodes following a given trigger |
| Burn rate over a window | Rolling episode frequency |
| Dead stock | *(no equivalent — drop)* |

The gates should be **tighter** here than in Sellora, not looser. Health data is
noisier than sales data and the cost of a false pattern is someone changing
their diet for nothing.

## Data Model

SQLite. Timestamps are **epoch milliseconds**. IDs come from
`newLocalId(prefix)`. Both are Sellora conventions — keep them.

```
episodes
  id TEXT PK              kind TEXT ('migraine'|'reflux')
  started_at INTEGER      ended_at INTEGER NULL
  severity INTEGER        (1–10, required)
  notes TEXT              created_at / updated_at INTEGER

episode_symptoms         episode_id → episodes(id) ON DELETE CASCADE
  symptom_code TEXT       (see constants/symptoms.dart)

episode_relievers        episode_id, reliever_code, taken_at INTEGER
  helped INTEGER NULL     (-1 worse / 0 no change / 1 helped; NULL = unrated)

episode_triggers         episode_id, trigger_code
  source TEXT             ('user' = they said so | 'inferred' = Tier 2 found it)

daily_log                one row per local day — the correlation substrate
  local_day INTEGER PK    (days since epoch, NOT a timestamp)
  sleep_hours REAL        stress_level INTEGER (1–5)
  meals_skipped INTEGER   caffeine_units INTEGER
  alcohol_units INTEGER   water_glasses INTEGER
  late_meal INTEGER       (0/1 — ate within 3h of lying down; reflux rule)
  cycle_day INTEGER NULL

meds
  id TEXT PK              name TEXT
  dose_text TEXT          (free text the user typed — the app never suggests one)
  kind TEXT               ('rescue'|'preventive')
  active INTEGER

med_doses                 med_id, taken_at INTEGER, episode_id TEXT NULL

chat_messages
  id TEXT PK              role TEXT ('user'|'assistant')
  content TEXT            created_at INTEGER
  tier TEXT               ('triage'|'template'|'online') — provenance matters
  episode_id TEXT NULL
```

`local_day` on `daily_log` is a **day number, not a timestamp**. Correlating a
23:40 episode against "last night's sleep" is off-by-one if you compare
timestamps; Sellora's `_localDay` helper exists for exactly this and should come
across with the rest of `core/dates.dart`.

Reference data (`symptom_code`, `trigger_code`, `reliever_code`) lives in
`lib/constants/` as Dart constants, mirroring Sellora's `product_units.dart`
pattern — not in database tables. They ship with the build and never need
migrating.

## Red-Flag Triage

**This is the part that must not be wrong.** Deterministic Dart in
`lib/data/triage/`. No network, no model, no probability. A symptom checkbox or
a matched phrase fires it; when it fires, the app stops giving self-care advice
and says to seek emergency care.

Built on the standard **SNOOP** headache warning framework plus common upper-GI
warning signs:

**Headache / migraine**
- Sudden "thunderclap" onset, or "worst headache of my life"
- Fever, or neck stiffness
- Neurological deficit — weakness, numbness on one side, confusion, trouble
  speaking, vision loss
- Follows a head injury
- New pattern after age 50, or a clear change from this person's usual pattern
- Worse when lying flat, coughing, or straining
- During pregnancy or postpartum

**Reflux / upper GI**
- Chest pain radiating to arm, jaw, or back — especially with sweating,
  nausea, or shortness of breath *(cardiac until proven otherwise)*
- Difficulty or pain swallowing
- Vomiting blood, or coffee-ground vomit
- Black tarry stools
- Unintentional weight loss
- Persistent vomiting

Implementation rules:

- Triage runs **before** Tier 1 on every symptom entry and every chat message.
- The escalation screen is a distinct, unmissable UI state — not a banner on a
  normal answer.
- It fires on **any** match. No scoring, no thresholds, no "probably fine".
- Tier 3 never overrides Tier 0. The system prompt reinforces the same rules,
  but the deterministic check is what the app relies on.
- Log every fire to `chat_messages` with `tier='triage'` so the pattern is
  visible in the export.

> **Before shipping to anyone other than yourself,** review this list against a
> current clinical source. It is assembled from standard published warning signs
> and is not a substitute for clinical review.

## The Online Assistant (Tier 3) — DEFERRED

**Status: not being built yet, and possibly never.** Phases 0–3 deliver the
whole product without it. Revisit at Phase 4 with real usage in hand.

### Why it is deferred rather than designed now

The question Tier 3 answers is "did the Tier 1 templates fall short?" — and
that is not answerable from a plan. It is answerable from three weeks of
logging real attacks and noticing what you wanted to ask that the app could not
handle. Building it first would mean choosing a provider, a key-handling
strategy, and a privacy posture to solve a problem not yet demonstrated.

### Provider options, for when the decision comes

There is **no free tier for the Claude API** — the free tier on claude.ai is
the consumer chat product, not the API an app calls. Paid API access starts at
about a $5 credit purchase, which at personal usage (~20 messages/day on
`claude-haiku-4-5`, roughly $0.004 each) lasts many months.

Genuinely free options do exist:

| Provider | Free allowance | Notes |
|---|---|---|
| Gemini Flash | ~1,500 req/day, ~10/min, no card | Most generous; Pro models left the free tier April 2026 |
| Groq | 1,000 req/day, 200K tokens/day binds first (~80 turns) | Open models |
| Cloudflare Workers AI | 10,000 neurons/day (compute budget) | Smaller models |
| OpenRouter | 50/day until $10 lifetime spend | Not useful until paid |
| `flutter_gemma` on-device | Unlimited, no network | ~1–1.5GB model, several GB RAM, much weaker |

### The tradeoff to decide consciously

**Free API tiers are generally free because traffic may be used to improve the
provider's models. Paid tiers generally are not.** For most apps this is not
worth a paragraph. For a log of someone's migraines, reflux, sleep, and
medications, it is a real choice — and it directly contradicts the Privacy And
Data section below unless made deliberately.

Three coherent positions, all defensible:

- **Free provider** — accept that this data may be used for training. Fine for
  a solo app if you have decided it, not fine as a default nobody chose.
- **Paid Claude Haiku** — ~$5 buys months; paid traffic is not used for
  training. Best privacy per peso.
- **No Tier 3** — the app stays entirely local and the Privacy section stays
  literally true.

Whatever is chosen, record it here and update Privacy And Data to match.

### Key handling, if Phase 4 happens

Key in `flutter_secure_storage`, called directly from Dart. Correct while the
APK stays on your own device — an APK is a zip and any embedded key is
extractable, so this holds only as long as you do not share it.

**Upgrade path if you share the APK:** a single Cloudflare Worker proxy
(~100k req/day free, no cold start). Move the key and the system prompt there.
Gains a rate limit and the ability to change the prompt without redistributing
the APK. `AssistantClient` is an interface with two implementations for exactly
this reason — swapping is a provider change, not a rewrite.

**Context sent per turn** (this is the full list of what leaves the device):

- The system prompt (safety rules, tone, scope limits)
- The current conversation
- The last ~10 episodes: kind, severity, timestamps, symptoms, what helped
- Tier 2's **already-computed** findings as plain sentences

The model receives findings. It does not compute them. If a correlation appears
in an answer that Tier 2 did not produce, that is a bug.

**System prompt lives in `lib/data/assistant/system_prompt.dart`** as a single
const, versioned in git. It must: refuse diagnosis, never name a dose, defer to
Tier 0 on red flags, and stay inside migraine and reflux.

## Notifications

`flutter_local_notifications`, scheduled on-device. No push infrastructure.

- **Weekly pattern summary** — the highest-severity Tier 2 finding, once a week
- **Episode follow-up** — "still going?" a few hours after an unclosed episode
- **Daily log nudge** — optional, off by default

Android 13+ needs a runtime `POST_NOTIFICATIONS` request. Ask for it *after*
the person has logged something, not on first launch — permission asked before
value is shown gets denied.

## Design System

Same rules as Sellora, plus the decisions below.

Tokens through `context.t`, type through `context.text`, spacing through `Gap`
and `Radii`. No hex literals in `lib/features/**`.

### Olive green is the default accent

Decided 2026-09-06. Define it in this app’s own palette enum as the default
and the `fallback`:

```dart
olive('Olive', Color(0xFF5A6E3A), Color(0xFFA3B57A)),
```

Light accent ≈ 5.6:1 on the near-white canvas, dark accent ≈ 8.5:1 on the
near-black — both clear of AA. Follow Sellora's rule that the pair is
hand-picked, not one hue lightened programmatically; `accentSoft` and `onAccent`
stay computed by `withPalette`.

**Chosen partly for a functional reason, not only taste.** Olive is low-chroma.
Photophobia is a core migraine symptom, and a saturated accent is genuinely
unpleasant on a dimmed screen — which is exactly the condition the in-attack
flow runs under. Any future palette added here must stay muted for the same
reason. Sellora's brighter options (fuchsia, cyan, lime) are not carried over.

Keep the palette *mechanism* — the shape is worth reusing — but trim the
list to a few muted choices. This app has one user, not eighteen
businesses branding it.

### Green never encodes status

A green accent collides with the convention that green means "good", so here
the semantics move instead of the brand:

- **Severity runs neutral → amber → red. There is no green on the scale.**
  Olive belongs to the brand and to nothing else.
- **A day with no episode is neutral, not a success.** Do not colour it green,
  do not put a streak on it, do not congratulate it. Framing a quiet day as a
  win frames a bad day as a failure, and the user does not control which one
  they get. This is a chronic condition, not a habit tracker.
- Sellora's rule still stands underneath: nothing may signal success or failure
  through the accent alone.

**Severity is not the accent colour.** Sellora's rule that nothing signals
success or failure through the accent alone applies harder here: a severity-9
migraine must read as severe on every palette. Severity maps to the fixed
semantic tokens, never the user's chosen accent.

**In-attack UI is its own mode.** Phone screens hurt during a migraine. The
logging flow needs: large tap targets, minimal text, no white flash, and a
one-tap "I'm having one now" entry point. Consider forcing dark and reducing
motion inside that flow regardless of theme setting.

## Database Migrations

Follow Sellora's pattern exactly, including the parts that look strange:

- `SageDatabase.migrate(db, oldVersion)` is **public** so `test/migration_test.dart`
  can drive upgrades against hand-built old schemas.
- **Foreign keys OFF in `onConfigure`, back ON in `onOpen`.** Read the Database
  Migrations section of `SELLORA_MOBILE_PROJECT_GUIDE.md` before changing this
  — it documents three traps that already cost real data there, and the pragma
  sequence *is* the safety mechanism.
- Every schema change adds a migration test case from each still-plausible old
  version.
- Bump the export schema version to match.

## Signing

Release signing reads `android/key.properties`, which is gitignored and must
never be committed. When it is absent the release build falls back to the debug
key, so a fresh clone still builds — it just produces an APK that cannot update
an installed release build.

To set it up once:

```
keytool -genkey -v -keystore ~/sage-release.jks   -keyalg RSA -keysize 2048 -validity 10000 -alias sage
```

Then create `android/key.properties`:

```
storePassword=<what you just typed>
keyPassword=<what you just typed>
keyAlias=sage
storeFile=C:/Users/<you>/sage-release.jks
```

**Back the keystore up somewhere that is not this machine.** Losing it is
unrecoverable: an installed release build can never be updated in place again,
and the only way to install a newer version is to uninstall first — which wipes
the log. That is a worse outcome here than in most apps, because the log is the
product and there is no backup feature yet.

The release build does not minify or shrink resources. The app is sideloaded
rather than published, so there is no download size to defend, and an
obfuscated stack trace from your own phone is worse than a large APK.

## Privacy And Data

**As currently planned (Phases 0–3), no health data leaves the device at all.**
There is no account, no server, no analytics, and no network call anywhere
outside `lib/data/assistant/` — which is not built.

- All health data is local. There is no account and no server-side copy.
- **Cycle data is opt-in and off by default.** It is the most sensitive field in
  the schema, it never leaves the device any more than the rest does, and it
  appears in the doctor export only if it was recorded.
- The only possible egress is a Tier 3 chat turn, and only the slice listed
  above. That tier is deferred and may never ship.
- **If Tier 3 ships it is opt-in**, first use shows plainly what gets sent, and
  this section must be updated to name the provider and state whether that
  provider may use the data for model training. A free tier that trains on
  traffic is a defensible choice, but it must be written down here, not
  inherited by accident.
- Export produces a file the person shares deliberately via `share_plus`.
- No analytics SDK. No crash reporter that captures screen content.
- `android:allowBackup="false"` — as in Sellora.

## Roadmap

### Phase 0 — Foundation
Flutter project, own `core/` written against Sellora’s token/theme patterns,
database + migration test harness,
router and shell, theme. **Done when** an empty app builds to APK and installs.

### Phase 1 — The logging loop
`episodes`, symptoms, relievers. One-tap "having one now". History list. Edit
and close an episode. **Done when** you can log a real attack in under 30
seconds without network.

### Phase 2 — Safety and in-attack help
Tier 0 triage with the full red-flag set and its escalation screen. Tier 1
templated guidance keyed to symptoms. **Done when** the app is genuinely useful
mid-attack, offline, with no API key configured.

### Phase 3 — The correlation engine
`daily_log`, its entry UI, and the retargeted insights rules with evidence
gates. A `dump_insights.dart` tool as in Sellora. **Done when** it produces a
sentence you did not already know, from a seeded database.

### Phase 4 — The online assistant *(optional, decide at the time)*
**Entry condition:** three weeks of real use showing questions Tier 1 could not
answer. Write down two or three of them before starting. If you cannot, skip
this phase — that is a success, not a shortfall.

Then: pick a provider (see The Online Assistant), `AssistantClient`, secure key
storage, settings screen, Tier 3 chat with Tier 2 findings as context, graceful
offline degradation. **Done when** it answers a question the templates cannot,
and still says something useful with the network off.

### Phase 5 — Notifications
Weekly summary, episode follow-up, permission flow.

### Phase 6 — Export for a doctor
A clean chronological log plus the current findings, shared as a file.

### Phase 7 — Polish and release
Empty/loading/error states, contrast pass, narrow-screen check, signed release
APK. **Keep the keystore backed up** — losing it means users must uninstall to
update, wiping their log.

## Data Rules For Implementers

- `newLocalId(prefix)` for IDs; epoch milliseconds for timestamps.
- `daily_log.local_day` is a day number. Use the `_localDay` helper for every
  episode↔day comparison.
- One episode plus its symptoms/relievers/triggers is a **single transaction**.
- Never write an inferred trigger with `source='user'`.
- Invalidate affected Riverpod providers after writes.
- Correlation rules never query the network and never call the assistant.
- A rule whose evidence gate fails produces **nothing**. It is never softened
  into a hedge.

## AI Agent Operating Instructions

`CLAUDE.md` at the repository root carries the git and GitHub conventions —
identity, no attribution, branch per phase, no emoji in PRs — and the
pre-PR checklist. Read it first; it exists so a session on a different account
or tool starts from the same rules.

Before making changes:

1. Read this file and `CLAUDE.md`.
2. For anything touching design system, database, migrations, insights, or
   export — read the matching section of
   `../sellora_mobile/SELLORA_MOBILE_PROJECT_GUIDE.md` first. The patterns are
   deliberate and already debugged.
3. Keep edits scoped to the requested feature.
4. Update this guide when direction, roadmap, or feature status changes.

When changing the database: bump the version, add upgrade logic, add a
migration test case, keep `onCreate` and `onUpgrade` consistent, bump the export
schema version.

When changing triage or the system prompt: treat it as a safety change. Say so
explicitly in the commit, and do not bundle it with unrelated work.

When finishing: `dart format`, `flutter analyze`, `flutter test` for anything
touching repositories/database/triage/insights, and `flutter build apk --debug`
for anything touching routing, startup, or Android behavior.

## Definition Of Done

- Works offline unless it is explicitly Tier 3.
- Stores through the established repository/provider pattern.
- Handles empty, loading, success, validation, and error states.
- Refreshes affected screens after writes.
- Any correlation finding states the numbers it came from.
- Formatted and analyzed.
- Anything safety-related has a test.

## Known Gaps

The roadmap is complete. These are the things deliberately not built, in the
order they matter:

1. **The red-flag list has not been reviewed by a clinician.** Adequate for the
   author's own use; check it against a current clinical source before the APK
   goes to anyone else. Outstanding since Phase 2.
2. **Tier 3 is deferred** and may never be built. See The Online Assistant.
3. **Type is the platform font.** Bundled families were deferred in Phase 0 and
   never revisited.
4. ~~Preventive doses are not logged.~~ **Closed in Phase 11** — any dose can
   now be recorded on its own.

## Open Questions

Decide before the phase that needs them:

1. **Health Connect** — auto-import sleep and steps instead of manual entry?
   **Attempted in Phase 10 and rejected.** The `health` package's current
   release requires `share_plus ^12`, and this project is on `^13.3.0` for the
   export and backup share sheets; pub resolves `health` to **3.0.6** (2021,
   predating Health Connect entirely) rather than fail. Taking it would mean
   downgrading a dependency two shipped features use and rewriting their share
   calls, to add an import that cannot be tested without a device with Health
   Connect populated. Revisit when `health` supports `share_plus ^13`.
2. **Menstrual cycle tracking** — **Resolved in Phase 10: opt-in, off by
   default.** Shipping it on would put a period question in front of everyone
   who installs the app; shipping it not at all would drop one of the strongest
   patterns in migraine. Opt-in resolves that without deciding for anyone.
3. **Reflux and migraine in one app or two modes?** They share the logging
   substrate but have different triggers, symptoms, and red flags. Current plan
   is one app, `kind` on the episode. Revisit if the UI starts branching
   everywhere.
4. **Does Tier 3 happen at all, and on which provider?** *Deferred to Phase 4
   by decision, 2026-09-06.* Entry condition and options are in The Online
   Assistant section. Not a blocker for anything in Phases 0–3.
5. **Who else gets the APK?** Only matters if Tier 3 ships. Solo → keep the key
   on-device. Anyone else → a proxy, before you send the file.

## Feature Status

| Phase | State |
|---|---|
| 0 — Foundation | **Built.** Branch `phase-0-foundation`. |
| 1 — Logging loop | **Built.** Branch `phase-1-logging`. |
| 2 — Safety and in-attack help | **Built.** Branch `phase-2-safety`. |
| 3 — Correlation engine | **Built.** Branch `phase-3-correlation`. |
| 4 — Online assistant | Deferred by decision; may never be built |

### What Phase 12 added

- `MedCalendarScreen`: a month grid of medication intake. A marked cell
  means a dose that day, and a number means more than one. Tap a day to see its
  doses, remove one, or record a dose taken earlier that day.
- `MedQuickLog` on Today, for one-tap dose recording. Medication had only
  been reachable through Settings, the wrong place for something done daily,
  and during an attack in the case of rescue medication. It shows nothing at
  all when no medications exist, so Today never nags someone in pain.
- `core/calendar_month.dart`: the grid arithmetic, pure and tested.
- `dose_actions.dart`: record and remove with Undo, shared by every
  logger so they behave the same.

**A calendar cell makes no judgement.** There is no colour for "too much" and
none for "good". The limit belongs to the person and is counted over a rolling
30 days on the Medications screen. A calendar month is the wrong window for
that anyway, because it resets on the 1st and physiology does not. The marker is
the accent colour, which is the brand, not a status.

**The first day of the week comes from the locale.** It is Sunday in the
Philippines and Monday across most of Europe. The grid and its header both
read `MaterialLocalizations.firstDayOfWeekIndex`. The leading-blank arithmetic
is tested exhaustively over a year for both conventions, since an off-by-one
there shifts every date under the wrong weekday.

**Undo on removal restores the original row**, with its id, time and episode
link, rather than recording a new dose, which would silently unlink it from
the episode it was taken for. If that episode was deleted in between, the dose
comes back unlinked instead of failing on the foreign key.

A dose cannot be recorded in the future, and the calendar does not browse past
the current month.

#### The layout suite had been measuring spinners

The calendar's query was still running when its layout test ended, which
surfaced a harness bug dating back to Phase 7. sqflite queries run on a real
background isolate, and `pump` only advances the test's fake clock, so no
data-backed screen ever finished loading in the suite. Every one was measured
in its loading state.

`test/layout_test.dart` now calls `settle()`, which gives real time through
`runAsync` and then pumps, and **asserts no spinner remains** before checking
for overflow. That keeps the suite from quietly slipping back.

Measuring real screens found three overflows straight away:

- **History at 2x text, both widths.** The episode-kind label sat in a `Row`
  without `Flexible` and ran 47px past the edge. It now wraps.
- **Export at 320dp, 2x text.** The notice and the button row were fixed
  height with the preview in an `Expanded` between them, and on a small phone
  the fixed parts alone were taller than the screen. The notice now scrolls
  with the preview, and only the buttons stay pinned.

### What Phase 11 added

Asked for directly: someone using the app wants to track medication intake in
order to control it. Phase 9 only recorded doses attached to an episode, which
undercounts by however much the person does not feel like logging an attack.

- **Schema v2** — `meds.monthly_limit_days`, the first real migration.
- Standalone dose logging: `MedsRepository.recordDose`, with no episode.
- Per-medication intake over a rolling 30 days, on the Medications screen.
- A recent-dose list, so a mistake noticed later can still be removed.
- Intake in the doctor export.

**The unit is days used, not doses**, because that is how a limit is given.
Two tablets in one afternoon is one day.

**The window is rolling, not calendar.** "Ten days a month" resets mentally on
the 1st, and a calendar window would hand someone a clean slate on a date that
means nothing physiologically — hiding exactly the sustained pattern this is
for.

#### The limit is the person's, and never the app's

`monthly_limit_days` is null until someone fills it in, and the app never
suggests a value. How many days of a given medication is too many is a clinical
question with different answers for different drugs; a default here would be
the app quietly issuing medical advice, which non-negotiable 6 forbids.

A number in that field came from the person or from what their doctor told
them. All the app does is count against it — "used on 12 of the last 30 days,
against the 10 you set" is arithmetic on their own target, not a judgement of
the app's own. The export labels it a self-set limit for the same reason.

Null is not zero, and there are tests for both: with no limit set there is
nothing to be over, and a limit of nought is a real limit someone can exceed.
Being *at* the limit is not over it.

Going over uses `severityHigh`, not `alert`. Alert is reserved for red-flag
escalation, and spending it on a self-set target would blunt the one signal
that must never be ignorable.

#### The first migration

v1 to v2 is a single additive `ALTER`, guarded on `oldVersion >= 1` so a fresh
install — where `createSchema` already declares the column — does not run it
and fail on a duplicate. Three tests drive a hand-built v1 database forward
through `openOptions()`: the column arrives and every row survives, nothing
cascades away, and a fresh install ends up with exactly one copy of the column.

It also gave the backup its first real older-version file to restore. A v1
backup has no `monthly_limit_days`; the column takes its schema default rather
than the restore failing, which is the additive case `BackupService` was
written for and could not be proven until now.

### What Phase 10 added

Resolves both of the guide's outstanding Open Questions — one by building it,
one by finding out it cannot be built yet.

- `lib/data/insights/cycle.dart` — the perimenstrual arithmetic, pure and
  separate from the database.
- `lib/data/settings/cycle_tracking.dart` — the opt-in switch.
- A cycle section in the daily log, shown only when tracking is on.
- A perimenstrual correlation rule.

**Only day 1 is really recorded.** `cycle_day = 1` is a period start, and every
other day number and the whole rule are derived from those. Nobody is asked to
work out that today is day 14 — the day number fills itself in from the last
recorded start, and offers nothing when the answer would be absurd (day 97 is a
period that was never logged, not a 97-day cycle).

**The rule only classifies days inside a span bracketed by recorded starts.**
Before the first and after the last, "not around a period" is a guess: a day
three weeks after the last start might be mid-cycle, or might be a period
nobody logged. Counting those as baseline would manufacture the very pattern
the rule is looking for. There is a test that puts a cluster of episodes past
the end of the span and asserts none of the reported figures grow.

The window is two days before to three days after a period start — the
convention used in migraine research, written as a named constant with its
reason so nobody tunes it to fit their own data. It needs three recorded starts
before firing, because two starts is one cycle and one cycle is an anecdote.

Turning tracking off hides the question and keeps what was recorded. Deleting
on a toggle would be a surprise.

### Why Health Connect was rejected

Worth recording so it is not re-attempted from scratch. `flutter pub add health`
resolves to **3.0.6** — released in 2021, before Health Connect existed — because
the current `health 13.x` requires `share_plus ^12` while this project is on
`^13.3.0` for the export and backup share sheets.

The trade would have been: downgrade a dependency two shipped features rely on,
rewrite their share calls, and ship an integration that cannot be tested here
without a physical device with Health Connect installed and populated. Not worth
it for a convenience import. Revisit when `health` supports `share_plus ^13`.

### What Phase 9 added

- `lib/data/models/med.dart` + `MedsRepository` — medications and their doses.
- `MedsScreen`, reached from Settings.
- A medication picker on the episode editor, writing `med_doses` in the same
  transaction as the episode.
- A rescue-use count, in Patterns and in its own export section.

**There is no autocomplete, no drug database and no interaction check, and that
absence is the design.** A field offering completions would imply the app knew
what the drug was and had checked something about it. `dose_text` is free text
because people write "two at onset" and "half if it's bad"; a number and a unit
would either lose the instruction or invent precision that was never there.

- **"No longer taking this" is not deletion.** Deactivating keeps the row so
  past doses still name what was taken. Deleting cascades the doses away and
  rewrites a history the person may be showing a doctor — the dialog says so
  and offers the other route first.
- **A dose is timed to the episode's start, not to now.** Filling a form in a
  week later must not move the dose into today, which would put it in the wrong
  day for the rescue-use count.
- **Editing an episode rewrites only its own doses.** A dose on another episode
  is not the editor's to remove.

#### The rescue-medication count

`InsightsService.rescueUseFinding` reports distinct days with a rescue dose in
the last 30. It is **a count and nothing else**, and that restraint is
deliberate: how many days is too many is a clinical question with different
answers for different drugs, and this app has no view on it.

Reporting the figure only *above* some threshold would itself be a hidden
judgement, so it is reported whenever there is anything to report. A test seeds
20 rescue days in a month — clinically notable — and asserts the app still says
nothing about it.

It is `info` strength, so it cannot lead the Patterns list or become the weekly
notification, and it is suppressed entirely until the 30-day window has actually
been observed. "3 of the last 30 days" after a week of use describes a window
that never happened.

### What Phase 8 added

Not in the original roadmap. Added because it was the highest-value item left
in Known Gaps: non-negotiable 4 rules out cloud sync, so losing the phone means
losing years of data, and a manual backup is the only safety net that can exist
under that constraint.

- `lib/data/backup/backup_service.dart` — whole-database JSON export and
  restore.
- `BackupScreen`, reached from Settings.

**This is not the doctor export, and neither substitutes for the other.** The
doctor export is prose written for a human, lossy by design; nothing could
rebuild the database from it. The backup carries raw rows and a schema version.

Decisions that matter:

- **Restore replaces; it does not merge.** Merging two logs of the same
  condition needs identity rules nobody can specify — is an episode at 09:00 in
  both files one episode or two? Getting that wrong silently doubles someone's
  attack count and corrupts every rate the correlation engine computes.
  Replacing is blunt but knowable, and the dialog names what is about to be
  destroyed.
- **The whole restore is one transaction.** A half-applied restore — old
  episodes deleted, new ones not yet written — is the worst outcome this app
  could produce. There is a test that fails a restore partway and asserts the
  original data is untouched.
- **`inspect` is separate from `restore`** so the confirmation can say what is
  in the file before anyone agrees to anything. It writes nothing.
- **A backup from a newer build is refused**, because it may carry columns this
  one has never heard of and dropping them silently would lose data the user
  believes is backed up.
- **Unknown columns are dropped rather than fatal**, and missing ones take
  their schema default. That covers additive migrations, which is nearly all of
  them. A migration that renames or repurposes a column needs explicit handling
  in `restore` — this is the one place that will not just work.
- **`insertOrder` is load-bearing.** Foreign keys are enforced during a
  restore, so a child written before its parent fails outright. `deleteOrder`
  is its reverse.

When the schema version changes, bump nothing here — `BackupService.schemaVersion`
reads `SageDatabase.schemaVersion` directly, because Sellora's guide records
that a private duplicate of that number is exactly how the two drifted apart.

### What Phase 7 added

- `test/layout_test.dart` — every screen rendered at 320dp and 360dp, at 1x,
  1.5x and 2x text. 60 combinations, and an overflow fails the build.
- A vector adaptive launcher icon, replacing the default Flutter logo.
- Release signing via `android/key.properties` — see Signing above.
- Version to 1.0.0.

**Large text is not an edge case in this app.** Photophobia and visual aura are
core migraine symptoms, and a large system font is one of the first things
people with them turn on. An app for migraine that breaks at 2x text is broken
for a meaningful share of the people it is for, which is why that check is a
test rather than a manual pass.

Before trusting a layout suite, confirm it can fail: a deliberate `Row` of two
500dp boxes at 320dp was checked to produce `A RenderFlex overflowed by 680
pixels`. A green suite that cannot go red is worse than no suite.

> **Correction, Phase 12.** That check proved the suite could *detect* an
> overflow. It did not prove the screens had loaded. Under `testWidgets`' fake
> clock, sqflite's queries run on a real isolate and never complete inside
> `pump`, so every database-backed screen was measured showing its spinner.
> From Phase 7 to Phase 12 the suite genuinely covered only the static
> screens. Fixed in Phase 12, and it found three real overflows immediately.

The icon is vector-only — an adaptive icon plus an Android 13 monochrome layer,
no bitmap at any density. AGP renames resources in the release APK
(`res/0E.xml`), so grepping the zip for `ic_launcher` finds nothing; check
`resources.arsc` for the names instead.

**Not verified: how the icon actually looks.** It is a path written without
seeing it rendered. Install and glance at the launcher before assuming it is
right.

### What Phase 6 added

- `lib/data/export/export_service.dart` — the document, as plain text.
- `ExportScreen` — a full preview, then Copy or Share.
- `test/tools/dump_export.dart`, the counterpart to `dump_insights.dart`.

**Plain text, not PDF or Markdown.** A PDF costs a rendering dependency for
something a doctor is as happy to paste into a record; a `.md` file opened on a
phone shows the reader raw asterisks.

Four things the document must always do, each with a test:

- **Say everything is self-reported, above the numbers.** A clinician reading a
  tidy generated document can reasonably take it for measured data unless told
  otherwise before they start.
- **Never present a dose as a prescription.** `meds.dose_text` is reproduced
  verbatim and labelled as the person's own words.
- **Keep the correlational caveat beside the patterns**, not in a footer nobody
  reaches.
- **Include every safety check that fired.** Designed into Tier 0 for this —
  "the app told me to go to A&E and I did not" cannot be reconstructed from
  episode rows.

The preview screen is not decoration. This is the one place health data leaves
the phone, through whatever app the person picks from the share sheet. Handing
that over without showing what is in it would make the app's "everything stays
here" promise rest on trusting a button.

Smaller decisions: the person's own trigger attributions are printed as "they
thought", kept distinct from the app's findings in PATTERNS; an unrated
reliever prints "(not rated)" rather than blank, so it does not read as having
done nothing; summary figures are medians.

**Not built, and worth knowing:** `meds` still has no entry UI, so the
medications section is empty in practice. And there is no backup or restore —
losing the phone loses the log. Both are candidates for Phase 7 or a phase of
their own; neither was in this phase's scope.

### What Phase 5 added

- `lib/data/notifications/notification_policy.dart` — pure decisions: when to
  schedule, and what each notification says.
- `lib/data/notifications/notification_service.dart` — the plugin plumbing.
- A real `SettingsScreen`, replacing the placeholder: appearance, reminders,
  and a plain statement of where the data lives.

**Policy is split from plumbing** because the plugin is a platform channel that
cannot run in a test. Everything worth getting right — *whether* to send and
*what it says* — is pure and covered; only the delivery is untested.

Four rules encoded:

- **A notification with nothing to say is not sent.** Every policy method can
  return null, and null means silence. A weekly ping reading "no patterns yet"
  teaches someone to swipe the next one away without reading it, and the one
  after that is the one that mattered. `info`-strength findings do not qualify.
- **All three reminders are off by default.** An app that sends things nobody
  asked for gets its notifications disabled wholesale.
- **The permission is requested when a toggle is switched on, never at
  launch.** Android gives one good chance: asked before any value is shown it
  gets denied, and a second denial is permanent until the user digs into system
  settings.
- **Nothing may tell anyone to seek care.** Same rule as the insights, and more
  so — a notification can arrive days late and be read on a lock screen. There
  is a test.

Three Android details worth not rediscovering:

- **Core library desugaring is required** by `flutter_local_notifications`, and
  the build fails without it. Enabled in `android/app/build.gradle.kts`.
- **Scheduling is inexact on purpose.** Exact alarms need
  `SCHEDULE_EXACT_ALARM`, which on Android 14 is a separate user grant meant
  for alarm clocks. A summary that lands at 19:14 instead of 19:00 is the same
  summary.
- **`RECEIVE_BOOT_COMPLETED` and the boot receiver are declared by us**, not by
  the plugin. Without them every schedule is silently lost on the first reboot
  — which is exactly the case the weekly summary exists for, someone who has
  stopped opening the app.

Notifications post with `NotificationVisibility.private`, so the body is hidden
on a secure lock screen. "You had a migraine on 10 of the 20 days you slept
under 6 hours" is health data, and a lock screen is read by whoever picks the
phone up.

### What Phase 3 added

- `lib/data/models/daily_log.dart` + its repository — one row per local day,
  every measure nullable.
- `lib/data/insights/day_conditions.dart` — the yes/no day properties the
  engine tests, as SQL `guard`/`predicate` pairs.
- `lib/data/insights/insights_service.dart` — four rules: day-condition
  concentration, weekday clustering, frequency against the person's own
  baseline, and reliever track record.
- `DailyLogScreen`, `PatternsScreen`, and `test/tools/dump_insights.dart`.

**Null is the load-bearing part of this phase.** A blank measure means "not
recorded", and every condition's SQL `guard` is a NOT NULL check on the one
column it reads. A day where sleep was logged but stress was not is evidence
about sleep and no evidence at all about stress. If blanks were read as
"condition false" — which is what a `DEFAULT 0` would have produced — every
unlogged day would join the baseline and the rules would find patterns in
people's forgetfulness. There is a test for exactly this.

Gates, all deliberately tighter than Sellora's equivalents:

| Gate | Value | Why |
|---|---|---|
| `minEpisodes` | 8 | Floor below which every rule is arithmetic on noise |
| `minLoggedDays` | 14 | Day comparisons need day coverage |
| `minDaysEachSide` | 5 | Both sides, or it compares a sample to an anecdote |
| `minEpisodesOnCondition` | 3 | Cannot fire off one bad week |
| `minLift` | 2.0 | Twice as often, not 10% more |
| `minEpisodesForWeekday` | 12 over 12 weeks | Three Tuesdays is not a pattern |
| `minRatedRelieverAttempts` | 4 | Framed as a finding, so stricter than Tier 1's 3 |

Two subtleties worth not relearning:

- **A zero baseline needs an absolute floor as well as a ratio.** "3 of 5 days
  against 0 of 30" has infinite lift, which is why the ratio alone cannot be
  the test. The condition side must also clear 0.4.
- **Weekday rates divide by how many times that weekday actually occurred** in
  the window, not by a flat count — otherwise whichever weekday came round one
  time fewer is penalised.

**No insight is ever an alarm, and none may tell anyone to seek care.** Urgency
belongs to Tier 0, evaluated deterministically at the moment it matters; a card
someone reads next week is the wrong instrument for it. `InsightStrength` is
evidence, not urgency, and is carried by weight rather than an alarming colour.
There is a test asserting no finding's text matches emergency language.

Run `flutter test test/tools/dump_insights.dart` after touching a rule. A gate
can be right while the sentence built on it is unreadable, and only one of
those is caught by a test — that tool is how "You had **a reflux** on 11 of the
23 days" was found before anyone saw it on a screen.

### What Phase 2 added

- `lib/data/triage/` — the red-flag set and `TriageService`. `evaluate` is pure
  and synchronous, so nothing about the decision depends on I/O that could
  fail, and it can be exercised exhaustively in tests.
- `lib/data/guidance/` — fixed steps per condition, plus personal notes behind
  evidence gates (3 rated reliever attempts at 60% helped; 3 closed episodes
  for a duration).
- `SafetyCheckScreen`, `EscalationScreen`, `GuidanceScreen`, all on the root
  navigator so the tab bar cannot be used to step around the gate.

**The check gates advice, not logging.** Today's one-tap logging stays ungated
— the log is a fact, it costs nothing to be wrong about, and blocking it would
push someone to not log at all. Advice is different: the moment the app says
what to do about symptoms it owns whether that is right, and "lie down in a
dark room" is actively harmful for a subarachnoid haemorrhage. So every route
to guidance passes through the check, and `/guidance/:kind` is linked from
nowhere else.

Four rules encoded so they cannot quietly erode:

- **A single tap escalates. There is no Submit.** A list of checkboxes with a
  button underneath is a list someone can fill in and then put the phone down
  without pressing anything.
- **The escalation screen carries no self-care advice at all**, not even below
  the fold, and offers no path onward to guidance. A helpful-looking suggestion
  under the warning undoes the entire point of the gate.
- **Urgency is routing, not scoring.** Emergency and urgent both stop advice;
  they differ only in what the screen says to do. Collapsing them would either
  send someone with unexplained weight loss to an ambulance, or send someone
  with a thunderclap headache to make an appointment.
- **An unknown flag code is ignored, but a missing one fails towards care.**
  `evaluate` skips codes it does not recognise; `EscalationScreen` with an
  unresolvable code still tells the person to contact a doctor.

**Still outstanding:** the red-flag list has not been reviewed by a clinician.
It follows the SNOOP framework for headache plus the standard upper-GI alarm
features, and is adequate for the author's own use. Review it against a current
clinical source before this APK goes to anyone else.

### What Phase 1 added

- `lib/constants/` — episode kinds, symptoms, relievers and triggers as Dart
  constants, scoped per condition. **Codes are permanent once shipped**; a
  rename orphans every row that used it. Labels are free to be reworded.
- `lib/data/repositories/episode_repository.dart` — the only place episodes are
  written. Two invariants live there rather than at call sites: `started_day`
  is always derived from `started_at` (so editing a start time moves its day
  with it), and an episode plus its children is one transaction.
- `TodayScreen` — one large tap per condition records an accurate start time
  and nothing else. Severity defaults to `Severity.quickLogDefault` (5) and is
  refined later; the point is that the *timestamp* is captured while the person
  is in no state to fill in a form.
- `EpisodeEditorScreen` — one screen for create and edit, so the two cannot
  drift. Ten discrete severity targets rather than a slider: precise dragging
  is exactly what a bad migraine takes away.
- `HistoryScreen` — grouped by `started_day` as it renders.

Three rules encoded in code that are easy to undo by accident:

- **The editor never touches an inferred trigger.** A user-stated trigger is a
  belief; an inferred one is arithmetic. `update` clears only
  `source = 'user'` rows, and Phase 3 must read `daily_log` and inferred rows —
  never the user's own attributions, or the rules will confirm whatever the
  user already suspected and report it as a finding.
- **An unrated reliever is not "no change".** `helped` is nullable and null
  means unrated. Counting unrated attempts as neutral would drag every
  reliever's score down, and the people least likely to go back and rate are
  the ones having the worst episodes.
- **"Last time, X helped" is one remembered fact, and the wording says so.**
  Aggregate claims about what usually helps are a Phase 3 rule with an
  evidence gate that states its numbers.
| 5 — Notifications | **Built.** Branch `phase-5-notifications`. |
| 6 — Doctor export | **Built.** Branch `phase-6-export`. |
| 7 — Polish and release | **Built.** Branch `phase-7-polish`. |
| 8 — Backup and restore | **Built.** Branch `phase-8-backup`. Added after the original roadmap. |
| 9 — Medications | **Built.** Branch `phase-9-medications`. |
| 10 — Cycle tracking | **Built.** Branch `phase-10-cycle`. |
| 11 — Medication intake | **Built.** Branch `phase-11-intake`. Schema v2. |
| 12 — Medication calendar | **Built.** Branch `phase-12-med-calendar`. |

### What Phase 0 actually laid down

- `lib/core/` — `SageTokens` (`ThemeExtension`, no `success` token by design),
  `buildSageTheme`, six low-chroma palettes with olive as `fallback`,
  `ThemeController`, `newLocalId`, and the day arithmetic.
- `lib/data/db/sage_database.dart` — schema v1 and the `openOptions()` pragma
  sequence.
- `lib/router.dart` + `lib/features/shell/` — four-tab `StatefulShellRoute`
  with per-tab stacks. Each tab renders a `PlaceholderScreen` naming the phase
  that owns it, so an unbuilt screen reads as unfinished rather than as an
  empty state.
- `test/` — 74 tests: migrations driven through the real open path, day
  arithmetic, and a contrast pass over every palette in both brightnesses.

Two things worth not relearning:

- **`localDayOf` re-anchors the local calendar date to UTC midnight before
  dividing.** Dividing a local midnight's epoch millis is off by one anywhere
  east or west of UTC — in UTC+8, local midnight on the 6th is 16:00 on the
  5th in UTC. `dates_test.dart` caught it; keep those tests.
- **The release APK carries no `INTERNET` permission, verified against the
  merged manifest.** The debug variant does carry it, from Flutter's own
  `src/debug/AndroidManifest.xml`, for hot reload. That is expected — see
  non-negotiable 10.
