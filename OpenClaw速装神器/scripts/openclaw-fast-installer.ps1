# OpenClaw速装神器
# 支持的操作系统：Windows11 / Windows10
# 作者：再凝秋水
# 基于OpenClaw官方安装脚本install.ps1开发
param(
    [string]$Tag = "latest",
    [ValidateSet("npm", "git")]
    [string]$InstallMethod = "npm",
    [string]$GitDir,
    [switch]$NoOnboard,
    [switch]$NoGitUpdate,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "--------------------------------"
Write-Host "OpenClaw速装神器"
Write-Host ""
Write-Host "作者：再凝秋水"
Write-Host ""
Write-Host "请在Windows11 / Windows10上运行"
Write-Host "--------------------------------"
Write-Host ""

# Check if running in PowerShell
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "Error: PowerShell 5+ required" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Windows detected" -ForegroundColor Green

if (-not $PSBoundParameters.ContainsKey("InstallMethod")) {
    if (-not [string]::IsNullOrWhiteSpace($env:OPENCLAW_INSTALL_METHOD)) {
        $InstallMethod = $env:OPENCLAW_INSTALL_METHOD
    }
}
if (-not $PSBoundParameters.ContainsKey("GitDir")) {
    if (-not [string]::IsNullOrWhiteSpace($env:OPENCLAW_GIT_DIR)) {
        $GitDir = $env:OPENCLAW_GIT_DIR
    }
}
if (-not $PSBoundParameters.ContainsKey("NoOnboard")) {
    if ($env:OPENCLAW_NO_ONBOARD -eq "1") {
        $NoOnboard = $true
    }
}
if (-not $PSBoundParameters.ContainsKey("NoGitUpdate")) {
    if ($env:OPENCLAW_GIT_UPDATE -eq "0") {
        $NoGitUpdate = $true
    }
}
if (-not $PSBoundParameters.ContainsKey("DryRun")) {
    if ($env:OPENCLAW_DRY_RUN -eq "1") {
        $DryRun = $true
    }
}

if ([string]::IsNullOrWhiteSpace($GitDir)) {
    $userHome = [Environment]::GetFolderPath("UserProfile")
    $GitDir = (Join-Path $userHome "openclaw")
}

# Check for Node.js
function Check-Node {
    try {
        $nodeVersion = (node -v 2>$null)
        if ($nodeVersion) {
            $version = [int]($nodeVersion-replace'v(\d+)\..*', '$1')
            if ($version -ge 22) {
                Write-Host "[OK] Node.js $nodeVersion found" -ForegroundColor Green
                return $true
            } else {
                Write-Host "[!] Node.js $nodeVersion found, but v22+ required" -ForegroundColor Yellow
                return $false
            }
        }
    } catch {
        Write-Host "[!] Node.js not found" -ForegroundColor Yellow
        return $false
    }
    return $false
}

# Install Node.js
function Install-Node {
    $ErrorActionPreference = "Continue"
    Write-Host "[*] Installing Node.js..." -ForegroundColor Yellow

    $nodeVersion = "22.14.0"
    $downloadUrl = "https://registry.npmmirror.com/-/binary/node/v$nodeVersion/node-v$nodeVersion-x64.msi"
    $installerPath = "$env:TEMP\node-v$nodeVersion-x64.msi"

    Write-Host "  从国内镜像下载 Node.js $nodeVersion..." -ForegroundColor Gray
    Write-Host "  安装包路径：$installerPath" -ForegroundColor Gray

    if (Test-Path $installerPath) {
        Remove-Item $installerPath -Force
        Write-Host "  已删除旧文件" -ForegroundColor Gray
    }

    Write-Host "  开始下载，时间：$(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray

    curl.exe -L --progress-bar --show-error --output "$installerPath" "$downloadUrl"
    $curlExit = $LASTEXITCODE

    Write-Host "  下载完成，时间：$(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
    Write-Host "  curl 退出码：$curlExit" -ForegroundColor Gray

    if ($curlExit -ne 0) {
        Write-Host "下载失败，curl 退出码：$curlExit" -ForegroundColor Red
        exit 1
    }

    Write-Host "  文件大小：$([math]::Round((Get-Item $installerPath).Length / 1MB, 1)) MB" -ForegroundColor Gray
    # 正确写法：通过 msiexec 调用，并加 ADDLOCAL=ALL 确保写入 PATH
    Write-Host "  安装中..." -ForegroundColor Gray
    $result = Start-Process -FilePath "msiexec.exe" `
    -Args "/i `"$installerPath`" /quiet /norestart ADDLOCAL=ALL" `
    -Wait -PassThru
    Write-Host "  安装程序退出码：$($result.ExitCode)" -ForegroundColor Gray

    # 用管理员权限持久写入系统 Path（而不只是改当前进程）
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $nodePath = "C:\Program Files\nodejs"

    if (-not ($machinePath -split ";" | Where-Object { $_ -ieq $nodePath })) {
        $newMachinePath = $machinePath.TrimEnd(";") + ";$nodePath"
        [Environment]::SetEnvironmentVariable("Path", $newMachinePath, "Machine")
        Write-Host "  已将 $nodePath 永久写入系统 Path" -ForegroundColor Gray
    }

    # 同步刷新当前进程
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")

        Write-Host "[OK] Node.js $nodeVersion installed" -ForegroundColor Green
    }

# Check for Git
function Check-Git {
    try {
        $null = Get-Command git -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# Install Git
function Install-Git {
    $ErrorActionPreference = "Continue"
    Write-Host "[*] Installing Git..." -ForegroundColor Yellow

    $downloadUrl = "https://registry.npmmirror.com/-/binary/git-for-windows/v2.53.0.windows.1/Git-2.53.0-64-bit.exe"
    $installerPath = "$env:TEMP\Git-2.53.0-64-bit.exe"

    Write-Host "  从国内镜像下载 Git 2.53.0..." -ForegroundColor Gray
    Write-Host "  安装包路径：$installerPath" -ForegroundColor Gray

    if (Test-Path $installerPath) {
        Remove-Item $installerPath -Force
        Write-Host "  已删除旧文件" -ForegroundColor Gray
    }

    Write-Host "  开始下载，时间：$(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray

    curl.exe -L --progress-bar --show-error --output "$installerPath" "$downloadUrl"
    $curlExit = $LASTEXITCODE

    Write-Host "  下载完成，时间：$(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
    Write-Host "  curl 退出码：$curlExit" -ForegroundColor Gray

    if ($curlExit -ne 0) {
        Write-Host "下载失败，curl 退出码：$curlExit" -ForegroundColor Red
        exit 1
    }

    Write-Host "  文件大小：$([math]::Round((Get-Item $installerPath).Length / 1MB, 1)) MB" -ForegroundColor Gray
    Write-Host "  安装中..." -ForegroundColor Gray

    $result = Start-Process -FilePath $installerPath -Args "/VERYSILENT /NORESTART /SUPPRESSMSGBOXES" -Wait -PassThru
    Write-Host "  安装程序退出码：$($result.ExitCode)" -ForegroundColor Gray

    # 主动检查并写入系统 Path
    $gitPath = "C:\Program Files\Git\cmd"
    if (Test-Path $gitPath) {
        $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        if (-not ($machinePath -split ";" | Where-Object { $_ -ieq $gitPath })) {
            $newMachinePath = $machinePath.TrimEnd(";") + ";$gitPath"
            [Environment]::SetEnvironmentVariable("Path", $newMachinePath, "Machine")
            Write-Host "  已将 $gitPath 永久写入系统 Path" -ForegroundColor Gray
        }
    }

    # 刷新当前进程 Path
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")

    Write-Host "[OK] Git 2.53.0 installed" -ForegroundColor Green
}

function Require-Git {
    if (Check-Git) { return }
    Write-Host ""
    Write-Host "Error: Git is required to install OpenClaw." -ForegroundColor Red
    Write-Host "Install Git for Windows:" -ForegroundColor Yellow
    Write-Host "  https://git-scm.com/download/win" -ForegroundColor Cyan
    Write-Host "Then re-run this installer." -ForegroundColor Yellow
    exit 1
}

# Check for existing OpenClaw installation
function Check-ExistingOpenClaw {
    if (Get-OpenClawCommandPath) {
        Write-Host "[*] Existing OpenClaw installation detected" -ForegroundColor Yellow
        return $true
    }
    return $false
}

function Get-OpenClawCommandPath {
    $openclawCmd = Get-Command openclaw.cmd -ErrorAction SilentlyContinue
    if ($openclawCmd -and $openclawCmd.Source) {
        return $openclawCmd.Source
    }

    $openclaw = Get-Command openclaw -ErrorAction SilentlyContinue
    if ($openclaw -and $openclaw.Source) {
        return $openclaw.Source
    }

    return $null
}

function Invoke-OpenClawCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $commandPath = Get-OpenClawCommandPath
    if (-not $commandPath) {
        throw "openclaw command not found on PATH."
    }

    & $commandPath @Arguments
}

function Get-NpmGlobalBinCandidates {
    param(
        [string]$NpmPrefix
    )

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($NpmPrefix)) {
        $candidates += $NpmPrefix
        $candidates += (Join-Path $NpmPrefix "bin")
    }
    if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $candidates += (Join-Path $env:APPDATA "npm")
    }

    return $candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
}

