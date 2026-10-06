# .NET Version Upgrade

## Scenario

Upgrade eShopLite.StoreFx (ASP.NET MVC 5 / Entity Framework 6, .NET Framework 4.8) to ASP.NET Core on .NET 10.

## Parameters

- **Solution**: `eShopLiteFx.sln`
- **Projects**: `src\eShopLite.StoreFx\eShopLite.StoreFx.csproj` (net48)
- **Target framework**: `net10.0` (LTS)

## Source Control

- **Source branch**: `main` (`f7ce4ca`)
- **Working branch**: `sojorgensen/upgradedotnet10`
- **Commit strategy**: Commit after each task

## Preferences

### Flow Mode

Automatic — run end-to-end, pause only when blocked.

## Upgrade Options

### Strategy
- Upgrade Strategy: All-at-Once

### Project Structure
- Project Approach: In-place rewrite

### Compatibility
- Unsupported Packages: Resolve Inline (1 incompatible package)
- Unsupported API Handling: Fix Inline
- System.Web Adapters: Direct Migration to ASP.NET Core APIs

### Modernization
- Assembly Binding Redirects: Remove Binding Redirects
- Nullable Reference Types: Leave Disabled
- Entity Framework: Keep EF6

### Reliability
- Test Coverage: Skip

## Strategy
**Selected**: All-at-Once
**Rationale**: Single project (eShopLite.StoreFx, net48 ASP.NET MVC 5), no project-to-project dependencies.

### Execution Constraints
- SDK-style conversion is its own task and stays on net48; it must build before the TFM change starts.
- The in-place rewrite to ASP.NET Core / net10.0 is one atomic pass: update project file → update packages → restore → build and fix all compilation errors.
- Validate with a full solution build (0 errors, 0 warnings) after the rewrite; there are no test projects.
- Runtime check: app starts on Kestrel and serves the home page; DB-backed pages are expected to fail without SQL Server.
- Commit after each task (user's explicit choice, kept over the All-at-Once single-commit default).

## User Preferences

### Technical Preferences

- No database is available locally; the app is expected to fail when it reaches the DB. Validation should not depend on a live SQL Server.
- `connectionStrings.config` holds a placeholder password (documented in README Setup). Keep it a placeholder; never commit a real credential.
- `Web.Debug.config` / `Web.Release.config` were intentionally removed; the app will not be published as-is.

## Decisions

- The Upgrade MCP `start_task` could not parse `plan.md` (its internal LLM client was unavailable), so tasks were tracked manually in `tasks.md` and in commit history instead of per-task folders.
- `Autofac.Mvc5` (incompatible) was resolved inline by moving the six simple Autofac registrations to built-in DI; no Autofac-specific features were in use.
- `connectionStrings.config` was replaced by `appsettings.json` (same placeholder value); README Setup updated.

## Follow-ups (deferred, out of scope for this upgrade)

- Migrate EF6 → EF Core (and `System.Data.SqlClient` → `Microsoft.Data.SqlClient`).
- Replace salted SHA-1 password hashing (`AuthService`) with a modern hasher, rehashing on login.
- Enable nullable reference types.
- Migrate `Newtonsoft.Json` attributes on `Product`/`StoreInfo` to `System.Text.Json` if they are still needed.
- Replace the legacy jQuery/Modernizr script bundle in `wwwroot` with LibMan or npm-managed assets.
