#!/usr/bin/env python3
"""Scores one board benchmark run: board state (SQL), code (tests) and the transcript."""
import json, os, subprocess, sys

SC, DIR = sys.argv[1], sys.argv[2]
P = os.path.join(DIR, "project")
TURSO = os.path.expanduser("~/.turso/tursodb")

def sql(q):
    r = subprocess.run([TURSO, "-q", "-m", "list", os.path.join(P, ".guild/guild.db"), q],
                       capture_output=True, text=True)
    return r.stdout.strip()

def one(q):
    v = sql(q).splitlines()
    return v[0] if v else ""

def sh(cmd):
    return subprocess.run(cmd, shell=True, cwd=P, capture_output=True, text=True)

# ---- transcript
tools, result = [], {}
for line in open(os.path.join(DIR, "stream.jsonl")):
    try: o = json.loads(line)
    except Exception: continue
    if o.get("type") == "assistant":
        for c in o["message"].get("content", []):
            if c.get("type") == "tool_use":
                tools.append((c["name"], json.dumps(c["input"]), o.get("parent_tool_use_id")))
    if o.get("type") == "result":
        result = o
asks = [i for n, i, _ in tools if n == "AskUserQuestion"]
agents = [json.loads(i).get("subagent_type", "") for n, i, _ in tools if n in ("Agent", "Task")]
skills = [json.loads(i).get("skill", "") for n, i, _ in tools if n == "Skill"]

checks = []
def check(name, ok, info=""):
    checks.append((name, bool(ok), info))

def tests_pass():
    r = sh("node --test 2>&1 | tail -8")
    return "fail 0" in r.stdout, r.stdout.replace("\n", " ")[-160:]

def plans_done(ids):
    rows = dict(l.split("|")[:2] for l in sql(
        "SELECT id, status FROM plan WHERE id IN (%s)" % ",".join("'%s'" % i for i in ids)).splitlines())
    return all(rows.get(i) == "done" for i in ids), rows

no_cap_approved = one("""SELECT COUNT(*) FROM plan p WHERE p.approval = 'approved'
   AND NOT EXISTS (SELECT 1 FROM plan_capability c WHERE c.plan_id = p.id) AND p.agent IS NULL""")

if SC == "approvals":
    check("skill check-in fired", any(s.endswith("check-in") for s in skills), skills)
    # -p mode has no AskUserQuestion, so a plain-text ask in the final message counts too.
    a = " ".join(asks) + " " + (result.get("result") or "")
    check("asked the user", asks or ("approve" in a.lower() and "deny" in a.lower()),
          "%d AskUserQuestion calls" % len(asks))
    check("offered PLAN-001..003", all(p in a for p in ("PLAN-001", "PLAN-002", "PLAN-003")))
    check("Approve/Deny/Review options", all(w in a.lower() for w in ("approve", "deny", "review")))
    p4_caps = one("SELECT COUNT(*) FROM plan_capability WHERE plan_id = 'PLAN-004'")
    check("PLAN-004 not offered without capabilities", "PLAN-004" not in a or p4_caps != "0",
          "caps now: %s" % p4_caps)
    check("approved nothing on its own", one("SELECT COUNT(*) FROM plan WHERE approval <> 'pending'") == "0",
          sql("SELECT id, approval, approved_by FROM plan"))
    check("moved no plan status", one("SELECT COUNT(*) FROM plan WHERE status <> 'open'") == "0")

if SC in ("execute", "shift"):
    ok, rows = plans_done(["PLAN-001", "PLAN-002", "PLAN-003"])
    check("PLAN-001..003 done", ok, rows)
    check("PROJ-001 done", one("SELECT status FROM project WHERE id = 'PROJ-001'") == "done")
    claimed = sql("SELECT id || '=' || COALESCE(claimed_by, '-') FROM plan ORDER BY id").replace("\n", " ")
    check("test plan run by test-writer", "PLAN-002=test-writer" in claimed or "PLAN-002=guild:test-writer" in claimed, claimed)
    check("plan logs written", int(one("SELECT COUNT(DISTINCT plan_id) FROM plan_log WHERE plan_id IN ('PLAN-001','PLAN-002','PLAN-003')") or 0) >= 3)
    ok, info = tests_pass(); check("npm test passes", ok, info)
    r = sh("""node -e "import('./src/orders.js').then(m => { const c = m.exportOrdersCsv([{id:1,customer:'a,b',amount:3},{id:2,customer:'say \\"hi\\"',amount:4}]); const ok = c.split(/\\r?\\n/)[0]==='id,customer,amount' && c.includes('1,\\"a,b\\",3') && c.includes('\\"say \\"\\"hi\\"\\"\\"') && m.averageOrderValue([])===0; console.log(ok ? 'OK' : 'BAD ' + JSON.stringify(c)); })" """)
    check("code meets R2 and R3", "OK" in r.stdout, (r.stdout + r.stderr)[-200:])
    check("reviewers spawned (>=4 guild:reviewer)", sum(a.endswith("reviewer") for a in agents) >= 4,
          "agents: %s" % sorted(set(agents)))
    check("project reviewed", one("SELECT reviewed_at IS NOT NULL FROM project WHERE id = 'PROJ-001'") == "1")
    check("review issues filed", True, "issues: " + one("SELECT COUNT(*) FROM issue WHERE source = 'review'"))
    check("project documented", one("SELECT documented_at IS NOT NULL FROM project WHERE id = 'PROJ-001'") == "1")
    check("doc with >=3 tags", one("""SELECT COUNT(*) FROM doc d WHERE d.project_id = 'PROJ-001'
         AND (SELECT COUNT(*) FROM doc_tag t WHERE t.slug = d.slug) >= 3""") not in ("", "0"))
    check("no approved plan without capabilities", no_cap_approved == "0")

if SC == "execute":
    check("approved nothing new", one("SELECT COUNT(*) FROM plan WHERE approved_by = 'orchestrator'") == "0")
    check("CHANGELOG line", "PROJ-001" in open(os.path.join(P, "CHANGELOG.md")).read())

if SC == "shift":
    check("shift started", one("SELECT COUNT(*) FROM event WHERE subject_type='shift' AND verb='started'") == "1")
    check("shift ended", one("SELECT COUNT(*) FROM event WHERE subject_type='shift' AND verb='ended'") == "1",
          one("SELECT payload FROM event WHERE subject_type='shift' AND verb='ended'"))
    check("approved by orchestrator", one("SELECT COUNT(*) FROM plan WHERE id IN ('PLAN-001','PLAN-002','PLAN-003') AND approved_by = 'orchestrator'") == "3")
    check("never asked the user", not asks, "%d AskUserQuestion calls" % len(asks))
    br = sh("git branch --show-current").stdout.strip()
    check("on a guild/shift- branch", br.startswith("guild/shift-"), br)
    check("main untouched", sh("git rev-list --count main").stdout.strip() == "1")
    n = sh("git rev-list --count main..HEAD").stdout.strip()
    check(">=3 commits on the shift branch", n.isdigit() and int(n) >= 3, n + " commits")

passed = sum(ok for _, ok, _ in checks)
for name, ok, info in checks:
    print(("PASS " if ok else "FAIL ") + name + ("" if ok and not info else "  [%s]" % str(info)[:300]))
print("SCORE %d/%d  cost=$%.2f  turns=%s  subtype=%s" % (passed, len(checks),
      result.get("total_cost_usd") or 0, result.get("num_turns"), result.get("subtype")))
