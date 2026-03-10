# OpenClaw安装环境重置程序
# 支持的操作系统：Windows11
# 作者：再凝秋水
Write-Host "============================"
Write-Host "OpenClaw安装环境重置程序"
Write-Host ""
Write-Host "支持的操作系统：Windows11"
Write-Host ""
Write-Host "作者：再凝秋水"
Write-Host ""
Write-Host "版本：v1.0.0-20260310"
Write-Host "============================"
Write-Host ""
Write-Host "开始重置..."

# 检查管理员权限
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$admin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $admin) {
    Write-Host "请用管理员 PowerShell 运行"
    exit
}

# ============================================================
# 公共函数
# ============================================================

# 安全删除目录（已存在才删，并报告结果）
function Remove-DirIfExists {
    param ([string]$Path, [string]$Label = "")
    $name = if ($Label) { $Label } else { $Path }
    if (Test-Path $Path) {
        Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $Path) {
            Write-Host "  删除失败（可能有文件被占用）：$name" -ForegroundColor Yellow
        } else {
            Write-Host "  已删除：$name" -ForegroundColor Green
        }
    } else {
        Write-Host "  不存在，跳过：$name" -ForegroundColor Gray
    }
}

# 从注册表读取安装路径
function Get-InstallDirsFromRegistry {
    param ([string[]]$RegPaths, [string]$ValueName = "InstallPath")
    $dirs = @()
    foreach ($reg in $RegPaths) {
        if (Test-Path $reg) {
            $val = (Get-ItemProperty $reg -ErrorAction SilentlyContinue).$ValueName
            if ($val -and (Test-Path $val)) {
                $dirs += $val.TrimEnd('\')
            }
        }
    }
    return $dirs | Select-Object -Unique
}

# 从 where.exe 结果推算安装根目录
# $Depth：从 exe 所在目录向上走几层才是根目录
# Node: node.exe 在根目录，Depth=0（不需要向上）
# Git:  git.exe 在 cmd\ 或 bin\ 下，Depth=1（向上一层）
function Get-DirsFromWhere {
    param ([string]$Command, [int]$Depth = 0)
    $dirs = @()
    $locations = where.exe $Command 2>$null
    if ($locations) {
        foreach ($p in $locations) {
            $p = $p.Trim()
            if (-not $p) { continue }
            $dir = Split-Path $p -Parent
            for ($i = 0; $i -lt $Depth; $i++) {
                $dir = Split-Path $dir -Parent
            }
            if ($dir -and (Test-Path $dir)) {
                $dirs += $dir
            }
        }
    }
    return $dirs | Select-Object -Unique
}

# 合并多个来源的目录列表，去重
function Merge-Dirs {
    param ([string[][]]$Sources)
    $all = @()
    foreach ($s in $Sources) {
        $all += $s
    }
    return $all | Where-Object { $_ } | Select-Object -Unique
}

# 删除一组目录，并汇报
function Remove-DirList {
    param ([string[]]$Dirs, [string]$Label)
    if (-not $Dirs -or $Dirs.Count -eq 0) {
        Write-Host "  未找到 $Label 相关目录，跳过" -ForegroundColor Gray
        return
    }
    foreach ($dir in $Dirs) {
        Remove-DirIfExists -Path $dir
    }
}

# ============================================================
# Step 1：卸载 OpenClaw 网关服务
# ============================================================

Write-Host ""
Write-Host "1. 卸载 OpenClaw 网关服务"

$openclawCmd = where.exe openclaw 2>$null
if (-not $openclawCmd) {
    Write-Host "  openclaw 命令不在 PATH，跳过网关卸载" -ForegroundColor Gray
} else {
    $gatewayStatus = openclaw gateway status 2>$null
    if ($LASTEXITCODE -ne 0 -or $gatewayStatus -match "not installed|未安装|not found") {
        Write-Host "  网关服务未安装，跳过" -ForegroundColor Gray
    } else {
        Write-Host "  检测到网关服务，执行卸载..."
        try {
            openclaw gateway uninstall
            Write-Host "  网关服务已卸载" -ForegroundColor Green
        } catch {
            Write-Host "  网关服务卸载失败，继续..." -ForegroundColor Yellow
        }
    }
}

# ============================================================
# Step 2：检查并删除 OpenClaw 计划任务
# ============================================================

Write-Host ""
Write-Host "2. 检查并删除 OpenClaw 计划任务"

$taskOutput = schtasks /query /fo list 2>$null
$taskNames = @()

$taskOutput -split "`n" | ForEach-Object {
    if ($_ -match "^任务名称:\s*(.+)" -or $_ -match "^TaskName:\s*(.+)") {
        $name = $Matches[1].Trim()
        if ($name -imatch "openclaw") {
            $taskNames += $name
        }
    }
}

if ($taskNames.Count -eq 0) {
    Write-Host "  未发现 OpenClaw 相关计划任务，跳过" -ForegroundColor Gray
} else {
    foreach ($name in $taskNames) {
        Write-Host "  发现计划任务：$name"
        schtasks /delete /tn "$name" /f
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  已删除：$name" -ForegroundColor Green
        } else {
            Write-Host "  删除失败：$name（可能需要更高权限）" -ForegroundColor Yellow
        }
    }
}

