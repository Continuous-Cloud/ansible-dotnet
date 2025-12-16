#!powershell

#AnsibleRequires -CSharpUtil Ansible.Basic

$DOCUMENTATION = @"
---
module: win_dotnet_core_info

short_description: Lookup information about dotnet core installs on a host

version_added: "1.0.0"

description: >-
  Queries the host system for dotnet installs. Returns the versions installed and their components if available.
  Results are broken up by dotnet type (sdk, runtime)

options:
    type:
        description: The type of install you want to search for. If unset, all types will be queried
        required: false
        type: str
        choices: [sdk, runtime]

    version:
        description: >-
          The version to search for. The version can be just the major, major and minor, or major minor and patch.
          If no version is specified, all versions are returned
        type: str
        required: false

    executable_path:
        description: >-
          The absolute path to the dotnet executable on the remote host. If you have dotnet installed to a non-standard
          location, you may want to set this.
        type: str
        required: false
        default: 'c:\program files\dotnet\dotnet.exe'

author:
    - Mike Morency
"@

$EXAMPLES = @"
- name: Lookup All Dotnet Core Info
  continuouscloud.dotnet.win_dotnet_core_info: {}

- name: Lookup Just Runtime Info
  continuouscloud.dotnet.win_dotnet_core_info:
    type: runtime

- name: Lookup Dotnet SDK 8 Info
  continuouscloud.dotnet.win_dotnet_core_info:
    type: sdk
    version: 8
"@

$RETURN = @"
"@


$spec = @{
    options = @{
        type = @{ type = "str"; required = $false; choices = @('runtime', 'sdk', 'desktop') }
        version = @{ type = "str"; required = $false; default = "" }
        executable_path = @{ type = "str"; required = $false; default = "c:\program files\dotnet\dotnet.exe"}
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.Result.stdout_lines = @()
$module.Result.stdout = ""
$module.Result.stderr_lines = @()
$module.Result.stderr = ""
$module.Result.changed = $false
$module.Result.sdk = @{'versions' = @()}
$module.Result.runtime = @{'versions' = @(); 'components' = @{}}
$module.Result.desktop = @{'versions' = @(); 'components' = @{}}

$type = $module.Params.type
$version = $module.Params.version
$executablePath = $module.Params.executable_path


function Get-SdkVersions {
    $dotnetOutput = & "$executablePath" --list-sdks | `
        select-string "([^\.]|^)${version}" | `
        select -expandproperty line
    if (-not $dotnetOutput) { return }

    $dotnetVersions = @()
    foreach ($dotnetLine in $dotnetOutput) {
        $lineSplit = $dotnetLine -split ' '
        $dotnetVersions += $lineSplit[0]
    }
    $dotnetVersions
}


function Get-RuntimeVersions {
    $dotnetOutput = & "$executablePath" --list-runtimes | `
        select-string "\s${version}" | `
        select -expandproperty line
    if (-not $dotnetOutput) { return }

    $dotnetVersions = @{}
    foreach ($dotnetLine in $dotnetOutput) {
        $lineSplit = $dotnetLine -split ' '
        $lineVersion = $lineSplit[1]
        if (-not $dotnetVersions[$lineVersion]) {
            $dotnetVersions[$lineVersion] = @($lineSplit[0])
        } else {
            $dotnetVersions[$lineVersion] += $lineSplit[0]
        }
    }
    $dotnetVersions
}

if (-not (Test-Path "$executablePath")) {
    write-host "No dotnet command was found, nothing to do"
    $module.ExitJson()
}


if ((-not $type) -or ($type -eq 'sdk')) {
    $sdkVersions = Get-SdkVersions
    if ($sdkVersions) {
        $module.Result.sdk = @{
            "versions" = [array]($sdkVersions | %{ new-object System.Version ($_) } | sort -descending | %{ $_.tostring() })
        }
    }
}

if ((-not $type) -or ($type -eq 'runtime') -or ($type -eq 'desktop')) {
    $runtimeVersions = Get-RuntimeVersions
    if ($runtimeVersions) {
        $module.Result.runtime = @{
            "versions" = [array]($runtimeVersions.keys | %{ new-object System.Version ($_) } | sort -descending | %{ $_.tostring() })
            "components" = $runtimeVersions
        }
        $module.Result.desktop = $module.Result.runtime
    }
}

$module.ExitJson()
