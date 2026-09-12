# Scheduled battle effects (v1)

Moves may contain a `scheduled_effect` recipe with `effect_id`, `effect_group`, `owner`, `trigger`, `delay_turns`, `repeat_count`, `stacking`, `payload`, and optional `animation_id`. Recipes are immutable authoring data: battle resolution copies them into `BattleEffectInstance`, which holds source/target references and mutable delay/repeat counters.

Owners are `user_battler`, `target_battler`, or `battle`; triggers are `start_of_turn` and `end_of_turn`. Payload kinds are `heal`, `damage`, `condition`, and `stat_change`. Heal/damage amounts from 0 through 1 are fractions of maximum HP; larger values are flat points. Condition payloads use `condition` and optional `chance`. Stat changes accept either `stat` plus `amount`, or a `changes` array using the existing stat-change shape.

`replace_group` removes an existing instance only when both owner identity and `effect_group` match. Other stacking names are reserved but rejected in v1. Battler-owned effects are removed on faint or switch, and the registry is cleared at battle start/end. A matching phase decrements a pending delay or, when ready, requests animation playback, executes the payload, decrements its trigger count, and expires it at zero. Animation lookup/playback is intentionally non-authoritative: failure never prevents mechanics.

Deferred: reactive triggers, Counter integration, weather migration, hazards, switch persistence, stack/refresh/reject semantics, and Move Creator UI.
