# k8s
#1.minikube
minikube start --memory=32768 --cpus=4 --disk-size=100g
minikube addons enable metrics-server
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

#7 echo Waiting for cert-manager to be installed...
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo update
helm search repo jetstack
helm pull jetstack/cert-manager --version 1.15.1 
helm install cert-manager ./cert-manager --namespace cert-manager --create-namespace --version v1.15.1 --set crds.enabled=true

#8 keycloak (FIDO2: https://www.youtube.com/watch?v=VAP4mc6R1Do)
cd ~/SmartConsultor/microservices/k8s 
kubectl apply -f 0_cert.yaml 
base64_data=$(kubectl get secret smartconsultor-certificate-tls -n istio-system -o jsonpath="{.data['ca\.crt']}")
echo $base64_data | base64 --decode > ca.crt (dua file nay vao trinh duyet vùng trust certificates để test)
kubectl apply -f /Users/cunkem/kubernetes/keycloak/other/jar_pvc.yaml
kubectl apply -f /Users/cunkem/kubernetes/keycloak/other/copy_pod.yaml
cd ~/utility/device-management 
mvn clean package (device-management)
kubectl cp /Users/cunkem/utility/device-management/target/device-management-1.0-SNAPSHOT.jar copy-pod:/mnt/data -n keycloak
kubectl cp /Users/cunkem/kubernetes/keycloak/other/device-theme copy-pod:/mnt/data -n keycloak

cd ~/utility/keycloak-spi-trusted-device/spi 
mvn clean package (spi-trusted-device)
kubectl cp /Users/cunkem/utility/keycloak-spi-trusted-device/spi/target/keycloak-spi-trusted-device-1.0-SNAPSHOT.jar copy-pod:/mnt/data -n keycloak

helm uninstall keycloak -n keycloak
helm install keycloak /Users/cunkem/kubernetes/keycloak --namespace keycloak
sudo kubectl port-forward svc/keycloak 443:443 -n keycloak --address $(ipconfig getifaddr en0)
sudo sed -i '' "/auth.smartconsultor.com/c\\
$(ipconfig getifaddr en0) auth.smartconsultor.com\\
" /etc/hosts
sudo minikube tunnel
trong /etc/hosts them dong "127.0.0.1 smartconsultor.com"

# thiet lap gia tri trong docker.json: 
1. Lấy thông tin realm-public-key
Đăng nhập vào giao diện quản trị của Keycloak.
Chọn realm mà bạn muốn lấy thông tin (ví dụ: master).
Chọn Realm Settings từ menu bên trái.
Chọn tab Keys.
Ở mục Active, bạn sẽ thấy danh sách các keys. Chọn RS256 (thường là loại mặc định) và sao chép giá trị của Public Key. Đây là giá trị realm-public-key.
2. Lấy thông tin resource (Client ID)
Trong giao diện quản trị của Keycloak, chọn realm của bạn (ví dụ: master).
Chọn Clients từ menu bên trái.
Chọn client mà bạn muốn lấy thông tin (ví dụ: 06bd4e91fadb).
Trong tab Settings, bạn sẽ thấy trường Client ID. Đây là giá trị resource.
3. Lấy thông tin secret
Trong giao diện quản trị của Keycloak, chọn realm của bạn (ví dụ: master).
Chọn Clients từ menu bên trái.
Chọn client mà bạn muốn lấy thông tin (ví dụ: 06bd4e91fadb).
Chọn tab Credentials.
Bạn sẽ thấy giá trị Secret. Đây là giá trị secret.

# Thiết lập url trên keycloak
Trong giao diện client , chọn client để kết nối (test)
Tại màn hinh setting: set 
- Valid redirect URIs bằng https://smartconsultor.com/callback (trùng với callback_url trong docker.json)
- Web origins bằng https://smartconsultor.com

# Thiết lập preferred_username
Trong giao diện client , chọn client để kết nối (test)
chọn tab client scope
chọn test-dedicated
chọn add mapper by configuration
chọn User Attributes
type name : preferred_username
chọn  User Attribute : username
type Token Claim Name: preferred_username
save
# google auth2 với keycloak
## lấy clientid, clientsecret trong google để tích hợp với google auth2
🔹 Bước 1: Truy cập Google Cloud Console
Mở Google Cloud Console: https://console.cloud.google.com/
Đăng nhập bằng tài khoản Google của bạn.
🔹 Bước 2: Chọn hoặc tạo một dự án
Ở góc trên cùng bên trái, nhấp vào danh sách dự án và chọn một dự án có OAuth2 đã được cấu hình.
Nếu chưa có, nhấp vào Tạo dự án mới và làm theo hướng dẫn.
🔹 Bước 3: Truy cập phần OAuth2 Credentials
Trong menu bên trái, chọn API & Services → Credentials.
Trong phần OAuth 2.0 Client IDs, bạn sẽ thấy danh sách các Client ID đã tạo.
Nếu chưa có, nhấp vào Create Credentials → chọn OAuth client ID.
Chọn loại ứng dụng (Web, Android, iOS, hoặc Desktop).
Điền thông tin cần thiết:
- Authorized JavaScript origins: https://auth.smartconsultor.com
- Authorized redirect URIs: https://auth.smartconsultor.com/realms/master/broker/google/endpoint
nhấp Create.
🔹 Bước 4: Lấy Client ID
Sau khi tạo, bạn sẽ thấy Client ID hiển thị ngay trên màn hình.
Bạn cũng có thể nhấp vào tên của OAuth Client để xem chi tiết Client ID & Client Secret.
## setting
vào màn hình Identity providers
chon google
điền Client ID & Client Secret của google
điền Scopes=openid profile email
chon tab mapper
add mapper
type name : preferred_username
chọn  User Attribute : username
save
# thiet lap theme
Chọn Realm Settings từ menu bên trái
Chọn tab Themes
Chọn Login theme là device-theme
save
# thiet lap authentication
Chọn Authentication từ menu bên trái
tại tab Flows: duplicate browser dat ten CustomDeviceFlow
add step : Custom Device Verification
add step : Conditional OTP Form
tại man hình flow, ấn ... tại CustomDeviceFlow chọn bind flow, chọn Browser flow
# thiet lap email


# thiet lap login 
Chọn Realm Settings từ menu bên trái
Chọn tab login
tick : User registration, Forgot password, Remember me, Verify email 









#9 infinispan
helm install infinispan ./infinispan --namespace infinispan

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

#16 echo Waiting for microservices to be installed...
cd ./frontend
flutter build web
#copy vào thư mục buid/web tới src/main/resources/webroot (gateway project)
#vào main.dart.js thay :
#https://www.gstatic.com/flutter-canvaskit/3f3e560236539b7e2702f5ac790b2a4691b32d49/ thay bằng canvaskit/
#https://fonts.gstatic.com/s/roboto/v20/KFOmCnqEu92Fr1Me5WZLCzYlKw.ttf thành assets/fonts/KFOmCnqEu92Fr1Me5WZLCzYlKw.ttf (trc do download file va copy vào thu muc assets/fonts)

cd ./backend
skaffold dev
#skaffold delete
kubectl port-forward service/gateway 8080:80

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