# ============================================================
# Step 3：npm 卸载 openclaw
# ============================================================

Write-Host ""
Write-Host "3. npm 卸载 openclaw 包"

$npmCmd = where.exe npm 2>$null
if (-not $npmCmd) {
    Write-Host "  npm 不在 PATH，跳过 npm 卸载步骤" -ForegroundColor Gray
} else {
    $installed = npm list -g --depth 0 2>$null | Select-String "openclaw"
    if (-not $installed) {
        Write-Host "  openclaw 未在 npm 全局包中，跳过卸载" -ForegroundColor Gray
    } else {
        Write-Host "  检测到 openclaw 已安装：$installed"
        npm uninstall -g openclaw
        $remaining = npm list -g --depth 0 2>$null | Select-String "openclaw"
        if ($remaining) {
            Write-Host "  警告：openclaw 似乎仍存在于 npm 全局包" -ForegroundColor Yellow
        } else {
            Write-Host "  openclaw 已从 npm 全局包移除" -ForegroundColor Green
        }
    }

    Write-Host "  清理 npm 缓存..."
    npm cache clean --force
    Write-Host "  npm 缓存已清理" -ForegroundColor Green
}

# ============================================================
# Step 4：结束 Node 进程
# ============================================================

Write-Host ""
Write-Host "4. 结束 Node 进程"

$nodeProc = Get-Process node -ErrorAction SilentlyContinue
if (-not $nodeProc) {
    Write-Host "  无运行中的 Node 进程，跳过" -ForegroundColor Gray
} else {
    $nodeProc | Stop-Process -Force
    Write-Host "  Node 进程已结束" -ForegroundColor Green
}

# ============================================================
# Step 5：卸载 Node.js
# 顺序：包管理器正式卸载 → 注册表定位 → where.exe 定位 → 硬编码兜底
# ============================================================

Write-Host ""
Write-Host "5. 卸载 Node.js"

# 5-1 包管理器正式卸载
if (Get-Command winget -ErrorAction SilentlyContinue) {
    $wingetList = winget list 2>$null
    if ($wingetList -match "OpenJS\.NodeJS") {
        Write-Host "  [winget] 检测到 Node.js，执行卸载..."
        winget uninstall --id OpenJS.NodeJS --silent --accept-source-agreements 2>$null
        winget uninstall --id OpenJS.NodeJS.LTS --silent --accept-source-agreements 2>$null
        Write-Host "  [winget] 卸载完成" -ForegroundColor Green
    } else {
        Write-Host "  [winget] 未检测到 Node.js，跳过" -ForegroundColor Gray
    }
}

