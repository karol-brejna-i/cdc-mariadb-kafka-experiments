docker run --name mariadb -v $PWD/conf.d:/etc/mysql/conf.d -v $PWD/initdb.d:/docker-entrypoint-initdb.d -e MYSQL_ROOT_PASSWORD=test -d mariadb:10.2

