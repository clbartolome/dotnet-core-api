FROM mcr.microsoft.com/dotnet/core/aspnet:3.1-buster-slim AS base
WORKDIR /app
EXPOSE 5000
ENV ASPNETCORE_URLS=http://*:5000

RUN echo $MODE
 
FROM mcr.microsoft.com/dotnet/core/sdk:3.1-buster AS build
WORKDIR /src
COPY ["TodoApi.csproj", "./"]
RUN dotnet restore "./TodoApi.csproj"
COPY dotnet-core-api .
WORKDIR "/src/."
RUN rm -rf obj bin out
RUN dotnet build "TodoApi.csproj" -c Release -o /app/build
 
FROM build AS publish
RUN dotnet publish "TodoApi.csproj" -c Release -o /app/publish
 
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "TodoApi.dll"]