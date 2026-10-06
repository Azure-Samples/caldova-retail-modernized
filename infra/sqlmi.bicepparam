using './sqlmi.bicep'

// Optional SQL Managed Instance only. Freemium first; use Regular when the free offer is unavailable.

param prefix = readEnvironmentVariable('LAB04_PREFIX', 'caldova-lab04')
param suffix = readEnvironmentVariable('LAB04_SUFFIX')
param location = readEnvironmentVariable('LAB04_SECONDARY_LOCATION', 'centralus')
param sqlEntraAdminObjectId = readEnvironmentVariable('LAB04_SQL_ADMIN_OBJECT_ID')
param sqlEntraAdminLogin = readEnvironmentVariable('LAB04_SQL_ADMIN_LOGIN')
param pricingModel = readEnvironmentVariable('LAB04_SQL_MI_PRICING_MODEL', 'Freemium')

param vCores = 4
param storageSizeInGB = 64