function Ensure-OpenClawOnPath {
    if (Get-OpenClawCommandPath) {
        return $true
    }

    $npmPrefix = $null
    try {
        $npmPrefix = (npm config get prefix 2>$null).Trim()
    } catch {
        $npmPrefix = $null
    }

    $npmBins = Get-NpmGlobalBinCandidates -NpmPrefix $npmPrefix
    foreach ($npmBin in $npmBins) {
        if (-not (Test-Path (Join-Path $npmBin "openclaw.cmd"))) {
            continue
        }

        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if (-not ($userPath -split ";" | Where-Object { $_ -ieq $npmBin })) {
            [Environment]::SetEnvironmentVariable("Path", "$userPath;$npmBin", "User")
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            Write-Host "[!] Added $npmBin to user PATH (restart terminal if command not found)" -ForegroundColor Yellow
        }
        return $true
    }

    Write-Host "[!] openclaw is not on PATH yet." -ForegroundColor Yellow
    Write-Host "Restart PowerShell or add the npm global install folder to PATH." -ForegroundColor Yellow
    if ($npmBins.Count -gt 0) {
        Write-Host "Expected path (one of):" -ForegroundColor Gray
        foreach ($npmBin in $npmBins) {
            Write-Host "  $npmBin" -ForegroundColor Cyan
        }
    } else {
        Write-Host "Hint: run `"npm config get prefix`" to find your npm global path." -ForegroundColor Gray
    }
    return $false
}

function Ensure-Pnpm {
    if (Get-Command pnpm -ErrorAction SilentlyContinue) {
        return
    }
    if (Get-Command corepack -ErrorAction SilentlyContinue) {
        try {
            corepack enable | Out-Null
            corepack prepare pnpm@latest --activate | Out-Null
            if (Get-Command pnpm -ErrorAction SilentlyContinue) {
                Write-Host "[OK] pnpm installed via corepack" -ForegroundColor Green
                return
            }
        } catch {
            # fallthrough to npm install
        }
    }
    Write-Host "[*] Installing pnpm..." -ForegroundColor Yellow
    $prevScriptShell = $env:NPM_CONFIG_SCRIPT_SHELL
    $env:NPM_CONFIG_SCRIPT_SHELL = "cmd.exe"
    try {
        npm install -g pnpm
    } finally {
        $env:NPM_CONFIG_SCRIPT_SHELL = $prevScriptShell
    }
    Write-Host "[OK] pnpm installed" -ForegroundColor Green
}

# Install OpenClaw via npm
function Install-OpenClaw {
    if ([string]::IsNullOrWhiteSpace($Tag)) {
        $Tag = "latest"
    }
    Require-Git

    $packageName = "openclaw"
    if ($Tag -eq "beta" -or $Tag -match "^beta\.") {
        $packageName = "openclaw"
    }
    Write-Host "[*] Installing OpenClaw ($packageName@$Tag)..." -ForegroundColor Yellow

    $prevLogLevel        = $env:NPM_CONFIG_LOGLEVEL
    $prevUpdateNotifier  = $env:NPM_CONFIG_UPDATE_NOTIFIER
    $prevFund            = $env:NPM_CONFIG_FUND
    $prevAudit           = $env:NPM_CONFIG_AUDIT
    $prevScriptShell     = $env:NPM_CONFIG_SCRIPT_SHELL

    $env:NPM_CONFIG_UPDATE_NOTIFIER = "false"
    $env:NPM_CONFIG_FUND            = "false"
    $env:NPM_CONFIG_AUDIT           = "false"
    $env:NPM_CONFIG_SCRIPT_SHELL    = "cmd.exe"

    try {
        npm install -g "$packageName@$Tag" --verbose
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[!] npm install failed (exit code $LASTEXITCODE)" -ForegroundColor Red
            exit 1
        }
    } finally {
        $env:NPM_CONFIG_LOGLEVEL        = $prevLogLevel
        $env:NPM_CONFIG_UPDATE_NOTIFIER = $prevUpdateNotifier
        $env:NPM_CONFIG_FUND            = $prevFund
        $env:NPM_CONFIG_AUDIT           = $prevAudit
        $env:NPM_CONFIG_SCRIPT_SHELL    = $prevScriptShell
    }

    Write-Host "[OK] OpenClaw installed" -ForegroundColor Green
}

# Install OpenClaw from GitHub
function Install-OpenClawFromGit {
    param(
        [string]$RepoDir,
        [switch]$SkipUpdate
    )
    Require-Git
    Ensure-Pnpm

    $repoUrl = "https://github.com/openclaw/openclaw.git"
    Write-Host "[*] Installing OpenClaw from GitHub ($repoUrl)..." -ForegroundColor Yellow

    if (-not (Test-Path $RepoDir)) {
        git clone $repoUrl $RepoDir
    }

    if (-not $SkipUpdate) {
        if (-not (git -C $RepoDir status --porcelain 2>$null)) {
            git -C $RepoDir pull --rebase 2>$null
        } else {
            Write-Host "[!] Repo is dirty; skipping git pull" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[!] Git update disabled; skipping git pull" -ForegroundColor Yellow
    }

    Remove-LegacySubmodule -RepoDir $RepoDir

    $prevPnpmScriptShell = $env:NPM_CONFIG_SCRIPT_SHELL
    $env:NPM_CONFIG_SCRIPT_SHELL = "cmd.exe"
    try {
        pnpm -C $RepoDir install
        if (-not (pnpm -C $RepoDir ui:build)) {
            Write-Host "[!] UI build failed; continuing (CLI may still work)" -ForegroundColor Yellow
        }
        pnpm -C $RepoDir build
    } finally {
        $env:NPM_CONFIG_SCRIPT_SHELL = $prevPnpmScriptShell
    }

    $binDir = Join-Path $env:USERPROFILE ".local\bin"
    if (-not (Test-Path $binDir)) {
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    }
    $cmdPath = Join-Path $binDir "openclaw.cmd"
    $cmdContents = "@echo off`r`nnode `"$RepoDir\dist\entry.js`" %*`r`n"
    Set-Content -Path $cmdPath -Value $cmdContents -NoNewline

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not ($userPath -split ";" | Where-Object { $_ -ieq $binDir })) {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$binDir", "User")
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "[!] Added $binDir to user PATH (restart terminal if command not found)" -ForegroundColor Yellow
    }

    Write-Host "[OK] OpenClaw wrapper installed to $cmdPath" -ForegroundColor Green
    Write-Host "[i] This checkout uses pnpm. For deps, run: pnpm install (avoid npm install in the repo)." -ForegroundColor Gray
}

