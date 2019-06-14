#!/bin/bash

# Copyright 2018 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# 
# Licensed under the Apache License, Version 2.0 (the "License").
# You may not use this file except in compliance with the License.
# A copy of the License is located at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# or in the "license" file accompanying this file. This file is distributed 
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either 
# express or implied. See the License for the specific language governing 
# permissions and limitations under the License.


# Create dedicated folders to keep postgres database and docker configuration files.
echo Creating folders for PostgreSQL docker configuration and database files.
mkdir ~/postgres-fabricexplorer
mkdir ~/postgres-fabricexplorer/pgdata

# Create docker compose file
echo Creating docker-compose file for PostgreSQL.

cat <<EOF >~/postgres-fabricexplorer/postgres-compose.yml
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
EOF

ls -l ~/postgres-fabricexplorer

# Start Docker container
echo Starting Postres container.
docker-compose -f ~/postgres-fabricexplorer/postgres-compose.yml up -d

# Verify container is working and database has started accepting connections
echo Verifying Postgres container is up and accepting connections.

postgres_container_name=$(docker ps | grep -oP '(postgresf).*')
docker logs $postgres_container_name


