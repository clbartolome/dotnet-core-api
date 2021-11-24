# OpenShift Demo

## 1. Dotnet Application

### 1.1. Code

The `C#` application used for this demo can be downloaded from the following url:

```sh
git clone https://github.com/Azure-Samples/dotnet-core-api 
```

To run it locally:

```sh
# Restore
dotnet restore

# Run
dotnet run     
```

Go to a web browser and open [this](http://localhost:5000/) url.

### 1.2. Docker

In order to run this application locally using docker include the following changes:

- Modify line *13* in `wwwroot/app/scripts/app.js` with the following code:
```js
        templateUrl: "/app/views/TodoList.html",
```

- Add the following `Dockerfile`:
```dockerfile
FROM mcr.microsoft.com/dotnet/core/aspnet:3.1-buster-slim AS base
WORKDIR /app
EXPOSE 5000
ENV ASPNETCORE_URLS=http://*:5000
 
FROM mcr.microsoft.com/dotnet/core/sdk:3.1-buster AS build
WORKDIR /src
COPY ["TodoApi.csproj", "./"]
RUN dotnet restore "./TodoApi.csproj"
COPY . .
WORKDIR "/src/."
RUN dotnet build "TodoApi.csproj" -c Release -o /app/build
 
FROM build AS publish
RUN dotnet publish "TodoApi.csproj" -c Release -o /app/publish
 
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "TodoApi.dll"]
```

- Add the following `.dockerignore`:
```
bin/
obj/
out/
```

Once these files are created/changed build and run Docker locally:

> Stop dotnet application if already running to avoid port already in use errors

```sh
# Build docker image
docker build --tag dotnet-api .

# Run docker image
docker run -d -p 5000:5000 4ccd56677415
```

Go to a web browser and open [this](http://localhost:5000/) url.

## 2. OpenShift

### 2.1. CLI

The easiest way to download the CLI is using the download link provided by the OpenShift cluster. This will ensure the version is the right one.

Build the following url with your cluster information:

```
https://downloads-openshift-console.apps.<cluster-dn>
```

Once the CLI is downloaded, [here](https://docs.openshift.com/container-platform/4.7/cli_reference/openshift_cli/getting-started-cli.html) are the instructions to configure it (change version if needed).

### 2.2. Deploy Dotnet API

#### 2.2.1. Project

Projects are used to organize and isolate application/team resources from other ones:

Find [here](https://docs.openshift.com/container-platform/4.7/applications/projects/working-with-projects.html) the documentation.

> Validate with cluster admins the default resources included in projects (network policies, limits, quotas,...)

Use the following commands to create a project:

```sh
# Create project
oc new-project ocp-demo

# Check if we are in the right project
oc project

# Get all project resources (now should be empty)
oc get all
```

#### 2.2.2. App Image

> OpenShift Image Registry will be used to store images.

OpenShift provide different ways to build images, for this demo the image is built using Docker strategy. [Here](https://docs.openshift.com/container-platform/4.7/openshift_images/create-images.html) is described all the different ways to build images in OpenShift.

Use the following commands to build the application using previously created Dockerfile:

```sh
# Go inside you application folder
# Create the new build
oc new-build --name dotnet-api --strategy docker --binary

# Start build and follow to see he result
# Image is created and pushed into internal registry
oc start-build dotnet-api --from-dir=. --follow

# Check there is a new Image Stream (latest)
oc get is

# Tag the image to the desired version
oc tag dotnet-api:latest dotnet-api:1.0

# Take a look at the Image Stream to see all avalilable references (tags)
oc get is dotnet-api -o yaml
```

#### 2.2.3. Deployment Config

In Openshift there are different strategies to deploy applications. Here are the strategies provided by default:

- Recreate
- Rolling
- Custom

This is the [link](https://docs.openshift.com/container-platform/4.7/applications/deployments/deployment-strategies.html) to OCP deployment strategies official documentation.

For this demo a Deployment config is used, find [here](https://docs.openshift.com/container-platform/4.7/applications/deployments/what-deployments-are.html) more information about deployments and deployment configs.

Use the following commands to create the deployment config:

```sh
# Create Deployment Config
cat << EOF >deployment-config.yaml
apiVersion: apps.openshift.io/v1
kind: DeploymentConfig
metadata:
  name: dotnet-api
spec:
  replicas: 1
  selector:
    deploymentconfig: dotnet-api
  strategy:
    type: Rolling
  template:
    metadata:
      labels:
        app: dotnet-api
        deploymentconfig: dotnet-api
        technology: dotnet
    spec:
      containers:
      - image: image-registry.openshift-image-registry.svc:5000/ocp-demo/dotnet-api:1.0
        imagePullPolicy: Always
        name: dotnet-api
        ports:
        - containerPort: 5000
          protocol: TCP
        resources: {}
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
      dnsPolicy: ClusterFirst
      restartPolicy: Always
      schedulerName: default-scheduler
      securityContext: {}
      terminationGracePeriodSeconds: 30
  test: false
  triggers:
  - type: ConfigChange
EOF

# Apply the created deployment config
oc apply -f deployment-config.yaml

# Watch pods creation
watch oc get pods

# Get the lis of pods
oc get pods

# Take a look at logs (follow option enabled)
oc logs -f <pod_id>

# Take a look at a pod (get and describe)
oc get pod <pod_id> -o yaml
oc describe pod <pod_id>

# Scale to 2 replicas
oc scale dc dotnet-api --replicas=3

# Check again the lis of pods
oc get pods
```

> It is recommended to use at least 2 replicas in development environment to ensure our application will able to manage multiple replicas.  

#### 2.2.4. Service

Services are used to provide a permanent IP to group of similar pods. Services have a DNS name internal to OS and Pods have access to it (`<service-name>.<project>.svc.cluster.local`).

Use the following commands to create a service:

```sh
# Create Service
cat << EOF >service.yaml
apiVersion: v1
kind: Service
metadata:
  name: dotnet-api
spec:
  ports:
  - port: 8080
    protocol: TCP
    targetPort: 5000
  selector:
    deploymentconfig: dotnet-api
EOF

# Apply Service
oc apply -f service.yaml

# Take a look at the new service
oc get svc

# Test connection inside Openshift Pod to the service (ip and internal DNS)
oc exec dotnet-api-<pod_id> -- curl http://<service-ip>:8080/api/todo

oc exec dotnet-api-<pod_id> -- curl -s http://<service>.<project>.svc.cluster.local:8080/api/todo
```


#### 2.2.5. Route

Routes are used to expose services outside the OpenShift cluster. [Here](https://docs.openshift.com/container-platform/4.7/networking/routes/route-configuration.html) is the route configuration documentation.

Use the following commands to create a route:

```sh
# Expose service using a route
# Create Route
cat << EOF >route.yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: todo-api
spec:
  port:
    targetPort: 5000
  to:
    kind: Service
    name: dotnet-api
    weight: 100
EOF

# Apply Route
oc apply -f route.yaml

# Get Route
oc get route
```

> Copy the route url and open it on a web browser to validate the deployment

### 2.3. Templates

Templates can be used to group all the resources needed to run an application in OpenShift. Parameters can also be included to make templates reusable between environments.

The following template can be used to deploy the previous application:

```yaml
apiVersion: v1
kind: Template
labels:
  app: ${APPLICATION_NAME}
objects:

# -- Deployment Config --
- apiVersion: apps.openshift.io/v1
  kind: DeploymentConfig
  metadata:
    name: ${APPLICATION_NAME}
    namespace: ${PROJECT_NAME}
  spec:
    replicas: 1
    selector:
      deploymentconfig: ${APPLICATION_NAME}
    strategy:
      type: Rolling
    template:
      metadata:
        labels:
          app: ${APPLICATION_NAME}
          deploymentconfig: ${APPLICATION_NAME}
          technology: dotnet
      spec:
        containers:
        - image: image-registry.openshift-image-registry.svc:5000/${PROJECT_NAME}/${IMAGE_STREAM_NAME}:${IMAGE_TAG}
          imagePullPolicy: Always
          name: ${APPLICATION_NAME}
          ports:
          - containerPort: 5000
            protocol: TCP
          resources: {}
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
        dnsPolicy: ClusterFirst
        restartPolicy: Always
        schedulerName: default-scheduler
        securityContext: {}
        terminationGracePeriodSeconds: 30
    test: false
    triggers:
    - type: ConfigChange

# -- Service --
- apiVersion: v1
  kind: Service
  metadata:
    name: ${APPLICATION_NAME}
    namespace: ${PROJECT_NAME}
  spec:
    ports:
    - port: 8080
      protocol: TCP
      targetPort: 5000
    selector:
      deploymentconfig: ${APPLICATION_NAME}

# -- Route --
- apiVersion: route.openshift.io/v1
  kind: Route
  metadata:
    name: ${APPLICATION_NAME}
    namespace: ${PROJECT_NAME}
  spec:
    port:
      targetPort: 5000
    to:
      kind: Service
      name: ${APPLICATION_NAME}
      weight: 100
      
parameters:
- description: Name of the project where the application has to be deployed
  displayName: Project name
  name: PROJECT_NAME
  required: true
- description: Name of the application
  displayName: Application name
  name: APPLICATION_NAME
  required: true
- description: Name of the image stream where to pull the docker image from (with no tag)
  displayName: Image stream name
  name: IMAGE_STREAM_NAME
  required: true
- description: Tag of the image stream to deploy as the version of the application for this deployment
  displayName: Image Tag
  name: IMAGE_TAG
  required: true
```

To dry-run this template:

```sh
oc process -f <template_name>.yaml -p PROJECT_NAME='ocp-demo' -p APPLICATION_NAME='dotnet-api' -p IMAGE_STREAM_NAME='dotnet-api' -p IMAGE_TAG='1.0'
```

To apply the template:
```sh
oc process -f <template_name>.yaml -p PROJECT_NAME='ocp-demo' -p APPLICATION_NAME='dotnet-api' -p IMAGE_STREAM_NAME='dotnet-api' -p IMAGE_TAG='1.0' | oc apply -f -
```

# BUILD TEST:

```sh
oc new-build --name dotnet-api --strategy docker --binary

oc patch bc dotnet-api --patch "{\"spec\":{\"strategy\":{\"dockerStrategy\":{\"dockerfilePath\":\"dotnet-core-api/Dockerfile\"}}}}"

oc start-build dotnet-api --from-dir=. --follow
```