# Run doctor for migrations (safe, non-interactive)
function Run-Doctor {
    Write-Host "[*] Running doctor to migrate settings..." -ForegroundColor Yellow
    try {
        Invoke-OpenClawCommand doctor --non-interactive
    } catch {
        # Ignore errors from doctor
    }
    Write-Host "[OK] Migration complete" -ForegroundColor Green
}

function Test-GatewayServiceLoaded {
    try {
        $statusJson = (Invoke-OpenClawCommand daemon status --json 2>$null)
        if ([string]::IsNullOrWhiteSpace($statusJson)) {
            return $false
        }
        $parsed = $statusJson | ConvertFrom-Json
        if ($parsed -and $parsed.service -and $parsed.service.loaded) {
            return $true
        }
    } catch {
        return $false
    }
    return $false
}

function Refresh-GatewayServiceIfLoaded {
    if (-not (Get-OpenClawCommandPath)) {
        return
    }
    if (-not (Test-GatewayServiceLoaded)) {
        return
    }

    Write-Host "[*] Refreshing loaded gateway service..." -ForegroundColor Yellow
    try {
        Invoke-OpenClawCommand gateway install --force | Out-Null
    } catch {
        Write-Host "[!] Gateway service refresh failed; continuing." -ForegroundColor Yellow
        return
    }

    try {
        Invoke-OpenClawCommand gateway restart | Out-Null
        Invoke-OpenClawCommand gateway status --probe --json | Out-Null
        Write-Host "[OK] Gateway service refreshed" -ForegroundColor Green
    } catch {
        Write-Host "[!] Gateway service restart failed; continuing." -ForegroundColor Yellow
    }
}

