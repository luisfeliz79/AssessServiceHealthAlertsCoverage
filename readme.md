# AssessServiceHealthAlertsCoverage.ps1

Scans Service Health Alerts, Subscriptions and App services and provides Alerting, Logging and App insights data.
The output file is a the JSON code for an Azure Monitor Workbook



# *How to use this script*


## In Azure Shell (Bash)

Execute this:

```
	wget https://raw.githubusercontent.com/luisfeliz79/AssessServiceHealthAlertsCoverage/main/AssessServiceHealthAlertsCoverage.ps1

	pwsh AssessServiceHealthAlertsCoverage.ps1
```

## In Linux Bash (assumes Powershell is installed, if not see https://aka.ms/azurepowershell)

Requires
- Linux Powershell ( https://aka.ms/powershell )

- Azure PowerShell Module ( https://aka.ms/azurepowershell )
	--or--
- Azure CLI	            ( https://aka.ms/azcli )

```
	wget https://raw.githubusercontent.com/luisfeliz79/AssessServiceHealthAlertsCoverage/main/AssessServiceHealthAlertsCoverage.ps1

	pwsh AssessServiceHealthAlertsCoverage.ps1
```

## In Windows

Requires:
- Azure PowerShell Module ( https://aka.ms/azurepowershell )

```
	Invoke-WebRequest -Uri https://raw.githubusercontent.com/luisfeliz79/AssessServiceHealthAlertsCoverage/main/AssessServiceHealthAlertsCoverage.ps1 -OutFile AssessServiceHealthAlertsCoverage.ps1

	PowerShell -ExecutionPolicy Bypass -file AssessServiceHealthAlertsCoverage.ps1
```

# Viewing the resulting Azure Workbook

An Azure Workbook with static data is created as a result of this script.
To use it:
	- Go to https://portal.azure.com and Search for Monitor
	- In the Monitor blade, click on Workbooks and the New button
	- Click on the Advanced Editor icon </>
	- Copy and paste the JSON code into this screen and apply




