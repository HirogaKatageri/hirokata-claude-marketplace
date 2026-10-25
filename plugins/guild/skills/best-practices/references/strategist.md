# Strategist — Best Practices

How the `strategist` agent does its job well. The agent file (`agents/strategist.md`) keeps the procedure — board reads and writes, reporting, what not to do. This page keeps the craft. The project's own conventions and the plan take precedence over anything here.

## Design the Work

Based on the requirement and what you surveyed:

1. **Break down into components**: What needs to be built, changed, or integrated?
2. **Determine task boundaries**: Each ticket should be independently deliverable
3. **Order by dependency**: Foundation first, then work that depends on it
4. **Assess complexity**: Rate each task (1=simple, 2=moderate, 3=complex)
5. **Design for parallel work — parallel is the default, not the exception.** Two tickets may run
   in the same wave only if they **own disjoint resources** and neither consumes what the other
   produces. **What a resource IS comes from your domain profile (Slot 2 of the domain profile, `guild:domain-software`)** — on the `software`
   profile it is a file path, and the profile carries the full rule. Whatever the domain, the
   shape is the same: shape ticket boundaries so the owned sets do not overlap, then organize the
   tasks into **waves** — an ungrouped foundational task runs solo first if others build on it;
   every remaining task lands in a `parallel-group` wave (`A`, then `B` for a second wave that
   depends on the first). If a natural decomposition puts two tasks on the same resource, prefer
   redrawing the boundary over serializing them. Leave a task ungrouped **only** when it is
   foundational, or when you genuinely cannot bound what it owns. A plan whose tickets are all
   sequential should be rare and justified in the plan's Technical Decisions section.

   **You ASSERT that disjointness on the record, and nothing verifies it.** Each ticket's owned set
   goes into `task.files` (Step 5 of `agents/strategist.md`) — an opaque JSON array that no view parses — and the `implement`
   node fans out one node per implement ticket (`fanout: per-task`), so those sets are what makes
   concurrent dispatch reviewable. Two tickets in one `parallel_group` claiming the same resource
   means two members contending for it. If you cannot make the sets disjoint, do not pretend they
   are: split `implement` into sequential waves with a `reshape` deviation (Step 6 of `agents/strategist.md`) and say why.
6. **Identify risks**: What could go wrong? What assumptions are we making?
