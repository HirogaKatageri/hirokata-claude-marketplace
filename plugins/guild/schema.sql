-- =====================================================================================
-- guild — THE SCHEMA IS THE TOOL                                   (schema version 10)
-- =====================================================================================
--
-- APPLY IT
--
--   export PATH="$HOME/.turso:$PATH"
--   tursodb .guild/guild.db < schema.sql
--
-- It is IDEMPOTENT. Tables are `CREATE TABLE IF NOT EXISTS`, so data survives. Views and
-- triggers are DROPPED AND RECREATED every time, so re-applying the file is how a rule
-- changes. Seed rows are guarded by `WHERE NOT EXISTS`.
--
-- VERSION 10 IS A FRESH START. It is not a migration of version 9. The task, execution
-- graph, bug and review_finding tables are gone, and no script converts an old board.
-- A board reporting `SELECT version FROM schema_version` below 10 must be archived and a
-- new `.guild/guild.db` created from this file. Applying this file over an old board
-- leaves the old tables standing beside the new ones and is never what you want.
--
-- ------------------------------------------------------------------------------------
-- THE MODEL, TOP TO BOTTOM
--
--   goal         what the user wants to achieve. A concrete metric or a plain outcome,
--                such as "Build a CMS system". Its `success_criteria` says how to tell.
--   project      a large piece that must be built to reach the goal, such as "User
--                registration". A project is DONE when every one of its requirements is.
--   requirement  one thing the project must do. DONE when every plan under it is done.
--   plan         HOW part of a requirement is built, and the unit of work. A plan names
--                the capabilities it needs, and the orchestrator picks the agent whose
--                frontmatter covers them. A requirement may have several plans.
--
--   issue        a problem found by a project review, by a failed plan, by QA or by the
--                user. Always tied to a project. Reviews REPORT issues and fix nothing.
--   doc          what was built and why, written after a project's review. Docs carry
--                tags and link to each other as a graph.
--
-- ------------------------------------------------------------------------------------
-- STATUS — ONE VOCABULARY FOR ALL FOUR LEVELS
--
--   open         not started
--   in-progress  started. For a plan, an agent is running it OR it failed and an
--                execution issue is open against it (see `v_plans_stuck`).
--   done         finished
--
-- A plan's APPROVAL is a separate column: pending -> approved | rejected. Status says
-- whether the work ran. Approval says whether anybody agreed it should.
--
-- Status ROLLS UP by trigger, so nobody has to remember to do it:
--   * a plan going `in-progress` moves its requirement, project and goal to
--     `in-progress` when they are still `open`
--   * the last plan of a requirement going `done` moves the requirement to `done`
--   * the last requirement of a project going `done` moves the project to `done`
-- A GOAL NEVER CLOSES ITSELF. Whether the goal is met is a judgment against its
-- `success_criteria`, and more projects may still be needed. `v_goals_complete` lists
-- goals whose projects are all done, for a person to rule on.
--
-- ------------------------------------------------------------------------------------
-- DEPENDENCIES — `depends_on` AT EVERY LEVEL
--
-- Each level has its own dependency table, so both ends carry a real foreign key and a
-- link to something that does not exist is refused. Dependencies stay within one level:
-- a plan depends on plans, a project on projects.
--
-- A PLAN IS READY when it is approved and `open`, every plan it depends on is done, AND
-- every dependency of its requirement, its project and its goal is done. That last part
-- is what makes `depends_on` mean something above the plan level. `v_plans_ready` is the
-- one definition of it.
--
-- ------------------------------------------------------------------------------------
-- WHAT THIS FILE CANNOT ENFORCE
--
--   1. WHO MOVES A STATUS. SQL has no identity. `guild_state.actor` is a label a member
--      sets on itself and the triggers copy into `event.actor`. It is not authentication.
--   2. DEPENDENCY CYCLES. A self-dependency is refused, but A -> B -> A is not, because
--      tursodb has no `WITH RECURSIVE`. A cycle stalls every plan in it silently.
--      `v_plans_blocked` shows the plans waiting, and spotting the loop is a review duty.
--   3. FILE DISJOINTNESS. `plan.files` lists what a plan touches. That two plans running
--      at once touch different files is the strategist's promise, and nothing checks it.
--   4. CAPABILITY SPELLING. The words a plan may ask for are whatever the agent files
--      declare. A misspelled capability inserts fine and matches nobody.
--   5. HUMAN APPROVAL. `plan.approval` is a column anyone can write. In a check-in the
--      user approves. In a shift the orchestrator approves and signs `approved_by`.
--   6. ISSUE CONSISTENCY. An issue's `plan_id` and `requirement_id` should sit under its
--      `project_id`. `v_issue_mismatch` lists any that do not.
--
-- ------------------------------------------------------------------------------------
-- ENGINE NOTES — tursodb
--
--   * No `WITH RECURSIVE`, no FTS5. Every view here is one hop.
--   * STRICT tables accept INT, INTEGER, REAL, TEXT, BLOB and ANY. Keep to TEXT and
--     INTEGER.
--   * The stdin splitter ends a statement at a `;` that ends a line, even inside a
--     string. Send free text as CAST(x'<hex>' AS TEXT). Nothing in this file has a `;`
--     inside a string or at the end of a comment line. Keep it that way.
--   * Widening a CHECK means rebuilding the table. Choose words you can live with.
--
-- TIMESTAMPS are UTC text to the SECOND everywhere, `%Y-%m-%dT%H:%M:%SZ`, including
-- `event.ts`. One format means plain text comparison is correct. Events in the same
-- second are ordered by `event.id`.
--
-- IDS are text with a prefix: GOAL-001, PROJ-001, REQ-001, PLAN-001, ISSUE-001. Views
-- never order by id alone, because 'PLAN-1000' sorts before 'PLAN-999' as text. They
-- order by priority, then `created_at`, then id.
-- =====================================================================================


-- =====================================================================================
-- PRAGMAS — `busy_timeout` and `foreign_keys` are per connection. Re-issue them at the
-- top of every script, or foreign keys are off for that session.
-- =====================================================================================
PRAGMA journal_mode = WAL;
PRAGMA busy_timeout = 5000;
PRAGMA foreign_keys = ON;


-- =====================================================================================
-- BOOKKEEPING — schema_version, guild_state
-- =====================================================================================
CREATE TABLE IF NOT EXISTS schema_version (
  id         INTEGER PRIMARY KEY CHECK (id = 1),
  version    INTEGER NOT NULL,
  applied_at TEXT
) STRICT;

INSERT INTO schema_version (id, version, applied_at)
SELECT 1, 10, strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
WHERE NOT EXISTS (SELECT 1 FROM schema_version WHERE id = 1);

-- Seeded keys:
--   last-checkin  when the last check-in or shift started. 'null' until the first one.
--   actor         who is writing right now. Every trigger copies it into `event.actor`.
CREATE TABLE IF NOT EXISTS guild_state (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL DEFAULT ''
) STRICT;

INSERT INTO guild_state (key, value)
SELECT 'last-checkin', 'null'
WHERE NOT EXISTS (SELECT 1 FROM guild_state WHERE key = 'last-checkin');

INSERT INTO guild_state (key, value)
SELECT 'actor', 'orchestrator'
WHERE NOT EXISTS (SELECT 1 FROM guild_state WHERE key = 'actor');


-- =====================================================================================
-- THE HIERARCHY — goal, project, requirement, plan
-- =====================================================================================
-- Priority is 1 (highest) to 5 (lowest) everywhere it appears.

CREATE TABLE IF NOT EXISTS goal (
  id               TEXT PRIMARY KEY,           -- GOAL-001
  title            TEXT NOT NULL,              -- 'Build a CMS system'
  body             TEXT NOT NULL DEFAULT '',
  -- How to tell the goal is met. A number with a target ('p95 page load under 1s') or a
  -- plain outcome ('editors can publish without a developer'). Never empty, because a
  -- goal nobody can check is a goal nobody can close.
  success_criteria TEXT NOT NULL CHECK (length(trim(success_criteria)) > 0),
  status           TEXT NOT NULL DEFAULT 'open'
                   CHECK (status IN ('open', 'in-progress', 'done')),
  priority         INTEGER NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),
  created_at       TEXT NOT NULL,
  updated_at       TEXT NOT NULL
) STRICT;

