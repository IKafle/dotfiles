https://www.youtube.com/watch?v=3c-iBn73dDE&t=7221s

# Pulls the latest postgres image from the repository. (similar to github)
docker pull postgres

# Pulls the postgres image of given version
docker pull postgres:9.6

# docker checks this image locally, if not found, pulls from dockerhub and runs it 
docker run postgres

# List all the running containers
docker ps

OS have 2 layers
---------------------------------------------------------------------------------------------------
Applications | - Layer 2  app: applications run on the kernel layer. They are based on the kernel |
OS Kernel    | - Layer 1									  |
Hardware     | h/w : cpu, memory, I/O, etc							  |
---------------------------------------------------------------------------------------------------

Docker & Virtual box are both virtualization tools. Question is : what part of the OS does they virtualize ?
Ans : Docker virtualizes the Application layer. When you download the docker image, it actually contains the application layer of the OS and some other applications installed on top of it.
      The downloaded image uses the kernel of the host because it doesn't have its own kernel.

Ans: The Virtual box or VM  has the application layers layer and its own kernel. So it virtualizes the complete OS (Applications + Os Kernel). When you download a virtual machine image on your host, it doesn't use your host kernel.
     It puts up its own.


The differences between docker and VM ?

Size:
Size of docker image are much smaller (because they just have to implement one layer). Size are mostly in MB.
VM image size are much larger generally in GB.

Speed:
Docker containers are much faster than the VMs. Everytime you start VMs, they have to put the OS kernel and the applications on top of it.

Compatibility:
You can run VM image of any OS on any other Operating system host. But you can't do that with docker.

Whats the problem exactly here ?
Let's say you have a windows OS with a kernel and some applications and you wan't to run linux based docker image on that windows host. The problem here is that a Linux based docker image might not be compatible with the
windows kernel. This is actually true for windows versions below 10 (note: docker natively runs on windows 10)  and also for the old mac versions.Which if you have seen how to install docker on different Operating systems, you see that the first step is to check whether your hosts can actually run Docker natively.Which basically means is the kernel compatible with the docker images? so in that case, a workaround is that you install a technology called docker toolbox which abstracts way the kernel to make it possible for your hosts to run different docker images.
docker toolbox = bridge b/w your OS and docker which will enable you to run docker on your legacy computer.

How to install docker on different OS?
Ans : The installation will differ not only based on the OS, but also the version of the operating system.
      check the system requirements, OS versions etc based on the docker installation official documentations.
Generally, we use stable channel to download the docker binaries.

- Download and install docker
- enable/start the docker automatically on the system start up.

On windows ,check:
1. if your windows version is compatible with the docker
2. and the virtualization is enabled. (virtualization by default is always enabled other than you manually disabled it.)

To check if virtualization is enabled or not in your windows, goto task manager > performance tab -> cpu -> check the status of the Virtualization. (it is displayed as Virtualization: Enabled )


On Linux,
- Check the OS/System requirements
- Check if the older versions of the docker should be removed before installing a newer version.
- Check the supported storage drivers (if required)
- For different linux distribution, the installation steps will differ. Go explore the docker official installation documentation.



-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
									BASIC DOCKER COMMANDS
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Container vs Image :
- Container is an running environment of Image. Or running instance of an image.
- Container has a port (e.g : 5000 ) which makes it possible to talk to the application which is running inside the container.
- Container has its own abstraction of an operating system including the file system and the environment (which is off course different from the file system and the environment of the host)

e.g
|--------------------------------------------------|
|		    Container			   |
|						   |
| File System                Environment config    |
|       			     		   |------------|
|                   Application Image	           |PORT = 5000 |
|--------------------------------------------------|------------|

Images: all the artifacts that are in the dockerhub are images and not containers. e.g redis image, postgres image, etc.
images have different layers. when downloading an image from  docker hub, look at the different layers being downloaded.

# List all the docker images
- docker images Or docker image ls

TAG :
Images have TAG (or versions). latest is always the one that you get when you don't specify the version. If you have dependency on the specific version, you can actually choose the version you want and specified.


How to Run redis and connect your application to it.
Ans : Create the container of that Redis image that will make it possible to connect to the Redis application.

# Run the Redis container (container = running environment of an image)
# Redis container is run on the terminal on the Attached Mode.
- docker run redis (ctrl + c to stop the container)

# List all the running containers
- docker ps

