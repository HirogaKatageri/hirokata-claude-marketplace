# Arming a shift, and notifying on it

Two opt-in features on top of the core loop: running shifts on a schedule, and pushing a
notification when one needs the user. Neither is part of running a single shift. Set them
up only when the user asks.

## Arming it on a schedule — opt-in, per project

A shift is one run. A schedule is what makes it a night's work. Both of these run **this
skill**:

```
/loop 30m /guild:shift              # this session, on an interval
```

or a scheduled agent (the `schedule` skill) running `/guild:shift` on a cron expression.

**Only set one up when the user asks, and only for the project they asked about.** Say what
it will do and how it stops: each run works until its budget runs out or only the user can
move the board, the budget applies per run, and a run that ends with `needs-user` makes
the next run end the same way until the user acts. Tell them how to turn it off in the same
breath.

## Notifications — when a shift needs the user

**Opt-in per project.** The switch is a file, so it is a fact and not a memory:

```bash
[ -f .guild/shift.notify ] && echo "notifications on"
```

Create it only when the user says yes. Absent means **never notify**.

When it exists, send **PushNotification** on exactly two kinds of stop: **`needs-user`**,
and an **abnormal stop** (`infrastructure` or `collision`, because both mean the run ended
early and something is wrong). One line, under 200 characters, leading with what they would
act on:

> `3 plans need your approval, 1 stuck plan. 6 plans done, 2 projects documented, 48 min.`

Never notify on `max-plans`, `max-minutes`, `idle` or `operator`, or on progress. A shift
that pushes for every event trains the user to mute it, and then the one that mattered
arrives silenced.