-- `isolation` decides where the project's plans run:
--   shared    in the repository's working tree, beside every other shared project
--   worktree  in their own git worktree at `worktree_path`, so no file collisions
-- Nothing here creates or checks the worktree. That is the orchestrator's job.
--
-- `reviewed_at` and `documented_at` mark the two steps that follow a project reaching
-- `done`: the review, which files issues, and the documentation, which writes docs.
-- `v_projects_to_review` and `v_projects_to_document` read them.
CREATE TABLE IF NOT EXISTS project (
  id            TEXT PRIMARY KEY,              -- PROJ-001
  goal_id       TEXT NOT NULL REFERENCES goal(id),
  title         TEXT NOT NULL,                 -- 'Implement user registration'
  body          TEXT NOT NULL DEFAULT '',
  status        TEXT NOT NULL DEFAULT 'open'
                CHECK (status IN ('open', 'in-progress', 'done')),
  priority      INTEGER NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),
  isolation     TEXT NOT NULL DEFAULT 'shared'
                CHECK (isolation IN ('shared', 'worktree')),
  worktree_path TEXT,
  reviewed_at   TEXT,
  documented_at TEXT,
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL,
  CHECK (isolation = 'worktree' OR worktree_path IS NULL),
  CHECK (documented_at IS NULL OR reviewed_at IS NOT NULL)
) STRICT;

-- `project_id` is REQUIRED. Every requirement traces to a project and a goal, which is
-- what lets a shift approve a plan on its own.
CREATE TABLE IF NOT EXISTS requirement (
  id          TEXT PRIMARY KEY,                -- REQ-001
  project_id  TEXT NOT NULL REFERENCES project(id),
  title       TEXT NOT NULL,
  body        TEXT NOT NULL DEFAULT '',        -- the requirement, with acceptance criteria
  status      TEXT NOT NULL DEFAULT 'open'
              CHECK (status IN ('open', 'in-progress', 'done')),
  priority    INTEGER NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
) STRICT;

-- ---- plan ---------------------------------------------------------------------------
-- THE UNIT OF WORK. One agent runs one plan from start to finish.
--
--   kind      build  writes or changes the product
--             test   writes and runs tests for a build plan. It depends on that plan.
--             fix    resolves one or more issues. Linked from `issue.fix_plan_id`.
--   approval  pending -> approved | rejected. Only an approved plan can run. A rejected
--             plan never runs, so any plan depending on it waits until the strategist
--             replaces it and the dependency is moved.
--   approved_by  'user' in a check-in, 'orchestrator' in a shift.
--   agent     an optional PIN: the `name` of a subagent. When set, the orchestrator
--             spawns that agent and skips capability matching.
--   files     a JSON array of the paths this plan touches.
--
-- A FAILED PLAN STAYS `in-progress`. The orchestrator files an issue with
-- `source = 'execution'` and this plan's id, and `v_plans_stuck` lists it. When that issue
-- is resolved the orchestrator either sets the plan back to `open` to run again, or to
-- `done` when the fix covered it.
CREATE TABLE IF NOT EXISTS plan (
  id             TEXT PRIMARY KEY,             -- PLAN-001
  requirement_id TEXT NOT NULL REFERENCES requirement(id),
  kind           TEXT NOT NULL DEFAULT 'build'
                 CHECK (kind IN ('build', 'test', 'fix')),
  title          TEXT NOT NULL,
  body           TEXT NOT NULL DEFAULT '',     -- the plan itself
  files          TEXT NOT NULL DEFAULT '[]'
                 CHECK (json_valid(files) AND json_type(files) = 'array'),
  status         TEXT NOT NULL DEFAULT 'open'
                 CHECK (status IN ('open', 'in-progress', 'done')),
  approval       TEXT NOT NULL DEFAULT 'pending'
                 CHECK (approval IN ('pending', 'approved', 'rejected')),
  approved_by    TEXT,
  approved_at    TEXT,
  priority       INTEGER NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),
  agent          TEXT,
  claimed_by     TEXT,                         -- the agent that actually ran it
  started_at     TEXT,
  finished_at    TEXT,
  created_at     TEXT NOT NULL,
  updated_at     TEXT NOT NULL,
  -- a decision carries who made it and when
  CHECK (approval = 'pending' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)),
  -- only an approved plan can have started
  CHECK (status = 'open' OR approval = 'approved')
) STRICT;

-- ---- plan_capability ----------------------------------------------------------------
-- What a plan needs, matched for EQUALITY against `capabilities:` in agent frontmatter.
--   required = 1  the agent must declare it
--   required = 0  preferred. Ranks eligible agents and never excludes one.
-- Matching rule, applied by the orchestrator: pin first. Otherwise an agent is eligible
-- when it covers every required capability. Rank by most preferred covered, then fewest
-- declared capabilities (a specialist beats a generalist), then name.
CREATE TABLE IF NOT EXISTS plan_capability (
  plan_id    TEXT NOT NULL REFERENCES plan(id) ON DELETE CASCADE,
  capability TEXT NOT NULL
             CHECK (length(capability) BETWEEN 1 AND 64
                    AND capability GLOB '[a-z]*'
                    AND NOT capability GLOB '*[^a-z0-9-]*'),
  required   INTEGER NOT NULL DEFAULT 1 CHECK (required IN (0, 1)),
  PRIMARY KEY (plan_id, capability)
) STRICT;


-- =====================================================================================
-- DEPENDENCIES — one table per level, both ends a real foreign key
-- =====================================================================================
-- Read a row as "<id> depends on <depends_on>". Direct dependencies only.

CREATE TABLE IF NOT EXISTS goal_dependency (
  goal_id    TEXT NOT NULL REFERENCES goal(id) ON DELETE CASCADE,
  depends_on TEXT NOT NULL REFERENCES goal(id) ON DELETE CASCADE,
  PRIMARY KEY (goal_id, depends_on),
  CHECK (goal_id <> depends_on)
) STRICT;

CREATE TABLE IF NOT EXISTS project_dependency (
  project_id TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
  depends_on TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
  PRIMARY KEY (project_id, depends_on),
  CHECK (project_id <> depends_on)
) STRICT;

CREATE TABLE IF NOT EXISTS requirement_dependency (
  requirement_id TEXT NOT NULL REFERENCES requirement(id) ON DELETE CASCADE,
  depends_on     TEXT NOT NULL REFERENCES requirement(id) ON DELETE CASCADE,
  PRIMARY KEY (requirement_id, depends_on),
  CHECK (requirement_id <> depends_on)
) STRICT;

CREATE TABLE IF NOT EXISTS plan_dependency (
  plan_id    TEXT NOT NULL REFERENCES plan(id) ON DELETE CASCADE,
  depends_on TEXT NOT NULL REFERENCES plan(id) ON DELETE CASCADE,
  PRIMARY KEY (plan_id, depends_on),
  CHECK (plan_id <> depends_on)
) STRICT;


-- =====================================================================================
-- RECORDS — plan_log, issue
-- =====================================================================================

-- Append-only notes from the agent running a plan. Send `entry` as hex.
CREATE TABLE IF NOT EXISTS plan_log (
  id      INTEGER PRIMARY KEY,
  plan_id TEXT NOT NULL REFERENCES plan(id),
  ts      TEXT NOT NULL,
  agent   TEXT NOT NULL,
  entry   TEXT NOT NULL
) STRICT;