# Delete the docker container
- docker rm <CONTAINER ID>

# Delete the docker image
- docker rmi <IMAGE ID>

# Run the container in the detached mode
- docker run -d redis (it will also give you the id of the running container)

# Stop the running container
- docker stop <ID of the container> (whole id is not required, just first few string of the ID suffices)

# Start the container
- docker start <ID of the container>

# History of all the docker containers
# List all the containers which are running or not running.
- docker ps -a

# Run multiple versions of the same image parallely.
- docker run redis:4.0 # Run the redis image of version 4.0
- docker run redis # Run the most latest version of redis image

run = checks the image in local host, if found runs it. If the image is not found, it then downloads it from the docker hub and runs the downloaded image.


How you can use the container that you just started?
docker ps # gives the port number on which the container is listening to the incoming requests.

If both the containers are running on the same port (port number given by docker ps command)

-Container is just the virtual environment running on your host.
- Multiple containers can run simultaneously on your host machine. Your host machine (e.g laptop, pc, server, etc) have certain ports available open for certain applications.

So how it works? (Container port Vs Host port)
- You need to create so-called binding between a port that your host machine has and the container.
- Conflict occurs when same port on the host machine is used by the multiple containers. BUT, reverse is possible. i.e, you can have two containers listening/running on the same port (e.g listening on port 3000) which is absolutely OK
  as long as you bind them to two different ports from your host machine.

Once the port binding between the host and the container is done, you can actually connect to the running container using the port of the host.

|------------------|
| Host Port : 3001 |
|------------------|
       |
       |
       |
      \|/
|-----------------------|
| container Port : 3000 | "app is running inside this container"
|-----------------------|

app://localhost:3001 ( when you point to host port 3001, the host port will forward that request to the container port. Inside that container port, "app" is running 
In this example, you would have some app localhost and then the port of the host. And the host will know how to forward the request to the container using the port binding.


How to create the binding between host port : 3001 and container port : 3000
- We can specify the binding of the port during the 'run' command

Run the first container (latest redis image)

# docker run -phost port : container port image
- docker run -p3001:3000 redis  
- docker ps # to check the bindings.

# In the detached mode
- docker run -p3001:3000 -d redis

Run the second container (redis image of version 4.0)

- docker run -p3002:3000 -d redis:4.0



-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
							Debugging containers
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
helps to get the logs of the container,
helps to get inside the container, get the terminal and execute some commands on it.

- docker logs <ID of the container>
- docker logs <NAME of the container> # if you don't want to remember the id of the container. You can get the name of the container from "docker ps or docker ps -a" command

Note:
When a container is created, you get the random names of the container.(shown by docker ps command).
The best way is to give your container a name in the "run" command using "--name" flag.
- docker run -p3001:3000 -d --name redis-older redis:4.0 (verify using "docker ps" command)

# Check the logs of the container
- docker logs redis-older


How to get the terminal of the running container?

# Get the interactive bash terminal inside the container.
- docker exec -it <ID of the container> /bin/bash  # here -it = interactive 
- exit # to exit the terminal.

OR using the name
- docker exec -it <NAME of the container> /bin/bash
- exit # to exit the interactive terminal

Since most of the container images are based on some lightweight linux distributions, you won't have much of the linux commands or applications installed here.
For e.g: applications like curl, httpie, etc are not installed by default. so you are little bit more limited in that sense. For most of the debugging work, it should be enough. :)



Docker run vs docker start

# create a new container
docker run : create a new container from an image. e.g : docker run redis:4.0

# restart a stopped container
docker start : with docker start, you are not working with the images but with the containers. e.g: docker start <ID of the container> or docker run <NAME of the container>

# Start the already created docker container which had a name redis-older.
# The container will retain all the attributes that we defined when creating the container using docker run. ( e.g  docker run -p3001:3000 -d --name redis-older redis:4.0)
- docker start redis-older # Just Run already created container



-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
							Docker Network
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

- Docker creates its isolated docker network where the containers are running in.
- Lets say we want to deploy two containers (mongodb, mongo express UI) in the same docker network, they can talk to each other using just the container name without localhost, port number, etc. They can do this because they are in the same docker network.
- And the application that runs outside of the docker such as NodeJs serverside application (which runs from the node server) is going to connect to them(mongodb and mongo express UI containers) from outside or from the host using localhost and the port number.


Later we can package our nodejs server side application into its own docker image.

