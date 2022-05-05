#region Script Functions
function Invoke-ResourceExplorerQuery ($KQL, $AccessToken) {
    
    $CompleteResult=@()
    
    $headers=@{

        
        "Content-Type"  = 'application/json'        
        "Authorization" = "Bearer $AccessToken"
    }

    $Payload=@{
        "Query"=$KQL
    } | ConvertTo-Json

    $Url="https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01"

    $Result=Invoke-RestMethod -Method POST -UseBasicParsing -Uri $Url -Headers $headers -Body $Payload -ContentType 'application/json' #-Verbose

    $CompleteResult+=$Result.data

    if ($Result.'$Skiptoken') {

        while ($Result.'$Skiptoken') {

                Write-Warning "Getting more results ..."
                

                $Payload=@{
                    "Query"=$KQL
                    "options"=[pscustomobject]@{
                        '$skiptoken'=$($Result.'$skiptoken')
                     }
                } | ConvertTo-Json
        
                #Write-Warning $Payload

                $Result=Invoke-RestMethod -Method POST -UseBasicParsing -Uri $Url -Headers $headers -Body $Payload -ContentType 'application/json' #-Verbose

                $CompleteResult+=$Result.data

        }

    }
    return $CompleteResult
}

function Invoke-ARMAPIQuery ($Url) {

    $headers=@{

        
        "Content-Type"  = 'application/json'        
        "Authorization" = "Bearer $AccessToken"
    }

    $Uri=$URL

    Invoke-RestMethod -Method Get -UseBasicParsing -Uri $Uri -Headers $headers -ContentType 'application/json' 

}

Function Get-ResourceByType ($type,$AccessToken,$SubscriptionFilter, $AppendKQLClause){

Write-Warning "Getting list of resource type $type ..."

If ($SubscriptionFilter.count -eq 0) {

$KQL=@"
        resources | where type == '$type'
"@
# the line above is purposedly aligned to the left due to the here string requirement

} else {

Write-warning "Using Subscription Filter: $SubscriptionFilter"

$KQL=@"
        resources | where type == '$type' | where subscriptionId matches regex "$($SubscriptionFilter -join '|')"
"@
# the line above is purposedly aligned to the left due to the here string requirement



}

if ($AppendKQLClause.Lenght -gt 0) {
    $KQL += ' | ' + $AppendKQLClause

}



return (Invoke-ResourceExplorerQuery -AccessToken $AccessToken -KQL $KQL)



}

Function CreateHealthAlertsArray ($results) {

$results | foreach {


        # Ensure clean variables
        $tmpName            = ""
        $tmpId              = ""
        $tmpSubscriptions   = ""
        $tmpActions         = ""
        $tmpServices        = ""
        $tmpRegions         = ""
        $tmpCategory        = ""
        $tmpSubscriptions   = ""
        $tmpIncidentType    = ""
        $data               = ""
        
        # Temporary variables holding Health Alert data       
        $tmpName            = $_.Name
        $tmpId              = $_.id
        $tmpSubscriptions   = $_.properties.scopes -replace '/Subscriptions/'
        $tmpActions         = ($_.properties.actions.actionGroups | foreach {($_.actionGroupId -split '/')[-1]})
        $data               = $_.properties

        # Examine the conditions for the Health Alert
        $data.condition.allOf | ForEach-Object {

            $allOf=$_

            switch ($allOf.field) {

                "category" {
                    $tmpCategory=$allOf | select -expand equals
                }
                'properties.impactedServices[*].ImpactedRegions[*].RegionName' {
                        $tmpRegions=$allOf.'containsAny' -replace ' ','' -replace '(|)',''
                 }
                'properties.impactedServices[*].ServiceName' {$tmpServices=$allOf.'containsAny'}

            }
            #if ($allOf.anyOf.field) {Write-Warning "$tmpName - $tmpCategory";Write-warning $($allOf.anyOf | ConvertTo-Json)}
            switch ($allOf.anyOf.field) {

                'properties.incidentType' {

                    $tmpIncidentType=$allOf.anyOf | select -expand equals

                }

                
            }

        }

        # Create a PS Object with all the Health Alert details
        [PSCustomObject]@{
    
            Name=$tmpName
            ID=$tmpID
            Actions=$tmpActions
            Services=$tmpServices
            Regions=$tmpRegions
            IncidentType=if ($tmpIncidentType -eq "" -or $tmpIncidentType -eq $null) {"All"} else {$tmpIncidentType}
            Category=$tmpCategory
            Subscriptions=$tmpSubscriptions
            Valid="False"
            ServicesValidFor=@()
            Notes=""
        }
        
   }
}

