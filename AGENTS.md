# AGENTS.md

Notes is a Silica app: the rules of `silica-desktop/AGENTS.md` apply (clean-room, assets,
never crash, everything is a command, measured parity, English everywhere). On top of them:

- Interface texts are our own words, in English with translations (`lib/l10n/*.arb`).
- Look and measures come from the Amalfi kit (`App · Notes`, `Apps/Notes/*`); values the kit
  does not give are named constants marked provisional in `lib/src/style.dart`.
- The storage format is documented in `docs/format.md`; change both together.
- Before every commit: `dart format --set-exit-if-changed lib test`,
  `flutter analyze --fatal-infos`, `flutter test`, `tool/check_assets.sh`.
- No dead controls: a feature that does not work is not shown, and has an issue.
- Nothing may reach the user's desktop from tests (`lib/src/external.dart`, `startsNothing`);
  tests write their files in temporary directories only.