Now we will have three docker images :
1. nodejs server side application,
2. mongo
2. mongo express UI


									Isolated Docker network
					|------------------------------------------------------------------------------------------|
					|										           |
					|     											   |
					|    index.htm,index.js                                                                    |                        
					|   |---------------|           |----------------|          |-------------------|          |
					|   | Node JS App   |           | Mongo DB       |          |Mongo Express UI   |          |
					|   | (backend)     |---------->|                |--------->|                   |          |
					|   |               |           |                |          |(docker hub image) |          |
					|   |---------------|           |----------------|          |-------------------|          |
					|   	   /|\						    				   |
					|	    |										   |
					|	    |										   |
					|	    |										   |
					|-----------|------------------------------------------------------------------------------|
						    |
                                                    |
						    |
						    |
   						    |
                                       |----------------------------|
				       |                            |
				       |	                    |
				       |   localhost:3000           |
				       |                            |
				       |          (Browser)	    |
				       |	host:port           |
				       |----------------------------|
				             Running on host machine (outside docker network)
						
- Docker bydefault already provides some network.

  # List the docker networks
- docker network ls

# Create a new docker network
- docker network create mongo-network


Add mongo db and mongo express UI containers to the mongo-network and run inside this network:
- Provide the network option when we run the container using the "docker run" command

# run mongo image inside user created mongo-network.
# visit the mongo documentation on the dockerhub for -e flags and other details. -e = environmental variable, see documentation for more details.
- docker run -p27017:27017 -d -e MONGO_INITDB_ROOT_USERNAME=admin -e MONGO_INITDB_ROOT_PASSWORD=password --name mongodb --net mongo-network

# run mongo db inside the user created mongo-network.
# here, ME_CONFIG_MONGODB_SERVER=mongodb, mongodb = container name of mongodb (which we have run on the above step)
- docker run -p8081:8081 -d -e ME_CONFIG_MONGODB_ADMINUSERNAME=admin -e ME_CONFIG_MONGODB_ADMINPASSWORD=password --name mongo-express --net mongo-network -e ME_CONFIG_MONGODB_SERVER=mongodb mongo-express

Any Way to automate this tideous process? we do not want to run "docker run " commands everysingle time.
Yes, Dockercompose!!

docker compose = structured way to contain very normal common docker commands.

----------------------------
mongo-docker-compose.yml
---------------------------

version:'3' # Version of the docker compose.
services:   # This is where the container list goes.
    mongodb: # Container with the name -> mongodb. It maps to the container name when the docker creates the container out of this blueprint.
        image:mongo # Image Name. Which image does the container is going to be built from.You can also specify the version here if you want.
	ports:
	    - 27017:27017 # Host : Container
	environment:
	    - MONGO_INITDB_ROOT_USERNAME=admin
	    - MONGO_INITDB_ROOT_PASSWORD=password
    mongo-express:
        image:mongo-express 
        ports:
            - 8081:8081
        environment:
            - ME_CONFIG_MONGODB_ADMINUSERNAME=admin
            - ME_CONFIG_MONGODB_ADMINPASSWORD=password 

Note : You might have noticed that, there is no docker network mentioned anywhere in the docker compose file. The dockercompose takes care of creating a common network for those containers by itself.
- docker network ls # check the network that docker compose has created.

# Start the docker containers using the docker compose
# Generally installing docker on your laptop, also installs docker compose package inside it. If it not the case, you might have to also install the docker compose by yourself.
- docker-compose -f mongo-docker-compose.yml up # -f = docker compose file, up = start all the containers which are in the .yml file.
- docker network ls # verify the name of the network created by the docker compose command.
- docker-compose -f mongo-docker-compose.yml down # It will go through all the containers and shut them all. It also removes the network but this network gets recreated on docker-compose up command.

Important!
The logs of all the containers defined inside the .yml file are mixed when starting containers with the docker compose-command because we are starting all containers at the same time.
If one container has a dependency with another then the dependent container will wait and try to reconnect with its dependency until successful connection is made. Until then, "connection refused" error gets shown in the log.

You can actually configure this waiting logic in the .yml file.


Note!
When you restart the containers, everything that you configured in that containers application is gone.So data is lost.There is no data persistance in the containers itself.
Solution = docker volumes for data persistence between the container restarts.


--------------------------------------------------------------------------------

   Build a docker image from NodeJs server side backend application - Dockerfile
