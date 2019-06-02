# Running Hyperledger Explorer on Amazon Managed Blockchain

Customers want to visualise their Fabric networks on Amazon Managed Blockchain. Hyperledger Explorer is an open source browser for viewing activity on the underlying Fabric network. It offers a web application that provides a view into the configuration of the Fabric network (channels, chaincodes, peers, orderers, etc.), as well as the activity taking place on the network (transactions, blocks, etc.). It can be used with Amazon Managed Blockchain though it requires a few tweaks to get it working.

An Amazon Managed Blockchain network provisioned based on the steps in [Part 1](../ngo-fabric/README.md) is a pre-requisite. The steps in this README will provision and run the Hyperledger Explorer sync & web app components on the Fabric client node you created in [Part 1](../ngo-fabric/README.md).

Hyperledger Explorer consists of a few components:

* a database that stores the Fabric network configuration, such as peers, orderers, as well as details of the chaincodes, channels, blocks & transactions
* a 'sync' component that regularly queries the Fabric network for changes to the config and details of new transactions and blocks
* a web application the provides a view of the current network state

We will configure Hyperledger Explorer to use an Amazon RDS PostgreSQL instance so we can benefit from a managed database service, rather than running PostgreSQL locally. 

The instructions below are complete. You can refer to the instructions in the Hyperledger Explorer GitHub repo for reference, but you do not need to use them.

