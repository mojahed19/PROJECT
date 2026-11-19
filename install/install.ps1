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
   -AppId       رقم التطبيق عند التنزيل (الافتراضي 100)
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
  [int]$AppId      = 100,
  [switch]$Reset,
  [switch]$SkipDb,
  [switch]$SkipApp
)

$ErrorActionPreference = 'Stop'

function Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

# ---------------------------------------------------------------- 1) التنزيل من GitHub
Step 'تنزيل / تحديث المشروع من GitHub'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git غير مثبت' }
if (Test-Path (Join-Path $Dir '.git')) {
  git -C $Dir pull --ff-only
} else {
  git clone $RepoUrl $Dir
}
if ($LASTEXITCODE -ne 0) { throw 'فشل التنزيل من GitHub' }

$sqlplus = Get-Command sqlplus -ErrorAction SilentlyContinue
if (-not $sqlplus) { throw 'sqlplus غير موجود في PATH' }

# السكربتات فيها نصوص عربية: يجب أن يعمل sqlplus بترميز UTF-8
$env:NLS_LANG = 'AMERICAN_AMERICA.AL32UTF8'
$OutputEncoding = [Text.Encoding]::UTF8

# كلمة المرور تُطلب مرة واحدة عند أول اتصال ولا تُحفظ
$script:pass = $null
function Get-Pass {
  if (-not $script:pass) {
    $sec = Read-Host "كلمة مرور $DbUser" -AsSecureString
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
  if ($code -ne 0) { throw "فشل تنفيذ $script (رمز الخطأ $code). راجع ملف السجل في مجلد install\logs" }
}

New-Item -ItemType Directory -Force (Join-Path $Dir 'install\logs') | Out-Null

# ---------------------------------------------------------------- 2) قاعدة البيانات
if (-not $SkipDb) {
  if ($Reset) {
    Step 'حذف جداول المشروع (Reset)'
    $ok = Read-Host 'سيتم حذف كل جداول المشروع وبياناتها في هذه الـ Schema. اكتب YES للمتابعة'
    if ($ok -ne 'YES') { throw 'أُلغي الحذف' }
    Run-Sql 'install\drop_all.sql' @()
  }
  Step 'تنفيذ سكربتات قاعدة البيانات'
  Run-Sql 'install\install_db.sql' @()
  Write-Host 'تم إنشاء الجداول والبيانات الأولية' -ForegroundColor Green
}

# ---------------------------------------------------------------- 3) تطبيق APEX
if (-not $SkipApp) {
  $app = Join-Path $Dir 'apex\app\f100.sql'
  if (-not (Test-Path $app)) {
    Write-Warning 'ملف التطبيق apex\app\f100.sql غير موجود بعد في المستودع، فتم تخطي تنزيل التطبيق.'
  } elseif (-not $Workspace) {
    Write-Warning 'لم يُحدد -Workspace، فتم تخطي تنزيل التطبيق.'
  } else {
    Step "تنزيل تطبيق APEX في Workspace $Workspace برقم $AppId"
    Run-Sql 'install\install_app.sql' @($Workspace, $AppId)
    Write-Host "تم تنزيل التطبيق. افتحه من: http://localhost/ords/r/$($Workspace.ToLower())/" -ForegroundColor Green
  }
}

$script:pass = $null
Step 'انتهى'