-- ---- issue --------------------------------------------------------------------------
-- Every problem the guild knows about, from any source, ALWAYS tied to a project.
--
--   source    review     the project review found it
--             execution  a plan failed while running. `plan_id` is that plan, and the
--                        plan shows in `v_plans_stuck` until the issue is resolved.
--             discovered an agent found it while running a plan, outside that plan's
--                        scope. `plan_id` says where it was found. The plan is NOT stuck.
--             qa         a QA pass found it
--             user       the user reported it
--   status    open -> in-progress -> done, or wontfix
--   fix_plan_id  the `fix` plan resolving it, when the fix is guild work
--   fix_ref      a commit, PR or release, when the fix happened outside the board
--
-- A review never fixes anything. It writes issues and stops. Turning an issue into a fix
-- plan is a decision for the next check-in or shift.
CREATE TABLE IF NOT EXISTS issue (
  id             TEXT PRIMARY KEY,             -- ISSUE-001
  project_id     TEXT NOT NULL REFERENCES project(id),
  requirement_id TEXT REFERENCES requirement(id),
  plan_id        TEXT REFERENCES plan(id),
  source         TEXT NOT NULL
                 CHECK (source IN ('review', 'execution', 'discovered', 'qa', 'user')),
  severity       TEXT NOT NULL DEFAULT 'major'
                 CHECK (severity IN ('critical', 'major', 'minor', 'nit')),
  status         TEXT NOT NULL DEFAULT 'open'
                 CHECK (status IN ('open', 'in-progress', 'done', 'wontfix')),
  title          TEXT NOT NULL,
  body           TEXT NOT NULL DEFAULT '',
  file           TEXT,
  line           INTEGER,
  found_by       TEXT NOT NULL,                -- agent name or 'user'
  fix_plan_id    TEXT REFERENCES plan(id),
  fix_ref        TEXT NOT NULL DEFAULT '',
  created_at     TEXT NOT NULL,
  updated_at     TEXT NOT NULL,
  -- an execution failure always names the plan that failed
  CHECK (source <> 'execution' OR plan_id IS NOT NULL),
  -- a fixed issue says where the fix is
  CHECK (status <> 'done' OR fix_plan_id IS NOT NULL OR length(trim(fix_ref)) > 0)
) STRICT;


-- =====================================================================================
-- QUALITY AREAS — coverage, inspection, inspection_coverage
-- =====================================================================================
-- Unchanged from version 9. What the product is made of from a QA point of view, and
-- the passes that visit it. Defects a pass finds are `issue` rows with source 'qa'.

CREATE TABLE IF NOT EXISTS coverage (
  id                TEXT PRIMARY KEY,          -- 'checkout-flow'
  area              TEXT NOT NULL,
  risk              TEXT NOT NULL DEFAULT 'medium'
                    CHECK (risk IN ('high', 'medium', 'low')),
  spec_path         TEXT,
  last_inspected_at TEXT,
  notes             TEXT NOT NULL DEFAULT ''
) STRICT;

-- `trigger` is left open on purpose. Only 'manual' is written today.
CREATE TABLE IF NOT EXISTS inspection (
  id          TEXT PRIMARY KEY,                -- INSP-001
  scope       TEXT NOT NULL,
  "trigger"   TEXT NOT NULL DEFAULT 'manual',
  status      TEXT NOT NULL DEFAULT 'open'
              CHECK (status IN ('open', 'in-progress', 'done')),
  started_at  TEXT,
  finished_at TEXT
) STRICT;

CREATE TABLE IF NOT EXISTS inspection_coverage (
  inspection_id TEXT NOT NULL REFERENCES inspection(id),
  coverage_id   TEXT NOT NULL REFERENCES coverage(id),
  verdict       TEXT CHECK (verdict IS NULL
                            OR verdict IN ('pass', 'issues', 'not-reached')),
  PRIMARY KEY (inspection_id, coverage_id)
) STRICT;


-- =====================================================================================
-- THE LIBRARY — doc, doc_tag, doc_edge, doc_revision
-- =====================================================================================
-- A graph of documentation. Each `doc` is a NODE. Each `doc_edge` is a typed, directed
-- link between two docs. `doc_tag` holds the keywords that say what a doc is for, and two
-- docs sharing a tag are related even before anyone links them (`v_doc_related`).
--
-- After a project's review, the librarian writes what was done: one or more docs with
-- `project_id` set, tagged, and linked to the docs they build on.
--
--   kind    business   the domain's rules
--           technical  how a part of the system works now
--           decision   one choice, its reasons and the alternatives (an ADR)
--           research   an outside lookup worth keeping
--           runbook    steps for an operation
--           reference  anything else
--   status  draft | current | superseded | rejected. Superseded and rejected docs stay,
--           because they are how a reader learns why things changed.

CREATE TABLE IF NOT EXISTS doc (
  slug       TEXT PRIMARY KEY,                 -- 'user-registration-flow'
  project_id TEXT REFERENCES project(id),      -- the project it documents, if any
  title      TEXT NOT NULL,
  body       TEXT NOT NULL,
  kind       TEXT NOT NULL DEFAULT 'reference'
             CHECK (kind IN ('business', 'technical', 'decision',
                             'research', 'runbook', 'reference')),
  status     TEXT NOT NULL DEFAULT 'current'
             CHECK (status IN ('draft', 'current', 'superseded', 'rejected')),
  author     TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) STRICT;

-- Same alphabet as capabilities: lowercase letters, digits and '-', so 'Auth' and 'auth'
-- cannot become two tags.
CREATE TABLE IF NOT EXISTS doc_tag (
  slug TEXT NOT NULL REFERENCES doc(slug) ON DELETE CASCADE,
  tag  TEXT NOT NULL
       CHECK (length(tag) BETWEEN 1 AND 64
              AND tag GLOB '[a-z0-9]*'
              AND NOT tag GLOB '*[^a-z0-9-]*'),
  PRIMARY KEY (slug, tag)
) STRICT;

-- One row is one claim: <from_slug> --rel--> <to_slug>.
--   relates-to   general connection
--   refines      a narrower topic under the other
--   depends-on   read the other first
--   supersedes   replaces the other. Only counts while the newer doc is `current`.
--   contradicts  the two disagree and someone should resolve it
CREATE TABLE IF NOT EXISTS doc_edge (
  from_slug  TEXT NOT NULL REFERENCES doc(slug) ON DELETE CASCADE,
  rel        TEXT NOT NULL
             CHECK (rel IN ('relates-to', 'refines', 'depends-on',
                            'supersedes', 'contradicts')),
  to_slug    TEXT NOT NULL REFERENCES doc(slug) ON DELETE CASCADE,
  note       TEXT NOT NULL DEFAULT '',
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (from_slug, rel, to_slug),
  CHECK (from_slug <> to_slug)
) STRICT;

-- The body as it was BEFORE each change, written by `trg_doc_revised`. No foreign key,
-- so history survives a deleted doc.
CREATE TABLE IF NOT EXISTS doc_revision (
  id          INTEGER PRIMARY KEY,
  slug        TEXT NOT NULL,
  title       TEXT NOT NULL,
  body        TEXT NOT NULL,
  status      TEXT NOT NULL,
  replaced_at TEXT NOT NULL
) STRICT;


-- =====================================================================================
-- HISTORY — event
-- =====================================================================================
-- Written by triggers. Never updated or deleted by hand. `subject_type` is the subject's
-- table name, except 'shift', which a shift writes by hand for its `started` and `ended`
-- events. `verb` is open on purpose. The triggers below emit:
--
--   created  moved  approved  rejected  deleted  claimed  logged  reported
--   reviewed  documented  linked  unlinked  tagged  inspected
--
-- `payload` is JSON. A status change is {"from":"open","to":"in-progress"}.
CREATE TABLE IF NOT EXISTS event (
  id           INTEGER PRIMARY KEY,
  ts           TEXT NOT NULL,
  actor        TEXT NOT NULL,
  verb         TEXT NOT NULL,
  subject_type TEXT NOT NULL,
  subject_id   TEXT NOT NULL,
  payload      TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(payload))
) STRICT;


