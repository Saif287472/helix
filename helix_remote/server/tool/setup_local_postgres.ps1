<#
.SYNOPSIS
Creates the local PostgreSQL role and databases for the Helix Remote v2 server.

.DESCRIPTION
Run this yourself, once, in your own PowerShell window. It is safe to run
again: it creates what is missing and resets the helix role's password.

- psql asks for the PostgreSQL superuser password (the one chosen when
  PostgreSQL was installed).
- The script asks for a new password for the `helix` role.

Neither password is printed or written to disk. The only exception is
-SaveTestUrl, which stores HELIX_TEST_DATABASE_URL (containing the helix
password) as an environment variable of your Windows user, so the server
tests can connect.

Creates: role `helix` (LOGIN, no superuser), and databases `helix` (for the
server) and `helix_test` (for tests), both owned by `helix`.

.EXAMPLE
./setup_local_postgres.ps1 -SaveTestUrl
#>
param(
    [string]$PsqlPath = 'C:\Program Files\PostgreSQL\17\bin\psql.exe',
    [string]$SuperUser = 'postgres',
    [string]$HostName = '127.0.0.1',
    [int]$Port = 5432,
    [switch]$SaveTestUrl
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $PsqlPath)) {
    throw "psql was not found at '$PsqlPath'. Pass -PsqlPath with its location."
}

$secure = Read-Host -AsSecureString 'New password for the helix role'
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}
if ([string]::IsNullOrEmpty($plain)) {
    throw 'The helix password must not be empty.'
}

# SQL string literal: double any single quote. The script goes to psql on
# stdin, so the password never appears in a process command line.
$sqlPassword = $plain.Replace("'", "''")
$sql = @"
DO `$`$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'helix') THEN
    CREATE ROLE helix LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
  END IF;
END
`$`$;
ALTER ROLE helix WITH LOGIN PASSWORD '$sqlPassword';
SELECT 'CREATE DATABASE helix OWNER helix'
  WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'helix')\gexec
SELECT 'CREATE DATABASE helix_test OWNER helix'
  WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'helix_test')\gexec
"@

try {
    $sql | & $PsqlPath -h $HostName -p $Port -U $SuperUser -d postgres -v ON_ERROR_STOP=1 -q -f -
    if ($LASTEXITCODE -ne 0) {
        throw "psql failed with exit code $LASTEXITCODE."
    }
    Write-Host "Role 'helix' and databases 'helix' and 'helix_test' are ready."

    if ($SaveTestUrl) {
        $encoded = [Uri]::EscapeDataString($plain)
        $url = "postgresql://helix:$encoded@${HostName}:$Port/helix_test?sslmode=disable"
        [Environment]::SetEnvironmentVariable('HELIX_TEST_DATABASE_URL', $url, 'User')
        Write-Host 'Saved HELIX_TEST_DATABASE_URL for your Windows user. Open a new terminal (and restart your editor) to pick it up.'
    } else {
        Write-Host 'To run the server tests, set HELIX_TEST_DATABASE_URL to'
        Write-Host '  postgresql://helix:<password>@127.0.0.1:5432/helix_test?sslmode=disable'
        Write-Host '(percent-encode the password), or re-run this script with -SaveTestUrl.'
    }
} finally {
    Remove-Variable -Name plain, sqlPassword, sql -ErrorAction SilentlyContinue
    Remove-Variable -Name encoded, url -ErrorAction SilentlyContinue
}
