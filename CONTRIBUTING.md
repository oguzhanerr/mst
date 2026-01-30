# Contributing to Giga MST

Thank you for your interest in contributing to the Giga Mobile Simulation Tool! This document provides guidelines and instructions for contributing.

## Code of Conduct

Please be respectful and constructive in all interactions. We welcome contributors from all backgrounds and experience levels.

## How to Contribute

### Reporting Bugs

1. Check if the bug has already been reported in [Issues](https://github.com/oguzhanerr/mst/issues)
2. If not, create a new issue using the bug report template
3. Include as much detail as possible:
   - Steps to reproduce
   - Expected vs actual behavior
   - Screenshots if applicable
   - Environment details (OS, Docker version, etc.)

### Suggesting Features

1. Check existing issues for similar suggestions
2. Create a new issue using the feature request template
3. Describe the use case and expected behavior

### Submitting Changes

1. **Fork** the repository
2. **Clone** your fork locally
3. **Create a branch** for your changes:
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/issue-description
   ```
4. **Make your changes** following the coding standards below
5. **Test** your changes locally:
   ```bash
   docker compose -f compose.init.yaml up --build
   docker compose up --build -d
   ```
6. **Commit** with a clear message:
   ```bash
   git commit -m "Add feature: description of changes"
   ```
7. **Push** to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```
8. **Open a Pull Request** against the `main` branch

## Development Setup

### Prerequisites

- Docker & Docker Compose
- Git

### Local Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/mst.git
cd mst

# Copy environment templates
cp env/.superset.env.template env/.superset.env
cp env/.database.env.template env/.database.env
cp env/.metadata.env.template env/.metadata.env

# Edit env files with your local values
# ...

# Initialize (first time)
docker compose -f compose.init.yaml up --build

# Start the stack
docker compose up --build -d
```

### Testing Changes

After making changes:

```bash
# Rebuild affected services
docker compose up --build -d superset celery_worker celery_beat

# Check logs for errors
docker compose logs -f superset

# Access the application
open http://localhost:8088
```

## Coding Standards

### Python

- Follow PEP 8 style guidelines
- Use meaningful variable and function names
- Add comments for complex logic

### Docker

- Keep images small - use multi-stage builds where possible
- Don't include secrets in images
- Use specific version tags, not `latest`

### SQL

- Use uppercase for SQL keywords
- Include comments for complex queries
- Test migrations thoroughly

### Documentation

- Update README.md if adding new features
- Document new environment variables in templates
- Add inline comments for non-obvious code

## Commit Messages

Use clear, descriptive commit messages:

```
Add feature: brief description

- Detail 1
- Detail 2
```

Prefixes:
- `Add:` New features
- `Fix:` Bug fixes
- `Update:` Changes to existing features
- `Remove:` Removing features or code
- `Docs:` Documentation only
- `Refactor:` Code changes that don't add features or fix bugs

## Pull Request Guidelines

- Keep PRs focused on a single change
- Update documentation as needed
- Ensure all services start without errors
- Respond to review feedback promptly

## Questions?

Feel free to open an issue for any questions about contributing.

Thank you for contributing! 🎉