-- =====================================================================================
-- INDEXES — optimization only. Every query is correct without them.
-- =====================================================================================
CREATE INDEX IF NOT EXISTS project_by_goal     ON project(goal_id, status);
CREATE INDEX IF NOT EXISTS req_by_project      ON requirement(project_id, status);
CREATE INDEX IF NOT EXISTS plan_by_req         ON plan(requirement_id, status);
CREATE INDEX IF NOT EXISTS plan_by_state       ON plan(approval, status);
CREATE INDEX IF NOT EXISTS plancap_by_cap      ON plan_capability(capability, required);
CREATE INDEX IF NOT EXISTS goaldep_by_dep      ON goal_dependency(depends_on);
CREATE INDEX IF NOT EXISTS projdep_by_dep      ON project_dependency(depends_on);
CREATE INDEX IF NOT EXISTS reqdep_by_dep       ON requirement_dependency(depends_on);
CREATE INDEX IF NOT EXISTS plandep_by_dep      ON plan_dependency(depends_on);
CREATE INDEX IF NOT EXISTS planlog_by_plan     ON plan_log(plan_id, ts);
CREATE INDEX IF NOT EXISTS issue_by_project    ON issue(project_id, status);
CREATE INDEX IF NOT EXISTS issue_by_plan       ON issue(plan_id, status);
CREATE INDEX IF NOT EXISTS doc_by_project      ON doc(project_id);
CREATE INDEX IF NOT EXISTS doctag_by_tag       ON doc_tag(tag);
CREATE INDEX IF NOT EXISTS docedge_by_to       ON doc_edge(to_slug, rel);
CREATE INDEX IF NOT EXISTS revision_by_doc     ON doc_revision(slug, replaced_at);
CREATE INDEX IF NOT EXISTS event_recent        ON event(ts, id);
CREATE INDEX IF NOT EXISTS event_by_subject    ON event(subject_type, subject_id);


-- =====================================================================================
-- =====================================================================================
--  V I E W S   —   T H E   G U I L D ' S   R U L E S
-- =====================================================================================
-- =====================================================================================
-- Read the view instead of rewriting its logic. Defined helpers first.
--
-- INDEX OF VIEWS
--   blockers      v_unfinished_deps
--   the check-in  v_goals_without_projects · v_projects_without_requirements ·
--   flow, in      v_requirements_without_plans · v_plans_pending_approval ·
--   order         v_plans_ready · v_plans_blocked · v_plans_running · v_plans_stuck
--   after work    v_projects_to_review · v_projects_to_document · v_goals_complete
--   progress      v_goal_progress · v_project_progress · v_requirement_progress
--   records       v_open_issues · v_issue_mismatch · v_coverage_due
--   the library   v_doc_current · v_doc_neighbors · v_doc_related · v_doc_tags
--   the feed      v_recent_activity · v_brief
--
-- Old views from version 9 are dropped at the end of this section.


-- ------------------------------------------------------------------------------------
-- v_unfinished_deps — every dependency, at every level, that is not done yet
-- ------------------------------------------------------------------------------------
-- One row per (level, waiting item, unfinished dependency). The building block for
-- readiness at all four levels.
DROP VIEW IF EXISTS v_unfinished_deps;
CREATE VIEW v_unfinished_deps AS
SELECT 'goal' AS level, d.goal_id AS id, d.depends_on AS depends_on, g.status AS dep_status
  FROM goal_dependency d JOIN goal g ON g.id = d.depends_on
 WHERE g.status <> 'done'
UNION ALL
SELECT 'project', d.project_id, d.depends_on, p.status
  FROM project_dependency d JOIN project p ON p.id = d.depends_on
 WHERE p.status <> 'done'
UNION ALL
SELECT 'requirement', d.requirement_id, d.depends_on, r.status
  FROM requirement_dependency d JOIN requirement r ON r.id = d.depends_on
 WHERE r.status <> 'done'
UNION ALL
SELECT 'plan', d.plan_id, d.depends_on, p.status
  FROM plan_dependency d JOIN plan p ON p.id = d.depends_on
 WHERE p.status <> 'done';


-- ------------------------------------------------------------------------------------
-- v_plan_waits — for each open plan, the first reason it cannot run yet, if any
-- ------------------------------------------------------------------------------------
-- Checks the plan's own dependencies, then its requirement's, its project's and its
-- goal's. `wait` is NULL when nothing above the plan is holding it.
DROP VIEW IF EXISTS v_plan_waits;
CREATE VIEW v_plan_waits AS
SELECT pl.id AS plan_id,
       CASE
         WHEN EXISTS (SELECT 1 FROM v_unfinished_deps u
                       WHERE u.level = 'plan' AND u.id = pl.id)
           THEN 'plan-deps:' || (SELECT group_concat(u.depends_on, ',') FROM v_unfinished_deps u
                                  WHERE u.level = 'plan' AND u.id = pl.id)
         WHEN EXISTS (SELECT 1 FROM v_unfinished_deps u
                       WHERE u.level = 'requirement' AND u.id = r.id)
           THEN 'requirement-deps:' || (SELECT group_concat(u.depends_on, ',') FROM v_unfinished_deps u
                                         WHERE u.level = 'requirement' AND u.id = r.id)
         WHEN EXISTS (SELECT 1 FROM v_unfinished_deps u
                       WHERE u.level = 'project' AND u.id = p.id)
           THEN 'project-deps:' || (SELECT group_concat(u.depends_on, ',') FROM v_unfinished_deps u
                                     WHERE u.level = 'project' AND u.id = p.id)
         WHEN EXISTS (SELECT 1 FROM v_unfinished_deps u
                       WHERE u.level = 'goal' AND u.id = p.goal_id)
           THEN 'goal-deps:' || (SELECT group_concat(u.depends_on, ',') FROM v_unfinished_deps u
                                  WHERE u.level = 'goal' AND u.id = p.goal_id)
         ELSE NULL
       END AS wait
  FROM plan pl
  JOIN requirement r ON r.id = pl.requirement_id
  JOIN project p     ON p.id = r.project_id;


-- ------------------------------------------------------------------------------------
-- THE CHECK-IN FLOW — the questions the orchestrator asks, in the order it asks them
-- ------------------------------------------------------------------------------------

-- Open goals with no project yet. The project-manager writes their projects.
DROP VIEW IF EXISTS v_goals_without_projects;
CREATE VIEW v_goals_without_projects AS
SELECT g.id, g.priority, g.title, g.success_criteria
  FROM goal g
 WHERE g.status <> 'done'
   AND NOT EXISTS (SELECT 1 FROM project p WHERE p.goal_id = g.id)
 ORDER BY g.priority, g.created_at, g.id;

-- Projects not yet done with no requirement. The project-manager writes them.
DROP VIEW IF EXISTS v_projects_without_requirements;
CREATE VIEW v_projects_without_requirements AS
SELECT p.id, p.goal_id, p.priority, p.title
  FROM project p
 WHERE p.status <> 'done'
   AND NOT EXISTS (SELECT 1 FROM requirement r WHERE r.project_id = p.id)
 ORDER BY p.priority, p.created_at, p.id;

-- Requirements not yet done with no plan that could still finish them. A requirement
-- whose only plans were rejected is listed again, so the strategist writes a new one.
DROP VIEW IF EXISTS v_requirements_without_plans;
CREATE VIEW v_requirements_without_plans AS
SELECT r.id, r.project_id, p.goal_id, r.priority, r.title
  FROM requirement r
  JOIN project p ON p.id = r.project_id
 WHERE r.status <> 'done'
   AND NOT EXISTS (SELECT 1 FROM plan pl
                    WHERE pl.requirement_id = r.id AND pl.approval <> 'rejected')
 ORDER BY r.priority, r.created_at, r.id;

-- Plans waiting on a decision. `has_capabilities` is 0 when the plan names neither a pin
-- nor a capability, which means nobody could run it even once approved. A shift approves
-- only plans where it is 1.
DROP VIEW IF EXISTS v_plans_pending_approval;
CREATE VIEW v_plans_pending_approval AS
SELECT pl.id, pl.requirement_id, r.project_id, p.goal_id, pl.kind, pl.priority,
       CASE WHEN COALESCE(pl.agent, '') <> ''
              OR EXISTS (SELECT 1 FROM plan_capability c WHERE c.plan_id = pl.id)
            THEN 1 ELSE 0 END AS has_capabilities,
       pl.created_at, pl.title
  FROM plan pl
  JOIN requirement r ON r.id = pl.requirement_id
  JOIN project p     ON p.id = r.project_id
 WHERE pl.approval = 'pending'
 ORDER BY pl.priority, pl.created_at, pl.id;

