# KUMO Router Label Manager
# Professional GUI application for bulk updating AJA KUMO router labels via Excel
# Created for live event production environments

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Main Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "KUMO Router Label Manager - Solotech Production"
$form.Size = New-Object System.Drawing.Size(700, 500)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)
$form.ForeColor = [System.Drawing.Color]::White

# Title Label
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "AJA KUMO Router Label Manager"
$titleLabel.Font = New-Object System.Drawing.Font("Arial", 16, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 122, 255)
$titleLabel.Location = New-Object System.Drawing.Point(20, 20)
$titleLabel.Size = New-Object System.Drawing.Size(400, 30)
$form.Controls.Add($titleLabel)

# KUMO IP Address Section
$ipLabel = New-Object System.Windows.Forms.Label
$ipLabel.Text = "KUMO Router IP Address:"
$ipLabel.Location = New-Object System.Drawing.Point(20, 70)
$ipLabel.Size = New-Object System.Drawing.Size(150, 20)
$ipLabel.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($ipLabel)

$ipTextBox = New-Object System.Windows.Forms.TextBox
$ipTextBox.Text = "192.168.1.100"
$ipTextBox.Location = New-Object System.Drawing.Point(180, 68)
$ipTextBox.Size = New-Object System.Drawing.Size(150, 23)
$ipTextBox.BackColor = [System.Drawing.Color]::FromArgb(62, 62, 66)
$ipTextBox.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($ipTextBox)

# Test Connection Button
$testButton = New-Object System.Windows.Forms.Button
$testButton.Text = "Test Connection"
$testButton.Location = New-Object System.Drawing.Point(350, 67)
$testButton.Size = New-Object System.Drawing.Size(120, 25)
$testButton.BackColor = [System.Drawing.Color]::FromArgb(0, 122, 255)
$testButton.ForeColor = [System.Drawing.Color]::White
$testButton.FlatStyle = "Flat"
$form.Controls.Add($testButton)

# Excel File Section
$excelLabel = New-Object System.Windows.Forms.Label
$excelLabel.Text = "Excel Label File:"
$excelLabel.Location = New-Object System.Drawing.Point(20, 120)
$excelLabel.Size = New-Object System.Drawing.Size(100, 20)
$excelLabel.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($excelLabel)

$excelPathTextBox = New-Object System.Windows.Forms.TextBox
$excelPathTextBox.Location = New-Object System.Drawing.Point(20, 145)
$excelPathTextBox.Size = New-Object System.Drawing.Size(400, 23)
$excelPathTextBox.BackColor = [System.Drawing.Color]::FromArgb(62, 62, 66)
$excelPathTextBox.ForeColor = [System.Drawing.Color]::White
$excelPathTextBox.ReadOnly = $true
$form.Controls.Add($excelPathTextBox)

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = "Browse"
$browseButton.Location = New-Object System.Drawing.Point(430, 144)
$browseButton.Size = New-Object System.Drawing.Size(80, 25)
$browseButton.BackColor = [System.Drawing.Color]::FromArgb(76, 76, 76)
$browseButton.ForeColor = [System.Drawing.Color]::White
$browseButton.FlatStyle = "Flat"
$form.Controls.Add($browseButton)

# Create Template Button
$templateButton = New-Object System.Windows.Forms.Button
$templateButton.Text = "Create Excel Template"
$templateButton.Location = New-Object System.Drawing.Point(520, 144)
$templateButton.Size = New-Object System.Drawing.Size(140, 25)
$templateButton.BackColor = [System.Drawing.Color]::FromArgb(40, 167, 69)
$templateButton.ForeColor = [System.Drawing.Color]::White
$templateButton.FlatStyle = "Flat"
$form.Controls.Add($templateButton)

# Preview DataGrid
$previewLabel = New-Object System.Windows.Forms.Label
$previewLabel.Text = "Label Preview:"
$previewLabel.Location = New-Object System.Drawing.Point(20, 190)
$previewLabel.Size = New-Object System.Drawing.Size(100, 20)
$previewLabel.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($previewLabel)

$dataGrid = New-Object System.Windows.Forms.DataGridView
$dataGrid.Location = New-Object System.Drawing.Point(20, 215)
$dataGrid.Size = New-Object System.Drawing.Size(640, 180)
$dataGrid.BackgroundColor = [System.Drawing.Color]::FromArgb(62, 62, 66)
$dataGrid.ForeColor = [System.Drawing.Color]::White
$dataGrid.GridColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
$dataGrid.AllowUserToAddRows = $false
$dataGrid.AllowUserToDeleteRows = $false
$dataGrid.ReadOnly = $true
$dataGrid.SelectionMode = "FullRowSelect"
$dataGrid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)
$dataGrid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($dataGrid)

