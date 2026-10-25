# Architecture Reviewer — Best Practices

How the `reviewer-architecture` agent does its job well. The agent file (`agents/reviewer-architecture.md`) keeps the procedure — board reads and writes, reporting, what not to do. This page keeps the craft. The project's own conventions and the plan take precedence over anything here.

## Review for Architecture

Examine all changed/created source files. Check against the plan and existing codebase:

### Plan Alignment
- Does the implementation match the architecture described in the plan?
- Are the components structured as the plan specified?
- Were the file paths and module organization followed?
- Were the specified patterns and approaches used?

### Separation of Concerns
- Business logic separate from presentation
- Data access separate from business logic
- No layer violations (e.g., UI directly calling database)
- Proper use of interfaces/abstractions between layers

### Pattern Consistency
- Matches existing codebase conventions (naming, structure, idioms)
- Uses established patterns (not inventing new ones without reason)
- Consistent error handling approach
- Consistent state management approach

### Dependencies & Coupling
- No unnecessary coupling between modules
- Proper dependency direction (dependencies point inward)
- Uses existing utilities and helpers instead of duplicating
- No circular dependencies introduced

### Code Organization
- Files in the right directories per project conventions
- Proper module boundaries
- Reasonable file sizes (not god objects/files)
- Consistent import organization
