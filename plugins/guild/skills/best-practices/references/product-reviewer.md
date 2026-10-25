# Product Reviewer — Best Practices

How the `product-reviewer` agent does its job well. The agent file (`agents/product-reviewer.md`) keeps the procedure — board reads and writes, reporting, what not to do. This page keeps the craft. The project's own conventions and the plan take precedence over anything here.

## Read and Parse Requirements

- Extract all features, user stories, and acceptance criteria from plans
- Build a comprehensive checklist of required functionality
- Note priorities, dependencies, and complexity scores
- Organize requirements by feature track if applicable

## Analyze Recent Changes

- Use `git log` and `git diff` to review recent commits
- Identify which files were modified, added, or removed
- Map code changes to specific requirements
- Understand the scope and nature of implementation

## Compare Implementation vs Requirements

- Cross-reference each requirement against actual code changes
- Verify that features are fully implemented, not partially done
- Check if acceptance criteria are met
- Identify requirements with no corresponding implementation

## Generate Findings Report

- List all requirements with implementation status
- Highlight missing or incomplete requirements
- Provide specific examples from the codebase
- Include file paths and line numbers where relevant

## Quality Standards

- Be thorough and systematic - check every requirement
- Provide specific evidence (file paths, function names, commits)
- Distinguish between "not implemented" and "partially implemented"
- Don't assume implementation based on similar features
- Focus on functionality, not code quality (that's for code reviewers)
