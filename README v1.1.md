# k8s
#1.minikube
minikube start --memory=32768 --cpus=4 --disk-size=100g
#2.istio (istio-system)
istioctl install  
#3. tạo các namespace
kubectl create namespace cert-manager
kubectl create namespace keycloak
kubectl create namespace pulsar
kubectl create namespace infinispan
kubectl create namespace citus
kubectl create namespace microservices
kubectl create namespace redis
kubectl create namespace superset
kubectl create namespace bigdata
kubectl create namespace zookeeper
kubectl create namespace ignite



#4. tạo các serviceaccount
kubectl create serviceaccount cert-manager-controller -n cert-manager
kubectl create serviceaccount keycloak-admin -n keycloak
kubectl create serviceaccount pulsar-admin -n pulsar
kubectl create serviceaccount infinispan-user -n infinispan
kubectl create serviceaccount citus-user -n citus
kubectl create serviceaccount microservice-gateway -n microservices
kubectl create serviceaccount microservice-account -n microservices
#5. tạo các rolebinding
kubectl create rolebinding cert-manager-binding --clusterrole=admin --serviceaccount=cert-manager:cert-manager-controller -n cert-manager
kubectl create rolebinding keycloak-admin-binding --clusterrole=admin --serviceaccount=keycloak:keycloak-admin -n keycloak
kubectl create rolebinding pulsar-admin-binding --clusterrole=admin --serviceaccount=pulsar:pulsar-admin -n pulsar
kubectl create rolebinding infinispan-user-binding --clusterrole=edit --serviceaccount=infinispan:infinispan-user -n infinispan
kubectl create rolebinding citus-user-binding --clusterrole=edit --serviceaccount=citus:citus-user -n citus
kubectl create rolebinding microservice-gateway-binding --clusterrole=admin --serviceaccount=microservices:microservice-gateway -n microservices
kubectl create rolebinding microservice-account-binding --clusterrole=admin --serviceaccount=microservices:microservice-account -n microservices

#6 citus
kubectl apply -f citus/secrets.yaml 
kubectl apply -f citus/workers.yaml 
kubectl apply -f citus/master.yaml 
kubectl patch serviceaccount citus-user -n citus -p '{"secrets": [{"name": "citus-secrets"}]}'
kubectl exec -it citus-master-0 -n citus -- bash
-- master, all worker
psql -U postgres
CREATE USER smartconsultor WITH PASSWORD 'secret99';
ALTER USER smartconsultor SUPERUSER;
ALTER USER smartconsultor CREATEDB CREATEROLE;
CREATE DATABASE smartconsultor;
CREATE DATABASE superset;
CREATE DATABASE keycloak;
CREATE DATABASE metastore;


-- master, all worker
psql -U smartconsultor -d smartconsultor
CREATE SCHEMA standing;
CREATE SCHEMA history;
CREATE EXTENSION citus;

psql -U smartconsultor -d superset
CREATE EXTENSION citus;

--master 
psql -U smartconsultor -d smartconsultor
SELECT citus_set_coordinator_host('citus-master-0', 5432);
SELECT * from citus_add_node('citus-worker-0.citus-workers', 5432);
SELECT * from citus_add_node('citus-worker-1.citus-workers', 5432);
SELECT * FROM citus_get_active_worker_nodes();
ALTER SYSTEM SET citus.shard_replication_factor TO 2;
SELECT pg_reload_conf();

#7 keycloak
cd ~/SmartConsultor/microservices/k8s 
kubectl apply -f 0_cert.yaml 
base64_data=$(kubectl get secret smartconsultor-certificate-tls -n istio-system -o jsonpath="{.data['ca\.crt']}")
echo $base64_data | base64 --decode > ca.crt
helm install keycloak .\keycloak --namespace istio-system
sudo nano /etc/hosts #127.0.0.1 auth.smartconsultor.com
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder

#8 infinispan
helm install infinispan ./infinispan --namespace infinispan
#9 microservices
sudo kubectl port-forward svc/keycloak 443:443 -n keycloak  --address 192.168.220.190
sudo minikube tunnel

#10 pulsar
-- citus for pulsar
kubectl exec -it citus-master-0 -n citus -- psql -U smartconsultor -d smartconsultor -f - < ./k8s/pulsar/postgresql-schema.sql
-- install pulsar
helm repo add apache https://pulsar.apache.org/charts
helm search repo pulsar
helm repo update
helm pull apache/pulsar --version 3.5.0
helm install  pulsar ./pulsar --namespace pulsar
helm upgrade pulsar ./pulsar --namespace pulsar

#11 redis
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm search repo bitnami/redis
helm pull bitnami/redis
helm install redis ./redis --namespace redis

#12 superset
helm repo add superset https://apache.github.io/superset
helm repo update
helm search repo superset/superset
helm pull superset/superset --version 0.12.11 
helm install superset ./superset --namespace superset

#13 apache zookeeper
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm search repo bitnami/zookeeper
helm pull bitnami/zookeeper --version 13.4.12 
helm install zookeeper ./zookeeper --namespace zookeeper