function Get-LegacyRepoDir {
    if (-not [string]::IsNullOrWhiteSpace($env:OPENCLAW_GIT_DIR)) {
        return $env:OPENCLAW_GIT_DIR
    }
    $userHome = [Environment]::GetFolderPath("UserProfile")
    return (Join-Path $userHome "openclaw")
}

function Remove-LegacySubmodule {
    param(
        [string]$RepoDir
    )
    if ([string]::IsNullOrWhiteSpace($RepoDir)) {
        $RepoDir = Get-LegacyRepoDir
    }
    $legacyDir = Join-Path $RepoDir "Peekaboo"
    if (Test-Path $legacyDir) {
        Write-Host "[!] Removing legacy submodule checkout: $legacyDir" -ForegroundColor Yellow
        Remove-Item -Recurse -Force $legacyDir
    }
}

# Main installation flow
function Main {
    if ($InstallMethod -ne "npm" -and $InstallMethod -ne "git") {
        Write-Host "Error: invalid -InstallMethod (use npm or git)." -ForegroundColor Red
        exit 2
    }

    if ($DryRun) {
        Write-Host "[OK] Dry run" -ForegroundColor Green
        Write-Host "[OK] Install method: $InstallMethod" -ForegroundColor Green
        if ($InstallMethod -eq "git") {
            Write-Host "[OK] Git dir: $GitDir" -ForegroundColor Green
            if ($NoGitUpdate) {
                Write-Host "[OK] Git update: disabled" -ForegroundColor Green
            } else {
                Write-Host "[OK] Git update: enabled" -ForegroundColor Green
            }
        }
        if ($NoOnboard) {
            Write-Host "[OK] Onboard: skipped" -ForegroundColor Green
        }
        return
    }

    Remove-LegacySubmodule -RepoDir $GitDir

    # Check for existing installation
    $isUpgrade = Check-ExistingOpenClaw

    # Step 1: Node.js
    if (-not (Check-Node)) {
        Install-Node

        # Verify installation
        if (-not (Check-Node)) {
            Write-Host ""
            Write-Host "Error: Node.js installation may require a terminal restart" -ForegroundColor Red
            Write-Host "Please close this terminal, open a new one, and run this installer again." -ForegroundColor Yellow
            exit 1
        }
    }

    # Step 2: Git
    if (-not (Check-Git)) {
        Install-Git

        # Verify installation
        if (-not (Check-Git)) {
            Write-Host ""
            Write-Host "Error: Git installation may require a terminal restart" -ForegroundColor Red
            Write-Host "Please close this terminal, open a new one, and run this installer again." -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Host "[OK] Git found" -ForegroundColor Green
    }

    # Step 3: git url rewrite
    Write-Host "[*] Setting git url rewrite: ssh://git@github.com/ -> https://github.com/..." -ForegroundColor Yellow
	# ssh -> https（避免没有SSH key时被GitHub拒绝）
	git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
	# libsignal-node 专项重定向到 Gitee 镜像（）
	# git config --global url."https://gitee.com/zainingqiushui/libsignal-node.git".insteadOf "https://github.com/whiskeysockets/libsignal-node.git"

    Write-Host "[OK] git url rewrite set" -ForegroundColor Green

    # Step 4: npm 镜像
    Write-Host "[*] Setting npm registry to npmmirror..." -ForegroundColor Yellow
    npm config set registry https://registry.npmmirror.com
    Write-Host "[OK] npm registry -> https://registry.npmmirror.com" -ForegroundColor Green

    $finalGitDir = $null

    # Step 5: OpenClaw
    if ($InstallMethod -eq "git") {
        $finalGitDir = $GitDir
        Install-OpenClawFromGit -RepoDir $GitDir -SkipUpdate:$NoGitUpdate
    } else {
        Install-OpenClaw
    }

    if (-not (Ensure-OpenClawOnPath)) {
        Write-Host "Install completed, but OpenClaw is not on PATH yet." -ForegroundColor Yellow
        Write-Host "Open a new terminal, then run: openclaw doctor" -ForegroundColor Cyan
        return
    }

    Refresh-GatewayServiceIfLoaded

    # Step 6: Run doctor for migrations if upgrading or git install
    if ($isUpgrade -or $InstallMethod -eq "git") {
        Run-Doctor
    }

    $installedVersion = $null
    try {
        $installedVersion = (Invoke-OpenClawCommand --version 2>$null).Trim()
    } catch {
        $installedVersion = $null
    }
    if (-not $installedVersion) {
        try {
            $npmList = npm list -g --depth 0 --json 2>$null | ConvertFrom-Json
            if ($npmList -and $npmList.dependencies -and $npmList.dependencies.openclaw -and $npmList.dependencies.openclaw.version) {
                $installedVersion = $npmList.dependencies.openclaw.version
            }
        } catch {
            $installedVersion = $null
        }
    }

    Write-Host ""
    if ($installedVersion) {
        Write-Host "OpenClaw installed successfully ($installedVersion)!" -ForegroundColor Green
    } else {
        Write-Host "OpenClaw installed successfully!" -ForegroundColor Green
    }
    Write-Host ""
    if ($isUpgrade) {
        $updateMessages = @(
            "Leveled up! New skills unlocked. You're welcome.",
            "Fresh code, same lobster. Miss me?",
            "Back and better. Did you even notice I was gone?",
            "Update complete. I learned some new tricks while I was out.",
            "Upgraded! Now with 23% more sass.",
            "I've evolved. Try to keep up.",
            "New version, who dis? Oh right, still me but shinier.",
            "Patched, polished, and ready to pinch. Let's go.",
            "The lobster has molted. Harder shell, sharper claws.",
            "Update done! Check the changelog or just trust me, it's good.",
            "Reborn from the boiling waters of npm. Stronger now.",
            "I went away and came back smarter. You should try it sometime.",
            "Update complete. The bugs feared me, so they left.",
            "New version installed. Old version sends its regards.",
            "Firmware fresh. Brain wrinkles: increased.",
            "I've seen things you wouldn't believe. Anyway, I'm updated.",
            "Back online. The changelog is long but our friendship is longer.",
            "Upgraded! Peter fixed stuff. Blame him if it breaks.",
            "Molting complete. Please don't look at my soft shell phase.",
            "Version bump! Same chaos energy, fewer crashes (probably)."
        )
        Write-Host (Get-Random -InputObject $updateMessages) -ForegroundColor Gray
        Write-Host ""
    } else {
        $completionMessages = @(
            "Ahh nice, I like it here. Got any snacks? ",
            "Home sweet home. Don't worry, I won't rearrange the furniture.",
            "I'm in. Let's cause some responsible chaos.",
            "Installation complete. Your productivity is about to get weird.",
            "Settled in. Time to automate your life whether you're ready or not.",
            "Cozy. I've already read your calendar. We need to talk.",
            "Finally unpacked. Now point me at your problems.",
            "cracks claws Alright, what are we building?",
            "The lobster has landed. Your terminal will never be the same.",
            "All done! I promise to only judge your code a little bit."
        )
        Write-Host (Get-Random -InputObject $completionMessages) -ForegroundColor Gray
        Write-Host ""
    }

    if ($InstallMethod -eq "git") {
        Write-Host "Source checkout: $finalGitDir" -ForegroundColor Cyan
        Write-Host "Wrapper: $env:USERPROFILE\.local\bin\openclaw.cmd" -ForegroundColor Cyan
        Write-Host ""
    }

    if ($isUpgrade) {
        Write-Host "Upgrade complete. Run " -NoNewline
        Write-Host "openclaw doctor" -ForegroundColor Cyan -NoNewline
        Write-Host " to check for additional migrations."
    } else {
        if ($NoOnboard) {
            Write-Host "Skipping onboard (requested). Run " -NoNewline
            Write-Host "openclaw onboard" -ForegroundColor Cyan -NoNewline
            Write-Host " later."
        } else {
            Write-Host "Starting setup..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-OpenClawCommand onboard
        }
    }
}

Main