Function CreateResourceArray ($results) {
#Creates an array of resources using a common schema.

$results | foreach {

        # Create a PS Object and return it
        [PSCustomObject]@{
    
            Name           = $_.Name
            ID             = $_.id
            Subscription   = $_.subscriptionId
            Tenant         = $_.tenantId
            ResourceGroup  = $_.resourceGroup
            Kind           = $_.kind
            Type           = $_.type
            Location       = $_.location
            TypeDisplayName= ""
            AlertCoverage  = "None"
            AppInsights    = "N/A"
            DiagnosticMetrics=$false
            DiagnosticLogs=$false
            LogAnalyticsWorkspace=""
            CoveredBy      = @()
            Notes          = ""
        }
        
   }
    

}

Function CreateDataTable ($Data,$Props) {


    $Props=($Data | get-member | where MemberType -eq "NoteProperty").Name
    
    $DTData=@()

    #For each row in the PSOBject
    $Data | foreach {

        $tmpArray=@()
        $CurData=$_

        #For each prop in the Row
        $Props | foreach {

          $tmpArray+=$($CurData.$_ -join '; ' -replace '\\','-')  

        }

        $DTLine='"'+$($tmpArray -join '", "')+'"'
        $DTData+=$DTLine


    }

    $Header="datatable($($Props -join ':string, ')"+':string)'
    
    $DTComplete=@"
    $Header [
    $($DTData -join ",`n")
    ]
"@

$DTComplete
}

#endregion

#region Workbooks_Functions
$Counter=0
Function New-AzureWorkbook {

    [pscustomobject]@{

        version='Notebook/1.0'
        items=@{}
        fallbackResourceIds=@("Azure Monitor")
        '$schema'='https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json'

    } 

}

Function Add-AzureWorkbookTextItem ($MarkDownString) {


      [pscustomobject]@{

        type=1
        content=[pscustomobject]@{
            json=$MarkDownString
        }
        name="text - $Counter"

      } 
      $Counter++
}

Function Add-AzureWorkbookJSONQuery ($JsonQuery) {

      #Wrap the Json query into the needed object
      $WrappedJsonQuery=$(@{version="1.0.0";content=$JsonQuery} | ConvertTo-Json -Depth 99 -Compress)


      [pscustomobject]@{

        type=3
        content=@{
            "version"       = "KqlItem/1.0"
            "query"         = $WrappedJsonQuery
            "size"          = 0
            "showExportToExcel" = "true"
            "queryType"     = 8
            "gridSettings"  = [pscustomobject]@{
                 "rowLimit" = 1000
                 "filter"   = "true"
                 
            }
        }
        name="text - $Counter"

      } 
      $Counter++
}


#endregion

