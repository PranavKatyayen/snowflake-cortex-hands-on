<#
  Episode 1 · Smoke-test the Snowflake-managed MCP server without any AI client.
  Usage (PowerShell):
    .\test_mcp.ps1 -Account "<orgname>-<accountname>" -TokenFile "$HOME\.snowflake\pat.txt"
    .\test_mcp.ps1 -Account ... -TokenFile ... -Tool snowbrew_copilot -Text "Why did Shibuya revenue drop in September?"
  Use hyphens, not underscores, in the account part of the URL.
#>
param(
  [Parameter(Mandatory)] [string] $Account,
  [Parameter(Mandatory)] [string] $TokenFile,
  [string] $Database = "SNOWBREW_LAB",
  [string] $Schema   = "CORE",
  [string] $Server   = "SNOWBREW_MCP",
  [string] $Tool,
  [string] $Text
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$token = (Get-Content -Raw $TokenFile).Trim()
$url   = "https://$($Account.ToLower()).snowflakecomputing.com/api/v2/databases/$Database/schemas/$Schema/mcp-servers/$Server"
$headers = @{
  "Authorization" = "Bearer $token"
  "Accept"        = "application/json, text/event-stream"
}
$script:id = 0

function Invoke-Mcp([string] $method, $params) {
  $script:id++
  $body = @{ jsonrpc = "2.0"; id = $script:id; method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
  $resp = Invoke-WebRequest -Uri $url -Method Post -Headers $headers -ContentType "application/json; charset=utf-8" `
            -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing -TimeoutSec 300
  $raw = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
  # tools/call answers as Server-Sent Events: keep the last JSON-RPC "data:" line
  if ($raw.TrimStart().StartsWith("{")) { return $raw | ConvertFrom-Json }
  $last = $raw -split "`n" | Where-Object { $_.StartsWith("data:") -and $_ -notmatch '\[DONE\]' } | Select-Object -Last 1
  return $last.Substring(5).Trim() | ConvertFrom-Json
}

Write-Host "MCP endpoint: $url`n"

if (-not $Tool) {
  $init = Invoke-Mcp "initialize" @{ protocolVersion = "2025-11-25"; capabilities = @{}; clientInfo = @{ name = "snowbrew-smoke-test"; version = "1.0" } }
  Write-Host "initialize -> server: $($init.result.serverInfo.name) $($init.result.serverInfo.version), protocol $($init.result.protocolVersion)"
  $list = Invoke-Mcp "tools/list" @{}
  Write-Host "`ntools/list -> $($list.result.tools.Count) tools"
  $list.result.tools | ForEach-Object { Write-Host ("  - {0,-26} {1}" -f $_.name, $_.title) }
  return
}

$args_ = switch ($Tool) {
  "search_customer_feedback" { @{ query = $Text; limit = 3 } }
  "sales_analyst"            { @{ message = $Text } }
  "simulate_price_change"    { $p = $Text -split ","; @{ PRODUCT_NAME = $p[0].Trim(); PRICE_CHANGE_PCT = [double]$p[1] } }
  default                    { @{ text = $Text } }
}
$res = Invoke-Mcp "tools/call" @{ name = $Tool; arguments = $args_ }
if ($res.error) { Write-Host "ERROR: $($res.error | ConvertTo-Json -Depth 10)"; exit 1 }
$res.result.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }
