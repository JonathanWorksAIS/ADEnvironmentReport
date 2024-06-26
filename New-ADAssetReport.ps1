<#
    .SYNOPSIS
        Creates HTML reports of an active directory forest and its domains.
   
       	#Original Author: Zachary Loeber
        #Updated by: Jonathan Works
    	
    	THIS CODE IS MADE AVAILABLE AS IS, WITHOUT WARRANTY OF ANY KIND. THE ENTIRE 
    	RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS CODE REMAINS WITH THE USER.
    	
    	Version 2.0 - 3/21/2024
	
    .DESCRIPTION
        Creates HTML reports of an active direcotry forest and its domains.

    	IMPORTANT NOTE: The script requires powershell 3.0 as well as .Net 3.5 for Linq to be 
                        able to highlight HTML cells.
	
	.PARAMETER ReportFormat
        One of three report formats to use; HTML, Excel, and Custom. The first two are precanned options, 
        the last requires custom code further on in the script.
    
        HTML - This is the default option. Saves the report locally.
        Excel - This can be used to spit out all the report elements to excel, each section in its own 
                workbook.
        Custom - You will need to supply your own mix of parameters later in the code to use this.
        
    .PARAMETER ReportType
        Which reports will you be generating?
        
        Forest - Generate forest discovery report.
        Domain - Generate per domain privileged user reports.
        ForestAndDomain - Default value. Generate both reports.
    
    .PARAMETER ExportAllUsers
	    When processing the domain information gathering, also export all users with normalized attributes to a CSV.
        
    .PARAMETER ExportPrivilegedUsers
        When processing the domain information gathering, also export all privileged users with normalized attributes to a CSV.
        
    .PARAMETER ExportGraphvizDefinitionFiles
        When processing the forest information gathering, also create export graphviz diagram definition files.
        
    .PARAMETER SaveData
        Save data to an xml file for later report processing.
        
    .PARAMETER LoadData
        Load data for report processing (skips information gathering).
        
    .PARAMETER DataFile
        XML file base name used for domain and forest load/save data (without a path!). This will automatically be prefixed with domain_ or forest_.
        
	.PARAMETER PromptForInput
    	By default global variables are used (which can be found shortly after the parameters section). 
        If PromptForInput is set then the report variables will be prompted for at the console.
    
	.EXAMPLE
        Generate the HTML report using the predefined global variables and preselected html reports. 
        Show verbose status updates (HIGHLY RECOMMENDED!!)
        .\Get-ADAssetReport.ps1 -Verbose
    	
    .EXAMPLE
        Generate the Excel report, prompt for report variables. Be verbose.
        .\Get-ADAssetReport.ps1 -PromptForInput -ReportFormat 'Excel' -Verbose
        
    .EXAMPLE
        Generate the HTML report, prompt for report variables.
        .\Get-ADAssetReport.ps1 -PromptForInput
   
    .EXAMPLE
        Gather forest related information. Create graphviz diagram source files. Save all data collected for later report generation.
        .\Get-ADAssetReport.ps1 -ReportType Forest -ExportGraphvizDefinitionFiles -SaveData

    .EXAMPLE
        Load previously saved xml forest data and generate the HTML report.
        .\Get-ADAssetReport.ps1 -LoadData -ReportType Forest
        
    .NOTES
        Author: Zachary Loeber
        
    .LINK 
        http://www.the-little-things.net 
#>
[CmdletBinding()] 
param ( 
    [Parameter(HelpMessage='Format of report(s) to generate. Defaults to HTML.')]
    [ValidateSet('HTML','Excel','Custom')]
    [String]$ReportFormat='HTML',
    
    [Parameter(HelpMessage='Types of report(s) to generate. Defaults to ForestAndDomain.')]
    [ValidateSet('Forest','Domain','ForestAndDomain','Custom')]
    [String]$ReportType='ForestAndDomain',
    
    [Parameter(HelpMessage='CSV Export of all users.(Only applies to Domain account report)')]
    [switch]$ExportAllUsers,
    
    [Parameter(HelpMessage='CSV Export of all priviledged users. (Only applies to Domain account report)')]
    [switch]$ExportPrivilegedUsers,
    
    [Parameter(HelpMessage='Export graphviz definition files for diagram generation.(Only applies to Forest report)')]
    [switch]$ExportGraphvizDefinitionFiles,
    
    [Parameter(HelpMessage='Save all gathered data.')]
    [switch]$SaveData,
    
    [Parameter(HelpMessage='Load previously saved data.')]
    [switch]$LoadData,
    
    [Parameter(HelpMessage='Data file used when saving or loading data.')]
    [String]$DataFile='SaveData.xml',
    
    [Parameter(HelpMessage='Prompt for report variables.')]
    [switch]$PromptForInput
)