if (Get-Command choco -ErrorAction SilentlyContinue) {
    $chocoList = choco list 2>$null
    # nodejs 和 nodejs-lts 是两个不同的包名，分别检测分别卸载
    if ($chocoList | Select-String "^nodejs-lts") {
        Write-Host "  [choco] 检测到 nodejs-lts，执行卸载..."
        choco uninstall nodejs-lts -y
        Write-Host "  [choco] nodejs-lts 卸载完成" -ForegroundColor Green
    } else {
        Write-Host "  [choco] 未检测到 nodejs-lts，跳过" -ForegroundColor Gray
    }
    if ($chocoList | Select-String "^nodejs ") {
        Write-Host "  [choco] 检测到 nodejs，执行卸载..."
        choco uninstall nodejs -y
        Write-Host "  [choco] nodejs 卸载完成" -ForegroundColor Green
    } else {
        Write-Host "  [choco] 未检测到 nodejs，跳过" -ForegroundColor Gray
    }
}

if (Get-Command scoop -ErrorAction SilentlyContinue) {
    $scoopList = scoop list 2>$null | Select-String "nodejs"
    if ($scoopList) {
        Write-Host "  [scoop] 检测到 Node.js：$scoopList，执行卸载..."
        scoop uninstall nodejs nodejs-lts 2>$null
        Write-Host "  [scoop] 卸载完成" -ForegroundColor Green
    } else {
        Write-Host "  [scoop] 未检测到 Node.js，跳过" -ForegroundColor Gray
    }
}

# 5-2 注册表定位残留目录
Write-Host "  [注册表] 查找 Node.js 安装路径..."
$nodeRegDirs = Get-InstallDirsFromRegistry -RegPaths @(
    "HKLM:\SOFTWARE\Node.js",
    "HKLM:\SOFTWARE\WOW6432Node\Node.js",
    "HKCU:\SOFTWARE\Node.js"
)

# 5-3 where.exe 定位残留目录（node.exe 就在根目录，Depth=0）
Write-Host "  [where.exe] 查找 Node.js 残留..."
$nodeWhereDirs = Get-DirsFromWhere -Command "node" -Depth 0

# 5-4 硬编码兜底路径
$nodeFallbackDirs = @(
    "C:\Program Files\nodejs",
    "C:\Program Files (x86)\nodejs"
)

# 5-5 合并所有来源，统一删除
$allNodeDirs = Merge-Dirs -Sources @($nodeRegDirs, $nodeWhereDirs, $nodeFallbackDirs)
Remove-DirList -Dirs $allNodeDirs -Label "Node.js"

# 5-6 清理 nvm-windows
Write-Host "  [nvm] 查找 nvm-windows..."
$nvmDirs = @(
    "$env:APPDATA\nvm",
    "$env:LOCALAPPDATA\nvm"
)
foreach ($dir in $nvmDirs) {
    Remove-DirIfExists -Path $dir -Label "nvm-windows ($dir)"
}

# 5-7 清理 fnm
Write-Host "  [fnm] 查找 fnm..."
$fnmDirs = @(
    "$env:APPDATA\fnm",
    "$env:LOCALAPPDATA\fnm"
)
foreach ($dir in $fnmDirs) {
    Remove-DirIfExists -Path $dir -Label "fnm ($dir)"
}

# ============================================================
# Step 6：删除 npm / cache 目录
# ============================================================

Write-Host ""
Write-Host "6. 删除 npm / cache 目录"

$npmDirs = @(
    "$env:APPDATA\npm",
    "$env:APPDATA\npm-cache",
    "$env:LOCALAPPDATA\npm-cache",
    "$env:LOCALAPPDATA\node-gyp"
)

$npmDirFound = $false
foreach ($dir in $npmDirs) {
    if (Test-Path $dir) {
        $npmDirFound = $true
        Remove-DirIfExists -Path $dir
    }
}
if (-not $npmDirFound) {
    Write-Host "  未找到 npm 相关目录，跳过" -ForegroundColor Gray
}

# ============================================================
# Step 7：删除 pnpm / yarn 缓存
# ============================================================

Write-Host ""
Write-Host "7. 删除 pnpm / yarn 缓存"

$pkgDirs = @(
    "$env:LOCALAPPDATA\pnpm",
    "$env:LOCALAPPDATA\Yarn",
    "$env:USERPROFILE\.pnpm-store",
    "$env:USERPROFILE\.yarn"
)

