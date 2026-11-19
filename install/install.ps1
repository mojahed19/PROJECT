<#
=====================================================================
 install.ps1 - تنزيل المشروع من GitHub ثم تنفيذه على قاعدة البيانات وتنزيل تطبيق APEX

 مثال (أول تركيب):
   powershell -ExecutionPolicy Bypass -File install.ps1 -DbUser GRP_TEST -Workspace GRP

 الخيارات:
   -RepoUrl     رابط المستودع (الافتراضي mojahed19/PROJECT)
   -Dir         مجلد التنزيل (الافتراضي %USERPROFILE%\PROJECT)
   -DbUser      الـ Schema التي تُنشأ فيها الجداول (مطلوب)
   -Database    قاعدة البيانات (الافتراضي localhost:1521/orclpdb)
   -Workspace   اسم Workspace في APEX المرتبط بالـ Schema (لتنزيل التطبيق)
   -AppId       رقم التطبيق عند التنزيل (الافتراضي 115)
   -Reset       حذف جداول المشروع وإعادة إنشائها (يمسح البيانات!)
   -SkipDb      تخطي تنفيذ سكربتات قاعدة البيانات
   -SkipApp     تخطي تنزيل التطبيق

 كلمة المرور تُطلب عند التشغيل ولا تُحفظ في أي ملف، ولا تظهر في سطر الأوامر.
=====================================================================
#>
param(
  [string]$RepoUrl = 'https://github.com/mojahed19/PROJECT.git',
  [string]$Dir     = (Join-Path $env:USERPROFILE 'PROJECT'),
  [Parameter(Mandatory = $true)][string]$DbUser,
  [string]$Database = 'localhost:1521/orclpdb',
  [string]$Workspace,
  [int]$AppId      = 115,
  [switch]$Reset,
  [switch]$SkipDb,
  [switch]$SkipApp
)

$ErrorActionPreference = 'Stop'

function Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

# ---------------------------------------------------------------- 1) التنزيل من GitHub
Step 'Download / update project from GitHub'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is not installed' }
if (Test-Path (Join-Path $Dir '.git')) {
  git -C $Dir pull --ff-only
} else {
  git clone $RepoUrl $Dir
}
if ($LASTEXITCODE -ne 0) { throw 'Download from GitHub failed' }

$sqlplus = Get-Command sqlplus -ErrorAction SilentlyContinue
if (-not $sqlplus) { throw 'sqlplus not found in PATH' }

# السكربتات فيها نصوص عربية: يجب أن يعمل sqlplus بترميز UTF-8
$env:NLS_LANG = 'AMERICAN_AMERICA.AL32UTF8'
$OutputEncoding = [Text.Encoding]::UTF8

# كلمة المرور تُطلب مرة واحدة عند أول اتصال ولا تُحفظ
$script:pass = $null
function Get-Pass {
  if (-not $script:pass) {
    $sec = Read-Host "Password for $DbUser" -AsSecureString
    $script:pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                     [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
  }
  return $script:pass
}

function Run-Sql([string]$script, [string[]]$scriptArgs) {
  # الاتصال يُمرَّر عبر stdin حتى لا تظهر كلمة المرور في قائمة العمليات
  $stdin = @"
WHENEVER SQLERROR EXIT SQL.SQLCODE
WHENEVER OSERROR EXIT FAILURE
CONNECT $DbUser/"$(Get-Pass)"@$Database
@"$script" $($scriptArgs -join ' ')
EXIT
"@
  Push-Location $Dir
  try {
    $stdin | & sqlplus -L -S /nolog
    $code = $LASTEXITCODE
  } finally { Pop-Location }
  if ($code -ne 0) { throw "$script failed (code $code). See the log in install\logs" }
}

New-Item -ItemType Directory -Force (Join-Path $Dir 'install\logs') | Out-Null

# ---------------------------------------------------------------- 2) قاعدة البيانات
if (-not $SkipDb) {
  if ($Reset) {
    Step 'Drop project tables (Reset)'
    $ok = Read-Host 'All project tables and data in this schema will be deleted. Type YES to continue'
    if ($ok -ne 'YES') { throw 'Reset cancelled' }
    Run-Sql 'install\drop_all.sql' @()
  }
  Step 'Running database scripts'
  Run-Sql 'install\install_db.sql' @()
  Write-Host 'Tables and seed data created' -ForegroundColor Green
}

# ---------------------------------------------------------------- 3) تطبيق APEX
if (-not $SkipApp) {
  $app = Join-Path $Dir 'apex\app\f100.sql'
  if (-not (Test-Path $app)) {
    Write-Warning 'apex\app\f100.sql is not in the repository yet - app install skipped.'
  } elseif (-not $Workspace) {
    Write-Warning 'No -Workspace given - app install skipped.'
  } else {
    Step "Installing APEX app $AppId into workspace $Workspace"
    Run-Sql 'install\install_app.sql' @($Workspace, $AppId)
    Write-Host "App installed. Open: http://localhost/ords/r/$($Workspace.ToLower())/" -ForegroundColor Green
  }
}

$script:pass = $null
Step 'Finished'