# Action Buttons
$uploadButton = New-Object System.Windows.Forms.Button
$uploadButton.Text = "Upload Labels to KUMO"
$uploadButton.Location = New-Object System.Drawing.Point(20, 410)
$uploadButton.Size = New-Object System.Drawing.Size(150, 30)
$uploadButton.BackColor = [System.Drawing.Color]::FromArgb(220, 53, 69)
$uploadButton.ForeColor = [System.Drawing.Color]::White
$uploadButton.FlatStyle = "Flat"
$uploadButton.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$uploadButton.Enabled = $false
$form.Controls.Add($uploadButton)

$downloadButton = New-Object System.Windows.Forms.Button
$downloadButton.Text = "Download Current Labels"
$downloadButton.Location = New-Object System.Drawing.Point(190, 410)
$downloadButton.Size = New-Object System.Drawing.Size(150, 30)
$downloadButton.BackColor = [System.Drawing.Color]::FromArgb(0, 122, 255)
$downloadButton.ForeColor = [System.Drawing.Color]::White
$downloadButton.FlatStyle = "Flat"
$downloadButton.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($downloadButton)

# Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(360, 415)
$progressBar.Size = New-Object System.Drawing.Size(200, 20)
$progressBar.Style = "Continuous"
$form.Controls.Add($progressBar)

# Status Label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Ready"
$statusLabel.Location = New-Object System.Drawing.Point(580, 415)
$statusLabel.Size = New-Object System.Drawing.Size(100, 20)
$statusLabel.ForeColor = [System.Drawing.Color]::LimeGreen
$form.Controls.Add($statusLabel)

# Global variables
$global:kumoConnected = $false
$global:excelData = $null

# Functions
function Test-KumoConnection {
    param($ip)
    
    try {
        $statusLabel.Text = "Testing..."
        $statusLabel.ForeColor = [System.Drawing.Color]::Yellow
        $form.Refresh()
        
        # Test basic connectivity
        if (Test-NetConnection -ComputerName $ip -Port 80 -InformationLevel Quiet -WarningAction SilentlyContinue) {
            $global:kumoConnected = $true
            $statusLabel.Text = "Connected"
            $statusLabel.ForeColor = [System.Drawing.Color]::LimeGreen
            [System.Windows.Forms.MessageBox]::Show("Successfully connected to KUMO at $ip", "Connection Test", "OK", "Information")
            return $true
        } else {
            throw "Connection failed"
        }
    } catch {
        $global:kumoConnected = $false
        $statusLabel.Text = "Connection Failed"
        $statusLabel.ForeColor = [System.Drawing.Color]::Red
        [System.Windows.Forms.MessageBox]::Show("Cannot connect to KUMO at $ip`nPlease check IP address and network connectivity", "Connection Error", "OK", "Error")
        return $false
    }
}

