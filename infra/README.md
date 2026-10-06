# Azure infrastructure (Lab 04)

Bicep for the Azure foundation the storefront runs on. It was generated and reviewed in Lab 04 of the modernization bootcamp; the bootcamp's instructor-provisioned environment is what later labs actually use, so treat this as a reviewed design, not a deployed one.

## Entry points

All four are resource-group scoped and deploy in this order:

| Order | File | Resource group | What it creates |
| --- | --- | --- | --- |
| 1 | `primary.bicep` | primary (`northcentralus`) | Database VNet `10.0.0.0/20`, two private VMs behind Azure Bastion, Entra-only Azure SQL (`eShop`) with a private endpoint, Database Migration Service, container registry |
| 2 | `secondary.bicep` | secondary (`centralus`) | SQL MI VNet `10.1.0.0/20`, application VNet `10.20.0.0/20`, internal zone-redundant Container Apps environment and app, runtime identity, Key Vault, Data Protection storage, Redis, Application Insights, private endpoints and DNS, peerings, role assignments |
| 3 | `global.bicep` | global | Front Door Premium with one Private Link origin and a WAF policy |
| 4 | `sqlmi.bicep` | secondary | **Optional** Entra-only SQL Managed Instance; deploy separately, never with the base |

Each entry point has a matching `.bicepparam` file. Values come from environment variables (`LAB04_*`, `LAB06_*`, `AZURE_SUBSCRIPTION_ID`); the files contain no secrets.

## App configuration it provides

`secondary.bicep` sets the settings the app reads in [`src/eShopLite.StoreFx/Hosting/AzureIntegration.cs`](../src/eShopLite.StoreFx/Hosting/AzureIntegration.cs):
`AZURE_CLIENT_ID`, `ConnectionStrings__StoreDbContext` (passwordless), `KeyVault__Uri`, `DataProtection__BlobUri`, `DataProtection__KeyVaultKeyUri`, `DataProtection__ApplicationName`, `Redis__Endpoint`, `APPLICATIONINSIGHTS_CONNECTION_STRING` (as a Container Apps secret), and `ASPNETCORE_FORWARDEDHEADERS_ENABLED`.

The passwordless SQL connection string needs the app's EF6 provider switched to `Microsoft.EntityFramework.SqlServer` (still to do).

## Validate locally

```powershell
Get-ChildItem .\infra -Filter *.bicep -Recurse |
  ForEach-Object { az bicep build --file $_.FullName --stdout | Out-Null }
```

Building checks syntax and types only. It does not prove names are available, quotas are sufficient, or that deployment will succeed.

> [!WARNING]
> Do not run `az bicep build-params` on `primary.bicepparam` without `--stdout`: it writes
> `primary.parameters.json` containing the VM password, and that file is not git-ignored.

## Open review findings (not yet fixed)

- Redeploying `secondary.bicep` after SQL MI exists can fail: the SQL MI NSG and route table are managed declaratively, which conflicts with the rules SQL MI adds itself.
- Redeploying `primary.bicep` may remove VNet peerings created by `secondary.bicep` (verify with what-if).
- Redis runs without high availability, so it is a single point of failure for carts.
- No diagnostic settings: WAF detections, Front Door, Key Vault and SQL logs go nowhere.
- The app Key Vault name is reused after cleanup while the old vault is soft-deleted.
- Front Door's Private Link connection must be approved on the Container Apps environment after `global.bicep`.