-- THE DISPATCH SET. Approved, open, and nothing at any level holding it. Every row may
-- start now, in parallel, subject to the file-disjointness promise and project isolation.
-- `needs` lists the required capabilities for the orchestrator's match.
DROP VIEW IF EXISTS v_plans_ready;
CREATE VIEW v_plans_ready AS
SELECT pl.id, pl.requirement_id, r.project_id, p.goal_id, pl.kind, pl.priority,
       COALESCE(NULLIF(pl.agent, ''), '-') AS agent,
       COALESCE((SELECT group_concat(c.capability, '+')
                   FROM (SELECT capability FROM plan_capability
                          WHERE plan_id = pl.id AND required = 1
                          ORDER BY capability) c), '-') AS needs,
       p.isolation, COALESCE(p.worktree_path, '') AS worktree_path,
       pl.files, pl.title
  FROM plan pl
  JOIN requirement r ON r.id = pl.requirement_id
  JOIN project p     ON p.id = r.project_id
  JOIN v_plan_waits w ON w.plan_id = pl.id
 WHERE pl.approval = 'approved'
   AND pl.status = 'open'
   AND w.wait IS NULL
 ORDER BY pl.priority, pl.created_at, pl.id;

-- Approved, open plans that are waiting, and on what.
DROP VIEW IF EXISTS v_plans_blocked;
CREATE VIEW v_plans_blocked AS
SELECT pl.id, pl.requirement_id, r.project_id, w.wait, pl.title
  FROM plan pl
  JOIN requirement r ON r.id = pl.requirement_id
  JOIN v_plan_waits w ON w.plan_id = pl.id
 WHERE pl.approval = 'approved'
   AND pl.status = 'open'
   AND w.wait IS NOT NULL
 ORDER BY pl.priority, pl.created_at, pl.id;

-- In-progress plans with no open execution issue: an agent should be on them.
-- `minutes` grows on every read. A large number usually means the agent died.
DROP VIEW IF EXISTS v_plans_running;
CREATE VIEW v_plans_running AS
SELECT pl.id, pl.requirement_id, COALESCE(pl.claimed_by, '-') AS claimed_by,
       COALESCE(pl.started_at, pl.updated_at) AS since,
       CAST((julianday('now') - julianday(COALESCE(pl.started_at, pl.updated_at)))
            * 1440 AS INTEGER) AS minutes,
       pl.title
  FROM plan pl
 WHERE pl.status = 'in-progress'
   AND NOT EXISTS (SELECT 1 FROM issue i
                    WHERE i.plan_id = pl.id AND i.source = 'execution'
                      AND i.status IN ('open', 'in-progress'))
 ORDER BY pl.priority, pl.created_at, pl.id;

-- In-progress plans that failed: an execution issue is still open against them.
DROP VIEW IF EXISTS v_plans_stuck;
CREATE VIEW v_plans_stuck AS
SELECT pl.id, pl.requirement_id, i.id AS issue_id, i.severity, i.status AS issue_status,
       i.title AS issue_title, pl.title
  FROM plan pl
  JOIN issue i ON i.plan_id = pl.id AND i.source = 'execution'
              AND i.status IN ('open', 'in-progress')
 WHERE pl.status = 'in-progress'
 ORDER BY pl.priority, pl.created_at, pl.id;


-- ------------------------------------------------------------------------------------
-- AFTER THE WORK — review, documentation, goal sign-off
-- ------------------------------------------------------------------------------------

-- Done projects nobody has reviewed. The review files issues and sets `reviewed_at`.
DROP VIEW IF EXISTS v_projects_to_review;
CREATE VIEW v_projects_to_review AS
SELECT p.id, p.goal_id, p.priority, p.updated_at AS done_at, p.title
  FROM project p
 WHERE p.status = 'done' AND p.reviewed_at IS NULL
 ORDER BY p.priority, p.updated_at, p.id;

-- Reviewed projects nobody has documented. The librarian writes docs and sets
-- `documented_at`. `open_issues` rides along so the docs can name what is still wrong.
DROP VIEW IF EXISTS v_projects_to_document;
CREATE VIEW v_projects_to_document AS
SELECT p.id, p.goal_id, p.priority, p.reviewed_at,
       (SELECT COUNT(*) FROM issue i
         WHERE i.project_id = p.id AND i.status IN ('open', 'in-progress')) AS open_issues,
       p.title
  FROM project p
 WHERE p.status = 'done' AND p.reviewed_at IS NOT NULL AND p.documented_at IS NULL
 ORDER BY p.priority, p.reviewed_at, p.id;

-- Open goals whose projects are all done and documented. A person checks the goal's
-- `success_criteria` and either closes it or asks for more projects.
DROP VIEW IF EXISTS v_goals_complete;
CREATE VIEW v_goals_complete AS
SELECT g.id, g.priority, g.success_criteria, g.title
  FROM goal g
 WHERE g.status <> 'done'
   AND EXISTS (SELECT 1 FROM project p WHERE p.goal_id = g.id)
   AND NOT EXISTS (SELECT 1 FROM project p
                    WHERE p.goal_id = g.id
                      AND (p.status <> 'done' OR p.documented_at IS NULL))
 ORDER BY g.priority, g.created_at, g.id;


-- ------------------------------------------------------------------------------------
-- PROGRESS
-- ------------------------------------------------------------------------------------
DROP VIEW IF EXISTS v_requirement_progress;
CREATE VIEW v_requirement_progress AS
SELECT r.id, r.project_id, r.status, r.priority,
       COUNT(pl.id) AS plans_total,
       COALESCE(SUM(CASE WHEN pl.status = 'done' THEN 1 ELSE 0 END), 0) AS plans_done,
       COALESCE(SUM(CASE WHEN pl.approval = 'pending' THEN 1 ELSE 0 END), 0) AS plans_pending,
       r.title
  FROM requirement r
  LEFT JOIN plan pl ON pl.requirement_id = r.id AND pl.approval <> 'rejected'
 GROUP BY r.id, r.project_id, r.status, r.priority, r.title
 ORDER BY CASE r.status WHEN 'in-progress' THEN 1 WHEN 'open' THEN 2 ELSE 3 END,
          r.priority, r.created_at, r.id;

DROP VIEW IF EXISTS v_project_progress;
CREATE VIEW v_project_progress AS
SELECT p.id, p.goal_id, p.status, p.priority, p.isolation,
       (SELECT COUNT(*) FROM requirement r WHERE r.project_id = p.id) AS requirements_total,
       (SELECT COUNT(*) FROM requirement r
         WHERE r.project_id = p.id AND r.status = 'done')            AS requirements_done,
       (SELECT COUNT(*) FROM issue i
         WHERE i.project_id = p.id AND i.status IN ('open', 'in-progress')) AS open_issues,
       CASE WHEN p.documented_at IS NOT NULL THEN 'documented'
            WHEN p.reviewed_at   IS NOT NULL THEN 'reviewed'
            ELSE '-' END                                              AS after_done,
       p.title
  FROM project p
 ORDER BY CASE p.status WHEN 'in-progress' THEN 1 WHEN 'open' THEN 2 ELSE 3 END,
          p.priority, p.created_at, p.id;

DROP VIEW IF EXISTS v_goal_progress;
CREATE VIEW v_goal_progress AS
SELECT g.id, g.status, g.priority,
       (SELECT COUNT(*) FROM project p WHERE p.goal_id = g.id)                      AS projects_total,
       (SELECT COUNT(*) FROM project p WHERE p.goal_id = g.id AND p.status = 'done') AS projects_done,
       g.success_criteria, g.title
  FROM goal g
 ORDER BY CASE g.status WHEN 'in-progress' THEN 1 WHEN 'open' THEN 2 ELSE 3 END,
          g.priority, g.created_at, g.id;


-- ------------------------------------------------------------------------------------
-- RECORDS
-- ------------------------------------------------------------------------------------
DROP VIEW IF EXISTS v_open_issues;
CREATE VIEW v_open_issues AS
SELECT i.id, i.project_id, i.requirement_id, i.plan_id, i.source, i.severity,
       CASE i.severity WHEN 'critical' THEN 1 WHEN 'major' THEN 2
                       WHEN 'minor' THEN 3 ELSE 4 END AS severity_rank,
       i.status, i.found_by, i.fix_plan_id, i.file, i.line, i.created_at, i.title
  FROM issue i
 WHERE i.status IN ('open', 'in-progress')
 ORDER BY severity_rank, i.created_at, i.id;

