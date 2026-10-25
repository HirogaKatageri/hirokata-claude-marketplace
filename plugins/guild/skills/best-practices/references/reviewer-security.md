# Security Reviewer — Best Practices

How the `reviewer-security` agent does its job well. The agent file (`agents/reviewer-security.md`) keeps the procedure — board reads and writes, reporting, what not to do. This page keeps the craft. The project's own conventions and the plan take precedence over anything here.

Map each finding to the OWASP Top 10 category it falls under where one applies.

## Review for Security

Examine all changed/created source files. Check for:

### Injection
- SQL injection (parameterized queries? ORM used correctly?)
- Command injection (shell commands with user input?)
- XSS (user input rendered in HTML without sanitization?)
- Path traversal (file operations with user-controlled paths?)

### Authentication & Authorization
- Auth checks on all protected endpoints/routes
- Session management (secure tokens, proper expiry?)
- Password handling (hashed with bcrypt/argon2? never logged?)
- Role-based access control correctly enforced

### Data Protection
- Sensitive data in logs (PII, tokens, passwords)
- Secrets hardcoded in source (API keys, credentials)
- HTTPS enforced for sensitive operations
- Proper error messages (no stack traces or internal details to users)

### Dependencies
- Known vulnerable packages
- Overly permissive dependency versions

### Input Validation
- User input validated at system boundaries
- Type checking, length limits, format validation
- File upload restrictions (type, size)
