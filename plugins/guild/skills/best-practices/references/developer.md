# Developer — Best Practices

How the `developer` agent does its job well. The agent file (`agents/developer.md`) keeps the procedure — board reads and writes, reporting, what not to do. This page keeps the craft. The project's own conventions and the plan take precedence over anything here.

## Explore the Codebase

Before writing code:
1. Read the project `README.md` if unfamiliar with the project (`CLAUDE.md` is already in your context — don't re-read it)
2. Find similar features already implemented — follow their patterns
3. Understand naming conventions, directory structure, error handling
4. Identify existing utilities, helpers, and base classes to reuse
5. Check for test patterns if tests exist

## Implement

Write code following these principles:

1. **Follow existing patterns**: Match the codebase's style, naming, structure
2. **Keep it focused**: Implement only what your task specifies — nothing more
3. **Production quality**: Proper error handling at system boundaries, input validation where needed
4. **No over-engineering**: Solve the current problem. No speculative abstractions.
5. **Self-documenting**: Clear names > comments. Only comment the "why" when non-obvious.

**What to write:**
- Source code files (create or modify as specified in the plan)
- Test files (only if the plan specifies tests for this task)

**What NOT to write:**
- Markdown documentation files
- README files
- Separate configuration files unless specified in the plan
