#Script Functions
function Invoke-ResourceExplorerQuery ($KQL, $AccessToken) {
    $headers=@{

        
        "Content-Type"  = 'application/json'        
        "Authorization" = "Bearer $AccessToken"
    }

    $Payload=@{
        "Query"=$KQL
    } | ConvertTo-Json

    $Url="https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01"

    Invoke-RestMethod -Method POST -UseBasicParsing -Uri $Url -Headers $headers -Body $Payload -ContentType 'application/json' #-Verbose
}

function Invoke-ARMAPIQuery ($Url) {

    $headers=@{

        
        "Content-Type"  = 'application/json'        
        "Authorization" = "Bearer $AccessToken"
    }

    $Uri=$URL

    Invoke-RestMethod -Method Get -UseBasicParsing -Uri $Uri -Headers $headers -ContentType 'application/json' 

}

Function Get-ResourceByType ($type,$AccessToken){

Write-Warning "Getting list of resource type $type ..."


$KQL=@"
        resources | where type == '$type'
"@
# the line above is purposedly aligned to the left due to the here string requirement


return (Invoke-ResourceExplorerQuery -AccessToken $AccessToken -KQL $KQL)



}

Function CreateHealthAlertsArray ($results) {

$results.data | foreach {


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
            IncidentType=if ($tmpIncidentType -eq "") {"All"} else {$tmpIncidentType}
            Category=$tmpCategory
            Subscriptions=$tmpSubscriptions
            Valid=$false
            ServicesValidFor=@()
            Notes=""
        }
        
   }
}

Function CreateResourceArray ($results) {
#Creates an array of resources using a common schema.

$results.data | foreach {

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
            CoveredBy      = @()
            Notes          = ""
        }
        
   }
    

}

Function CreateDataTable ($Data,$Props) {


    #$Props=($Data | get-member | where MemberType -eq "NoteProperty").Name

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


# Assessment functions
Function AssessHealthAlerts ($Alerts) {



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

                $NeededSelections | foreach {
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
            $Alert.Valid = $true
            
        } else {
            $Alert.Valid = $false
            $Alert.Notes += "$($Notes -join ', ')"
        }
        
        

   }

   return $Alerts

}

Function AssessSubscriptions ($Subs) {

 $Subs | Add-Member -MemberType NoteProperty -Name AlertCoverage -Value "None"  -Force
 
 $Subs | ForEach-Object {

        $Sub=$_

        $AlertsThatCoverMe=@()
        $AlertsThatCoverMe=$HealthAlerts | where Valid -eq $true | where Subscriptions -Contains $Sub.SubscriptionId 

        
        $Sub.AlertCoverage=if ($AlertsThatCoverMe.IncidentType -contains "All") {"All"} else {$AlertsThatCoverMe.IncidentType | sort -Unique}
        If ($Sub.AlertCoverage -eq "") {$Sub.AlertCoverage -eq "None"}
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

            # Add a friendly display name for the type
            $Resource.TypeDisplayName=$ResourceTypeHash[$Resource.Type].Name

        } else {
            #Define default behavior

            
            $CheckForAlert=$True
            $CheckForInsights=$False

            # Add a friendly display name for the type
            $Resource.TypeDisplayName=$Resource.Type

        }






        # Check if App Insights is enabled
        If ($CheckForInsights -eq $true) {
                $Resource.AppInsights=if ($AppInsights.Name -contains $Resource.Name) {"Enabled"} else {"Disabled"}
        }

        # Check for Service Health Alerts
        If ($CheckForAlert -eq $true) {

            $tmpAlerts1=@()
            $tmpAlerts1=$HealthAlerts | where Valid -eq $true | where Subscriptions -Contains $Resource.Subscription 

        

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
             
                        $Resource.AlertCoverage=if ($AlertsThatCoverMe.IncidentType -contains "All") {"All"} else {$AlertsThatCoverMe.IncidentType | sort -Unique}
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







# MAIN starts



#Get Access token

#Using PowerShell Az Module
if ($AccessToken -eq $null) {
    $currentAzureContext = Get-AzContext
    $azureRmProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile;
    $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azureRmProfile);
    $AccessToken=$profileClient.AcquireAccessToken($currentAzureContext.Subscription.TenantId).AccessToken;
}

#Using the AZ Util
#if ($AccessToken -eq $null) {
#    $AccessToken=(az account get-access-token | convertfrom-json).accessToken
#}



 
# Script Global Variables
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

    }

    
}