---------------------------------------------------------------------------------
Simple text file which has to exactly named as "Dockerfile". 
Dockerfile: it is a blueprint for creating docker images.
Every docker image has a Dockerfile.
For more details, visit the docker file of any docker image on the github. (You will learn so much by doing this, so it is advised that you do so.)

-----------------
Dockerfile 
------------------
FROM node:13-alpine  # first line of every Dockerfile. syntax : FROM image:version.
           # Our backend app needs node inside our container so that it can run our node application instead of basing it on a linux alpine or some other lower level image because then we would have to install node ourselves on it.
	   # Hence, we are taking ready node image. goto docker hub and search "node" image on it.
#OPTIONAL: Configure environment variable inside our docker file
# Best practice : Define the environmental variable externally in a docker compose file. If something changes, you can override the dockercompose file instead of rebuilding the image.
ENV MONGO_INITDB_ROOT_USERNAME=admin \
    MONGO_INITDB_ROOT_PASSWORD=password

# using RUN, you can execute any linux commands.
RUN mkdir -p /home/app # This directory is going to live inside of the container and not in the host machine or laptop.

# COPY commands, actually executes on the host.
# The reason why we are not using linux 'cp' commands here is beacuse, it actually executes inside the docker container.
COPY . /home/app  #Copy files from current directory of host to /home/app of the container.

# Executes entry point linux command
# We have already installed node (using "FROM node" syntax on the first line of this Dockerfile), that is the reason why we can execute the command : node server.js as defined inside CMD array below.
CMD ["node", "server.js"] # this line translates to : node server.js (the command you run on the terminal to start the node js server)
                          # You can also execute a shell script (.sh) file instead of a seperate command.
RUN vs CMD:

CMD : entry point command. Hints the docker file that it should use CMD as an entry point to the application.
RUN : you can have multiple RUN commands with linux commands but CMD is just one.


Image layers on dockerfile (Simplified visualization)

alpine:3.10 <--- node:13-alpine <------ app:1.0

1. app: 1.0 # Our own image that we are building up with the version 1.0 is going to be based on a node image with the specific version 13-alpine.
2. node:13-alpine # MONGO_INITDB_ROOT_USERNAME=admin \
    MONGO_INITDB_ROOT_PASSWORD=password

# using RUN, you can execute any linux commands.
RUN mkdir -p /home/app # This directory is going to live inside of the container and not in the host machine or laptop.

# COPY commands, actually executes on the host.
# The reason why we are not using linux 'cp' commands here is beacuse, it actually executes inside the docker container.
COPY . /home/app  #Copy files from current directory of host to /home/app of the container.

# Executes entry point linux command
# We have already installed node (using "FROM node" syntax on the first line of this Dockerfile), that is the reason why we can execute the command : node server.js as defined inside CMD array below.
CMD ["node", "/home/app/server.js"] # this line translates to : node server.js (the command you run on the terminal to start the node js server)
                          # You can also execute a shell script (.sh) file instead of a seperate command.
RUN vs CMD:

CMD : entry point command. Hints the docker file that it should use CMD as an entry point to the application.
RUN : you can have multiple RUN commands with linux commands but CMD is just one.


Image layers on dockerfile (Simplified visualization)

alpine:3.10 <--- node:13-alpine <------ app:1.0

1. app: 1.0 # Our own image that we are building up with the version 1.0 is going to be based on a node image with the specific version 13-alpine.
2. node:13-alpine # node:13-alpine is going to be based on a alpine image with	the specific version 3.10
3. alpine:3.10 # Alpine is a lightweight based image

alpine:3.10 image that we install node on top of it and then we install our own application on top of it.


How to build image out of a Dockerfile?
syntax : docker build -t image-name:version <PATH of Dockerfile>

# Creates a docker image.
# Gives the id of the image once the command is completed.
- docker build -t my-app:1.0 . # my-app = image name
                               # . = current directory as the path of Dockerfile
# check the newly created image using the command
- docker image ls

Important!
- Whenever you make changes to the Dockerfile, you have to rebuild the image.
- To rebuild the docker image from Dockerfile, you have to first remove the docker container and then remove the docker image and then finally rebuild the docker image.


----------------------------
mongo-docker-compose.yml
---------------------------

