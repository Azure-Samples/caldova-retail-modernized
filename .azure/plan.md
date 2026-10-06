# Azure Deployment Plan

> **Status:** Planning — Phase A (app-code readiness) complete; Phases B–D pending

Generated: 2026-10-05

---

## 1. Project Overview

**Goal:** Make the eShopLite Blazor storefront (.NET 10, static server rendering) ready to run in Azure Container Apps, without breaking local development.

**Path:** Modernize Existing

**Ground rules (from the user):**

- Every Azure integration is **optional**: it is enabled only when its configuration is present, and the app falls back to today's local behavior otherwise. The app must build and run with no Azure resources.
- No hardcoded endpoints, keys, or connection strings — everything comes from configuration (appsettings, environment variables, or Key Vault).
- **Out of scope for now:** Dockerfile and anything database-related (Azure SQL, EF provider changes, schema/seed). These come later.
- Work happens on branch `sojorgensen/azureready`, one commit per phase.

---

## 2. Requirements

| Attribute | Value |
|-----------|-------|
| Classification | POC — bootcamp lab, torn down afterwards |
| Scale | Small |
| Budget | Cost-optimized |
| Hosting | Azure Container Apps (user choice) |
| **Subscription** | ⏳ To confirm with user before the infrastructure phase |
| **Location** | ⏳ To confirm with user before the infrastructure phase |

---

## 3. Components Detected

| Component | Type | Technology | Path |
|-----------|------|------------|------|
| storefront | SSR web app | ASP.NET Core Blazor (static SSR), .NET 10 | `src/eShopLite.StoreFx` |

| Dependency | Type | Current state |
|-----------|------|---------------|
| SQL Server | Relational DB | EF6 6.5.2 over `System.Data.SqlClient`, SQL auth, connection string in `appsettings.json` (placeholder password) |
| Session state | In-process | `AddDistributedMemoryCache` |
| Data Protection keys | In-process | Default (ephemeral in containers) |

| Existing infrastructure | Status |
|------|--------|
| `azure.yaml` | Not found |
| `infra/` | Not found |
| Dockerfile | Not found (deferred) |
| CI/CD | Not found |

---

## 4. Readiness Assessment

| # | Gap | Impact in Container Apps | Phase |
|---|-----|--------------------------|-------|
| 1 | No health endpoints | Platform can't probe liveness/readiness | A1 |
| 2 | TLS terminates at ingress; app sees `http` | Auth/session cookies not marked `Secure`; wrong scheme in redirects | A1 (config only) |
| 3 | No managed-identity credential | Can't reach Azure services passwordlessly | A2 |
| 4 | Secrets only in `appsettings.json` | No Key Vault source for the connection string or other secrets | A2 |
| 5 | Data Protection keys are ephemeral | Every restart/revision signs users out and invalidates antiforgery tokens (form posts fail with 400); replicas can't read each other's cookies | A3 |
| 6 | Session cache is in-process | Carts lost on restart; not shared across replicas | A3 |
| 7 | No telemetry | No Application Insights requests, dependencies, logs, or exceptions | A4 |
| 8 | No container image | Can't deploy to Container Apps | Deferred (B) |
| 9 | Database not cloud-ready (SQL auth as `sa`, `Encrypt=False`, `System.Data.SqlClient` has no Entra ID auth, no schema/seed path) | Can't connect to Azure SQL with a managed identity | Deferred (C) |
| 10 | No `azure.yaml` / Bicep | Nothing to provision | Deferred (D) |
| 11 | Salted SHA-1 password hashes | Weak credential storage (intentional lab "before" state) | Out of scope |

---

## 5. Recipe Selection

**Selected:** AZD (Bicep) — for the later infrastructure phase.

**Rationale:** Single-service app, no existing IaC, simplest `azd up` workflow; azd supports Container Apps natively.

---

## 6. Architecture (target)

**Stack:** Containers

| Component | Azure Service | SKU (POC) |
|-----------|---------------|-----|
| storefront | Azure Container Apps | Consumption, min 1 / max 1–2 replicas |
| container images | Azure Container Registry | Basic |
| database | Azure SQL Database | Basic / serverless (deferred) |
| session cache | Azure Managed Redis or Azure Cache for Redis (optional) | Smallest tier |
| Data Protection keys | Storage account (Blob) + Key Vault key (optional) | Standard LRS |

| Supporting service | Purpose |
|---------|---------|
| Log Analytics | Container Apps logs |
| Application Insights | Monitoring & APM |
| Key Vault | Secrets and Data Protection key wrapping |
| User-assigned managed identity | Passwordless access to Key Vault, Storage, Redis, SQL |

---

## 7. App Configuration Contract