#region Assessment_functions
Function AssessHealthAlerts ($Alerts) {


    if ($Alerts.count -eq 0 -or $ALerts -eq $null) {Write-Warning "No Health Alerts found!";break}


    # Loop through all alerts
    $Alerts | ForEach-Object {

        $Alert=$_
        

        # Array of notes regarding this alert
        $Notes=@()

        if ($Alert.actions.count -lt 1) {
            $Notes+="This alert does not seem to trigger any actions"
        }

        # Check if the alert convers at least one service
        if ($Alert.services -ne "" ) {
            #Since the services attribute is not empty, some services have been selected.



            # Loop through each of our defined service types
            # And find out if all needed selections are chosen
            # if so, then mark this alert entry valid for that service
            $ResourceTypeHash.keys | ForEach-Object {

                $NeededSelections=$ResourceTypeHash[$_].HealthSelections

                #Start with the assumption that the alert is valid for service
                $ValidForThisService=$true 

                $NeededSelections | ForEach-Object {
                    if ($Alert.Services -notcontains $_) {

                       #but if we find that something is missing, then make validforthisservice false
                       $ValidForThisService=$false
                    }
                }
                if ($ValidForThisService -eq $true) {
                    #If all checks out, go ahead and add this service type valid for this alert
                    $Alert.ServicesValidFor+=$_
                }


            }



        } else {
            #If the .services attribute is completely empty, it means that all services are selected.
            #Let's add "All" to the list
            $Alert.ServicesValidFor+="All"                    
        }

        # Finally, mark the alert valid if no other issues were found,
        # or invalid and provide some notes.
        If ($Notes.count -eq 0) {
            $Alert.Valid = "True"
            
        } else {
            $Alert.Valid = "False"
            $Alert.Notes += "$($Notes -join ', ')"
        }
        

     [PSCustomObject]@{
   
        AlertRule        = $Alert.ID
        Valid            = $Alert.Valid
        Actions          = if ($Alert.Actions -eq "") {"None"} else {$Alert.Actions}
        Regions          = if ($Alert.Regions -eq "") {"All"} else {$Alert.Regions}
        EventTypes       = if ($Alert.IncidentType -eq "") {"All"} else {$Alert.IncidentType}
        Services         = if ($Alert.Services -eq "") {"All"} else {$Alert.Services}
        Subscription     = $Alert.Subscriptions
  
     }
        

   }

   

 



}

Function AssessSubscriptions ($Subs) {

 
 $Subs | ForEach-Object {

        $Sub=$_

        #if ($Sub.displayname -match "lufeliz") {write-warning "break";$host.EnterNestedPrompt()}

        

        $AlertsThatCoverMe=@()
        $AlertsThatCoverMe=$AssessedHealthAlerts | where Valid -eq "True" | where Subscription -Contains $Sub.SubscriptionId 

        $Coverage=""
        $Coverage=if ($AlertsThatCoverMe.EventTypes -contains "All") {"All"} else {$AlertsThatCoverMe.EventTypes | Sort-Object -Unique}
        If ($Coverage -eq "") {$Coverage = "None"}

        [PSCustomObject]@{
        
            Subscription=$Sub.id
            Name=$Sub.DisplayName
            State=$Sub.State
            AlertCoverage=$Coverage
            CoveredBy=($AlertsThatCoverMe.AlertRule | Foreach-Object { ($_ -split '/')[-1] }) -join ', '
            SubscriptionID=$Sub.subscriptionId

        }
        
        
        
  }   


}
    