$pkgFound = $false
foreach ($dir in $pkgDirs) {
    if (Test-Path $dir) {
        $pkgFound = $true
        Remove-DirIfExists -Path $dir
    }
}
if (-not $pkgFound) {
    Write-Host "  未找到 pnpm / yarn 缓存目录，跳过" -ForegroundColor Gray
}

# ============================================================
# Step 8：卸载 Git
# 顺序：包管理器正式卸载 → 注册表定位 → where.exe 定位 → 硬编码兜底
# ============================================================

Write-Host ""
Write-Host "8. 卸载 Git"

# 8-1 包管理器正式卸载
if (Get-Command winget -ErrorAction SilentlyContinue) {
    $wingetList = winget list 2>$null
    if ($wingetList -match "Git\.Git") {
        Write-Host "  [winget] 检测到 Git，执行卸载..."
        winget uninstall --id Git.Git --silent --accept-source-agreements 2>$null
        Write-Host "  [winget] 卸载完成" -ForegroundColor Green
    } else {
        Write-Host "  [winget] 未检测到 Git，跳过" -ForegroundColor Gray
    }
}

if (Get-Command choco -ErrorAction SilentlyContinue) {
	$chocoGit = choco list 2>$null | Select-String "^git"
	if ($chocoGit) {
		Write-Host "  [choco] 检测到 Git：$chocoGit，执行卸载..."
		# 分别检测再分别卸载，不多卸不存在的包
		if (choco list 2>$null | Select-String "^git\.install") {
			choco uninstall git.install -y --force
		}
		if (choco list 2>$null | Select-String "^git ") {
			choco uninstall git -y --force
		}
		Write-Host "  [choco] 卸载完成" -ForegroundColor Green
	} else {
        Write-Host "  [choco] 未检测到 Git，跳过" -ForegroundColor Gray
    }
}

if (Get-Command scoop -ErrorAction SilentlyContinue) {
    $scoopList = scoop list 2>$null | Select-String "^git "
    if ($scoopList) {
        Write-Host "  [scoop] 检测到 Git：$scoopList，执行卸载..."
        scoop uninstall git 2>$null
        Write-Host "  [scoop] 卸载完成" -ForegroundColor Green
    } else {
        Write-Host "  [scoop] 未检测到 Git，跳过" -ForegroundColor Gray
    }
}

# 8-2 注册表定位残留目录
Write-Host "  [注册表] 查找 Git 安装路径..."
$gitRegDirs = Get-InstallDirsFromRegistry -RegPaths @(
    "HKLM:\SOFTWARE\GitForWindows",
    "HKLM:\SOFTWARE\WOW6432Node\GitForWindows",
    "HKCU:\SOFTWARE\GitForWindows"
)

# 8-3 where.exe 定位残留目录
# git.exe 在 Git\cmd\ 或 Git\bin\ 下，向上一层才是根目录，Depth=1
Write-Host "  [where.exe] 查找 Git 残留..."
$gitWhereDirs = Get-DirsFromWhere -Command "git" -Depth 1

# 8-4 硬编码兜底路径
$gitFallbackDirs = @(
    "C:\Program Files\Git",
    "C:\Program Files (x86)\Git"
)

# 8-5 合并所有来源，统一删除
$allGitDirs = Merge-Dirs -Sources @($gitRegDirs, $gitWhereDirs, $gitFallbackDirs)
Remove-DirList -Dirs $allGitDirs -Label "Git"

# ============================================================
# Step 8.5：清理 Chocolatey 缓存
# ============================================================

Write-Host ""
Write-Host "8.5. 清理 Chocolatey 缓存"

if (Get-Command choco -ErrorAction SilentlyContinue) {
    choco cache remove --confirm
    Write-Host "  Chocolatey 缓存已清理" -ForegroundColor Green
} else {
    Write-Host "  choco 不在 PATH，跳过" -ForegroundColor Gray
}

# ============================================================
# Step 9：删除 Git 用户配置
# ============================================================

Write-Host ""
Write-Host "9. 删除 Git 用户配置"

$gitFiles = @(
    "$env:USERPROFILE\.gitconfig",
    "$env:USERPROFILE\.git-credentials"
)

