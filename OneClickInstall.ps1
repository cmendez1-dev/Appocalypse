#Requires -Version 5.1
<#
.SYNOPSIS
    OneClickInstall - Bulk Software Installer with GUI
.DESCRIPTION
    A PowerShell tool with a Windows Forms GUI that allows you to select
    and install multiple software packages at once using winget.
.NOTES
    Author: OneClickInstall
    Version: 1.0.0
    Requires: Windows 10/11 with winget installed
#>

# ============================================
# CONFIGURATION
# ============================================
$Script:Version = "1.0.0"
$Script:AppName = "OneClickInstall"
$Script:LogFile = Join-Path $PSScriptRoot "install_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$Script:PackagesFile = Join-Path $PSScriptRoot "config\packages.json"

# ============================================
# HELPER FUNCTIONS
# ============================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $Script:LogFile -Value $logEntry
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARN"  { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        default { Write-Host $logEntry -ForegroundColor Cyan }
    }
}

function Test-WingetInstalled {
    try {
        $wingetVersion = winget --version 2>$null
        if ($wingetVersion) {
            Write-Log "Winget found: $wingetVersion"
            return $true
        }
    } catch {}
    return $false
}

function Install-Winget {
    Write-Log "Attempting to install winget..." "WARN"
    try {
        # Try to install via Add-AppxPackage
        $progressPreference = 'silentlyContinue'
        $latestWinget = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $wingetUrl = $latestWinget.assets | Where-Object { $_.name -match "\.msixbundle$" } | Select-Object -First 1 -ExpandProperty browser_download_url
        
        $tempFile = Join-Path $env:TEMP "winget.msixbundle"
        Invoke-WebRequest -Uri $wingetUrl -OutFile $tempFile
        Add-AppxPackage -Path $tempFile
        Remove-Item $tempFile -Force
        
        Write-Log "Winget installed successfully!" "SUCCESS"
        return $true
    } catch {
        Write-Log "Failed to install winget: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Install-Package {
    param(
        [string]$WingetId,
        [string]$Name
    )
    
    try {
        Write-Log "Installing: $Name ($WingetId)..."
        $process = Start-Process -FilePath "winget" -ArgumentList "install", "--id", $WingetId, "--accept-package-agreements", "--accept-source-agreements", "--silent" -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\winget_out.txt" -RedirectStandardError "$env:TEMP\winget_err.txt"
        
        if ($process.ExitCode -eq 0) {
            Write-Log "$Name installed successfully!" "SUCCESS"
            return @{ Success = $true; Message = "Installed successfully" }
        } elseif ($process.ExitCode -eq -1978335189) {
            Write-Log "$Name is already installed." "INFO"
            return @{ Success = $true; Message = "Already installed" }
        } else {
            $errorOutput = Get-Content "$env:TEMP\winget_err.txt" -Raw -ErrorAction SilentlyContinue
            Write-Log "Failed to install $Name (Exit Code: $($process.ExitCode)). $errorOutput" "ERROR"
            return @{ Success = $false; Message = "Exit code: $($process.ExitCode)" }
        }
    } catch {
        Write-Log "Error installing ${Name}: $($_.Exception.Message)" "ERROR"
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}

function Load-Packages {
    if (Test-Path $Script:PackagesFile) {
        try {
            $json = Get-Content $Script:PackagesFile -Raw | ConvertFrom-Json
            return $json.categories
        } catch {
            Write-Log "Error loading packages.json: $($_.Exception.Message)" "ERROR"
            return $null
        }
    } else {
        Write-Log "packages.json not found at: $Script:PackagesFile" "ERROR"
        return $null
    }
}

# ============================================
# GUI FUNCTIONS
# ============================================

function Show-GUI {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Load packages
    $categories = Load-Packages
    if (-not $categories) {
        [System.Windows.Forms.MessageBox]::Show("Failed to load package definitions. Please ensure config/packages.json exists.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }

    # ---- THEME COLORS ----
    $colorBackground = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $colorPanel = [System.Drawing.Color]::FromArgb(45, 45, 45)
    $colorAccent = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $colorAccentHover = [System.Drawing.Color]::FromArgb(0, 150, 255)
    $colorText = [System.Drawing.Color]::FromArgb(240, 240, 240)
    $colorTextDim = [System.Drawing.Color]::FromArgb(170, 170, 170)
    $colorSuccess = [System.Drawing.Color]::FromArgb(76, 175, 80)
    $colorError = [System.Drawing.Color]::FromArgb(244, 67, 54)
    $colorCategoryHeader = [System.Drawing.Color]::FromArgb(55, 55, 55)

    # ---- MAIN FORM ----
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$Script:AppName v$Script:Version - Bulk Software Installer"
    $form.Size = New-Object System.Drawing.Size(1000, 750)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = $colorBackground
    $form.ForeColor = $colorText
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false
    $form.Icon = [System.Drawing.SystemIcons]::Application

    # ---- HEADER PANEL ----
    $headerPanel = New-Object System.Windows.Forms.Panel
    $headerPanel.Dock = "Top"
    $headerPanel.Height = 80
    $headerPanel.BackColor = $colorPanel

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "⚡ $Script:AppName"
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = $colorAccent
    $titleLabel.AutoSize = $true
    $titleLabel.Location = New-Object System.Drawing.Point(20, 12)
    $headerPanel.Controls.Add($titleLabel)

    $subtitleLabel = New-Object System.Windows.Forms.Label
    $subtitleLabel.Text = "Select software to install and click 'Install Selected'. Uses winget package manager."
    $subtitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $subtitleLabel.ForeColor = $colorTextDim
    $subtitleLabel.AutoSize = $true
    $subtitleLabel.Location = New-Object System.Drawing.Point(22, 52)
    $headerPanel.Controls.Add($subtitleLabel)

    $form.Controls.Add($headerPanel)

    # ---- BUTTON PANEL (TOP) ----
    $buttonPanel = New-Object System.Windows.Forms.Panel
    $buttonPanel.Location = New-Object System.Drawing.Point(0, 80)
    $buttonPanel.Size = New-Object System.Drawing.Size(1000, 50)
    $buttonPanel.BackColor = $colorBackground

    # Select All Button
    $btnSelectAll = New-Object System.Windows.Forms.Button
    $btnSelectAll.Text = "☑ Select All"
    $btnSelectAll.Size = New-Object System.Drawing.Size(110, 35)
    $btnSelectAll.Location = New-Object System.Drawing.Point(20, 8)
    $btnSelectAll.FlatStyle = "Flat"
    $btnSelectAll.BackColor = $colorPanel
    $btnSelectAll.ForeColor = $colorText
    $btnSelectAll.FlatAppearance.BorderColor = $colorAccent
    $btnSelectAll.Cursor = "Hand"
    $buttonPanel.Controls.Add($btnSelectAll)

    # Deselect All Button
    $btnDeselectAll = New-Object System.Windows.Forms.Button
    $btnDeselectAll.Text = "☐ Deselect All"
    $btnDeselectAll.Size = New-Object System.Drawing.Size(120, 35)
    $btnDeselectAll.Location = New-Object System.Drawing.Point(140, 8)
    $btnDeselectAll.FlatStyle = "Flat"
    $btnDeselectAll.BackColor = $colorPanel
    $btnDeselectAll.ForeColor = $colorText
    $btnDeselectAll.FlatAppearance.BorderColor = $colorAccent
    $btnDeselectAll.Cursor = "Hand"
    $buttonPanel.Controls.Add($btnDeselectAll)

    # Search Box
    $searchBox = New-Object System.Windows.Forms.TextBox
    $searchBox.Size = New-Object System.Drawing.Size(200, 30)
    $searchBox.Location = New-Object System.Drawing.Point(290, 12)
    $searchBox.BackColor = $colorPanel
    $searchBox.ForeColor = $colorText
    $searchBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $searchBox.Text = "🔍 Search..."
    $buttonPanel.Controls.Add($searchBox)

    # Selected count label
    $lblCount = New-Object System.Windows.Forms.Label
    $lblCount.Text = "Selected: 0"
    $lblCount.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblCount.ForeColor = $colorAccent
    $lblCount.AutoSize = $true
    $lblCount.Location = New-Object System.Drawing.Point(520, 16)
    $buttonPanel.Controls.Add($lblCount)

    $form.Controls.Add($buttonPanel)

    # ---- SCROLLABLE PACKAGE PANEL ----
    $scrollPanel = New-Object System.Windows.Forms.Panel
    $scrollPanel.Location = New-Object System.Drawing.Point(10, 135)
    $scrollPanel.Size = New-Object System.Drawing.Size(965, 480)
    $scrollPanel.AutoScroll = $true
    $scrollPanel.BackColor = $colorBackground

    # Store all checkboxes for reference
    $Script:AllCheckboxes = @()
    $yOffset = 5

    foreach ($category in $categories) {
        # Category Header
        $catPanel = New-Object System.Windows.Forms.Panel
        $catPanel.Location = New-Object System.Drawing.Point(5, $yOffset)
        $catPanel.Size = New-Object System.Drawing.Size(920, 30)
        $catPanel.BackColor = $colorCategoryHeader

        $catLabel = New-Object System.Windows.Forms.Label
        $catLabel.Text = "  📁 $($category.name)"
        $catLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