Function AssessResources ($Resources,$HealthAlerts) {


    $Resources | ForEach-Object {

        $Resource=$_

        #Is it in our custom hash?
        if ($ResourceTypeHash[$Resource.Type].name -ne $null) {

            # Custom Settings
            $CheckForAlert=$ResourceTypeHash[$Resource.Type].AlertCheck
            $CheckForInsights=$ResourceTypeHash[$Resource.Type].InsightsCheck
            $DiagCheck=$ResourceTypeHash[$Resource.Type].DiagCheck

            # Add a friendly display name for the type
            $Resource.TypeDisplayName=$ResourceTypeHash[$Resource.Type].Name

        } else {
            #Define default behavior

            
            $CheckForAlert=$True
            $CheckForInsights=$False
            $DiagCheck=$False

            # Add a friendly display name for the type
            $Resource.TypeDisplayName=$Resource.Type

        }






        # Check if App Insights is enabled
        If ($CheckForInsights -eq $true) {
                $Resource.AppInsights=if ($AppInsights.Name -contains $Resource.Name) {"Enabled"} else {"Disabled"}
        }

        If ($DiagCheck -eq $true) {

            Write-warning "    -  Getting diagnostics info for $($Resource.Name)"

            $URL = "https://management.azure.com" + $Resource.ID + "/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview"
            
            $DiagResults=Invoke-ARMAPIQuery -Url $URL 
            
            

            $tmpMetricCheck=0
            $tmpLogCheck=0
            $tmpLawIds=@()
            
            $DiagResults.value | foreach {

                if ($_.properties.metrics.count -gt 0 -and $_.properties.workspaceId.count -gt 0) {
                    $tmpMetricCheck++
                    #Write-warning "          - Metrics"
                }

                if ($_.properties.logs.count -gt 0 -and $_.properties.workspaceId.count -gt 0) {
                    $tmpLogCheck++
                    #Write-warning "          - Logs"
                }

                if ($_.properties.workspaceId.count -gt 0) {
                    $tmpLawIds+=$_.properties.workspaceId
                }

            }

            
            $Resource.DiagnosticMetrics=if ($tmpMetricCheck -gt 0) {$True} else {$False}
            $Resource.DiagnosticLogs=if ($tmpLogCheck -gt 0) {$True} else {$False}
            $Resource.LogAnalyticsWorkspace=$tmpLawIds

        }

        # Check for Service Health Alerts
        If ($CheckForAlert -eq $true) {

            $tmpAlerts1=@()
            $tmpAlerts1=$HealthAlerts | where Valid -eq "True" | where Subscriptions -Contains $Resource.Subscription 

        

            if ($tmpAlerts1.count -gt 0 -or $tmpAlerts1 -ne $Null) {
                # If we got here, there is at least One valid Alert that covers the subscription.
                # Now lets check the regions

                $tmpAlerts2=@()
                $TmpAlerts2=$tmpAlerts1 | where {$_.Regions -eq "" -or $_.Regions -contains $Resource.Location }

                if ($tmpAlerts2.count -gt 0 -or $tmpAlerts2 -ne $Null) {
                # We found valid Health Alerts that match the region
                # Now lets check if it covers this resource type

                    $AlertsThatCoverMe=@()
                    $AlertsThatCoverMe=$tmpAlerts2 | where {$_.ServicesValidFor -Contains "All" -or $_.ServicesValidFor -Contains $Resource.Type }

                    if ($AlertsThatCoverMe.count -gt 0 -or $AlertsThatCoverMe -ne $Null) {
                    # We found Health Alerts that cover this resource type
                    # Therefore lets mark this resource covered!
             
                        $Resource.AlertCoverage=if ($AlertsThatCoverMe.IncidentType -contains "All") {"All"} else {$AlertsThatCoverMe.IncidentType | Sort-Object -Unique}
                        $Resource.Notes="Covered by $($AlertsThatCoverMe.Name -join ', ')"
                        $Resource.CoveredBy=$AlertsThatCoverMe

                    }
           
                } else {
                
                    $Resource.AlertCoverage="None"
                    $Resource.Notes="Not Covered by any alerts"

                }

            } else  {

                    $Resource.AlertCoverage="None"
                    $Resource.Notes="Not Covered by any alerts"

            } 

        }

   }

}

Function AccessTotals() {

    [PSCustomObject]@{
        
        Metric="Subscriptions: Require Coverage"
        Count= ($Subscriptions | Where AlertCoverage -eq 'None').count
    

    }

        [PSCustomObject]@{
        
        Metric="Service Health Alerts: Incomplete"
        Count= ($AssessedHealthAlerts | where valid -ne "True").count
    
      
    }

        [PSCustomObject]@{
        
        Metric="App Service Plan: No Diagnostics"
        Count= ($ResourceReport | where Type -eq 'microsoft.web/serverfarms' | where {$_.AlertCoverage -eq 'None' -or $_.DiagnosticMetrics -eq 'False' -or $_.DiagnosticLogs -eq 'False'}).count 

    
    }

    [PSCustomObject]@{
        
        Metric="Apps with no App Insights or Diagnostics"
        Count= ($ResourceReport | where Type -ne 'microsoft.web/serverfarms' | where {$_.AppInsights -eq 'False' -or $_.DiagnosticMetrics -eq 'False' -or $_.DiagnosticLogs -eq 'False'}).count 
       
   
    }

}

#endregion

