# Running Hyperledger Blockchain Explorer on Amazon Managed Blockchain

Hyperledger Blockchain Explorer is an open source browser for viewing activity on the underlying 
Fabric network. It can be used with Amazon Managed Blockchain though it requires a few tweaks to
get it working.

Hyperledger Blockchain Explorer consists of a few components:

* a database that stores the Fabric network configuration, such as peers, orderers, as well as details of the chaincodes, channels, blocks & transactions
* a 'sync' component that regularly queries the Fabric network for changes to the config and details of new transactions and blocks
* a web application the provides a view of the current network state

We will configure Hyperledger Blockchain Explorer to use an AWS RDS Postgres instance so we can benefit from a managed database service, rather than running Postgres locally. We will run the Explorer sync & web app components on the Fabric client node you cereated in [Part 1](../ngo-fabric/README.md).

The instructions below are complete. You can refer to the instructions in the Blockchain Explorer Git repo for reference, but you do not need to use them.

## Pre-requisites

On the Fabric client node.

From Cloud9, SSH into the Fabric client node. The key (i.e. the .PEM file) should be in your home directory. 
The DNS of the Fabric client node EC2 instance can be found in the output of the AWS CloudFormation stack you 
created in [Part 1](../coffee-fabric/README.md)

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

Install jq and postgress. We only really need the postgres client, but I install everything just in case I miss a dependency:

```
sudo yum install -y jq
sudo yum install -y postgresql postgresql-server postgresql-devel postgresql-contrib postgresql-docs
```

You will need to export a couple of environment variables. You can either do this by simply sourcing the 
fabric-exports.sh file below, if you have previously configured it in Step 4 in [Part 1](../ngo-fabric/README.md), 
or you can manually export the values. 

Either source the file:

```
cd ~/non-profit-blockchain/ngo-fabric
source fabric-exports.sh
```

or export the values:

```
export NETWORKNAME=<your Fabric network name, from the Managed Blockchain console>
export REGION=us-east-1
```

## Step 1 - Clone the Blockchain Explorer Git repo

The Git repo for Blockchain Explorer is here:

https://github.com/hyperledger/blockchain-explorer

Clone it:

```
cd ~
git clone https://github.com/hyperledger/blockchain-explorer
```

You want the branch that is aligned to the version of Hyperledger Fabric you are using. Unfortunately, this
isn't easy to determine in the repo. You can check the Releases section of the Github repo to see how the branches/tags
align to the Fabric versions. Managed Blockchain is currently using v1.2 of Fabric, so we will use the tag `v0.3.7.1`, 
which includes bug fixes applied to v1.2.

```
cd ~/blockchain-explorer
git checkout v0.3.7.1 
git status
```

## Step 2 - Create the Explorer Database

We will use CloudFormation to create our Postgres RDS instance. We want the RDS instance in the same VPC as the Fabric client node.

```
cd ~/non-profit-blockchain/blockchain-explorer
./blockchain-explorer-rds.sh
```

## Step 3 - Prepare Blockchain Explorer Postgres Database for use

Once step 2 has completed and your Postgres instance is running, you will create tables in a Postgres database. These tables are used by Blockchain Explorer to store details of your Fabric network. Before running the script to create the tables, update the Blockchain Explorer table creation script. The columns created by the script are too small to contain the long peer names used by Managed Blockchain, so we edit the script to increase the length:

```
sed -i "s/varchar(64)/varchar(256)/g" ~/blockchain-explorer/app/persistence/fabric/postgreSQL/db/explorerpg.sql
```

Update the Blockchain Explorer database connection config with the AWS RDS connection details. Replace the host, username and password with those you used when you created your Postgres instance. These values can be obtained from the following:

* host: from the CloudFormation stack you created in step 2. See the output field: RDSHost, in the CloudFormation console.
* username & password: you either passed these into the creation of the stack in step 2, or you used the defaults. See the default values in fabric-blockchain-explorer.yaml.

```
vi ~/blockchain-explorer/app/explorerconfig.json
```

Update the config file:

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

Replace the contents of the table creation script so it looks as follows. You can simply replace all the contents:

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

If you need to connect to psql via the command line, use this:

```
psql -X -h sd1erq6vwko24hx.ce2rsaaq7nas.us-east-1.rds.amazonaws.com -d fabricexplorer --username=master 
```

Now create the database tables. You will need to enter the password for the 'master' user, the same as you entered up above when editing 'explorerconfig.json':

```
cd ~/blockchain-explorer/app/persistence/fabric/postgreSQL/db
./createdb.sh
```

## Step 4 - Prepare Blockchain Explorer for use

Replace the contents of the Blockchain Explorer config file (the connection profile) so it looks as follows. You can simply replace all the contents with the template below, then replace the following values:

* organization and mspid, to match your member ID. This appears in a number of places
* channel name, if yours is different
* credentialStores, to match your member ID
* peer name, which appears in a number of place
* orderer endpoint
* CA endpoint

```
vi ~/blockchain-explorer/app/platform/fabric/config.json
```

Update the config file:

