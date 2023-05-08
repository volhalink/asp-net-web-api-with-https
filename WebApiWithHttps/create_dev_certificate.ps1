param ($projectname, $domain, $pwdvalue)

$pwd = ConvertTo-SecureString -String $pwdvalue -Force -AsPlainText

$cert = New-SelfSignedCertificate -DnsName $domain, "localhost" -CertStoreLocation "cert:\LocalMachine\My"

$certpath = "cert:\LocalMachine\My\$($cert.Thumbprint)"

# save certificates to the folder shared with docker
$sharedcertfolder = "$env:APPDATA\ASP.NET\Https"
$crtname = "$projectname.crt"
$pfxname = "$projectname.pfx"
$pemname = "$projectname.pem"


$crtnewpath = Join-Path -Path $sharedcertfolder -ChildPath $crtname
#The private key is not included in the export
Export-Certificate -Cert $certpath -FilePath $crtnewpath
Import-Certificate -CertStoreLocation "Cert:\LocalMachine\Root" -FilePath $crtnewpath

# Convert certificate raw data to Base64
$pemcert = @(
 '-----BEGIN CERTIFICATE-----'
 [System.Convert]::ToBase64String($cert.RawData, 'InsertLineBreaks')
 '-----END CERTIFICATE-----'
) 
# Output PEM file to the path
$pemnewpath = Join-Path -Path $sharedcertfolder -ChildPath $pemname
$pemcert | Out-File -FilePath $pemnewpath -Encoding ascii


$pfxnewpath = Join-Path -Path $sharedcertfolder -ChildPath $pfxname
#By default, extended properties and the entire chain are exported
Export-PfxCertificate -Cert $certpath -FilePath $pfxnewpath -Password $pwd

dotnet user-secrets init
dotnet user-secrets set "Kestrel:Certificates:Default:Password" $pwdvalue
# use the .pfx certificate from shared folder on local run
dotnet user-secrets set "Kestrel:Certificates:Default:Path" $pfxnewpath