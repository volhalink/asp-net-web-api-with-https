# ASP.NET Web API with HTTPS using self-signed certificates and docker-compose

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

[Kestrel needs certificate](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/kestrel/endpoints?view=aspnetcore-7.0) and a password it was signed with to work correctly with https. If certificate is not provided - application won't start:
![no certificate](/img/012.jpg)
And if the provided certificate is not trusted, there will be warning in the browser:
![connection is not private](/img/015.jpg)

See also: [Hosting ASP.NET Core images with Docker Compose over HTTPS](https://learn.microsoft.com/en-us/aspnet/core/security/docker-compose-https?view=aspnetcore-7.0)

Lets add another web api to the solution, so we can later test api calls from one container to another.

1. Create Api2 project, the same as Api1. 
2. And add container orchestration support the same way as for the first project (it will update docker-compose.yml and docker-compose.override.yml files).