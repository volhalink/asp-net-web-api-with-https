# ASP.NET Web API with HTTPS using self-signed certificates and docker-compose

* Host: Windows 10
* Containers: Debian 11 (the default for Docker image at the moment of writing, check [sdk image](https://hub.docker.com/_/microsoft-dotnet-sdk/) and [asp.net image](https://hub.docker.com/_/microsoft-dotnet-aspnet/))

## Creating a project

Lets create ASP.NET Core Web API project:

![default project's configuration on creation](/img/005.jpg)

By default, self-signed development cerificate for localhost is used. It is automatically created with `dotnet dev-certs` and you should trust it manually on the first start with the https configuration on your machine.

![trust the dev certificate](/img/016.jpg)

See: [dotnet dev-certs](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-dev-certs) and [Hosting ASP.NET Core images with Docker over HTTPS](https://learn.microsoft.com/en-us/aspnet/core/security/docker-https?view=aspnetcore-7.0) for more details.


We will also use docker-compose as a container orchestrator, so lets add it:

![container orchestration support](/img/006.jpg)
![docker compose](/img/007.jpg)
![linux](/img/008.jpg)

At the moment of writing, when we add docker-compose to the project, the asp.net https folder is mounted to the container in the configuration:

![mounting asp.net/https folder](/img/010.jpg)

Then, on the first run with docker compose, the self-signed certificate to use in docker container is automatically placed into this folder:

![certificate in asp.net/https folder](/img/009.jpg)

The password for this development cerificate is saved into user secrets:

![manage user secrets](/img/013.jpg)

![secrets.json](/img/014.jpg)

and `secrets.json` is also mounted to the container.

[Kestrel needs certificate and a password it was signed with](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/kestrel/endpoints?view=aspnetcore-7.0) to work correctly with https. If certificate is not provided - application won't start:

![no certificate](/img/012.jpg)

And if the provided certificate is not trusted, there will be warning in the browser:

![connection is not private](/img/015.jpg)

See also: [Hosting ASP.NET Core images with Docker Compose over HTTPS](https://learn.microsoft.com/en-us/aspnet/core/security/docker-compose-https?view=aspnetcore-7.0)

Lets add another web api to the solution, so we can later test api calls from one container to another.

1. Create Api2 project, the same as Api1. 
2. And add container orchestration support the same way as for the first project (it will update docker-compose.yml and docker-compose.override.yml files).

## Custom domain

The default development certificate is generated for the localhost only. So in case if we want to call the API in the container with its container name, or even better - from another container, we will need to create our own self-signed certificate and do a bit of configuration.

We have two standalone containers that need to communicate, so the default [network driver](https://docs.docker.com/network/) `bridge` is a perfect fit, but instead of running all the containers on the default network, we will create [user-defined bridge network](https://docs.docker.com/network/network-tutorial-standalone/#use-user-defined-bridge-networks) for better isolation.

![adding custom bridge network in docker-compose](/img/017.jpg)

The existing networks can be listed using `docker network ls` command and then inspected with `docker network inspect network_name` command.

New network with docker-compose project name and network name is created:

![list of networks](/img/018.jpg)


Note: We can specify more freindly compose container name by editing `docker-compose.dcproj` and adding `<DockerComposeProjectName>new-name</DockerComposeProjectName>`.


Now our two containers are connected via this new network:

![containers' network](/img/019.jpg)

And aren't connected to the default `bridge` network:

![bridge network](/img/020.jpg)


When we need to connect two services in different docker-compose projects we can connect to the `external` network of the other docker-compose like this:

```
networks:
  full-name-of-the-network-we-connect-to:
    external: true
```

where the full name is docker-compose-project-name_network-name in this example we created a network with the full name `dockercompose5890840066321555853_api`. See more on how to specify networks in docker-compose [here](https://docs.docker.com/compose/networking/#specify-custom-networks).

Now our containers can call each other via this new network using containers' names and their inner ports.

But the reality is, that generated https certificate works well when we call the api from the host, where it's trusted:

![certificate is valid](/img/021.jpg)

But fails verification during the call from another container:

![certificate is not valid](/img/022.jpg)

Two fix this, we will:

1. Generate new self-signed certificates for the apis with the containers' names as the domains.
2. Make them trusted on the host machine and in the containers.
3. Map container's ports to the host ports so we have the same urls when calling from the host or from another container.

### Generating self-signed sertificate for the project

See `create_dev_certificate.ps1` base script. We will need to call `create_api1_dev_certificate.ps1` and `create_api2_dev_certificate.ps1` from their projects' folders correspondingly (it's important because we set user secrets for the projects) and with admin rights as we set trusted certificates in this scripts.

Lets take a closer look on what's going on.

We need to pass 3 parameters to the base script:

```
param ($projectname, $domain, $pwdvalue)
```

First we convert plain text password to secure string so we can use it to sign the certificate.

```
$pwd = ConvertTo-SecureString -String $pwdvalue -Force -AsPlainText
```

Next we create the certificate itself for both our custom domain and `localhost`.

```
$cert = New-SelfSignedCertificate -DnsName $domain, "localhost" -CertStoreLocation "cert:\LocalMachine\My"
```

Newly created certificate is located at

```
$certpath = "cert:\LocalMachine\My\$($cert.Thumbprint)"
```

And we need to export 3 variants of it to a asp.net https folder mounted to docker containers

```
$sharedcertfolder = "$env:APPDATA\ASP.NET\Https"
$crtname = "$projectname.crt"
$pfxname = "$projectname.pfx"
$pemname = "$projectname.pem"
```

Why 3 certificates for one service?
* .pfx certificate contains private key and will be used by Kestrel
* .crt certificate doesn't contain private key - we will set it us trusted certificate on the host machine
* .pem - we need to trust the certificate inside the container and in case of Debian 11 we need the certificate in PEM format to do so.

So first we export .crt certificate and set it as trusted on our host machine:

```
$crtnewpath = Join-Path -Path $sharedcertfolder -ChildPath $crtname
#The private key is not included in the export
Export-Certificate -Cert $certpath -FilePath $crtnewpath
Import-Certificate -CertStoreLocation "Cert:\LocalMachine\Root" -FilePath $crtnewpath
```

Then we export the certificate in base64 format as .pem:

```
# Convert certificate raw data to Base64
$pemcert = @(
 '-----BEGIN CERTIFICATE-----'
 [System.Convert]::ToBase64String($cert.RawData, 'InsertLineBreaks')
 '-----END CERTIFICATE-----'
) 
# Output PEM file to the path
$pemnewpath = Join-Path -Path $sharedcertfolder -ChildPath $pemname
$pemcert | Out-File -FilePath $pemnewpath -Encoding ascii
```

Next we export .pfx certificate and sign it with the provided password:

```
$pfxnewpath = Join-Path -Path $sharedcertfolder -ChildPath $pfxname
#By default, extended properties and the entire chain are exported
Export-PfxCertificate -Cert $certpath -FilePath $pfxnewpath -Password $pwd
```

And finally, we set the password and .pfx certificate path in user secrets to override Kestrel defaults:

```
dotnet user-secrets init
dotnet user-secrets set "Kestrel:Certificates:Default:Password" $pwdvalue
# use the .pfx certificate from shared folder on local run
dotnet user-secrets set "Kestrel:Certificates:Default:Path" $pfxnewpath
```

This path from user secrets is correct in case of local run. But we need to override it once again in docker-compose to use the mounted folder insted:

![certificate path in docker-compose](/img/023.jpg)

Note: colon (:) separator [isn't supported](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/configuration/?view=aspnetcore-7.0#non-prefixed-environment-variables) in case of environment variables on Debian 11, we need to replace it with double underscore (__) which is then converted to colon (:) by asp.net core.


#### Use custom domains on host machine

Edit `C:\Windows\System32\drivers\etc\hosts` to add custom domains at the end of the file:

```
127.0.0.1 api1
127.0.0.1 api2
```

you'll need to run the editor with admin rights.

Then map containers' ports to the host's ports. Use the generated ports from the `launchSettings.json`. We can also remove http configuration and ports as we won't need them.

![launchSettings.json](/img/024.jpg)

![docker-compose.override.yml](/img/025.jpg)

We can also change localhost to our custom domain in the `launchSettings.json` to start the serivce with the curstom domain url locally.

Now if we run api2 locally and api1 in the container - we can get values from api1 in api2. But if we run both in the containers - we will still get the certificate error when trying to call api1 from api2.

So, last but not least:

#### Trust self-signed certificate in the container

On Debian 11 we can trust the self-signed certificate in few steps:

1. We need to put the previously generated PEM certificates into `/usr/local/share/ca-certificates/`
2. The tool we will use ignores files with `.pem` extension so we need to change it to `.crt`
3. And then we run `update-ca-certificates`

```
#!/bin/bash

# set develepment self-signed certificates as trusted
echo "coping certificates to ca-certificates directory"
cp /root/.aspnet/https/*.pem /usr/local/share/ca-certificates/

echo "changing certificate files' extension from .pem to .crt as .pem is ignored by the ca-certificates tool"
for f in /usr/local/share/ca-certificates/*.pem; do mv -- "$f" "${f%.pem}.crt"; done

echo "updating trusted certificates with the development self-signed certificates"
update-ca-certificates
```

As this certificates are needed only during the development, we won't change the `Dockerfile`. It would be nice to override docker-compose `entrypoint` with a custom script which installs certificates and then runs the app, but [Visual Studio overrides docker-compose file](https://github.com/microsoft/DockerTools/issues/9) for enabling debugging and any changes to the `entrypoint` both in Dockerfile and docker-compose will be ignored.

So for now we can run the script manually each time we recreate the container.

As soon as we run this script on api2's container - the api1's certificate becomes trusted and we can successfully call the api1 from api2.