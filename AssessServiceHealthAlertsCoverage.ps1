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

function Get-ResourceByType ($type,$AccessToken){

Write-Warning "Getting list of resource type $type ..."


$KQL=@"
        resources | where type == '$type'
"@
# the line above is purposedly aligned to the left due to the here string requirement


return (Invoke-ResourceExplorerQuery -AccessToken $AccessToken -KQL $KQL)



}

function CreateHealthAlertsArray ($results) {

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
        $tmpActions         = $_.properties.actions
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
            if ($allOf.anyOf.field) {Write-Warning "$tmpName - $tmpCategory";Write-warning $($allOf.anyOf | ConvertTo-Json)}
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

function CreateResourceArray ($results) {
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
            Coverage       = "None"
            CoveredBy      = @()
            Notes          = ""
        }
        
   }
    

}

# Assessment functions

Function AssessHealthAlerts ($Alerts) {



    # Loop through all alerts
    $Alerts | ForEach-Object {

        # Array of notes regarding this alert
        $Notes=@()

        if ($Alerts.actions.count -lt 1) {
            $Notes+="This alert does not seem to trigger any actions"
        }

        # Check if the alert convers at least one service
        if ($Alerts.services -ne "" ) {
            #Since the services attribute is not empty, some services have been selected.

            $Alert=$_


            # Loop through each of our defined service types
            # And find out if all needed selections are chosen
            # if so, then mark this alert entry valid for that service
            $ResourceTypeHash.keys | ForEach-Object {

                $NeededSelections=$ResourceTypeHash[$_].HealthSelections

                #Start with the assumption that the alert is valid for service
                $ValidForThisService=$true 

                $NeededSelections | foreach {
                    if ($Alerts.Services -notcontains $_) {

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
            $Alert.Notes += $($Alert.IncidentType -join ", ")
        } else {
            $Alert.Valid = $false
            $Alert.Notes += "$($Notes -join ', ')"
        }
        
        

   }

   return $Alerts

}
    
Function AssessResources ($Resources,$HealthAlerts) {


    $Resources | ForEach-Object {

        $Resource=$_




        [System.Collections.ArrayList]$tmpAlerts1=$HealthAlerts | where Valid -eq $true | where Subscriptions -Contains $Resource.Subscription 

        

        if ($tmpAlerts1.count -gt 0) {
            # If we got here, there is at least One valid Alert that covers the subscription.
            # Now lets check the regions

            [System.Collections.ArrayList]$TmpAlerts2=$tmpAlerts1 | where {$_.Regions -eq "" -or $_.Regions -contains $Resource.Location }

            if ($tmpAlerts2.count -gt 0) {
            # We found valid Health Alerts that match the region
            # Now lets check if it covers this resource type

                [System.Collections.ArrayList]$AlertsThatCoverMe=$tmpAlerts2 | where {$_.ServicesValidFor -Contains "All" -or $_.ServicesValidFor -Contains $Resource.Type }

                if ($AlertsThatCoverMe.count -gt 0) {
                # We found Health Alerts that cover this resource type
                # Therefore lets mark this resource covered!
             
                    $Resource.Coverage=if ($AlertsThatCoverMe.IncidentType -contains "All") {"All"} else {$AlertsThatCoverMe.IncidentType | sort -Unique}
                    $Resource.Notes="Covered by $($AlertsThatCoverMe.Name -join ', ')"
                    $Resource.CoveredBy=$AlertsThatCoverMe

                }
           
            } else {
                
                $Resource.Coverage="None"
                $Resource.Notes="Not Covered by any alerts"

            }

        } 
        
        else  {
                $Resource.Coverage="None"
                $Resource.Notes="Not Covered by any alerts"

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
                Name="App Service"
                HealthSelections=@(
                    'App Service \ Web Apps',
                    'App Service (Linux) \ Web Apps',
                    'App Service (Linux) \ Web App for Containers',
                    'App Service (Linux)',
                    'App Service'        
                    )
                Insights=$True
    }
}


# Get Health Alerts
$Results=Get-ResourceByType -type 'microsoft.insights/activitylogalerts' -AccessToken $AccessToken
$HealthAlerts=CreateHealthAlertsArray -Results $Results | where Category -eq "ServiceHealth"
# Process the Health alerts and assess them for validity
$AssessedHealthAlerts=AssessHealthAlerts -Alerts $HealthAlerts

$AssessedHealthAlerts | ft Name,valid,ServicesValidFor,Regions,Notes

# Iterate through each defined resource type, get a list of resources, and assess them.
$ResourceTypeHash.keys | ForEach-Object {

    $Results=Get-ResourceByType -type $_ -AccessToken $AccessToken
    $Resources=CreateResourceArray -Results $Results | where Subscription -eq 'f263b677-361a-4ec3-91d6-c4e05012c36b'
    AssessResources -Resources $Resources -HealthAlerts $HealthAlerts
    $Resources | ft name, subscription,Coverage

}