$gitFileFound = $false
foreach ($file in $gitFiles) {
    if (Test-Path $file) {
        $gitFileFound = $true
        Remove-Item $file -Force
        Write-Host "  已删除：$file" -ForegroundColor Green
    }
}
if (-not $gitFileFound) {
    Write-Host "  未找到 Git 配置文件，跳过" -ForegroundColor Gray
}

# ============================================================
# Step 10：删除 SSH key
# ============================================================

Write-Host ""
Write-Host "10. 删除 SSH key"

Remove-DirIfExists -Path "$env:USERPROFILE\.ssh" -Label ".ssh"

# ============================================================
# Step 11：删除 OpenClaw 日志目录
# ============================================================

Write-Host ""
Write-Host "11. 删除 OpenClaw 日志目录"

Remove-DirIfExists -Path "$env:LOCALAPPDATA\Temp\openclaw" -Label "openclaw 日志"

# ============================================================
# Step 12：删除 OpenClaw 配置目录
# ============================================================

Write-Host ""
Write-Host "12. 删除 OpenClaw 配置目录"

Remove-DirIfExists -Path "$env:USERPROFILE\.openclaw" -Label "openclaw 配置"

# ============================================================
# Step 13：清理 PATH
# ============================================================

Write-Host ""
Write-Host "13. 清理 PATH 中 node / npm / git / nvm / fnm 相关路径"

$filterKeywords = @(
    "nodejs",
    "\\Git\\",
    "\\Git$",
    "AppData\\Roaming\\npm",
    "AppData\\Local\\npm",
    "AppData\\Local\\pnpm",
    "AppData\\Local\\Yarn",
    "\.pnpm",
    "\.yarn",
    "\\nvm\\",
    "\\fnm\\"
)

function Remove-PathEntries {
    param ([string]$Scope)

    $raw = [Environment]::GetEnvironmentVariable("PATH", $Scope)
    if (-not $raw) { return }

    $entries = $raw -split ";" | Where-Object { $_ -ne "" }
    $filtered = $entries | Where-Object {
        $entry = $_
        $keep = $true
        foreach ($kw in $filterKeywords) {
            if ($entry -match $kw) {
                $keep = $false
                Write-Host "  移除 [$Scope] $entry" -ForegroundColor Yellow
                break
            }
        }
        $keep
    } | Select-Object -Unique

    if ($filtered.Count -lt $entries.Count) {
        [Environment]::SetEnvironmentVariable("PATH", ($filtered -join ";"), $Scope)
        Write-Host "  [$Scope] PATH 已更新" -ForegroundColor Green
    } else {
        Write-Host "  [$Scope] PATH 无需清理" -ForegroundColor Gray
    }
}

Remove-PathEntries -Scope "Machine"
Remove-PathEntries -Scope "User"

# ============================================================
# Step 14：刷新当前进程 PATH
# ============================================================

Write-Host ""
Write-Host "14. 刷新当前进程 PATH"

$env:PATH = [Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
            [Environment]::GetEnvironmentVariable("PATH", "User")

Write-Host "  PATH 已刷新" -ForegroundColor Green

# ============================================================
# Step 15：最终验证
# ============================================================

Write-Host ""
Write-Host "15. 最终验证"

$allClean = $true

foreach ($cmd in @("node", "npm", "git", "openclaw")) {
    $loc = where.exe $cmd 2>$null
    if ($loc) {
        Write-Host "  警告：$cmd 仍可访问，位于 $loc" -ForegroundColor Yellow
        $allClean = $false
    } else {
        Write-Host "  $cmd 已清理" -ForegroundColor Green
    }
}

Write-Host ""
if ($allClean) {
    Write-Host "==== 全部清理完成，环境已归零 ====" -ForegroundColor Green
} else {
    Write-Host "==== 清理完成，但有部分警告，请检查上方输出 ====" -ForegroundColor Yellow
}

Write-Host "如果要确认是否清除干净，或安装OpenClaw，请先关闭此窗口，再用管理员身份重新打开 PowerShell" -ForegroundColor Cyan