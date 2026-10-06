# .NET 10 Upgrade Plan — eShopLiteFx.sln

## Overview

Upgrade the eShopLite storefront (`src\eShopLite.StoreFx`) from ASP.NET MVC 5 on .NET Framework 4.8 to ASP.NET Core MVC on .NET 10 (LTS), rewriting the web project in place. See [assessment.md](assessment.md) for the full inventory.

### Selected Strategy
**All-At-Once** — All projects upgraded simultaneously in a single operation.
**Rationale**: 1 project, on .NET Framework 4.8, no project-to-project dependencies.

### Projects

| Project | Type | Current | Target |
|---------|------|---------|--------|
| `src\eShopLite.StoreFx\eShopLite.StoreFx.csproj` | ASP.NET MVC 5 web app (legacy csproj, packages.config) | net48 | net10.0 |

## Upgrade Options

| Option | Selected | Why |
|--------|----------|-----|
| Upgrade Strategy | All-at-Once | The solution has a single project, so there is no dependency graph to stage. |
| Project Approach (Web Projects) | In-place rewrite | Small web app (4 controllers, ~1.8k LOC) that won't be released, so there is no live traffic to keep up during migration. |
| Unsupported Packages | Resolve Inline | Only Autofac.Mvc5 has no .NET 10 version, which is small enough to resolve inline. |
| Unsupported API Handling | Fix Inline | 259 System.Web API issues in one small project are manageable to fix directly. |
| System.Web Adapters | Direct Migration to ASP.NET Core APIs | In-place rewrite of a small app with only 9 HttpContext uses; native ASP.NET Core APIs leave no shim layer to remove later. |
| Assembly Binding Redirects | Remove Binding Redirects | Web.config has 12 standard auto-generated redirects that .NET 10 doesn't use. |
| Nullable Reference Types | Leave Disabled | The assessment rates this upgrade High difficulty, so adding nullable warnings now would add noise. |
| Entity Framework | Keep EF6 | EF 6.5 runs on .NET 10, and migrating to EF Core at the same time would add a second source of breaking changes. |
| Test Coverage | Skip | The assessment recommends coverage for this High-difficulty project, but generating tests is opt-in because it adds time and tokens. |

## Tasks

### 01-prerequisites: Verify .NET 10 toolchain

Confirm a .NET 10 SDK is installed and usable for this repository, and check for any `global.json` that would pin an older SDK. The machine currently has SDKs 10.0.112 and 10.0.401 installed; no `global.json` exists in the repo.

**Done when**: `dotnet --version` from the repo root resolves to a 10.0.x SDK and no `global.json` blocks it.

### 02-sdk-style-conversion: Convert eShopLite.StoreFx to SDK-style on net48

Convert the legacy Web Application Project (`ProjectTypeGuids` WAP, `ToolsVersion`, `packages.config` with 22 packages) to an SDK-style project that still targets `net48`. `packages.config` moves to `PackageReference`. This is a structural change only — no TFM or API changes — so the app should still build with MSBuild and behave as before.

Risks: WAP-specific MSBuild imports (`Microsoft.WebApplication.targets`), `Content`/`Compile` item lists for Views, Scripts and Content, and the `Microsoft.CodeDom.Providers.DotNetCompilerPlatform` Roslyn compiler package. Research starting points: use `convert_project_to_sdk_style`; check that Views, `Global.asax`, `connectionStrings.config`, and static assets are still included.

**Done when**: the project is SDK-style, `packages.config` is gone, and the solution builds on net48 with 0 errors.

### 03-upgrade-storefront: Rewrite eShopLite.StoreFx in place as ASP.NET Core on net10.0

Retarget the project to `net10.0` on `Microsoft.NET.Sdk.Web` and replace the ASP.NET MVC 5 / System.Web stack with ASP.NET Core MVC. The assessment reports 259 API issues (207 binary-incompatible, 52 source-incompatible), 98.8% of them System.Web — `System.Web.Mvc` controllers and action results, `FormsAuthentication` (10 uses), `HttpContext` (9 uses), `RouteCollection` routes, `GlobalFilterCollection` filters, and `Global.asax.cs` startup. #skill:migrating-webapi-odata

Known risks: Autofac.Mvc5 has no .NET 10 version (registrations are simple and move to built-in DI); Forms authentication must become cookie authentication, and sign-ins on the old app will not carry over; session-based cart (`HttpContextSessionStore`) needs ASP.NET Core session; EF6 6.5.x stays but its configuration moves from `Web.config` to code/`appsettings.json`; `connectionStrings.config` must keep its placeholder password; 12 binding redirects and MVC 5 / Razor / WebPages / CodeDom packages are removed; one Legacy Cryptography issue (SHA-1 password hashing) is flagged. Research starting points: `Global.asax.cs`, `App_Start\*`, `Web.config` (`<authentication mode="Forms">`, session, `system.webServer`), `Services\` (auth, session, cart), `Views\` (`@Html`/`@Url` helpers, `_Layout`, `web.config` in Views), and bundling/Modernizr script references.

**Done when**: the project targets `net10.0`, contains no `System.Web` references, builds with 0 errors and 0 warnings, and the app starts on Kestrel and serves the home page.

### 04-final-validation: Validate the upgraded solution

Build the full solution from a clean state, run the app, and check that non-database pages load (home page, login page, static assets). Database-backed pages are expected to fail without a SQL Server. Update the README run instructions (MSBuild + IIS Express → `dotnet run`) and document deferred follow-ups (EF Core migration, nullable reference types, replacing SHA-1 password hashing).

**Done when**: `dotnet build` of `eShopLiteFx.sln` succeeds with 0 errors and 0 warnings, the app serves the home and login pages, and the README and follow-ups are updated.