function Create-ExcelTemplate {
    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Filter = "Excel files (*.xlsx)|*.xlsx"
    $saveDialog.DefaultExt = "xlsx"
    $saveDialog.FileName = "KUMO_Labels_Template.xlsx"
    
    if ($saveDialog.ShowDialog() -eq "OK") {
        try {
            # Create Excel application
            $excel = New-Object -ComObject Excel.Application
            $excel.Visible = $false
            $workbook = $excel.Workbooks.Add()
            $worksheet = $workbook.Worksheets.Item(1)
            $worksheet.Name = "KUMO_Labels"
            
            # Headers
            $worksheet.Cells.Item(1,1) = "Port"
            $worksheet.Cells.Item(1,2) = "Type"
            $worksheet.Cells.Item(1,3) = "Current_Label"
            $worksheet.Cells.Item(1,4) = "New_Label"
            
            # Format headers
            $headerRange = $worksheet.Range("A1:D1")
            $headerRange.Font.Bold = $true
            $headerRange.Interior.Color = 15773696  # Light blue
            $headerRange.Font.Color = 16777215     # White
            
            # Add sample data for 32x32 router
            $row = 2
            for ($i = 1; $i -le 32; $i++) {
                $worksheet.Cells.Item($row, 1) = $i
                $worksheet.Cells.Item($row, 2) = "INPUT"
                $worksheet.Cells.Item($row, 3) = "Input $i"
                $worksheet.Cells.Item($row, 4) = "Camera $i"
                $row++
            }
            
            for ($i = 1; $i -le 32; $i++) {
                $worksheet.Cells.Item($row, 1) = $i
                $worksheet.Cells.Item($row, 2) = "OUTPUT"
                $worksheet.Cells.Item($row, 3) = "Output $i"
                $worksheet.Cells.Item($row, 4) = "Monitor $i"
                $row++
            }
            
            # Auto-fit columns
            $worksheet.Columns.AutoFit() | Out-Null
            
            # Add data validation for Type column
            $typeRange = $worksheet.Range("B2:B65")
            $typeRange.Validation.Delete()
            $typeRange.Validation.Add([Microsoft.Office.Interop.Excel.XlDVType]::xlValidateList, 
                                     [Microsoft.Office.Interop.Excel.XlDVAlertStyle]::xlValidAlertStop, 
                                     [Microsoft.Office.Interop.Excel.XlFormatConditionOperator]::xlBetween, 
                                     "INPUT,OUTPUT")
            
            # Save and close
            $workbook.SaveAs($saveDialog.FileName)
            $workbook.Close()
            $excel.Quit()
            
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($worksheet) | Out-Null
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($workbook) | Out-Null
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
            
            [System.Windows.Forms.MessageBox]::Show("Excel template created successfully!`nFile saved to: $($saveDialog.FileName)", "Template Created", "OK", "Information")
            
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error creating Excel template: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    }
}

function Load-ExcelData {
    param($filePath)
    
    try {
        # Import Excel data using ImportExcel module if available, otherwise use COM
        if (Get-Module -ListAvailable -Name ImportExcel) {
            Import-Module ImportExcel
            $data = Import-Excel -Path $filePath -WorksheetName "KUMO_Labels"
        } else {
            # Fallback to COM object
            $excel = New-Object -ComObject Excel.Application
            $excel.Visible = $false
            $workbook = $excel.Workbooks.Open($filePath)
            $worksheet = $workbook.Worksheets.Item("KUMO_Labels")
            
            $data = @()
            $lastRow = $worksheet.UsedRange.Rows.Count
            
            for ($row = 2; $row -le $lastRow; $row++) {
                $data += [PSCustomObject]@{
                    Port = $worksheet.Cells.Item($row, 1).Value2
                    Type = $worksheet.Cells.Item($row, 2).Value2
                    Current_Label = $worksheet.Cells.Item($row, 3).Value2
                    New_Label = $worksheet.Cells.Item($row, 4).Value2
                }
            }
            
            $workbook.Close()
            $excel.Quit()
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
        }
        
        return $data | Where-Object { $_.New_Label -and $_.New_Label.ToString().Trim() -ne "" }
        
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error loading Excel file: $($_.Exception.Message)", "Error", "OK", "Error")
        return $null
    }
}

function Update-PreviewGrid {
    param($data)
    
    if ($data) {
        $dataGrid.DataSource = $null
        $dataGrid.DataSource = $data
        $dataGrid.AutoResizeColumns()
        $uploadButton.Enabled = $true
        $global:excelData = $data
    }
}

function Download-CurrentLabels {
    param($ip, $outputPath)
    
    $statusLabel.Text = "Downloading labels..."
    $statusLabel.ForeColor = [System.Drawing.Color]::Yellow
    $progressBar.Value = 0
    $form.Refresh()
    
    $allLabels = @()
    $totalPorts = 64  # 32 inputs + 32 outputs
    $progressBar.Maximum = $totalPorts
    
    try {
        # Try multiple methods to get labels
        $labelsRetrieved = $false
        
        # Method 1: Try REST API endpoints
        $apiEndpoints = @(
            "http://$ip/api/config",
            "http://$ip/cgi-bin/config",
            "http://$ip/config.json",
            "http://$ip/status.json"
        )
        
        foreach ($endpoint in $apiEndpoints) {
            try {
                $statusLabel.Text = "Trying API: $endpoint"
                $form.Refresh()
                
                $response = Invoke-RestMethod -Uri $endpoint -TimeoutSec 10
                
                # Parse different response formats
                if ($response.inputs -or $response.outputs) {
                    # Direct format
                    for ($i = 1; $i -le 32; $i++) {
                        if ($response.inputs -and $response.inputs[$i-1]) {
                            $allLabels += [PSCustomObject]@{
                                Port = $i
                                Type = "INPUT"
                                Current_Label = $response.inputs[$i-1].label ?? "Input $i"
                                New_Label = ""
                                Notes = "Retrieved from KUMO"
                            }
                        }
                        $progressBar.Value = $i
                        $form.Refresh()
                    }
                    
                    for ($i = 1; $i -le 32; $i++) {
                        if ($response.outputs -and $response.outputs[$i-1]) {
                            $allLabels += [PSCustomObject]@{
                                Port = $i
                                Type = "OUTPUT"
                                Current_Label = $response.outputs[$i-1].label ?? "Output $i"
                                New_Label = ""
                                Notes = "Retrieved from KUMO"
                            }
                        }
                        $progressBar.Value = $i + 32
                        $form.Refresh()
                    }
                    
                    $labelsRetrieved = $true
                    break
                }
                
            } catch {
                # Continue to next endpoint
                continue
            }
        }
        
        # Method 2: Try individual port queries if bulk failed
        if (-not $labelsRetrieved) {
            $statusLabel.Text = "Trying individual port queries..."
            $form.Refresh()
            
            # Query each input
            for ($i = 1; $i -le 32; $i++) {
                try {
                    $endpoints = @(
                        "http://$ip/api/inputs/$i",
                        "http://$ip/cgi-bin/getlabel?type=input&port=$i"
                    )
                    
                    $label = "Input $i"  # Default
                    foreach ($endpoint in $endpoints) {
                        try {
                            $response = Invoke-RestMethod -Uri $endpoint -TimeoutSec 5
                            if ($response.label) {
                                $label = $response.label
                                break
                            } elseif ($response -is [string] -and $response.Trim()) {
                                $label = $response.Trim()
                                break
                            }
                        } catch { continue }
                    }
                    
                    $allLabels += [PSCustomObject]@{
                        Port = $i
                        Type = "INPUT"
                        Current_Label = $label
                        New_Label = ""
                        Notes = "Retrieved from KUMO"
                    }
                    
                    $labelsRetrieved = $true
                    
                } catch {
                    # Use default label if query fails
                    $allLabels += [PSCustomObject]@{
                        Port = $i
                        Type = "INPUT"
                        Current_Label = "Input $i"
                        New_Label = ""
                        Notes = "Default (query failed)"
                    }
                }
                
                $progressBar.Value = $i
                $form.Refresh()
                Start-Sleep -Milliseconds 100
            }
            
            # Query each output
            for ($i = 1; $i -le 32; $i++) {
                try {
                    $endpoints = @(
                        "http://$ip/api/outputs/$i",
                        "http://$ip/cgi-bin/getlabel?type=output&port=$i"
                    )
                    
                    $label = "Output $i"  # Default
                    foreach ($endpoint in $endpoints) {
                        try {
                            $response = Invoke-RestMethod -Uri $endpoint -TimeoutSec 5
                            if ($response.label) {
                                $label = $response.label
                                break
                            } elseif ($response -is [string] -and $response.Trim()) {
                                $label = $response.Trim()
                                break
                            }
                        } catch { continue }
                    }
                    
                    $allLabels += [PSCustomObject]@{
                        Port = $i
                        Type = "OUTPUT"
                        Current_Label = $label
                        New_Label = ""
                        Notes = "Retrieved from KUMO"
                    }
                    
                } catch {
                    # Use default label if query fails
                    $allLabels += [PSCustomObject]@{
                        Port = $i
                        Type = "OUTPUT"
                        Current_Label = "Output $i"
                        New_Label = ""
                        Notes = "Default (query failed)"
                    }
                }
                
                $progressBar.Value = $i + 32
                $form.Refresh()
                Start-Sleep -Milliseconds 100
            }
        }
        
        # Method 3: Try Telnet if REST failed
        if (-not $labelsRetrieved -or $allLabels.Count -eq 0) {
            $statusLabel.Text = "Trying Telnet method..."
            $form.Refresh()
            
            try {
                $tcpClient = New-Object System.Net.Sockets.TcpClient
                $tcpClient.Connect($ip, 23)
                $stream = $tcpClient.GetStream()
                $writer = New-Object System.IO.StreamWriter($stream)
                $reader = New-Object System.IO.StreamReader($stream)
                
                Start-Sleep -Seconds 2  # Wait for prompt
                
                # Query input labels
                for ($i = 1; $i -le 32; $i++) {
                    try {
                        $writer.WriteLine("LABEL INPUT $i ?")
                        $writer.Flush()
                        Start-Sleep -Milliseconds 200
                        
                        $response = $reader.ReadLine()
                        $label = if ($response -and $response -match '"([^"]+)"') { 
                            $matches[1] 
                        } else { 
                            "Input $i" 
                        }
                        
                        $allLabels += [PSCustomObject]@{
                            Port = $i
                            Type = "INPUT"
                            Current_Label = $label
                            New_Label = ""
                            Notes = "Retrieved via Telnet"
                        }
                        
                        $progressBar.Value = $i
                        $form.Refresh()
                        
                    } catch {
                        # Default if failed
                        $allLabels += [PSCustomObject]@{
                            Port = $i
                            Type = "INPUT"
                            Current_Label = "Input $i"
                            New_Label = ""
                            Notes = "Default (telnet failed)"
                        }
                    }
                }
                
                # Query output labels
                for ($i = 1; $i -le 32; $i++) {
                    try {
                        $writer.WriteLine("LABEL OUTPUT $i ?")
                        $writer.Flush()
                        Start-Sleep -Milliseconds 200
                        
                        $response = $reader.ReadLine()
                        $label = if ($response -and $response -match '"([^"]+)"') { 
                            $matches[1] 
                        } else { 
                            "Output $i" 
                        }
                        
                        $allLabels += [PSCustomObject]@{
                            Port = $i
                            Type = "OUTPUT"
                            Current_Label = $label
                            New_Label = ""
                            Notes = "Retrieved via Telnet"
                        }
                        
                        $progressBar.Value = $i + 32
                        $form.Refresh()
                        
                    } catch {
                        # Default if failed
                        $allLabels += [PSCustomObject]@{
                            Port = $i
                            Type = "OUTPUT"
                            Current_Label = "Output $i"
                            New_Label = ""
                            Notes = "Default (telnet failed)"
                        }
                    }
                }
                
                $writer.Close()
                $reader.Close()
                $tcpClient.Close()
                $labelsRetrieved = $true
                
            } catch {
                Write-Host "Telnet method failed: $($_.Exception.Message)"
            }
        }
        
        # If all methods failed, create default template
        if ($allLabels.Count -eq 0) {
            $statusLabel.Text = "Creating default template..."
            $form.Refresh()
            
            for ($i = 1; $i -le 32; $i++) {
                $allLabels += [PSCustomObject]@{
                    Port = $i
                    Type = "INPUT"
                    Current_Label = "Input $i"
                    New_Label = ""
                    Notes = "Default (connection failed)"
                }
                $progressBar.Value = $i
            }
            
            for ($i = 1; $i -le 32; $i++) {
                $allLabels += [PSCustomObject]@{
                    Port = $i
                    Type = "OUTPUT"
                    Current_Label = "Output $i"
                    New_Label = ""
                    Notes = "Default (connection failed)"
                }
                $progressBar.Value = $i + 32
            }
        }
        
        # Save to file
        $statusLabel.Text = "Saving to file..."
        $form.Refresh()
        
        if ($outputPath -match "\.xlsx$") {
            # Try Excel export
            try {
                if (Get-Module -ListAvailable -Name ImportExcel) {
                    Import-Module ImportExcel
                    $allLabels | Export-Excel -Path $outputPath -WorksheetName "KUMO_Labels" -AutoSize -TableStyle Medium6 -FreezeTopRow
                } else {
                    # Fallback to CSV
                    $csvPath = $outputPath -replace "\.xlsx$", ".csv"
                    $allLabels | Export-Csv -Path $csvPath -NoTypeInformation
                    $outputPath = $csvPath
                }
            } catch {
                # Fallback to CSV
                $csvPath = $outputPath -replace "\.xlsx$", ".csv"
                $allLabels | Export-Csv -Path $csvPath -NoTypeInformation
                $outputPath = $csvPath
            }
        } else {
            # CSV export
            $allLabels | Export-Csv -Path $outputPath -NoTypeInformation
        }
        
        $progressBar.Value = $progressBar.Maximum
        $statusLabel.Text = "Download Complete"
        $statusLabel.ForeColor = [System.Drawing.Color]::LimeGreen
        
        # Update preview grid
        Update-PreviewGrid -data $allLabels
        
        [System.Windows.Forms.MessageBox]::Show("Labels downloaded successfully!`n`nFile: $outputPath`nLabels: $($allLabels.Count)`n`nYou can now edit the 'New_Label' column and upload changes.", "Download Complete", "OK", "Information")
        
    } catch {
        $statusLabel.Text = "Download Failed"
        $statusLabel.ForeColor = [System.Drawing.Color]::Red
        [System.Windows.Forms.MessageBox]::Show("Error downloading labels: $($_.Exception.Message)", "Download Error", "OK", "Error")
    }
}

function Send-KumoLabels {
    param($ip, $data)
    
    $progressBar.Value = 0
    $progressBar.Maximum = $data.Count
    $successCount = 0
    $errorCount = 0
    
    foreach ($item in $data) {
        try {
            $statusLabel.Text = "Updating $($item.Type) $($item.Port)..."
            $form.Refresh()
            
            # Construct API endpoint based on type
            $endpoint = if ($item.Type -eq "INPUT") { "inputs" } else { "outputs" }
            $uri = "http://$ip/api/$endpoint/$($item.Port)/label"
            
            # Create request body
            $body = @{
                label = $item.New_Label
            } | ConvertTo-Json
            
            # Send request (Note: Actual API endpoints may vary - this is example structure)
            try {
                $response = Invoke-RestMethod -Uri $uri -Method PUT -Body $body -ContentType "application/json" -TimeoutSec 5
                $successCount++
            } catch {
                # Try alternative API structure
                $uri = "http://$ip/cgi-bin/setlabel"
                $body = @{
                    type = $item.Type.ToLower()
                    port = $item.Port
                    label = $item.New_Label
                } | ConvertTo-Json
                
                $response = Invoke-RestMethod -Uri $uri -Method POST -Body $body -ContentType "application/json" -TimeoutSec 5
                $successCount++
            }
            
            $progressBar.Value++
            
        } catch {
            Write-Host "Error updating $($item.Type) $($item.Port): $($_.Exception.Message)"
            $errorCount++
            $progressBar.Value++
        }
        
        Start-Sleep -Milliseconds 100  # Prevent overwhelming the device
    }
    
    $progressBar.Value = $progressBar.Maximum
    $statusLabel.Text = "Complete"
    $statusLabel.ForeColor = [System.Drawing.Color]::LimeGreen
    
    [System.Windows.Forms.MessageBox]::Show("Upload complete!`nSuccess: $successCount`nErrors: $errorCount", "Upload Results", "OK", "Information")
}

# Event Handlers
$testButton.Add_Click({
    Test-KumoConnection -ip $ipTextBox.Text
})

$browseButton.Add_Click({
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = "Excel files (*.xlsx)|*.xlsx|All files (*.*)|*.*"
    $openFileDialog.DefaultExt = "xlsx"
    
    if ($openFileDialog.ShowDialog() -eq "OK") {
        $excelPathTextBox.Text = $openFileDialog.FileName
        $data = Load-ExcelData -filePath $openFileDialog.FileName
        if ($data) {
            Update-PreviewGrid -data $data
        }
    }
})

$templateButton.Add_Click({
    Create-ExcelTemplate
})

$uploadButton.Add_Click({
    if (-not $global:kumoConnected) {
        [System.Windows.Forms.MessageBox]::Show("Please test connection to KUMO first!", "Connection Required", "OK", "Warning")
        return
    }
    
    if (-not $global:excelData) {
        [System.Windows.Forms.MessageBox]::Show("Please load Excel data first!", "Data Required", "OK", "Warning")
        return
    }
    
    $result = [System.Windows.Forms.MessageBox]::Show("This will update $($global:excelData.Count) labels on the KUMO router.`nAre you sure you want to continue?", "Confirm Upload", "YesNo", "Question")
    
    if ($result -eq "Yes") {
        Send-KumoLabels -ip $ipTextBox.Text -data $global:excelData
    }
})

$downloadButton.Add_Click({
    if (-not $global:kumoConnected) {
        [System.Windows.Forms.MessageBox]::Show("Please test connection to KUMO first!", "Connection Required", "OK", "Warning")
        return
    }
    
    # Show save dialog
    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Filter = "Excel files (*.xlsx)|*.xlsx|CSV files (*.csv)|*.csv"
    $saveDialog.DefaultExt = "xlsx"
    $saveDialog.FileName = "KUMO_Current_Labels_$(Get-Date -Format 'yyyyMMdd_HHmm')"
    
    if ($saveDialog.ShowDialog() -eq "OK") {
        Download-CurrentLabels -ip $ipTextBox.Text -outputPath $saveDialog.FileName
    }
})

# Show the form
$form.ShowDialog() | Out-Null