#region Script_Global_Variables
# In the future, this hash will be read from a file.
$ResourceTypeHash=@{

    'microsoft.web/serverfarms'=@{
                Name="App Service Plan"
                HealthSelections=@(
                    'App Service \ Web Apps',
                    'App Service (Linux) \ Web Apps',
                    'App Service (Linux) \ Web App for Containers',
                    'App Service (Linux)',
                    'App Service'        
                    )
                InsightsCheck=$False
                AlertCheck=$true
                DiagCheck=$true

    }

    'microsoft.web/sites'=@{
                Name="App Service Webapp"
                HealthSelections=@(
                    'App Service \ Web Apps',
                    'App Service (Linux) \ Web Apps',
                    'App Service (Linux) \ Web App for Containers',
                    'App Service (Linux)',
                    'App Service'        
                    )
                InsightsCheck=$true
                AlertCheck=$false
                DiagCheck=$true

    }

     'microsoft.web/sites/slots'=@{
                Name="App Service Webapp Slot"
                HealthSelections=@(
                    'App Service \ Web Apps',
                    'App Service (Linux) \ Web Apps',
                    'App Service (Linux) \ Web App for Containers',
                    'App Service (Linux)',
                    'App Service'        
                    )
                InsightsCheck=$true
                AlertCheck=$false
                DiagCheck=$true

    }


    'microsoft.appplatform/spring'=@{
                Name="Azure Spring Cloud"
                HealthSelections=@(
                    'Azure Spring Cloud'       
                    )
                InsightsCheck=$true
                AlertCheck=$true
                DiagCheck=$true

    }




    
}
#endregion



#region MAIN

#$FilteredSubscriptions=@("f263b677-361a-4ec3-91d6-c4e05012c36b")


#Get Access token
#Using PowerShell Az Module

    $currentAzureContext = Get-AzContext
    $azureRmProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile;
    $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azureRmProfile);
    $AccessToken=$profileClient.AcquireAccessToken($currentAzureContext.Subscription.TenantId).AccessToken;


#Using the AZ Util
#if ($AccessToken -eq $null) {
#    $AccessToken=(az account get-access-token | convertfrom-json).accessToken
#}



# Get Health Alerts


    $Results=Get-ResourceByType -type 'microsoft.insights/activitylogalerts' -AccessToken $AccessToken #-AppendKQLClause 'extend category = properties.condition.allOf[0].equals | where category == "ServiceHealth"'

    

    $HealthAlerts=CreateHealthAlertsArray -Results $Results  | where Category -eq "ServiceHealth"


    # Get App insights data
    $AppInsights=(Get-ResourceByType -type 'microsoft.insights/components' -AccessToken $AccessToken)


    # Gather Subscription information
    $Subs= (Invoke-ARMAPIQuery  "https://management.azure.com/subscriptions?api-version=2020-01-01").value

    if ($FilteredSubscriptions.count -gt 0) {
        $Subs = $Subs | where subscriptionId -In $FilteredSubscriptions
    }



    # Process the Health alerts and assess them for validity
    # Needs to happen first
    $AssessedHealthAlerts=AssessHealthAlerts -Alerts $HealthAlerts

    $Subscriptions=AssessSubscriptions -Subs $Subs 


# Iterate through each defined resource type, get a list of resources, and assess them.
    $ResourceReport=@()
    $ResourceTypeHash.keys | ForEach-Object {

       
        $Results=Get-ResourceByType -type $_ -AccessToken $AccessToken -SubscriptionFilter $FilteredSubscriptions
        
        if ($Results -ne $null) {
            $Resources=CreateResourceArray -Results $Results #| where Subscription -eq 'f263b677-361a-4ec3-91d6-c4e05012c36b'
            AssessResources -Resources $Resources -HealthAlerts $HealthAlerts
            $ResourceReport+=$Resources 
        }
    }

    $AlertsReport           = $AssessedHealthAlerts   

    $SubsReport             = $Subscriptions
    $AppServicePlanReport   = $ResourceReport | where Type -eq 'microsoft.web/serverfarms' | select id,TypeDisplayName,AlertCoverage,DiagnosticMetrics,DiagnosticLogs,subscription 
    $WebappsReport          = $ResourceReport | where Type -like '*microsoft.web/sites*' | select id,TypeDisplayName,AppInsights,DiagnosticMetrics,DiagnosticLogs, kind, resourcegroup,subscription
    $SpringCloudReport      = $ResourceReport | where Type -eq 'microsoft.appplatform/spring' | select id,TypeDisplayName,AlertCoverage,AppInsights,DiagnosticMetrics,DiagnosticLogs, kind, resourcegroup,subscription

    $HeaderTotals           = AccessTotals

