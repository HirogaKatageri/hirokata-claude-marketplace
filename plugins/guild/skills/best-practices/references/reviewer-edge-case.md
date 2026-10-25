# Edge Case Reviewer — Best Practices

How the `reviewer-edge-case` agent does its job well. The agent file (`agents/reviewer-edge-case.md`) keeps the procedure — board reads and writes, reporting, what not to do. This page keeps the craft. The project's own conventions and the plan take precedence over anything here.

## Review for Edge Cases

Examine all changed/created source files. Think adversarially — what inputs, states, and conditions would break this?

### Boundary Conditions
- Empty strings, empty arrays, empty objects
- Zero, negative numbers, MAX_INT
- Single item vs. many items in collections
- First item, last item in sequences
- Exactly at limits (pagination boundaries, rate limits, timeouts)

### Null & Undefined
- Nullable fields accessed without checks
- Optional parameters missing
- API responses with missing fields
- Database queries returning no results

### Error Scenarios
- Network failures mid-operation
- Database connection lost
- File system permissions denied
- External API returning errors or unexpected formats
- Timeouts on long operations

### Concurrency (if applicable)
- Race conditions on shared state
- Duplicate form submissions
- Concurrent modifications to the same resource
- Stale data reads

### Data Edge Cases
- Unicode and special characters in strings
- Very long strings exceeding expected lengths
- Malformed dates, emails, URLs
- Mixed-case sensitivity issues
- Whitespace-only inputs

### State Edge Cases
- Operations on already-deleted resources
- Duplicate operations (idempotency)
- Operations in unexpected order
- Partially completed multi-step processes
