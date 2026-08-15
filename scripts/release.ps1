param(
    [switch]$Push
)

$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repositoryRoot

if ((git branch --show-current) -ne "main") {
    throw "Releases must be created from the main branch."
}

$status = git status --porcelain
if ($status) {
    throw "The working tree is not clean. Commit and push all release changes first."
}

git fetch --quiet origin main --tags
if ((git rev-parse HEAD) -ne (git rev-parse origin/main)) {
    throw "Local main and origin/main differ. Pull or push the release commit first."
}

$versionLine = Get-Content -LiteralPath "GuildCotiz.toc" |
    Where-Object { $_ -match '^## Version:\s*(.+)$' } |
    Select-Object -First 1

if (-not $versionLine -or $versionLine -notmatch '^## Version:\s*(.+)$') {
    throw "GuildCotiz.toc does not contain a version."
}

$version = $Matches[1].Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Version '$version' is not a final semantic version (X.Y.Z)."
}

$changelog = Get-Content -LiteralPath "CHANGELOG.md" -Raw
if ($changelog -notmatch ('(?m)^##\s+' + [regex]::Escape($version) + '\s+-\s+\d{4}-\d{2}-\d{2}\s*$')) {
    throw "CHANGELOG.md has no dated section for version $version."
}

$tag = "v$version"
if (git tag --list $tag) {
    throw "Tag $tag already exists locally."
}
if (git ls-remote --exit-code --tags origin "refs/tags/$tag" 2>$null) {
    throw "Tag $tag already exists on origin."
}

$testFiles = @(
    "tests/roster_test.lua",
    "tests/sync_test.lua",
    "tests/contribution_test.lua",
    "tests/grm_test.lua",
    "tests/layout_test.lua"
)
$lua = Get-Command lua -ErrorAction SilentlyContinue
if ($lua) {
    foreach ($testFile in $testFiles) {
        & $lua.Source $testFile
        if ($LASTEXITCODE -ne 0) { throw "Test failed: $testFile" }
    }
} else {
    Write-Warning "Lua was not found; automated Lua tests were not run."
}

git diff --check
if ($LASTEXITCODE -ne 0) { throw "git diff --check failed." }

Write-Host "Release preflight passed for GuildCotiz $version ($tag)."

if (-not $Push) {
    Write-Host "Dry run only. Run scripts/release.ps1 -Push to publish."
    exit 0
}

git tag -a $tag -m "GuildCotiz $version"
git push origin $tag
if ($LASTEXITCODE -ne 0) { throw "Failed to push $tag." }

Write-Host "Published $tag. GitHub Actions will package GitHub and CurseForge releases."