All settings are optional. When a setting is empty or missing, the app uses its current local behavior.

| Setting (env var form) | Enables | Fallback when absent |
|------------------------|---------|----------------------|
| `AZURE_CLIENT_ID` | Use this **user-assigned** managed identity | System-assigned managed identity (outside Development) or developer credentials (Development) |
| `KeyVault__Uri` | Key Vault as a configuration source (e.g. secret `ConnectionStrings--StoreDbContext`) | `appsettings.json` / environment only |
| `DataProtection__BlobUri` | Persist Data Protection keys to a blob | In-memory/local key ring |
| `DataProtection__KeyVaultKeyUri` | Wrap those keys with a Key Vault key (only used with `BlobUri`) | Keys stored unwrapped |
| `DataProtection__ApplicationName` | Stable app discriminator across replicas/revisions | Default (content-root based) |
| `Redis__Endpoint` | Redis-backed session cache with Entra ID auth (e.g. `myredis.redis.cache.windows.net:6380`) | In-memory session cache |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Azure Monitor OpenTelemetry (traces, metrics, logs) | Console logging only |
| `ASPNETCORE_FORWARDEDHEADERS_ENABLED=true` | Trust `X-Forwarded-Proto/For` from Container Apps ingress (built into ASP.NET Core, no code) | Request scheme taken as-is |

---

## 8. Execution Checklist

### Phase 1: Planning
- [x] Analyze workspace (Mode: MODERNIZE)
- [x] Gather requirements (POC, Container Apps)
- [ ] Confirm subscription and location with user — deferred to Phase D
- [x] Scan codebase
- [x] Select recipe (AZD Bicep, for Phase D)
- [x] Plan architecture
- [x] **User approved proceeding with app-code readiness** (Phase A)

### Phase 2: Execution

**Phase A — App-code readiness (this branch)**
- [x] A1 Health endpoints `/health` (liveness) and `/ready` (readiness); document forwarded-headers setting
- [x] A2 Shared Azure credential (managed identity in Azure, developer credential in Development) + optional Key Vault configuration source
- [x] A3 Optional Data Protection key persistence (Blob + Key Vault key) and optional Redis session cache
- [x] A4 Optional Azure Monitor OpenTelemetry
- [x] A5 Docs (README configuration table) + validate build/run with **no** Azure configuration

**Phase B — Container image (later)**
- [ ] Dockerfile (.NET 10 runtime, port 8080, non-root) and `.dockerignore`

**Phase C — Database (later)**
- [ ] Azure SQL Database with Entra ID-only auth
- [ ] Switch EF6 to `Microsoft.EntityFramework.SqlServer` (Microsoft.Data.SqlClient) for `Authentication=Active Directory Managed Identity`; `Encrypt=True`
- [ ] Schema + seed deployment path; database check on `/ready`

**Phase D — Infrastructure (later)**
- [ ] Confirm subscription and region
- [ ] `azure.yaml` + `infra/main.bicep`: Container Apps env, ACR, Log Analytics, App Insights, Key Vault, Storage, Redis (optional), user-assigned identity, RBAC role assignments, health probes, env vars from section 7
- [ ] Update plan status to "Ready for Validation"

### Phase 3: Validation
- [ ] Invoke azure-validate skill
- [ ] All validation checks pass
- [ ] Update plan status to "Validated"
- [ ] Record validation proof below

### Phase 4: Deployment
- [ ] Invoke azure-deploy skill
- [ ] Deployment successful
- [ ] Update plan status to "Deployed"

---

## 9. Validation Proof

> **⛔ REQUIRED**: The azure-validate skill MUST populate this section before setting status to `Validated`.

| Check | Command Run | Result | Timestamp |
|-------|-------------|--------|-----------|

**Validated by:** azure-validate skill
**Validation timestamp:** —

---

## 10. Files to Generate

| File | Purpose | Status |
|------|---------|--------|
| `.azure/plan.md` | This plan | ✅ |
| `src/eShopLite.StoreFx/Hosting/AzureIntegration.cs` | Optional Azure integrations | ✅ |
| `Dockerfile` | Container build | ⏸ Deferred (Phase B) |
| `azure.yaml` | AZD configuration | ⏸ Deferred (Phase D) |
| `infra/main.bicep` | Infrastructure | ⏸ Deferred (Phase D) |

---

## 11. Next Steps

> Current: Phase A complete — app code is Azure-ready behind optional configuration.

1. Phase B: Dockerfile (when the user is ready).
2. Phase C: database (Azure SQL + passwordless EF6 provider).
3. Phase D: confirm subscription/region, then `azure.yaml` + Bicep; then azure-validate and azure-deploy.