# Output reports to host
<#
    $AlertsReport 
    $SubsReport
    $AppServicePlanReport
    $WebappsReport 
    $HeaderTotals

# Save to CSV

    $AlertsReport           | Export-Csv ".\AlertsReport.csv" -NoTypeInformation
    $SubsReport             | Export-Csv ".\SubscriptionsReport.csv" -NoTypeInformation
    $AppServicePlanReport   | Export-Csv ".\AppServicePlanReport" -NoTypeInformation
    $WebappsReport          | Export-Csv ".\AppReport.csv" -NoTypeInformation

    if ($SpringCloudReport -ne $null) {
        $SpringCloudReport      | Export-Csv ".\SpringCloudReport.csv" -NoTypeInformation
    }
    
    Write-Warning "Exported results to CSV files..."
#>

#Create workbook

    #Create the JSON data for the queries
    $JsonHealthAlerts        = ( $AlertsReport         | ConvertTo-Json -Compress )
    $JsonSubscriptions       = ( $SubsReport           | ConvertTo-Json -Compress )


    $Counter=0
    $AssessWorkbook=New-AzureWorkbook
    $AssessWorkbook.items=@()

    $AssessWorkbook.items+=Add-AzureWorkbookTextItem -MarkDownString "Report created $(Get-Date)"
    $AssessWorkbook.items+=Add-AzureWorkbookTextItem -MarkDownString "# **Subscriptions - Service Health Alert Coverage**"
    $AssessWorkbook.items+=Add-AzureWorkbookJSONQuery -JsonQuery $JsonSubscriptions
    $AssessWorkbook.items+=Add-AzureWorkbookTextItem -MarkDownString "# **Service Health Alerts Configuration**"
    $AssessWorkbook.items+=Add-AzureWorkbookJSONQuery -JsonQuery $JsonHealthAlerts


    $JsonAppServicePlan      = ( $AppServicePlanReport | ConvertTo-Json -Compress )
    $JsonWebapps             = ( $WebappsReport        | ConvertTo-Json -Compress )
    
    $AssessWorkbook.items+=Add-AzureWorkbookTextItem -MarkDownString "# **App Service plans - Service Health Alert Coverage**"
    $AssessWorkbook.items+=Add-AzureWorkbookJSONQuery -JsonQuery $JsonAppServicePlan
    $AssessWorkbook.items+=Add-AzureWorkbookTextItem -MarkDownString "# **Apps - Insights and Diagnostics**"
    $AssessWorkbook.items+=Add-AzureWorkbookJSONQuery -JsonQuery $JsonWebapps

    if ($SpringCloudReport -ne $null) {
        $JsonSpringCloud         = ( $SpringCloudReport    | ConvertTo-Json -Compress )
        $AssessWorkbook.items+=Add-AzureWorkbookTextItem -MarkDownString "# **Spring Cloud - Alerts, Insights and Diagnostics**"
        $AssessWorkbook.items+=Add-AzureWorkbookJSONQuery -JsonQuery $JsonSpringCloud
    }

    $AssessWorkbook | ConvertTo-Json -Depth 99 | Out-File ".\AssessWorkbook.json"


    Write-Warning "Exported Static workbook to .\AssessWorkbook.json"
    Write-Warning "To View it, follow these steps:"
    Write-Warning " Azure Portal > Azure Monitor > Workbooks -> New"
    Write-Warning " Copy and Paste the contents of AssessWorkbook.json into the Advanced Editor section"



#endregion

# Todo
#  make this run nicely in Azure Shell


