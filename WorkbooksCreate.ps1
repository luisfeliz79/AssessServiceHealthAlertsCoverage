#$object=$a | ConvertFrom-Json


$object | fl *
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

      [pscustomobject]@{

        type=3
        content=@{
            "version"       = "KqlItem/1.0"
            "query"         = $JsonQuery
            "size"          = 0
            "queryType"     = 8
            "gridSettings"  = [pscustomobject]@{
                 "rowLimit" = 1000
               
            }
        }
        name="text - $Counter"

      } 
      $Counter++
}



$Luis = New-AzureWorkbook


$Luis.items=@()
$Luis.items+=Add-AzureWorkbookTextItem -MarkDownString "# **Hello##"
$Luis.items+=Add-AzureWorkbookJSONQuery -Query "KQL | 123"
$Luis | ConvertTo-Json -Depth 99 | clip