<#
---------------------------------------------------------------------------
 run_sql.ps1 - run the SQL scripts with sqlcmd on WINDOWS (PowerShell)

 Usage (from the db-security-ecommerce folder):
   .\run_sql.ps1                                  # run ALL scripts 01..07 in order
   .\run_sql.ps1 sql\03_rbac.sql                  # run one script
   .\run_sql.ps1 sql\00_reset.sql                 # remove everything
   .\run_sql.ps1 -SqlAuth                         # log in as sa (password from .env)
   .\run_sql.ps1 -Server "localhost\SQLEXPRESS"   # another instance name

 Default login = your WINDOWS account (-E). On a fresh SQL Server install,
 the Windows user who installed it is already a sysadmin.

 Why a runner? The scripts contain $(APP_PASSWORD) etc. instead of real
 passwords. This script reads them from .env and hands them to sqlcmd with
 -v NAME="value", so no secret is ever written inside a .sql file.

 If Windows blocks the script:  Set-ExecutionPolicy -Scope Process Bypass
---------------------------------------------------------------------------
#>
param(
    [string[]] $Scripts,
    [string]   $Server,
    [switch]   $SqlAuth
)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# --- read .env (KEY=VALUE per line, # = comment) ---
if (-not (Test-Path ".env")) { throw ".env not found. Copy .env.example to .env and fill it in." }
$envVars = @{}
foreach ($line in Get-Content ".env") {
    if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
    $key, $value = $line -split '=', 2
    $envVars[$key.Trim()] = $value.Trim()
}
if (-not $Server) { $Server = $envVars["DB_SERVER"] }

$varArgs = @()
foreach ($name in "APP_PASSWORD","LEGACY_APP_PASSWORD","STAFF_PASSWORD","DEMO_USER_PASSWORD",
                  "MASTER_KEY_PASSWORD","CERT_BACKUP_PASSWORD") {
    $varArgs += "-v"; $varArgs += "$name=$($envVars[$name])"
}

if (-not $Scripts) {
    $Scripts = "sql\01_schema.sql","sql\02_password_policy.sql","sql\03_rbac.sql","sql\04_abac.sql",
               "sql\05_stored_procedures.sql","sql\06_tde.sql","sql\07_mfa.sql"
}

# -E = Windows login, -U/-P = SQL login.  -C trust the local self-signed
# certificate, -b stop on errors, -I QUOTED_IDENTIFIER ON, -W trim spaces,
# -f 65001 read the .sql files as UTF-8
$auth = if ($SqlAuth) { @("-U", "sa", "-P", $envVars["SA_PASSWORD"]) } else { @("-E") }

foreach ($file in $Scripts) {
    Write-Host "=================== Running $file ===================" -ForegroundColor Cyan
    & sqlcmd -S $Server @auth -C -b -I -W -f 65001 @varArgs -i $file
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd failed on $file (exit code $LASTEXITCODE)" }
}
Write-Host "Done." -ForegroundColor Green