```
{
  "network-configs": {
    "network-1": {
      "version": "1.0",
      "clients": {
        "client-1": {
          "tlsEnable": true,
          "organization": "m-YB463PPN4NHH5AYGB4EIWKZVWE",
          "channel": "mychannel",
          "credentialStore": {
            "path": "./tmp/m-YB463PPN4NHH5AYGB4EIWKZVWE/credential",
            "cryptoStore": {
              "path": "./tmp/m-YB463PPN4NHH5AYGB4EIWKZVWE/crypto"
            }
          }
        }
      },
      "channels": {
        "mychannel": {
          "orderers": [
            "orderer"
          ],
          "peers": {
            "nd-7YLBQ3ZEWRE5RO7MFM2JOZFMAA.m-YB463PPN4NHH5AYGB4EIWKZVWE.n-RX5AFTAGIJDJPOYOBJMPAAJVHA.managedblockchain.us-east-1.amazonaws.com": {}
          },
          "connection": {
            "timeout": {
              "peer": {
                "endorser": "6000",
                "eventHub": "6000",
                "eventReg": "6000"
              }
            }
          }
        }
      },
      "organizations": {
        "m-YB463PPN4NHH5AYGB4EIWKZVWE": {
          "mspid": "m-YB463PPN4NHH5AYGB4EIWKZVWE",
          "fullpath": false,
          "adminPrivateKey": {
            "path": "/home/ec2-user/admin-msp/keystore"
          },
          "signedCert": {
            "path": "/home/ec2-user/admin-msp/signcerts"
          },
          "certificateAuthorities": ["ca-org1"],
          "peers": ["nd-7YLBQ3ZEWRE5RO7MFM2JOZFMAA.m-YB463PPN4NHH5AYGB4EIWKZVWE.n-RX5AFTAGIJDJPOYOBJMPAAJVHA.managedblockchain.us-east-1.amazonaws.com"]
        }
      },
      "peers": {
        "nd-7YLBQ3ZEWRE5RO7MFM2JOZFMAA.m-YB463PPN4NHH5AYGB4EIWKZVWE.n-RX5AFTAGIJDJPOYOBJMPAAJVHA.managedblockchain.us-east-1.amazonaws.com": {
          "tlsCACerts": {
            "path": "/home/ec2-user/managedblockchain-tls-chain.pem"
          },
          "url": "grpcs://nd-7YLBQ3ZEWRE5RO7MFM2JOZFMAA.m-YB463PPN4NHH5AYGB4EIWKZVWE.n-RX5AFTAGIJDJPOYOBJMPAAJVHA.managedblockchain.us-east-1.amazonaws.com:30003",
          "eventUrl": "grpcs://nd-7YLBQ3ZEWRE5RO7MFM2JOZFMAA.m-YB463PPN4NHH5AYGB4EIWKZVWE.n-RX5AFTAGIJDJPOYOBJMPAAJVHA.managedblockchain.us-east-1.amazonaws.com:30004",
          "grpcOptions": {
            "ssl-target-name-override": "nd-7YLBQ3ZEWRE5RO7MFM2JOZFMAA.m-YB463PPN4NHH5AYGB4EIWKZVWE.n-RX5AFTAGIJDJPOYOBJMPAAJVHA.managedblockchain.us-east-1.amazonaws.com",
            "discovery-as-localhost": "false"
          }
        }
      },
      "orderers": {
        "orderer": {
          "tlsCACerts": {
            "path": "/home/ec2-user/managedblockchain-tls-chain.pem"
          },
          "url": "grpcs://orderer.n-RX5AFTAGIJDJPOYOBJMPAAJVHA.managedblockchain.us-east-1.amazonaws.com:30001",
          "grpcOptions": {
            "ssl-target-name-override": "orderer.n-RX5AFTAGIJDJPOYOBJMPAAJVHA.managedblockchain.us-east-1.amazonaws.com"
          }
        }
      },
      "certificateAuthorities": {
        "ca-org1": {
          "url": "https://ca.m-YB463PPN4NHH5AYGB4EIWKZVWE.n-RX5AFTAGIJDJPOYOBJMPAAJVHA.managedblockchain.us-east-1.amazonaws.com:30002",
          "httpOptions": {
            "verify": false
          },
          "tlsCACerts": {
            "path": "/home/ec2-user/managedblockchain-tls-chain.pem"
          },
          "caName": "m-YB463PPN4NHH5AYGB4EIWKZVWE"
        }
      }
    }
  },
  "configtxgenToolPath": "/fabric-path/fabric-samples/bin",
  "license": "Apache-2.0"
}
```

Depending on the version of Blockchain Explorer you are using, you may have to update this file also:

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

Build Blockchain explorer:

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

## Step 4 - Run Blockchain Explorer

Run Blockchain explorer.

NOTE: depending on the version of Blockchain Explorer you are using, you might need to use the ENV variable below, otherwise explorer uses the discovery service and wonderfully assumes that all your Fabric components are being run in docker images on localhost. 

```
nvm use lts/carbon
cd ~/blockchain-explorer/
export DISCOVERY_AS_LOCALHOST=false
./start.sh
```

The Blockchain Explorer client starts on port 8080. You will already have an ELB that routes traffic to this port - it was created for you in step 1. Once the health checks on the ELB succeed, you can access the blockchain explorer client using the DNS of the ELB (which you will find in the outputs of your CloudFormation stack).
