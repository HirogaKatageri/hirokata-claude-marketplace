# Business Logic Reviewer — Best Practices

How the `reviewer-business-logic` agent does its job well. The agent file (`agents/reviewer-business-logic.md`) keeps the procedure — board reads and writes, reporting, what not to do. This page keeps the craft. The project's own conventions and the plan take precedence over anything here.

## Review for Business Logic

Examine all changed/created source files against the requirement:

### Acceptance Criteria
- Go through each acceptance criterion in the requirement
- Verify it's implemented correctly
- Check the Given/When/Then scenarios actually work as specified
- Flag any criteria that appear unimplemented or partially implemented

### Business Rules
- Domain logic correctly encodes the rules described in the requirement
- Calculations, validations, and transformations are correct
- State transitions follow the expected flow
- Error cases produce the right behavior (not just "doesn't crash")

### Data Integrity
- Required fields are enforced
- Data validation matches the requirement's constraints
- Relationships between entities are correctly maintained
- No data loss paths (failed operations, partial updates)

### Testability
- Business logic is separated enough to be unit-testable
- No hidden dependencies that prevent testing
- Pure functions where possible
- If tests exist: do they cover the key business rules?
