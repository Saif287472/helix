<#
.SYNOPSIS
Builds a Helix Global server release from a git tag, without touching the
running server.

.DESCRIPTION
Production runs compiled executables from the production folder, never the
development checkout (review H-02). This script:

1. checks the tag exists,
2. checks it out in a temporary short-path worktree (<WorkRoot>\helix-release-<tag>),
3. resolves dependencies there with the committed lockfile
   (flutter pub get --enforce-lockfile),
4. compiles bin\server.dart, bin\migrate.dart and bin\admin_tool.dart into
   <Dest>\releases\<tag>\helix-server.exe, helix-migrate.exe and
   helix-admin-tool.exe, with a VERSION file (tag, commit, build time),
5. removes the worktree.

It never stops, starts or migrates anything: deploy-helix.ps1 switches the
running server to a built release.

.EXAMPLE
git tag server-2026-10-14
.\release-helix.ps1 -Tag server-2026-10-14
#>
param(
    [Parameter(Mandatory = $true)][string]$Tag,
    [string]$Dest = 'J:\Projects\Servers\helix_server\helix',
    [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path,
    [string]$WorkRoot = 'J:\wt'
)

$ErrorActionPreference = 'Stop'

function Invoke-Native([string]$What, [scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$What failed (exit $LASTEXITCODE)" }
}

$commit = (git -C $Repo rev-parse --verify --quiet "refs/tags/$Tag^{commit}")
if (-not $commit) { throw "No tag $Tag in $Repo (create it with: git tag $Tag)" }

$out = Join-Path $Dest "releases\$Tag"
if (Test-Path -LiteralPath (Join-Path $out 'helix-server.exe')) {
    throw "$out already has a build. Delete it to build again."
}
$safe = $Tag -replace '[^A-Za-z0-9._-]', '_'
$tree = Join-Path $WorkRoot "helix-release-$safe"
if (Test-Path -LiteralPath $tree) { throw "$tree exists; remove it (git worktree remove) first." }

New-Item -ItemType Directory -Force -Path $WorkRoot, $out | Out-Null
Invoke-Native 'git worktree add' { git -C $Repo worktree add --detach $tree $Tag }
try {
    Push-Location (Join-Path $tree 'helix_remote')
    try {
        Invoke-Native 'flutter pub get' { flutter pub get --enforce-lockfile }
        foreach ($pair in @(
                @('server\bin\server.dart', 'helix-server.exe'),
                @('server\bin\migrate.dart', 'helix-migrate.exe'),
                @('server\bin\admin_tool.dart', 'helix-admin-tool.exe'))) {
            Write-Host "Compiling $($pair[0])"
            Invoke-Native "dart compile $($pair[0])" {
                dart compile exe $pair[0] -o (Join-Path $out $pair[1])
            }
        }
    } finally {
        Pop-Location
    }
    @(
        "tag=$Tag",
        "commit=$commit",
        "built=$(Get-Date -Format o)"
    ) | Set-Content -Path (Join-Path $out 'VERSION') -Encoding utf8
} finally {
    git -C $Repo worktree remove --force $tree
}

Write-Host ''
Write-Host "Built $Tag ($commit) into $out"
Write-Host "Next: .\deploy-helix.ps1 -Tag $Tag"