| RDS - PostgreSQL | Docker - PostgreSQL |
| --- | --- |
| [Pre-requisites](#pre-requisites) | (no change) |
| [Step 1 - Clone the appropriate version of the Hyperledger Explorer repository](#step-1---clone-the-appropriate-version-of-the-hyperledger-explorer-repository) | (no change) | 

## Pre-requisites

On the Fabric client node.

From Cloud9, SSH into the Fabric client node. The key (i.e. the .PEM file) should be in your home directory. 
The DNS of the Fabric client node EC2 instance can be found in the output of the AWS CloudFormation stack you 
created in [Part 1](../ngo-fabric/README.md)

```
ssh ec2-user@<dns of EC2 instance> -i ~/<Fabric network name>-keypair.pem
```

Install Node.js. You may have already done this, if you are running the REST API on the Fabric client node.

We will use Node.js v8.x.

```
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.0/install.sh | bash
```

```
. ~/.nvm/nvm.sh
nvm install lts/carbon
nvm use lts/carbon
```

Amazon Linux seems to be missing g++, so:

```
sudo yum install gcc-c++ -y
```

Install jq and PostgreSQL. We only really need the PostgreSQL client, but I install everything just in case I miss a dependency:

```
sudo yum install -y jq
sudo yum install -y postgresql postgresql-server postgresql-devel postgresql-contrib postgresql-docs
```

You will need to export a number of environment variables. The easiest way to do this is by simply sourcing the 
fabric-exports.sh file that you previously configured in Step 4 in [Part 1](../ngo-fabric/README.md):

```
cd ~/non-profit-blockchain/ngo-fabric
source fabric-exports.sh
```

## Step 1 - Clone the appropriate version of the Hyperledger Explorer repository

The GitHub repo for Hyperledger Explorer is here:

https://github.com/hyperledger/blockchain-explorer

Clone it:

```
cd ~
git clone https://github.com/hyperledger/blockchain-explorer
```

You want to check out the branch that is aligned to the version of Hyperledger Fabric you are using. Unfortunately, this isn't easy to determine in the repo. You can check the Releases section of the GitHub repo to see how the branches/tags align to the Fabric versions. Managed Blockchain is currently using v1.2 of Fabric, which aligns to the tag `v0.3.7.1`. You will check out this tag, which includes bug fixes applied to v1.2.

```
cd ~/blockchain-explorer
git checkout v0.3.7.1 
git status
```

## Step 2 - Create the Amazon RDS PostgreSQL instance used by Hyperledger Explorer

We will use CloudFormation to create our PostgreSQL RDS instance. We want the RDS instance in the same VPC as the Fabric client node.

```
cd ~/non-profit-blockchain/blockchain-explorer
./hyperledger-explorer-rds.sh
```

## Step 2 (Docker Postgres) -  Deploy Postgres Database as Docker

We can also use Docker`s official postgres image (https://hub.docker.com/_/postgres_) to persist FabricExplorer data, locally in the fabric client. You need PostgreSQL 9.5 or greater; therefore you can keep the latest image tag (at the time this piece is written the latest version was 11.3).

You may also want to create a dedicated folder to keep postgres database and docker configuration files. 

Create Postgres folders:
```
mkdir ~/postgres-fabricexplorer
mkdir ~/postgres-fabricexplorer/pgdata
```

We are going to keep the docker file for postgres simple; however you can further customize your deployment by following instructions in the link above. You can either create the file yourself; or use the file "postgres-compose.yml".

"postgres-compose.yml" file:
```
version: '3.1'

services:
  db:
    image: postgres
    restart: always
    environment:
      POSTGRES_USER: superuser
      POSTGRES_PASSWORD: superuser1234
    volumes:
      - ~/postgres-fabricexplorer/pgdata:/var/lib/postgresql/data
    ports:
      - 5432:5432
```

We can now start the postgres container in detached mode:

```
docker-compose -f ~/postgres-fabricexplorer/postgres-compose.yml up -d
```

The docker image will expose and map postgres port 5432 to the same port of the client. Please make sure to check container logs to see database is ready to accept connections:
```
docker ps
docker logs <postgres-container-id/name>
```


## Step 3 - Create the Hyperledger Explorer database tables in the PostgreSQL RDS database

Once step 2 has completed and your PostgreSQL instance is running, you will create tables in a PostgreSQL database. These tables are used by Hyperledger Explorer to store details of your Fabric network. Before running the script to create the tables, update the Hyperledger Explorer table creation script. The columns created by the script are too small to contain the long peer names used by Managed Blockchain, so we edit the script to increase the length:

```
sed -i "s/varchar(64)/varchar(256)/g" ~/blockchain-explorer/app/persistence/fabric/postgreSQL/db/explorerpg.sql
```

Update the Hyperledger Explorer database connection config with the Amazon RDS connection details. Replace the host, username and password with those you used when you created your PostgreSQL instance. These values can be obtained from the following:

* host: from the CloudFormation stack you created in step 2. See the output field: RDSHost, in the CloudFormation console.
* username & password: you either passed these into the creation of the stack in step 2, or you used the defaults. See the default values in hyperledger-explorer-cfn.yaml.

```
vi ~/blockchain-explorer/app/explorerconfig.json
```

Update the config file. I suggest you simply replace all the contents with the snippet below, then replace the 'host' property with your own:

```
{
  "persistence": "postgreSQL",
  "platforms": ["fabric"],
  "postgreSQL": {
    "host": "sd1erq6vwko24hx.ce2rsaaq7nas.us-east-1.rds.amazonaws.com",
    "port": "5432",
    "database": "fabricexplorer",
    "username": "master",
    "passwd": "master1234"
  },
  "sync": {
    "type": "local",
    "platform": "fabric",
    "blocksSyncTime": "3"
  }
}
```

Replace the contents of the table creation script so it looks as follows. You can simply replace all the contents with those below:

```
vi ~/blockchain-explorer/app/persistence/fabric/postgreSQL/db/createdb.sh
```

Update the script file:

```
#!/bin/bash
export CONN=$( jq -r .postgreSQL.conn ../../../../explorerconfig.json )
export HOSTNAME=$( jq -r .postgreSQL.host ../../../../explorerconfig.json )
export USER=$( jq -r .postgreSQL.username ../../../../explorerconfig.json )
export DATABASE=$(jq -r .postgreSQL.database ../../../../explorerconfig.json )
export PASSWD=$(jq .postgreSQL.passwd ../../../../explorerconfig.json | sed "y/\"/'/")
echo "USER=${USER}"
echo "DATABASE=${DATABASE}"
echo "PASSWD=${PASSWD}"
echo "CONN=${CONN}"
echo "HOSTNAME=${HOSTNAME}"
echo "Executing SQL scripts..."
psql -X -h $HOSTNAME -d $DATABASE --username=$USER -v dbname=$DATABASE -v user=$USER -v passwd=$PASSWD -f ./explorerpg.sql ;
psql -X -h $HOSTNAME -d $DATABASE --username=$USER -v dbname=$DATABASE -v user=$USER -v passwd=$PASSWD -f ./updatepg.sql ;
```

Now create the database tables. You will need to enter the password for the 'master' user, the same as you entered up above when editing 'explorerconfig.json'. You will need to enter this password for two different steps:

```
cd ~/blockchain-explorer/app/persistence/fabric/postgreSQL/db
./createdb.sh
```

If you need to connect to psql via the command line, use this (replacing the RDS DNS with your own):

```
psql -X -h sd1erq6vwko24hx.ce2rsaaq7nas.us-east-1.rds.amazonaws.com -d fabricexplorer --username=master 
```

## Step 3 (Docker Postgres) - Create the Hyperledger Explorer database tables in the PostgreSQL docker database
Once step 2 has completed and your PostgreSQL instance is running, you will create tables in a PostgreSQL database. These tables are used by Hyperledger Explorer to store details of your Fabric network. Before running the script to create the tables, update the Hyperledger Explorer table creation script. The columns created by the script are too small to contain the long peer names used by Managed Blockchain, so we edit the script to increase the length:

```
sed -i "s/varchar(64)/varchar(256)/g" ~/blockchain-explorer/app/persistence/fabric/postgreSQL/db/explorerpg.sql
```

Update the Hyperledger Explorer database connection config with the local postgresql docker details. Replace the host, username and password with those you used when you created your PostgreSQL instance. These values can be obtained from the following:

* host: docker postgres image is running in the client, localhost. Even though we have not made any changes to docker networking configuration; the localhost port 5432 is mapped to postgres image. 

* username & password: we setup superuser user&credentials in the docker compose file. 

```
vi ~/blockchain-explorer/app/explorerconfig.json
```

Update the config file. I suggest you simply replace all the contents with the snippet below, then replace the 'host' property and postgres user credentials with your own:

```
{
  "persistence": "postgreSQL",
  "platforms": ["fabric"],
  "postgreSQL": {
    "host": "localhost",
    "port": "5432",
    "database": "fabricexplorer",
    "username": "superuser",
    "passwd": "superuser1234"
  },
  "sync": {
    "type": "local",
    "platform": "fabric",
    "blocksSyncTime": "3"
  }
}
```

Replace the contents of the table creation script so it looks as follows. You can simply replace all the contents with those below:

```
vi ~/blockchain-explorer/app/persistence/fabric/postgreSQL/db/createdb.sh
```

Update the script file:

```
#!/bin/bash
export CONN=$( jq -r .postgreSQL.conn ../../../../explorerconfig.json )
export HOSTNAME=$( jq -r .postgreSQL.host ../../../../explorerconfig.json )
export USER=$( jq -r .postgreSQL.username ../../../../explorerconfig.json )
export DATABASE=$(jq -r .postgreSQL.database ../../../../explorerconfig.json )
export PASSWD=$(jq .postgreSQL.passwd ../../../../explorerconfig.json | sed "y/\"/'/")
echo "USER=${USER}"
echo "DATABASE=${DATABASE}"
echo "PASSWD=${PASSWD}"
echo "CONN=${CONN}"
echo "HOSTNAME=${HOSTNAME}"
echo "Executing SQL scripts..."
psql -X -h $HOSTNAME  --username=$USER -v dbname=$DATABASE -v user=$USER -v passwd=$PASSWD -f ./explorerpg.sql ;
psql -X -h $HOSTNAME  --username=$USER -v dbname=$DATABASE -v user=$USER -v passwd=$PASSWD -f ./updatepg.sql ;
```

Now create the database tables. You will need to enter the password for the 'superuser' user, the same as you entered up above when editing 'explorerconfig.json'. You will need to enter this password for two different steps:

```
cd ~/blockchain-explorer/app/persistence/fabric/postgreSQL/db
./createdb.sh
```

If you need to connect to psql via the command line, use this (replacing the RDS DNS with your own):

```
psql -X -h localhost -d fabricexplorer --username=superuser 
```

## Step 4 - Create a connection profile to connect Hyperledger Explorer to Amazon Managed Blockchain

Hyperledger Explorer uses a connection profile to connect to the Fabric network. If you have worked through Part 3 of this series you will have used connection profiles to connect the REST API to the Fabric network. As in part 3, I generate the connection profile here automatically, based on the ENV variables you populated in the pre-requisites section above (when you sourced fabric-exports.sh). The connection profile does assume that the MSP directory containing the keys and certificates is /home/ec2-user/admin-msp. If you are using a different directory you will need to update the connection profile.

```
cd ~/non-profit-blockchain/blockchain-explorer/connection-profile
./gen-connection-profile.sh
more ~/blockchain-explorer/app/platform/fabric/config.json
```

One difference between the connection profile used by Hyperledger Explorer compared to the profile used by the REST API, is that Hyperledger Explorer expects the peer name in the profile to be the full name of the peer, such as 'nd-mj2vophcizasdg5ssehagqe3n4.m-733fj7siwjavhmyj5z273dz7te.n-erwbh4ou2bhbzfbgnepspy3u5m.managedblockchain.us-east-1.amazonaws.com'. It's not just an ID that you choose. If you do not use the matching peer name you may see an error message when starting the Explorer, that looks like this: 'ReferenceError: host_port is not defined'

Depending on the version of Hyperledger Explorer you are using, you may have to update the config_ca.json file also. If the file does not exist, create it:

```
vi ~/blockchain-explorer/app/platform/fabric/config_ca.json
```

Update the config file:

```
{
  "enroll-id": "hlbeuser",
  "enroll-affiliation": ".department1",
  "admin-username": "admin",
  "admin-secret": "Adminpwd1!"
}
```

Now build Hyperledger Explorer:

```
nvm use lts/carbon
cd ~/blockchain-explorer
npm install
cd ~/blockchain-explorer/app/test
npm install
npm run test
cd ~/blockchain-explorer/client/
npm install
npm test -- -u --coverage
npm run build
```

## Step 5 - Run Hyperledger Explorer and view the dashboard

Run Hyperledger Explorer.

NOTE: depending on the version of Hyperledger Explorer you are using, you might need to use the ENV variable exported below (export DISCOVERY_AS_LOCALHOST=false), otherwise explorer uses the discovery service and assumes that all your Fabric components are being run in docker containers on localhost. 

```
nvm use lts/carbon
cd ~/blockchain-explorer/
export DISCOVERY_AS_LOCALHOST=false
./start.sh
```

The Hyperledger Explorer client starts on port 8080. You already have an ELB that routes traffic to this port. The ELB was created for you by the AWS CloudFormation template in step 2. Once the health checks on the ELB succeed, you can access the Hyperledger Explorer client using the DNS of the ELB. You can find the ELB endpoint using the key `BlockchainExplorerELBDNS` in the outputs tab of the CloudFormation stack.

## Step 6 - Use the Swagger Open API Specification UI to interact with Hyperledger Explorer
Hyperledger Explorer provides a RESTful API that you can use to interact with the Fabric network. Appending ‘api-docs’ to the same ELB endpoint you used in step 5 will display the Swagger home page for the API.

For example:

http://ngo-hyper-Blockcha-1O59LKQ979CAF-726033826.us-east-1.elb.amazonaws.com/api-docs

To use Swagger for live testing of the API, you will need to update the host property in swagger.json, pointing to your ELB DNS:

```
vi ~/blockchain-explorer/swagger.json
```

Update the 'host' property, using the same DNS as in step 5:

```
{
  "swagger": "2.0",
  "info": {
    "title": "Hyperledger Explorer REST API Swagger",
    "description": "Rest API for fabric .",
    "version": "1.0.0",
    "contact": {
      "name": "Hyperledger Team"
    }
  },
  "host": "ngo-hyper-Blockcha-1O59LKQ979CAF-726033826.us-east-1.elb.amazonaws.com",
```

After updating the file, restart Hyperledger Explorer, then navigate to the Swagger URL.

*If the Swagger UI is still pointing to localhost after you update swagger.json, you may need to rebuild Hyperledger Explorer, by following the build instructions in step 4*

## Step 7 - Keeping Hyperledger Explorer Running
Hyperledger Explorer runs on the Fabric client node. If you exit the SSH session on the Fabric client node, 
Hyperledger Explorer will automatically exit. You would need to restart it after SSH'ing back into 
the Fabric client node.

If you need to keep Hyperledger Explorer running after exiting the SSH session, you can use various methods to do this. I use `PM2`, using a command such as `pm2 start main.js`, which will keep the app running and restart it if it fails. The documentation for PM2 can be found here: http://pm2.keymetrics.io/docs/usage/quick-start/ 

Install PM2 as follows:

```
npm install pm2@latest -g
```

Then start Hyperledger Explorer:

```
nvm use lts/carbon
cd ~/blockchain-explorer/
export DISCOVERY_AS_LOCALHOST=false
rm -rf /tmp/fabric-client-kvs_peerOrg*
rm -rf ./tmp
pm2 start main.js
```

The PM2 logs can be found in `~/.pm2/logs`.

To restart Hyperledger Explorer after making changes:

```
nvm use lts/carbon
cd ~/blockchain-explorer/
export DISCOVERY_AS_LOCALHOST=false
rm -rf /tmp/fabric-client-kvs_peerOrg*
rm -rf ./tmp
pm2 restart main.js
```

To stop Hyperledger Explorer:

```
nvm use lts/carbon
cd ~/blockchain-explorer/
export DISCOVERY_AS_LOCALHOST=false
rm -rf /tmp/fabric-client-kvs_peerOrg*
rm -rf ./tmp
pm2 stop main.js
```

To remove the PM2 and Hyperledger Explorer logs:

```
rm ~/.pm2/logs/main*
rm ~/.pm2/logs/sync*
rm -rf ./logs
```
