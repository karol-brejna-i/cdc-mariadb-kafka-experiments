# Reading

http://debezium.io/docs/

https://github.com/debezium/docker-images

maybe this: http://debezium.io/blog/2016/05/31/Debezium-on-Kubernetes/

# Initial attempt
Let's check out how the examples work out of the box, then dig deeper.

Using this tutorial: http://debezium.io/docs/tutorial/


> I'll start MariaDBs, Zookeepers and other Kafkas from debezium images for now. If it works, I'll see how they differ from vanilla (original) images.

## Start Zookeeper

```
docker run --name zookeeper -p 2181:2181 -p 2888:2888 -p 3888:3888 --detach debezium/zookeeper:0.5
```

## Start Kafka
```
docker run --name kafka -p 9092:9092 --link zookeeper:zookeeper --detach debezium/kafka:0.5
```

> If we wanted to connect to Kafka from outside of a Docker container, then we’d want Kafka to advertise its address via the Docker host, which we could do by                            adding -e ADVERTISED_HOST_NAME= followed by the IP address or resolvable hostname of the Docker host, which on Linux or Docker on Mac this is the IP address of                            the host computer (not localhost).

## Start Mysql
```
docker run --name mysql -p 3306:3306 -e MYSQL_ROOT_PASSWORD=debezium -e MYSQL_USER=mysqluser -e MYSQL_PASSWORD=mysqlpw --detach debezium/example-mysql:0.5
```

## Access Mysql from CLI
```
docker run -it --rm --name mysqlterm --link mysql --rm mysql:5.7 sh -c 'exec mysql -h"$MYSQL_PORT_3306_TCP_ADDR" -P"$MYSQL_PORT_3306_TCP_PORT" -uroot -p"$MYSQL_ENV_MYSQL_ROOT_PASSWORD"'
```

## Start Kafka Connect
```
docker run --name connect -p 8083:8083 -e GROUP_ID=1 -e CONFIG_STORAGE_TOPIC=my_connect_configs -e OFFSET_STORAGE_TOPIC=my_connect_offsets --link zookeeper:zookeeper --link kafka:kafka --link mysql:mysql --detach debezium/connect:0.5
```

Now, that all the components are in place, I'll try to run debezium connector for mysql:

```
curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" localhost:8083/connectors/ -d '{ "name": "inventory-connector", "config": { "connector.class": "io.debezium.connector.mysql.MySqlConnector", "tasks.max": "1", "database.hostname": "mysql", "database.port": "3306", "database.user": "debezium", "database.password": "dbz", "database.server.id": "997", "database.server.name": "dbserver1", "database.whitelist": "inventory", "database.history.kafka.bootstrap.servers": "kafka:9092", "database.history.kafka.topic": "dbhistory.inventory" } }'
```

curl -s -X GET -H "Accept:application/json" localhost:8083/connectors | jq .

curl -s -X GET -H "Accept:application/json" localhost:8083/connectors/inventory-connector | jq .


docker run -it --name watcher --rm --link zookeeper:zookeeper debezium/kafka:0.5 watch-topic -a -k dbserver1.inventory.customers

# Monitor MariaDB
Debezium tutorial shows monitoring MySQL's CDC. Let's try to configure MariaDB to work with Debezium.

## Original MariaDB image
I plan to base on the original MariaDB image, so let's firstly check how the vanilla database behaves. 

Then, I'll check how to custom this image to work for me.

### Running MySQL/MariaDB
```
docker run --name mariadb -e MYSQL_ROOT_PASSWORD=test -d mariadb:10.2
```

### Running mysql cli
```
docker run -it --link mariadb:mysql --rm mysql sh -c 'exec mysql -h"$MYSQL_PORT_3306_TCP_ADDR" -P"$MYSQL_PORT_3306_TCP_PORT" -uroot -p"$MYSQL_ENV_MYSQL_ROOT_PA                           SSWORD"'
```

## Customizing MariaDB image
The changes that need to be done in order for debesium to work are:
* configure binlog (MariaDB startup configuration)
* adding grants for the user utilized by debezium connector (SQL DDL script)

I find the following passages of the image documentation to be music to my ears:
> The MariaDB startup configuration is specified in the file /etc/mysql/my.cnf,
> and that file in turn includes any files found in the /etc/mysql/conf.d directory that end with .cnf

> When a container is started for the first time, a new database with the specified name will be created [...].
> Furthermore, it will execute files with extensions .sh, .sql and .sql.gz that are found in /docker-entrypoint-initdb.d.

Most probably if I run maria container with proper volume mounting it should just work.

### MariaDB configuration
So, we need to prepare a config file (that will be mounted in /etc/mysql/conf.d) for enabling binary log.
It could look like this:

```
[mysqld]

# Enable binlog
server-id         = 997
log_bin           = mysql-bin
expire_logs_days  = 1
binlog_format     = row
```

Remember, you will be providing the server-id in connector config (http://debezium.io/docs/connectors/mysql/#configuration).


### SQL init script
The script that needs to be executed boils down to adding few grants to the user of choice.
For example:

```
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'batty' IDENTIFIED BY 'N6MAA10816';
```

Remember, you will be providing the user and password in connector config.

### Run
```
docker run --name mariadb -p 3306:3306 -v $PWD/conf.d:/etc/mysql/conf.d -v $PWD/initdb.d:/docker-entrypoint-initdb.d -e MYSQL_ROOT_PASSWORD=debezium -e MYSQL_USER=mysqluser -e MYSQL_PASSWORD=mysqlpw -d mariadb:10.2


docker run -it --link mariadb:mysql --rm mysql sh -c 'exec mysql -h"$MYSQL_PORT_3306_TCP_ADDR" -P"$MYSQL_PORT_3306_TCP_PORT" -uroot -p"$MYSQL_ENV_MYSQL_ROOT_PASSWORD"'

```

Start debezium images:
```
docker run --name zookeeper -p 2181:2181 -p 2888:2888 -p 3888:3888 --detach debezium/zookeeper:0.5

docker run --name kafka -p 9092:9092 --link zookeeper:zookeeper --detach debezium/kafka:0.5

docker run --name connect -p 8083:8083 -e GROUP_ID=1 -e CONFIG_STORAGE_TOPIC=my_connect_configs -e OFFSET_STORAGE_TOPIC=my_connect_offsets --link zookeeper:zookeeper --link kafka:kafka --link mariadb:mysql --detach debezium/connect:0.5

curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" 127.0.0.1:8083/connectors -d '{
  "name":"inventory-connector",
  "config":{
    "connector.class":"io.debezium.connector.mysql.MySqlConnector",
    "tasks.max":"1",
    "database.hostname":"mysql",
    "database.port":"3306",
    "database.user":"debezium",
    "database.password":"dbz",
    "database.server.id":"997",
    "database.server.name":"dbserver1",
    "database.whitelist":"inventory",
    "database.history.kafka.bootstrap.servers":"kafka:9092",
    "database.history.kafka.topic":"dbhistory.inventory"
  }
}'


```


curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" localhost:8083/connectors -d '{
  "name":"inventory-connector",
  "config":{
    "connector.class":"io.debezium.connector.mysql.MySqlConnector",
    "tasks.max":"1",
    "database.hostname":"28dfc1a5f493",
    "database.port":"3306",
    "database.user":"debezium",
    "database.password":"dbz",
    "database.server.id":"997",
    "database.server.name":"dbserver1",
    "database.whitelist":"inventory",
    "database.history.kafka.bootstrap.servers":"kafka:9092",
    "database.history.kafka.topic":"dbhistory.inventory"
  }
}'
