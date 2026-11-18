# When no agent can run a plan

Load this in Step 3 of the strategist, when the work needs a capability no agent declares.

## What to do

1. **Write the plan with the true capability anyway.** Do not bend the plan to fit an agent
   that exists. A Rust plan that says `implement` only would be handed to a developer who
   cannot do it.
2. **Check the roster for that exact word:**

   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/skills/check-in/scripts/roster.py" --covers implement,rust
   ```

   No output means nobody covers that set.
3. **Report the gap** in your final message, one line per missing word:

   ```
   Roster gap: PLAN-021 needs "rust". No agent declares it.
     Suggest: an agent file declaring capabilities [implement, rust].
   ```

That is all. The plan stays pending. In a check-in, the user decides at approval whether to
add an agent, change the plan, or deny it. A shift will not approve a plan nobody can run, so
it waits for the user.

## What not to do

- **Never write an agent file.** Adding a member to the guild is the user's decision.
- **Never pin a near match** to get around the gap. A pin skips the capability check entirely.
- **Never drop a required word** to make the match succeed. The gap is the information the
  user needs.

## Spelling

A capability is matched exactly. Use lowercase letters, digits and hyphens only (the schema
refuses anything else). Before inventing a word, check the roster for one that already means
the same thing. `e2e` and `end-to-end` would be two words that never match each other.