# Get Health Alerts
if ((test-path .\HealthData.xml) -eq $true) {

    $Results=Import-Clixml -Path .\HealthData.xml
} else {

    $Results=Get-ResourceByType -type 'microsoft.insights/activitylogalerts' -AccessToken $AccessToken
}

# need to filter servicehealth in KQL query
$HealthAlerts=CreateHealthAlertsArray -Results $Results | where Category -eq "ServiceHealth"


# Get App insights data
$AppInsights=(Get-ResourceByType -type 'microsoft.insights/components' -AccessToken $AccessToken).data


# Gather Subscription information
$Subs= (Invoke-ARMAPIQuery  "https://management.azure.com/subscriptions?api-version=2020-01-01").value
AssessSubscriptions -Subs $Subs


# Process the Health alerts and assess them for validity
$AssessedHealthAlerts=AssessHealthAlerts -Alerts $HealthAlerts

#$AssessedHealthAlerts | fl Name,valid,ServicesValidFor,Regions,IncidentType,Notes


#CreateDataTable -Data $AssessedHealthAlerts  -Props @("Name","Actions","Services","Regions","IncidentType","Subscriptions","Valid","ServicesValidFor","Notes" )




# Iterate through each defined resource type, get a list of resources, and assess them.
$ResourceReport=@()
$ResourceTypeHash.keys | ForEach-Object {

    if ((test-path .\AppServicePlans.xml) -eq $true) {
    
        $Results=Import-Clixml -Path .\AppServicePlans.xml
    } else {

        $Results=Get-ResourceByType -type $_ -AccessToken $AccessToken
    }


    $Resources=CreateResourceArray -Results $Results #| where Subscription -eq 'f263b677-361a-4ec3-91d6-c4e05012c36b'
    AssessResources -Resources $Resources -HealthAlerts $HealthAlerts
    $ResourceReport+=$Resources 

}


$ResourceReport | ft TypeDisplayName,Kind,name,AppInsights, subscription,AlertCoverage

#Create workbook


#Create the JSON data for the queries
$JsonHealthAlerts=($AssessedHealthAlerts | select valid,id,actions,regions,incidenttype,subsriptions,servicesvalidfor | ConvertTo-Json -Compress)                   #-replace '"','\"'
$JsonSubscriptions=($Subs | where alertcoverage -eq $null | select id,displayname,state | ConvertTo-Json -Compress)                                                 #-replace '"','\"'
$JsonAppServicePlan=($ResourceReport | where Type -eq 'microsoft.web/serverfarms' | select id,TypeDisplayName,AlertCoverage | ConvertTo-Json -Compress)             #-replace '"','\"'
$JsonWebapps=($ResourceReport | where Type -ne 'microsoft.web/serverfarms' | where AppInsights -ne "Enabled" | select id,TypeDisplayName,AppInsights, kind, resourcegroup | ConvertTo-Json -Compress) #-replace '"','\"'


#Load the template
$Workbook=gc .\WorkbookTemplate.json -Raw | ConvertFrom-Json

$Workbook.items[1].content.query=@{version="1.0.0";content=$JsonSubscriptions} | ConvertTo-Json -Depth 99 -Compress
$Workbook.items[3].content.query=@{version="1.0.0";content=$JsonHealthAlerts} | ConvertTo-Json -Depth 99 -Compress
$Workbook.items[5].content.query=@{version="1.0.0";content=$JsonAppServicePlan} | ConvertTo-Json -Depth 99 -Compress
$Workbook.items[7].content.query=@{version="1.0.0";content=$JsonWebapps} | ConvertTo-Json -Depth 99 -Compress
    
$Workbook | ConvertTo-Json -Depth 99 | clip