#14 spark(spark-3.5.4-bin-hadoop3 voi hadoop 3.3.4) on hadoop(3.3.6)
#https://github.com/mjaglan/docker-spark-yarn-cluster-mode/blob/master/README.md
#https://www.linode.com/docs/guides/install-configure-run-spark-on-top-of-hadoop-yarn-cluster
cd bigdata/v2.3

docker build . -t hadoop-spark
docker tag hadoop-spark:latest tuantahp/hadoop-spark:latest
docker login
docker push tuantahp/hadoop-spark:latest

kubectl apply -f 0_hadoop-config.yaml
kubectl apply -f 1_hive-config.yaml
kubectl apply -f 1.1_spark-config.yaml
kubectl apply -f 2_hdfs-namenode-resourcemanager-service.yaml
kubectl apply -f 3_hdfs-namenode-resourcemanager-statefulset.yaml
kubectl apply -f 4_hdfs-datanode-nodemanager-service.yaml
kubectl apply -f 5_hdfs-datanode-nodemanager-statefulset.yaml

cd ..
cd jar-pvc
kubectl apply -f jar_pvc.yaml
kubectl apply -f copy_pod.yaml
kubectl cp ./jars namenode-resourcemanager-0:/tmp  -n bigdata
kubectl cp ./postgres.jar copy-pod:/mnt/data  -n bigdata

kubectl exec -it pod/namenode-resourcemanager-0  -n bigdata -- bash
hdfs dfs -mkdir -p /user/spark/spark-events
hdfs dfs -mkdir /user/spark/staging
hadoop fs -copyFromLocal /tmp/jars /user/spark/lib
hadoop fs -chmod 755 /user/spark/lib/*.jar
hdfs dfs -mkdir -p /user/hive/warehouse/tmp/hive

cd ..
cd v2.3
kubectl apply -f 6_hive-metastore-service.yaml
kubectl apply -f 7_hive-metastore-deployment.yaml
kubectl apply -f 8_hive-service.yaml
kubectl apply -f 9_hive-deployment.yaml
kubectl apply -f 10_spark_history_server.yaml

cd ..
cd jar-pvc
kubectl delete -f copy_pod.yaml
#15 ignite
cd k8s
helm install  ignite ./ignite
kubectl exec -n ignite ignite-0 -- /opt/ignite/apache-ignite/bin/control.sh --activate --user ignite --password ignite
kubectl exec -n ignite ignite-1 -- /opt/ignite/apache-ignite/bin/control.sh --activate --user ignite --password ignite
kubectl exec -n ignite ignite-0 -- /opt/ignite/apache-ignite/bin/control.sh --state  --user ignite --password ignite
kubectl exec -it -n ignite ignite-0 -- bash
./apache-ignite/bin/sqlline.sh --verbose=true -u jdbc:ignite:thin://127.0.0.1:10800/ -n ignite -p ignite 

# tao bang va data ban dau
## chay tren terminal
cd k8s/citus
java -jar ./create_tables_from_excel.jar --path ./tables_v7.xlsx  --version v1 --dbUrl jdbc:postgresql://localhost:5432/smartconsultor --dbUser smartconsultor
## chay cac cau sql nay tren citus
ALTER TABLE today.user
ADD COLUMN user_entity_id character varying(36);
ALTER TABLE today.user
ADD CONSTRAINT fk_user_entity
FOREIGN KEY (user_entity_id)
REFERENCES public.user_entity (id);
INSERT INTO today."user"(user_type, experience, investment_strategy, capital_scale, ethical_commitment, risk_profile, investment_budget, unpaid_fee, status, user_entity_id)
select 'Leader', 'Robot', 'Tìm kiếm giải pháp hiệu quả nhất theo cách cải tiến hàng ngày', 1000000000, 'Vì lợi ích của Follower', 'Xác suất thành công dựa trên số liệu công bố', null, 0, 0, id
from public.user_entity
where username='admin';
## chay tren terminal
java -jar ./create_data_from_excel.jar --path ./datas_v11.xlsx  --version v1 --dbUrl jdbc:postgresql://localhost:5432/smartconsultor --dbUser smartconsultor
kubectl cp ./create_pulsar_hadoop.jar  spark-history-server:/mnt/data -n bigdata
kubectl exec -it spark-history-server -n bigdata -- bash
spark-submit --class com.smartconsultor.PostgresToPulsar /mnt/data/create_pulsar_hadoop.jar
java --add-opens java.base/java.nio=ALL-UNNAMED -jar ./create_ignite_tables_from_excel.jar

## build spark
mvn clean package
zip -d target/exceltodb-1.0-SNAPSHOT.jar 'META-INF/*.SF' 'META-INF/*.DSA' 'META-INF/*.RSA'
kubectl cp target/exceltodb-1.0-SNAPSHOT.jar spark-history-server:/mnt/data -n bigdata
kubectl exec -it spark-history-server -n bigdata -- bash
spark-submit --class com.smartconsultor.PostgresToPulsar /mnt/data/exceltodb-1.0-SNAPSHOT.jar
## hive examples
beeline -u 'jdbc:hive2://localhost:10000' -n hadoop
show tables;
create table hive_example(a string, b int) partitioned by(c int);
alter table hive_example add partition(c=1);
insert into hive_example partition(c=1) values('a', 1);
select count(distinct a) from hive_example;
select sum(b) from hive_example;
drop table hive_example;