# Used if calling script from command line
$Verbosity = ($PSBoundParameters['Verbose'] -eq $true)

# Import our variables
. .\src\Variables.ps1
. .\src\ReportSectionProcessing.ps1
. .\src\ReportVariables.ps1
. .\src\ReportContent.ps1

# Import all of our functions
. .\src\functions\Add-Zip.ps1
. .\src\functions\Append-ADUserAccountControl.ps1
. .\src\functions\ConvertTo-HashArray.ps1
. .\src\functions\ConvertTo-MultiArray.ps1
. .\src\functions\ConvertTo-PropertyValue.ps1
. .\src\functions\ConvertTo-PSObject.ps1
. .\src\functions\Create-ReportSection.ps1
. .\src\functions\Format-HTMLTable.ps1
. .\src\functions\Get-ADDomainPrivAccounts.ps1
. .\src\functions\Get-ADDomainReportInformation.ps1
. .\src\functions\Get-ADForestReportInformation.ps1
. .\src\functions\Get-ADPathName.ps1
. .\src\functions\Get-ADPrivilegedGroups.ps1
. .\src\functions\Get-LyncPoolAssociationHash.ps1
. .\src\functions\Get-NETBiosName.ps1
. .\src\functions\Get-ObjectFromLDAPPath.ps1
. .\src\functions\Get-TreeFromLDAPPath.ps1
. .\src\functions\Load-AssetDataFile.ps1
. .\src\functions\New-ConsolePrompt.ps1
. .\src\functions\New-ReportDelivery.ps1
. .\src\functions\New-ReportOutput.ps1
. .\src\functions\New-SelfContainedAssetReport.ps1
. .\src\functions\New-ZipFile.ps1
. .\src\functions\Normalize-ADUsers.ps1
. .\src\functions\Search-AD.ps1

# Prompting for input gives us a quick 
If ($PromptForInput) {
    $AD_CreateDiagramSourceFiles = New-ConsolePrompt 'Do you want to create diagram source txt files for later processing?'
    $AD_CreateDiagrams = New-ConsolePrompt 'Do you want to create diagrams with graphviz?'
    if ($AD_CreateDiagrams) {
        $Graphviz_Path = Read-Host "Enter your graphviz binary path if needed (if already in the environment path just press enter):"
    }
    $ExportAllUsers = New-ConsolePrompt 'Do you want to export a CSV of all user data?'
    $ExportPrivilegedUsers = New-ConsolePrompt 'Do you want to export a CSV of all privileged user data?'
    $Verbosity = New-ConsolePrompt 'Do you want verbose output?'
}

$reportsplat = @{}
if ($LoadData) {
    if (Test-Path ("forest_" + $DataFile)) {
        $ADForestReport = Load-AssetDataFile "forest_$DataFile"
    }
    if (Test-Path ("domain_" + $DataFile)) {
        $ADDomainReport = Load-AssetDataFile "domain_$DataFile"
    }
    $reportsplat.SkipInformationGathering = $true
}
elseif ($SaveData) {
    $reportsplat.SaveData = $true
    $reportsplat.SaveDataFile = $DataFile
}

if ($Verbosity) {
    $reportsplat.Verbose = $true
}

switch ($ReportFormat) {
	'HTML' {
        Write-Verbose "New-ADAssetReport: HTML format selected"
        $reportsplat.SaveReport = $true
        $reportsplat.OutputMethod = 'IndividualReport'
	}
	'Excel' {
        Write-Verbose "New-ADAssetReport: Excel format selected"
        $reportsplat.NoReport = $true
        $reportsplat.ReportType = 'ExportToExcel'
        $reportsplat.ExportToExcel = $true
	}
    'Custom' {
        # Fill this out as you see fit
	}
}

switch ($ReportType) {
    { @("Forest", "ForestAndDomain") -contains $_ } {
        # Create a new forest report
        Write-Verbose "New-ADAssetReport: Running a Forest level report"
        New-SelfContainedAssetReport `
                -ReportContainer $ADForestReport `
                -ReportNamePrefix 'forest_' `
                @reportsplat
    }
    { @("Domain", "ForestAndDomain") -contains $_ } {
        Write-Verbose "New-ADAssetReport: Running a Domain level report"
        # Create a new per-domain report
        New-SelfContainedAssetReport `
                -ReportContainer $ADDomainReport `
                -ReportNamePrefix 'domain_' `
                @reportsplat
    }
    'Custom' {
        # Fill out as you wish
    }
}