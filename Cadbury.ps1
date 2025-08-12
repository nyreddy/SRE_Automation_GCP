<#
.SYNOPSIS
  Build CMDB relationships in ServiceNow from GCP metadata.
  This version is parameterized to switch between NP and PD.

.PARAMETER Env
  np | pd

.PARAMETER Nuid
  ServiceNow user id used for basic auth (e.g., srvgcpsnowdp / srvgcpsnowpd)

.PARAMETER SecretName
  GCP Secret Manager secret name that stores the ServiceNow password

.PARAMETER SecretProject
  GCP project id that holds the secret

.PARAMETER SnowBaseUrl
  Base url for ServiceNow instance (e.g., https://huntingtontest.service-now.com)

.PARAMETER BatchSize
  Chunk size for posting payloads to ServiceNow
#>

param(
  [Parameter(Mandatory)]
  [ValidateSet('np','pd')]
  [string]$Env,

  [Parameter(Mandatory)]
  [string]$Nuid,

  [Parameter(Mandatory)]
  [string]$SecretName,

  [Parameter(Mandatory)]
  [string]$SecretProject,

  [Parameter(Mandatory)]
  [string]$SnowBaseUrl,

  [int]$BatchSize = 50,

  # NOTE: update the default if you move runners/service account
  [string]$ImpersonateSA = "srv-sre-ado-runner-audit-b@prj-secrets-fae9.iam.gserviceaccount.com"
)

Write-Host "Running for env '$Env' against $SnowBaseUrl" -ForegroundColor Cyan

# --- Build SNOW API URL from base ---
$api = "$SnowBaseUrl/api/thmb/v1/cloud_services_api/buildcloudrelationships"

# --- Pull ServiceNow password from Secret Manager in the provided project ---
$pass = gcloud secrets versions access latest `
  --secret "$SecretName" `
  --project "$SecretProject" `
  --impersonate-service-account=$ImpersonateSA `
  --verbosity=error

if (-not $pass) { throw "Failed to read secret '$SecretName' in project '$SecretProject'." }

# --- Auth header for ServiceNow ---
$user    = $Nuid
$headers = @{
  'Content-Type' = 'application/json'
  'Authorization' = "Basic $([System.Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$user`:$pass")))"
}

# --- Get GCP projects using the audit SA ---
$projects = gcloud projects list --format="value(projectId)" `
  --impersonate-service-account=$ImpersonateSA --verbosity=error

function Split-Into-Chunks {
  param(
    [Parameter(Mandatory, ValueFromPipeline)]
    [PSCustomObject[]]$InputArray,

    [Parameter(Mandatory)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$ChunkSize
  )
  for ($i = 0; $i -lt $InputArray.Count; $i += $ChunkSize) {
    $end = [math]::Min($i + $ChunkSize - 1, $InputArray.Count - 1)
    ,$InputArray[$i..$end]
  }
}

# ===========================
# BEGIN EXISTING MAPPING LOGIC
# ===========================
# Build $corridMap as an array of PSCustomObject with this shape:
# @{
#   cloudName             = "Google Cloud Platform"
#   cloudCorrelationId    = "900071"
#   applicationName       = $labels.'application-name'
#   applicationCorrelationId = $labels.'app-id'
#   cloudServices = @(
#     @{
#       cloudServiceName = "Big Table"
#       cloudServiceId   = "1234567890"
#     }
#   )
# }
# Keep your existing parallelization/label lookups; only the variables above changed.
$corridMap = @()

$projects | ForEach-Object {
  $project = $_
  $labels = gcloud projects describe $project --format=json `
    --impersonate-service-account=$ImpersonateSA --verbosity=error |
    ConvertFrom-Json | Select-Object -ExpandProperty labels -ErrorAction SilentlyContinue

  if ($null -ne $labels -and $labels.'app-id' -ne 900071) {
    $corridMap += [PSCustomObject]@{
      cloudName               = "Google Cloud Platform"
      cloudCorrelationId      = "900071"
      applicationName         = $labels.'application-name'
      applicationCorrelationId= $labels.'app-id'
      cloudServices           = @()  # fill if you attach services
    }
  }
}

# =========================
# END EXISTING MAPPING LOGIC
# =========================

if (-not $corridMap -or $corridMap.Count -eq 0) {
  Write-Warning "Nothing to send to ServiceNow."; return
}

Split-Into-Chunks -InputArray $corridMap -ChunkSize $BatchSize | ForEach-Object {
  $_ | ConvertTo-Json -Depth 10 |
    Invoke-RestMethod -Uri $api -Method Post -Headers $headers |
    Select-Object -ExpandProperty result
}
