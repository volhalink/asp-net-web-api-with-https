#Requires -Version 7.3

param ($projectname, [string[]]$domain, $pwdvalue, $shouldsavekey=$false)

$pwd = ConvertTo-SecureString -String $pwdvalue -Force -AsPlainText

$domains = $domain + "localhost"
$cert = New-SelfSignedCertificate -DnsName $domains  -CertStoreLocation "cert:\LocalMachine\My" -KeyExportPolicy Exportable

$certpath = "cert:\LocalMachine\My\$($cert.Thumbprint)"

# save certificates to the folder shared with docker
$sharedcertfolder = "$env:APPDATA\ASP.NET\Https"
$crtname = "dev_$projectname.crt"
$pfxname = "dev_$projectname.pfx"
$pemname = "dev_$projectname.pem"
$keyname = "dev_$projectname.key"


$crtnewpath = Join-Path -Path $sharedcertfolder -ChildPath $crtname
#The private key is not included in the export
Export-Certificate -Cert $certpath -FilePath $crtnewpath
Import-Certificate -CertStoreLocation "Cert:\LocalMachine\Root" -FilePath $crtnewpath

# Convert certificate raw data to Base64
$pemcert = $cert.ExportCertificatePem()
# Output PEM file to the path
$pemnewpath = Join-Path -Path $sharedcertfolder -ChildPath $pemname
$pemcert | Out-File -FilePath $pemnewpath -Encoding ascii

if($shouldsavekey){
	# Get certificate's key in Base64 (make sure that -KeyExportPolicy Exportable is specified when New-SelfSignedCertificate is called)
	$rsacng = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
	$key = $rsacng.ExportRSAPrivateKeyPem()
	# Output KEY file to the path
	$keynewpath = Join-Path -Path $sharedcertfolder -ChildPath $keyname
	$key | Out-File -FilePath $keynewpath -Encoding ascii
}

$pfxnewpath = Join-Path -Path $sharedcertfolder -ChildPath $pfxname
#By default, extended properties and the entire chain are exported
Export-PfxCertificate -Cert $certpath -FilePath $pfxnewpath -Password $pwd

dotnet user-secrets init
dotnet user-secrets set "Kestrel:Certificates:Default:Password" $pwdvalue
# use the .pfx certificate from the shared folder on the local run
dotnet user-secrets set "Kestrel:Certificates:Default:Path" $pfxnewpath