version:'3' # Version of the docker compose.
services:   # This is where the container list goes.
     my-app:
        image: 664574038682.dkr.ecr.eu-central-1.amazonaws.com/my-app:1.0  # We have pushed our app image to aws ECR.
	       								   # Prerequisities: We need to set up the docker registry login and aws cli on the server, otherwise, the image will not be downloaded from the aws ECR
	ports:
	    - 3000:3000
    mongodb: # Container with the name -> mongodb. It maps to the container name when the docker creates the container out of this blueprint.
        image:mongo # Image Name. Which image does the container is going to be built from.You can also specify the version here if you want.
	ports:
	    - 27017:27017 # Host : Container
	volumes:
	    - db-data: /var/lib/mysql/data  #named volume
	environment:
	    - MONGO_INITDB_ROOT_USERNAME=admin
	    - MONGO_INITDB_ROOT_PASSWORD=password
    mongo-express:
        image:mongo-express 
        ports:
            - 8081:8081
        environment:
            - ME_CONFIG_MONGODB_ADMINUSERNAME=admin
            - ME_CONFIG_MONGODB_ADMINPASSWORD=password
volumes:     # At the end of docker compose file, on the save level as the services, you would actually list all the volumes that you have defined.
    db-data
     driver:local # additional information for docker to create that physical storage on a local file system.

Note !!

If all the containers are running inside the same docker network created by the docker-compose, you can refer the services using the  services (defined inside docker compose .yml ) instead of complete url (host:port)
For e.g:

# Mongo db service url hosted inside a docker container.
mongodb://admin:password@localhost:27017

# Much Better way
# mongodb = service name defined inside the docker compose .yml file.
# mongodb = name of the services that are defined inside services section of docker compose .yml file.
# services defined in .yml file are = [ my-app, mongodb, mongo-express ].
# here, host and port are replaced by the valid service name.
# This url will work inside your codebase, and everywhere as long as all the docker containers are running inside the same docker network.
mongodb://admin:password@mongodb



----------------------------
docker volumes
---------------------------
- Docker volumes are used for data persistence in docker.
- For databases, and other stateful applications, we should use docker volumes.
- inside docker containers, there could be virtual file system. /var/lib/mysql/data . mysql data are stored on this virtual location. The data gets removed when the container is restarted or removed. The container then starts from the fresh state.


Folder in physical host file system is mounted into the virtual file system of docker.


       	  	   	     	       |----------------------------|
                                       |                            |
                                       |                            |
                                       |   container                |
                                       |                            |
                                       |  /var/lib/mysql/data       |
                                       |                            |
                                       |----------------------------|
                                                  /|\
                                                   |
                                                   |
                                                   | Localhost actual folder is mounted to the container's virtual filesystem.
						   | Localhost actual folder path : /home/ishwor/mount/data
						   | Containers virtual file system path: /var/lib/mysql/data
                                                   |  
                                       |----------------------------|
                                       |                            |
                                       |                            |
                                       |   localhost                |
                                       |                            |
                                       |   /home/ishwor/mount/data  |
                                       |                            |
                                       |----------------------------|
                                            
- Containers write to its file system, it gets replicated or automatically written on the host file system directory and vice-versa.

3 Volume Types:
------------------

1. Host volume : you decide where on the host file system the reference is made (which folder on the host file system you mount into the container)
docker run -v /home/mount/data:/var/lib/mysql/data

2. Anonymous volumes: # You create a volume just by referencing the container directory. You don't specify which directory on the host should be mounted.
		      # Docker automatically creates the host directory in the path : /var/lib/docker/volumes/random-hash/_data. 
   	     	      # For each container, there will be a folder generated that gets mounted automatically to the container
docker run -v /var/lib/mysql/data

3. Named Volumes: # Improvement of anonymous volumes
   	 	  # Specifies the name of the folder on the host file system.
		  # You can reference the volume just by name so you don't have to know exactly the path.
docker run -v name:/var/lib/mysql/data # the name could be any logical name (host volume) and /var/lib/mysql/data is the path in the container.

Recommended volume type to use in the production : Named volume


data path in different db: Each data base have its own data path. so you have to find the right one.
for mysql : var/lib/mysql
for postgres: var/lib/postgresql/data
for mongo db : data/db


Where are the docker volumes located on our local machine?
- it actually differs between the operating system.
- Each volume will have its own hash

Windows:  C:\ProgramData\docker\volumes
Linux :  /var/lib/docker/volumes
Mac: /var/lib/docker/volumes