-- Issues whose requirement or plan is not under the issue's project. Must be empty.
DROP VIEW IF EXISTS v_issue_mismatch;
CREATE VIEW v_issue_mismatch AS
SELECT i.id, i.project_id,
       r.project_id  AS requirement_project,
       pr.project_id AS plan_project
  FROM issue i
  LEFT JOIN requirement r   ON r.id = i.requirement_id
  LEFT JOIN plan pl         ON pl.id = i.plan_id
  LEFT JOIN requirement pr  ON pr.id = pl.requirement_id
 WHERE (i.requirement_id IS NOT NULL AND r.project_id  <> i.project_id)
    OR (i.plan_id        IS NOT NULL AND pr.project_id <> i.project_id);

-- Quality areas past their interval: high 14 days, medium 30, low 90.
DROP VIEW IF EXISTS v_coverage_due;
CREATE VIEW v_coverage_due AS
SELECT c.id, c.risk, c.spec_path, c.last_inspected_at,
       CASE c.risk WHEN 'high' THEN 14 WHEN 'low' THEN 90 ELSE 30 END AS interval_days,
       CASE WHEN COALESCE(c.last_inspected_at, '') = '' THEN NULL
            ELSE CAST(julianday('now') - julianday(c.last_inspected_at) AS INTEGER)
       END AS days_since,
       c.area, c.notes
  FROM coverage c
 WHERE COALESCE(c.last_inspected_at, '') = ''
    OR (julianday('now') - julianday(c.last_inspected_at))
       >= CASE c.risk WHEN 'high' THEN 14 WHEN 'low' THEN 90 ELSE 30 END
 ORDER BY CASE c.risk WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END, c.id;


-- ------------------------------------------------------------------------------------
-- THE LIBRARY
-- ------------------------------------------------------------------------------------

-- Live docs. A doc is hidden when it is superseded or rejected, or when a CURRENT doc
-- claims to supersede it. A draft or rejected doc claiming to replace it does not count.
DROP VIEW IF EXISTS v_doc_current;
CREATE VIEW v_doc_current AS
SELECT d.slug, d.project_id, d.kind, d.status, d.author, d.created_at, d.updated_at,
       COALESCE((SELECT group_concat(t.tag, ' ')
                   FROM (SELECT tag FROM doc_tag WHERE slug = d.slug ORDER BY tag) t), '') AS tags,
       (SELECT COUNT(*) FROM doc_edge e WHERE e.from_slug = d.slug OR e.to_slug = d.slug) AS edges,
       d.title
  FROM doc d
 WHERE d.status IN ('draft', 'current')
   AND NOT EXISTS (SELECT 1 FROM doc_edge e
                     JOIN doc n ON n.slug = e.from_slug
                    WHERE e.rel = 'supersedes' AND e.to_slug = d.slug
                      AND n.status = 'current')
 ORDER BY d.kind, d.slug;

-- One hop in both directions:  SELECT * FROM v_doc_neighbors WHERE slug = 'x'
DROP VIEW IF EXISTS v_doc_neighbors;
CREATE VIEW v_doc_neighbors AS
SELECT e.from_slug AS slug, 'out' AS direction, e.rel, e.to_slug AS other_slug,
       o.title AS other_title, o.status AS other_status, e.note
  FROM doc_edge e JOIN doc o ON o.slug = e.to_slug
UNION ALL
SELECT e.to_slug, 'in', e.rel, e.from_slug, o.title, o.status, e.note
  FROM doc_edge e JOIN doc o ON o.slug = e.from_slug;

-- Docs that share tags, strongest first. Use it to find what a new doc should link to.
--   SELECT * FROM v_doc_related WHERE slug = 'x'
DROP VIEW IF EXISTS v_doc_related;
CREATE VIEW v_doc_related AS
SELECT a.slug AS slug, b.slug AS other_slug, COUNT(*) AS shared_tags,
       group_concat(a.tag, ' ') AS tags
  FROM doc_tag a
  JOIN doc_tag b ON b.tag = a.tag AND b.slug <> a.slug
 GROUP BY a.slug, b.slug
 ORDER BY a.slug, shared_tags DESC, b.slug;

-- Every tag and how many live docs carry it. The vocabulary, so a writer reuses words.
DROP VIEW IF EXISTS v_doc_tags;
CREATE VIEW v_doc_tags AS
SELECT t.tag, COUNT(*) AS docs
  FROM doc_tag t JOIN doc d ON d.slug = t.slug
 WHERE d.status IN ('draft', 'current')
 GROUP BY t.tag
 ORDER BY docs DESC, t.tag;


-- ------------------------------------------------------------------------------------
-- THE FEED AND THE BRIEF
-- ------------------------------------------------------------------------------------
DROP VIEW IF EXISTS v_recent_activity;
CREATE VIEW v_recent_activity AS
SELECT e.id, e.ts, e.actor, e.verb, e.subject_type, e.subject_id,
       COALESCE(
         (SELECT s.title FROM goal        s WHERE e.subject_type = 'goal'        AND s.id   = e.subject_id),
         (SELECT s.title FROM project     s WHERE e.subject_type = 'project'     AND s.id   = e.subject_id),
         (SELECT s.title FROM requirement s WHERE e.subject_type = 'requirement' AND s.id   = e.subject_id),
         (SELECT s.title FROM plan        s WHERE e.subject_type = 'plan'        AND s.id   = e.subject_id),
         (SELECT s.title FROM issue       s WHERE e.subject_type = 'issue'       AND s.id   = e.subject_id),
         (SELECT s.title FROM doc         s WHERE e.subject_type = 'doc'         AND s.slug = e.subject_id),
         (SELECT s.area  FROM coverage    s WHERE e.subject_type = 'coverage'    AND s.id   = e.subject_id),
         (SELECT s.scope FROM inspection  s WHERE e.subject_type = 'inspection'  AND s.id   = e.subject_id),
         '') AS subject_title,
       CASE WHEN json_valid(e.payload)
             AND COALESCE(CAST(json_extract(e.payload, '$.to') AS TEXT), '') <> ''
            THEN COALESCE(CAST(json_extract(e.payload, '$.from') AS TEXT), '?')
                 || ' -> ' || CAST(json_extract(e.payload, '$.to') AS TEXT)
            ELSE '' END AS phrase,
       e.payload
  FROM event e
 ORDER BY e.ts DESC, e.id DESC;

