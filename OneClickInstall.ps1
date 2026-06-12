#Requires -Version 5.1
<#
.SYNOPSIS
    Appocalypse - Bulk Software Installer with GUI
.DESCRIPTION
    A PowerShell tool with a Windows Forms GUI that allows you to select
    and install multiple software packages at once using winget.
.PARAMETER ConfigFile
    Optional custom JSON config filename (must be in config folder)
#>

param(
    [string]$ConfigFile = ""
)

# ============================================
# CONFIGURATION
# ============================================
$Script:Version = "1.0.0"
$Script:AppName = "Appocalypse"
$Script:LogFile = Join-Path $PSScriptRoot "install_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

if ($ConfigFile) {
    $Script:PackagesFile = Join-Path $PSScriptRoot "config\$ConfigFile"
} else {
    $Script:PackagesFile = Join-Path $PSScriptRoot "configpackages.json"
}

# ============================================
# HELPER FUNCTIONS
# ============================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $Script:LogFile -Value $logEntry
    switch ($Level) {
        "ERROR"   { Write-Host $logEntry -ForegroundColor Red }
        "WARN"    { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        default   { Write-Host $logEntry -ForegroundColor Cyan }
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
# GUI
# ============================================

function Show-GUI {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $categories = Load-Packages
    if (-not $categories) {
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to load package definitions.`nPlease ensure config/packages.json exists at:`n$Script:PackagesFile",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }

    # ---- COLORS ----
    $colorBg        = [System.Drawing.Color]::FromArgb(15, 17, 23)       # #0F1117
    $colorPanel     = [System.Drawing.Color]::FromArgb(26, 29, 41)       # #1A1D29
    $colorAccent    = [System.Drawing.Color]::FromArgb(255, 94, 0)       # #FF5E00 (apocalypse orange)
    $colorSecondary = [System.Drawing.Color]::FromArgb(168, 85, 247)     # #A855F7 (electric purple)
    $colorSuccess   = [System.Drawing.Color]::FromArgb(34, 197, 94)      # #22C55E
    $colorError     = [System.Drawing.Color]::FromArgb(239, 68, 68)      # #EF4444
    $colorText      = [System.Drawing.Color]::FromArgb(248, 250, 252)    # #F8FAFC
    $colorTextDim   = [System.Drawing.Color]::FromArgb(148, 163, 184)    # #94A3B8
    $colorCatHeader = [System.Drawing.Color]::FromArgb(35, 38, 52)       # slightly lighter panel

    # ---- MAIN FORM ----
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$Script:AppName v$Script:Version"
    $form.Size = New-Object System.Drawing.Size(1000, 750)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = $colorBg
    $form.ForeColor = $colorText
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false

    # ---- HEADER ----
    $headerPanel = New-Object System.Windows.Forms.Panel
    $headerPanel.Dock = "Top"
    $headerPanel.Height = 70
    $headerPanel.BackColor = $colorPanel

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = $Script:AppName
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = $colorAccent
    $titleLabel.AutoSize = $true
    $titleLabel.Location = New-Object System.Drawing.Point(20, 10)
    $headerPanel.Controls.Add($titleLabel)

    $subtitleLabel = New-Object System.Windows.Forms.Label
    $subtitleLabel.Text = "Select software to install, then click Install Selected. Powered by winget."
    $subtitleLabel.ForeColor = $colorTextDim
    $subtitleLabel.AutoSize = $true
    $subtitleLabel.Location = New-Object System.Drawing.Point(22, 45)
    $headerPanel.Controls.Add($subtitleLabel)

    $form.Controls.Add($headerPanel)

    # ---- TOOLBAR ----
    $toolbar = New-Object System.Windows.Forms.Panel
    $toolbar.Location = New-Object System.Drawing.Point(0, 70)
    $toolbar.Size = New-Object System.Drawing.Size(1000, 50)
    $toolbar.BackColor = $colorBg

    $btnSelectAll = New-Object System.Windows.Forms.Button
    $btnSelectAll.Text = "[+] Select All"
    $btnSelectAll.Size = New-Object System.Drawing.Size(110, 32)
    $btnSelectAll.Location = New-Object System.Drawing.Point(20, 9)
    $btnSelectAll.FlatStyle = "Flat"
    $btnSelectAll.BackColor = $colorPanel
    $btnSelectAll.ForeColor = $colorText
    $btnSelectAll.FlatAppearance.BorderColor = $colorAccent
    $btnSelectAll.Cursor = "Hand"
    $toolbar.Controls.Add($btnSelectAll)

    $btnDeselectAll = New-Object System.Windows.Forms.Button
    $btnDeselectAll.Text = "[-] Deselect All"
    $btnDeselectAll.Size = New-Object System.Drawing.Size(120, 32)
    $btnDeselectAll.Location = New-Object System.Drawing.Point(140, 9)
    $btnDeselectAll.FlatStyle = "Flat"
    $btnDeselectAll.BackColor = $colorPanel
    $btnDeselectAll.ForeColor = $colorText
    $btnDeselectAll.FlatAppearance.BorderColor = $colorSecondary
    $btnDeselectAll.Cursor = "Hand"
    $toolbar.Controls.Add($btnDeselectAll)

    $searchBox = New-Object System.Windows.Forms.TextBox
    $searchBox.Size = New-Object System.Drawing.Size(200, 28)
    $searchBox.Location = New-Object System.Drawing.Point(290, 11)
    $searchBox.BackColor = $colorPanel
    $searchBox.ForeColor = $colorTextDim
    $searchBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $searchBox.Text = "Search..."
    $toolbar.Controls.Add($searchBox)

    $lblCount = New-Object System.Windows.Forms.Label
    $lblCount.Text = "Selected: 0"
    $lblCount.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblCount.ForeColor = $colorAccent
    $lblCount.AutoSize = $true
    $lblCount.Location = New-Object System.Drawing.Point(520, 14)
    $toolbar.Controls.Add($lblCount)

    $form.Controls.Add($toolbar)

    # ---- SCROLLABLE PACKAGE LIST ----
    $scrollPanel = New-Object System.Windows.Forms.Panel
    $scrollPanel.Location = New-Object System.Drawing.Point(10, 125)
    $scrollPanel.Size = New-Object System.Drawing.Size(965, 480)
    $scrollPanel.AutoScroll = $true
    $scrollPanel.BackColor = $colorBg

    $Script:AllCheckboxes = @()
    $yOffset = 5

    foreach ($category in $categories) {
        # Category header
        $catLabel = New-Object System.Windows.Forms.Label
        $catLabel.Text = "  > $($category.name)"
        $catLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $catLabel.ForeColor = $colorSecondary
        $catLabel.BackColor = $colorCatHeader
        $catLabel.Size = New-Object System.Drawing.Size(920, 28)
        $catLabel.Location = New-Object System.Drawing.Point(5, $yOffset)
        $catLabel.TextAlign = "MiddleLeft"
        $scrollPanel.Controls.Add($catLabel)
        $yOffset += 32

        # Packages in category
        foreach ($pkg in $category.packages) {
            $cb = New-Object System.Windows.Forms.CheckBox
            $cb.Text = "$($pkg.name)  -  $($pkg.description)"
            $cb.Tag = $pkg.wingetId
            $cb.Size = New-Object System.Drawing.Size(900, 24)
            $cb.Location = New-Object System.Drawing.Point(25, $yOffset)
            $cb.ForeColor = $colorText
            $cb.BackColor = $colorBg
            $cb.Font = New-Object System.Drawing.Font("Segoe UI", 9)
            $cb.Add_CheckedChanged({
                $count = ($Script:AllCheckboxes | Where-Object { $_.Checked }).Count
                $lblCount.Text = "Selected: $count"
            })
            $scrollPanel.Controls.Add($cb)
            $Script:AllCheckboxes += $cb
            $yOffset += 26
        }

        $yOffset += 10
    }

    $form.Controls.Add($scrollPanel)

    # ---- BOTTOM PANEL ----
    $bottomPanel = New-Object System.Windows.Forms.Panel
    $bottomPanel.Location = New-Object System.Drawing.Point(0, 615)
    $bottomPanel.Size = New-Object System.Drawing.Size(1000, 100)
    $bottomPanel.BackColor = $colorPanel

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(20, 10)
    $progressBar.Size = New-Object System.Drawing.Size(750, 25)
    $progressBar.Style = "Continuous"
    $bottomPanel.Controls.Add($progressBar)

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = "Ready"
    $lblStatus.ForeColor = $colorTextDim
    $lblStatus.AutoSize = $true
    $lblStatus.Location = New-Object System.Drawing.Point(20, 42)
    $bottomPanel.Controls.Add($lblStatus)

    $btnInstall = New-Object System.Windows.Forms.Button
    $btnInstall.Text = "INSTALL SELECTED"
    $btnInstall.Size = New-Object System.Drawing.Size(180, 50)
    $btnInstall.Location = New-Object System.Drawing.Point(790, 10)
    $btnInstall.FlatStyle = "Flat"
    $btnInstall.BackColor = $colorAccent
    $btnInstall.ForeColor = $colorText
    $btnInstall.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnInstall.FlatAppearance.BorderSize = 0
    $btnInstall.Cursor = "Hand"
    $bottomPanel.Controls.Add($btnInstall)

    $form.Controls.Add($bottomPanel)

    # ---- EVENT HANDLERS ----

    # Select All
    $btnSelectAll.Add_Click({
        foreach ($cb in $Script:AllCheckboxes) {
            if ($cb.Visible) { $cb.Checked = $true }
        }
    })

    # Deselect All
    $btnDeselectAll.Add_Click({
        foreach ($cb in $Script:AllCheckboxes) {
            $cb.Checked = $false
        }
    })

    # Search focus clear placeholder
    $searchBox.Add_GotFocus({
        if ($searchBox.Text -eq "Search...") {
            $searchBox.Text = ""
            $searchBox.ForeColor = $colorText
        }
    })

    $searchBox.Add_LostFocus({
        if ($searchBox.Text -eq "") {
            $searchBox.Text = "Search..."
            $searchBox.ForeColor = $colorTextDim
        }
    })

    # Search filter
    $searchBox.Add_TextChanged({
        $query = $searchBox.Text.ToLower()
        if ($query -eq "search..." -or $query -eq "") {
            foreach ($cb in $Script:AllCheckboxes) { $cb.Visible = $true }
            return
        }
        foreach ($cb in $Script:AllCheckboxes) {
            $cb.Visible = $cb.Text.ToLower().Contains($query)
        }
    })

    # Install button
    $btnInstall.Add_Click({
        $selected = $Script:AllCheckboxes | Where-Object { $_.Checked }

        if ($selected.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "No packages selected. Please check at least one item.",
                "Nothing Selected",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            return
        }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Install $($selected.Count) selected package(s)?`n`nThis may take several minutes.",
            "Confirm Installation",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($confirm -ne "Yes") { return }

        # Disable UI during install
        $btnInstall.Enabled = $false
        $btnSelectAll.Enabled = $false
        $btnDeselectAll.Enabled = $false
        $progressBar.Maximum = $selected.Count
        $progressBar.Value = 0

        $successCount = 0
        $failCount = 0
        $results = @()

        foreach ($cb in $selected) {
            $pkgName = $cb.Text.Split(" - ")[0].Trim()
            $pkgId = $cb.Tag

            $lblStatus.Text = "Installing: $pkgName ($($progressBar.Value + 1)/$($selected.Count))..."
            $lblStatus.ForeColor = $colorAccent
            $form.Refresh()

            $result = Install-Package -WingetId $pkgId -Name $pkgName

            if ($result.Success) {
                $successCount++
                $cb.ForeColor = $colorSuccess
                $results += "[OK] $pkgName - $($result.Message)"
            } else {
                $failCount++
                $cb.ForeColor = $colorError
                $results += "[FAIL] $pkgName - $($result.Message)"
            }

            $progressBar.Value++
            $form.Refresh()
        }

        # Re-enable UI
        $btnInstall.Enabled = $true
        $btnSelectAll.Enabled = $true
        $btnDeselectAll.Enabled = $true
        $lblStatus.Text = "Done! Success: $successCount | Failed: $failCount"
        $lblStatus.ForeColor = if ($failCount -eq 0) { $colorSuccess } else { $colorError }

        # Show summary
        $summary = "Installation Complete!`n`n"
        $summary += "Successful: $successCount`n"
        $summary += "Failed: $failCount`n"
        $summary += "Log: $Script:LogFile`n`n"
        $summary += ($results -join "`n")

        [System.Windows.Forms.MessageBox]::Show(
            $summary,
            "Installation Summary",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            $(if ($failCount -eq 0) { [System.Windows.Forms.MessageBoxIcon]::Information } else { [System.Windows.Forms.MessageBoxIcon]::Warning })
        )
    })

    # ---- SHOW FORM ----
    [void]$form.ShowDialog()
    $form.Dispose()
}

# ============================================
# MAIN ENTRY POINT
# ============================================

Write-Log "=== $Script:AppName v$Script:Version started ==="

# Check winget
if (-not (Test-WingetInstalled)) {
    Write-Log "Winget not found." "WARN"
    $installWinget = Read-Host "Winget is required but not installed. Attempt to install? (Y/N)"
    if ($installWinget -eq "Y") {
        if (-not (Install-Winget)) {
            Write-Host "ERROR: Could not install winget. Please install manually:" -ForegroundColor Red
            Write-Host "https://aka.ms/getwinget" -ForegroundColor Yellow
            pause
            exit 1
        }
    } else {
        Write-Host "Winget is required. Exiting." -ForegroundColor Red
        pause
        exit 1
    }
}

# Launch GUI
Show-GUI

Write-Log "=== $Script:AppName finished ==="