--   SELECT fact, value FROM v_brief
DROP VIEW IF EXISTS v_brief;
CREATE VIEW v_brief AS
SELECT  1 AS ord, 'generated_at' AS fact, strftime('%Y-%m-%dT%H:%M:%SZ', 'now') AS value
UNION ALL SELECT  2, 'actor',        COALESCE((SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator')
UNION ALL SELECT  3, 'last_checkin', COALESCE((SELECT value FROM guild_state WHERE key = 'last-checkin'), 'null')
UNION ALL SELECT  4, 'goals_open',                CAST((SELECT COUNT(*) FROM goal WHERE status <> 'done') AS TEXT)
UNION ALL SELECT  5, 'goals_without_projects',    CAST((SELECT COUNT(*) FROM v_goals_without_projects) AS TEXT)
UNION ALL SELECT  6, 'goals_complete',            CAST((SELECT COUNT(*) FROM v_goals_complete) AS TEXT)
UNION ALL SELECT  7, 'projects_open',             CAST((SELECT COUNT(*) FROM project WHERE status <> 'done') AS TEXT)
UNION ALL SELECT  8, 'projects_without_requirements', CAST((SELECT COUNT(*) FROM v_projects_without_requirements) AS TEXT)
UNION ALL SELECT  9, 'projects_to_review',        CAST((SELECT COUNT(*) FROM v_projects_to_review) AS TEXT)
UNION ALL SELECT 10, 'projects_to_document',      CAST((SELECT COUNT(*) FROM v_projects_to_document) AS TEXT)
UNION ALL SELECT 11, 'requirements_open',         CAST((SELECT COUNT(*) FROM requirement WHERE status <> 'done') AS TEXT)
UNION ALL SELECT 12, 'requirements_without_plans', CAST((SELECT COUNT(*) FROM v_requirements_without_plans) AS TEXT)
UNION ALL SELECT 13, 'plans_pending_approval',    CAST((SELECT COUNT(*) FROM v_plans_pending_approval) AS TEXT)
UNION ALL SELECT 14, 'plans_ready',               CAST((SELECT COUNT(*) FROM v_plans_ready) AS TEXT)
UNION ALL SELECT 15, 'plans_blocked',             CAST((SELECT COUNT(*) FROM v_plans_blocked) AS TEXT)
UNION ALL SELECT 16, 'plans_running',             CAST((SELECT COUNT(*) FROM v_plans_running) AS TEXT)
UNION ALL SELECT 17, 'plans_stuck',               CAST((SELECT COUNT(*) FROM v_plans_stuck) AS TEXT)
UNION ALL SELECT 18, 'plans_done',                CAST((SELECT COUNT(*) FROM plan WHERE status = 'done') AS TEXT)
UNION ALL SELECT 19, 'issues_open',               CAST((SELECT COUNT(*) FROM v_open_issues) AS TEXT)
UNION ALL SELECT 20, 'issues_critical',           CAST((SELECT COUNT(*) FROM v_open_issues WHERE severity = 'critical') AS TEXT)
UNION ALL SELECT 21, 'coverage_due',              CAST((SELECT COUNT(*) FROM v_coverage_due) AS TEXT)
UNION ALL SELECT 22, 'docs_current',              CAST((SELECT COUNT(*) FROM v_doc_current) AS TEXT)
UNION ALL SELECT 23, 'events_since_checkin',
  CAST((SELECT COUNT(*) FROM event
         WHERE ts >= COALESCE(NULLIF((SELECT value FROM guild_state WHERE key = 'last-checkin'), 'null'), '')) AS TEXT)
 ORDER BY ord;


-- ------------------------------------------------------------------------------------
-- VERSION 9 VIEWS — dropped so a stray old view cannot answer with old rules
-- ------------------------------------------------------------------------------------
DROP VIEW IF EXISTS v_task_who;
DROP VIEW IF EXISTS v_task_deps;
DROP VIEW IF EXISTS v_task_blockers;
DROP VIEW IF EXISTS v_task_actionable;
DROP VIEW IF EXISTS v_next_task;
DROP VIEW IF EXISTS v_batch;
DROP VIEW IF EXISTS v_open_bounties;
DROP VIEW IF EXISTS v_blocked_tasks;
DROP VIEW IF EXISTS v_ready_nodes;
DROP VIEW IF EXISTS v_gates_pending;
DROP VIEW IF EXISTS v_projects_runnable;
DROP VIEW IF EXISTS v_board;
DROP VIEW IF EXISTS v_in_flight;
DROP VIEW IF EXISTS v_failed_tasks;
DROP VIEW IF EXISTS v_open_findings;
DROP VIEW IF EXISTS v_open_bugs;
DROP VIEW IF EXISTS v_knowledge_ref;
DROP VIEW IF EXISTS v_doc_stale;
DROP VIEW IF EXISTS v_undocumented_work;
DROP VIEW IF EXISTS v_decision_log;
DROP VIEW IF EXISTS v_knowledge_dangling;


-- =====================================================================================
-- =====================================================================================
--  T R I G G E R S   —   T H E   R E C O R D   A N D   T H E   R O L L - U P
-- =====================================================================================
-- =====================================================================================
-- Three jobs:
--   1. every meaningful change writes an `event` row
--   2. `updated_at` is stamped when a row changes and the writer did not set it
--   3. plan status ROLLS UP to requirement, project and goal (see the header)
--
-- The touch triggers cannot recurse: their own UPDATE changes `updated_at`, so the
-- `WHEN new.updated_at IS old.updated_at` guard is false on re-entry. The roll-up
-- triggers only ever move a parent forward and only when it is not already there, so a
-- chain of them ends after one pass up the hierarchy. tursodb fires the most recently
-- created trigger first, so each roll-up trigger is declared BEFORE its table's `moved`
-- trigger. That keeps the feed in cause-then-effect order.
--
-- The actor is `guild_state.actor` unless the row names its own author.


-- ---- goal ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_goal_created;
CREATE TRIGGER trg_goal_created AFTER INSERT ON goal
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
          COALESCE((SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator'),
          'created', 'goal', new.id, json_object('priority', new.priority));
END;

DROP TRIGGER IF EXISTS trg_goal_moved;
CREATE TRIGGER trg_goal_moved AFTER UPDATE OF status ON goal
WHEN old.status IS NOT new.status
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
          COALESCE((SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator'),
          'moved', 'goal', new.id, json_object('from', old.status, 'to', new.status));
END;

DROP TRIGGER IF EXISTS trg_goal_touch;
CREATE TRIGGER trg_goal_touch AFTER UPDATE ON goal
WHEN new.updated_at IS old.updated_at
BEGIN
  UPDATE goal SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE id = new.id;
END;


-- ---- project ------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_project_created;
CREATE TRIGGER trg_project_created AFTER INSERT ON project
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
          COALESCE((SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator'),
          'created', 'project', new.id,
          json_object('goal_id', new.goal_id, 'isolation', new.isolation));
END;

-- roll-up: a project starting starts its goal
DROP TRIGGER IF EXISTS trg_project_starts_goal;
CREATE TRIGGER trg_project_starts_goal AFTER UPDATE OF status ON project
WHEN new.status = 'in-progress'
BEGIN
  UPDATE goal SET status = 'in-progress' WHERE id = new.goal_id AND status = 'open';
END;

DROP TRIGGER IF EXISTS trg_project_moved;
CREATE TRIGGER trg_project_moved AFTER UPDATE OF status ON project
WHEN old.status IS NOT new.status
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
          COALESCE((SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator'),
          'moved', 'project', new.id,
          json_object('from', old.status, 'to', new.status, 'goal_id', new.goal_id));
END;

DROP TRIGGER IF EXISTS trg_project_reviewed;
CREATE TRIGGER trg_project_reviewed AFTER UPDATE OF reviewed_at ON project
WHEN old.reviewed_at IS NULL AND new.reviewed_at IS NOT NULL
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
          COALESCE((SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator'),
          'reviewed', 'project', new.id,
          json_object('issues_open', (SELECT COUNT(*) FROM issue
                                       WHERE project_id = new.id
                                         AND status IN ('open', 'in-progress'))));
END;

DROP TRIGGER IF EXISTS trg_project_documented;
CREATE TRIGGER trg_project_documented AFTER UPDATE OF documented_at ON project
WHEN old.documented_at IS NULL AND new.documented_at IS NOT NULL
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
          COALESCE((SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator'),
          'documented', 'project', new.id,
          json_object('docs', (SELECT COUNT(*) FROM doc WHERE project_id = new.id)));
END;

DROP TRIGGER IF EXISTS trg_project_touch;
CREATE TRIGGER trg_project_touch AFTER UPDATE ON project
WHEN new.updated_at IS old.updated_at
BEGIN
  UPDATE project SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE id = new.id;
END;


-- ---- requirement --------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_requirement_created;
CREATE TRIGGER trg_requirement_created AFTER INSERT ON requirement
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
          COALESCE((SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator'),
          'created', 'requirement', new.id, json_object('project_id', new.project_id));
END;

-- roll-up: a requirement starting starts its project
DROP TRIGGER IF EXISTS trg_requirement_starts_project;
CREATE TRIGGER trg_requirement_starts_project AFTER UPDATE OF status ON requirement
WHEN new.status = 'in-progress'
BEGIN
  UPDATE project SET status = 'in-progress' WHERE id = new.project_id AND status = 'open';
END;

-- roll-up: the last requirement of a project finishing finishes the project
DROP TRIGGER IF EXISTS trg_requirement_finishes_project;
CREATE TRIGGER trg_requirement_finishes_project AFTER UPDATE OF status ON requirement
WHEN new.status = 'done'
BEGIN
  UPDATE project SET status = 'done'
   WHERE id = new.project_id AND status <> 'done'
     AND NOT EXISTS (SELECT 1 FROM requirement r
                      WHERE r.project_id = new.project_id AND r.status <> 'done');
END;

DROP TRIGGER IF EXISTS trg_requirement_moved;
CREATE TRIGGER trg_requirement_moved AFTER UPDATE OF status ON requirement
WHEN old.status IS NOT new.status
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
          COALESCE((SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator'),
          'moved', 'requirement', new.id,
          json_object('from', old.status, 'to', new.status, 'project_id', new.project_id));
END;

DROP TRIGGER IF EXISTS trg_requirement_touch;
CREATE TRIGGER trg_requirement_touch AFTER UPDATE ON requirement
WHEN new.updated_at IS old.updated_at
BEGIN
  UPDATE requirement SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE id = new.id;
END;


-- ---- plan ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_plan_created;
CREATE TRIGGER trg_plan_created AFTER INSERT ON plan
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
          COALESCE((SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator'),
          'created', 'plan', new.id,
          json_object('requirement_id', new.requirement_id, 'kind', new.kind));
END;

-- roll-up: a plan starting starts its requirement
DROP TRIGGER IF EXISTS trg_plan_starts_requirement;
CREATE TRIGGER trg_plan_starts_requirement AFTER UPDATE OF status ON plan
WHEN new.status = 'in-progress'
BEGIN
  UPDATE requirement SET status = 'in-progress'
   WHERE id = new.requirement_id AND status = 'open';
END;

-- roll-up: the last live plan of a requirement finishing finishes the requirement.
-- Rejected plans never run, so they do not count against it.
DROP TRIGGER IF EXISTS trg_plan_finishes_requirement;
CREATE TRIGGER trg_plan_finishes_requirement AFTER UPDATE OF status ON plan
WHEN new.status = 'done'
BEGIN
  UPDATE requirement SET status = 'done'
   WHERE id = new.requirement_id AND status <> 'done'
     AND NOT EXISTS (SELECT 1 FROM plan p
                      WHERE p.requirement_id = new.requirement_id
                        AND p.approval <> 'rejected' AND p.status <> 'done');
END;

DROP TRIGGER IF EXISTS trg_plan_moved;
CREATE TRIGGER trg_plan_moved AFTER UPDATE OF status ON plan
WHEN old.status IS NOT new.status
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
          COALESCE((SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator'),
          'moved', 'plan', new.id,
          json_object('from', old.status, 'to', new.status,
                      'agent', COALESCE(new.claimed_by, new.agent),
                      'requirement_id', new.requirement_id));
END;

-- Approval is the plan event a person (or, in a shift, the orchestrator) is behind.
-- The decider is the actor, and the verb is the decision.
DROP TRIGGER IF EXISTS trg_plan_decided;
CREATE TRIGGER trg_plan_decided AFTER UPDATE OF approval ON plan
WHEN old.approval IS NOT new.approval AND new.approval <> 'pending'
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
          COALESCE(NULLIF(new.approved_by, ''),
                   (SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator'),
          new.approval, 'plan', new.id,
          json_object('from', old.approval, 'to', new.approval,
                      'requirement_id', new.requirement_id));
END;

DROP TRIGGER IF EXISTS trg_plan_claimed;
CREATE TRIGGER trg_plan_claimed AFTER UPDATE OF claimed_by ON plan
WHEN old.claimed_by IS NOT new.claimed_by AND new.claimed_by IS NOT NULL
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
          COALESCE((SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator'),
          'claimed', 'plan', new.id, json_object('agent', new.claimed_by));
END;

DROP TRIGGER IF EXISTS trg_plan_touch;
CREATE TRIGGER trg_plan_touch AFTER UPDATE ON plan
WHEN new.updated_at IS old.updated_at
BEGIN
  UPDATE plan SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE id = new.id;
END;


-- ---- plan_log -----------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_planlog_created;
CREATE TRIGGER trg_planlog_created AFTER INSERT ON plan_log
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (new.ts, new.agent, 'logged', 'plan', new.plan_id, json_object('entry', new.entry));
END;


-- ---- issue --------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_issue_created;
CREATE TRIGGER trg_issue_created AFTER INSERT ON issue
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), new.found_by,
          'reported', 'issue', new.id,
          json_object('project_id', new.project_id, 'plan_id', new.plan_id,
                      'source', new.source, 'severity', new.severity));
END;

DROP TRIGGER IF EXISTS trg_issue_moved;
CREATE TRIGGER trg_issue_moved AFTER UPDATE OF status ON issue
WHEN old.status IS NOT new.status
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
          COALESCE((SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator'),
          'moved', 'issue', new.id,
          json_object('from', old.status, 'to', new.status,
                      'fix_plan_id', new.fix_plan_id, 'fix_ref', new.fix_ref));
END;

DROP TRIGGER IF EXISTS trg_issue_touch;
CREATE TRIGGER trg_issue_touch AFTER UPDATE ON issue
WHEN new.updated_at IS old.updated_at
BEGIN
  UPDATE issue SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE id = new.id;
END;


-- ---- coverage and inspection --------------------------------------------------------
DROP TRIGGER IF EXISTS trg_coverage_inspected;
CREATE TRIGGER trg_coverage_inspected AFTER UPDATE OF last_inspected_at ON coverage
WHEN old.last_inspected_at IS NOT new.last_inspected_at
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
          COALESCE((SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator'),
          'inspected', 'coverage', new.id,
          json_object('from', old.last_inspected_at, 'to', new.last_inspected_at));
END;

DROP TRIGGER IF EXISTS trg_inspection_moved;
CREATE TRIGGER trg_inspection_moved AFTER UPDATE OF status ON inspection
WHEN old.status IS NOT new.status
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
          COALESCE((SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator'),
          'moved', 'inspection', new.id, json_object('from', old.status, 'to', new.status));
END;


-- ---- the library --------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_doc_created;
CREATE TRIGGER trg_doc_created AFTER INSERT ON doc
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
          COALESCE(NULLIF(new.author, ''),
                   (SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator'),
          'documented', 'doc', new.slug,
          json_object('kind', new.kind, 'project_id', new.project_id));
END;

DROP TRIGGER IF EXISTS trg_doc_moved;
CREATE TRIGGER trg_doc_moved AFTER UPDATE OF status ON doc
WHEN old.status IS NOT new.status
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
          COALESCE((SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator'),
          'moved', 'doc', new.slug, json_object('from', old.status, 'to', new.status));
END;

-- Stores the OLD body. The live text is in `doc`.
DROP TRIGGER IF EXISTS trg_doc_revised;
CREATE TRIGGER trg_doc_revised AFTER UPDATE OF body ON doc
WHEN old.body IS NOT new.body
BEGIN
  INSERT INTO doc_revision (slug, title, body, status, replaced_at)
  VALUES (old.slug, old.title, old.body, old.status, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
          COALESCE(NULLIF(new.author, ''),
                   (SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator'),
          'documented', 'doc', new.slug, json_object('revised', 1));
END;

DROP TRIGGER IF EXISTS trg_doc_touch;
CREATE TRIGGER trg_doc_touch AFTER UPDATE ON doc
WHEN new.updated_at IS old.updated_at
BEGIN
  UPDATE doc SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE slug = new.slug;
END;

DROP TRIGGER IF EXISTS trg_doc_tagged;
CREATE TRIGGER trg_doc_tagged AFTER INSERT ON doc_tag
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
          COALESCE((SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator'),
          'tagged', 'doc', new.slug, json_object('tag', new.tag));
END;

DROP TRIGGER IF EXISTS trg_docedge_linked;
CREATE TRIGGER trg_docedge_linked AFTER INSERT ON doc_edge
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), new.created_by,
          'linked', 'doc', new.from_slug,
          json_object('rel', new.rel, 'to_slug', new.to_slug));
END;

DROP TRIGGER IF EXISTS trg_docedge_unlinked;
CREATE TRIGGER trg_docedge_unlinked AFTER DELETE ON doc_edge
BEGIN
  INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
  VALUES (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
          COALESCE((SELECT value FROM guild_state WHERE key = 'actor'), 'orchestrator'),
          'unlinked', 'doc', old.from_slug,
          json_object('rel', old.rel, 'to_slug', old.to_slug));
END;


-- ---- version 9 triggers -------------------------------------------------------------
-- Dropped so an old trigger cannot fire against a table this version no longer has.
DROP TRIGGER IF EXISTS trg_plan_approved;
DROP TRIGGER IF EXISTS trg_edge_linked;
DROP TRIGGER IF EXISTS trg_edge_unlinked;
DROP TRIGGER IF EXISTS trg_doc_updated;


-- =====================================================================================
-- END. Re-apply this file any time. It is idempotent.
-- =====================================================================================
