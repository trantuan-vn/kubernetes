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

cd ~/utility/keycloak-2fa-sms-authenticator
mvn clean package 
kubectl cp /Users/cunkem/utility/keycloak-2fa-sms-authenticator/target/dasniko.keycloak-2fa-sms-authenticator.jar copy-pod:/mnt/data -n keycloak

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
# thiet lap authentication
##cach thiet lap dien thoai test tren sandbox
- https://aws.amazon.com/console/
- go sns trong search , chon Amazon Simple Notification Service
- chon Text messaging
- add phone trong sandbox
- verify phone
##cach lay access key va secret key cho sms trên aws
- https://aws.amazon.com/console/
- go iam trong search , chon Manage access to AWS resources
- chon users
- chon create user
- dat ten : sms-service-user
- set permission= Attach existing policies directly
- chon AmazonSNSFullAccess
- kich chon user sms-service-user
- chon tab Security credentials
- chon Create access key
- chon CLI
- Description tag value=sns
- download csv
## tao browser sms trusted-device
Chọn Authentication từ menu bên trái
tại tab Flows: duplicate browser dat ten "browser sms trusted-device"
xoa Condition - user configured
xoa OTP Form
trong subflow : browser sms trusted-device Browser - Conditional OTP 
    add step : Condition - Device Trusted (setting : Negate output= true)
    add step : SMS Authentication (AWS sms setting: SenderID=Keycloak (duoi 12 ky tu), AWS Access Key , AWS Secret Key , AWS Region)
    add step : Register Trusted Device
tại man hình flow, ấn ... tại "browser sms trusted-device" chọn bind flow, chọn Browser flow
# thiet lap email
## Chuẩn bị tài khoản Gmail
- https://myaccount.google.com/security
- bat 2FA
- kich vao 2-Step Verification
- chon app password
- tao app password= keycloak
- copy mat khau (luu cung aws access key)
## khai bao email tren keycloak
- Nhấn Realm Settings > Tab Email
Host: smtp.gmail.com
Port: 587 (dùng TLS).
From Display Name: Tên hiển thị trong email (ví dụ: Keycloak).
From: Địa chỉ email Gmail của bạn (ví dụ: tuanta2021@gmail.com).
Enable StartTLS: Bật (check vào ô này, vì Gmail dùng TLS).
Enable Authentication: Bật (check vào ô này).
Username: Địa chỉ email Gmail (ví dụ: tuanta2021@gmail.com).
Nếu dùng 2FA: Nhập App Password đã tạo ở bước chuẩn bị email
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

| Thành phần     | Tải vào từ Producer  | Tải ra cho Consumer | Tải Disk   | Tải RAM  | Tải Network |
| -------------- | -------------------  | ------------------- | ---------  | -------  | ----------- |
| **Broker**     | ✅ cao               | ✅ cao               | ❌ nhỏ     | ✅ trung | ✅ cao       |
| **BookKeeper** | ✅ rất cao           | ✅ cao               | ✅ rất cao | ✅ trung | ✅ trung     |
| **ZooKeeper**  | ❌ rất nhỏ           | ❌ rất nhỏ           | ❌ nhỏ     | ❌ nhỏ   | ❌ nhỏ       |

pulsar-admin topics set-retention gateway-requests-{0..999} --time 24h --size 2G
pulsar-admin topics set-retention gateway-responses-{0..999} --time 24h --size 2G
pulsar-admin topics set-retention dead-message-topic-{0..999} --time 24h --size 2G

tenant/project-name/
├── order/
├── wallet/
├── event/
├── audit/
├── error/
├── fraud/


persistent://exchange/order/input/group-<groupId>
persistent://exchange/order/priority/group-<groupId>
persistent://exchange/order/dead/group-<groupId>
persistent://exchange/result/symbol-<symbolId>
persistent://wallet/event/user-group-<groupId>
persistent://wallet/dead/user-group-<groupId>
persistent://audit/log/group-<groupId>
persistent://audit/event/symbol-<symbolId>
persistent://exchange/order/dead/group-<groupId>
persistent://wallet/dead/user-group-<groupId>

VD:
persistent://exchange/order/input/group-042
persistent://exchange/result/symbol-BTC-USDT
persistent://wallet/event/user-group-357
persistent://audit/log/group-042


Topic	                      Partition count	        Mục tiêu
order/input/group-*	        10–20 partitions	      Tăng parallelism
result/symbol-*	            3–5 partitions	        Tùy vào volume
wallet/event/user-group-*	  5–10 partitions	        Dễ scale theo region
audit/*	                    thường không cần	      Mostly append-only

Mỗi partition nên phục vụ tối đa khoảng 100–200 user/symbol active.
Cấu hình: retention 7 ngày, TTL 1 tuần.
Dùng Flink hoặc batch processor để re-process hoặc gửi alert.
Đảm bảo schema Protobuf rõ ràng:
  OrderMessage
  MatchResult
  WalletEvent
  AuditEvent

Ví dụ cho hệ thống của bạn (giả sử 1 triệu user, 2000 cặp symbol)
Tổng thể số topic:
Loại	                  Số lượng ước tính
order.input.group-*	    1000 group
order.priority.group-*	1000 group (nếu cần ưu tiên)
order.dead.group-*	    1000 group
result.symbol-*	        2000 symbol
wallet.event.group-*	  1000 group
wallet.dead.group-*	    1000 group
audit.log.group-*	      1000 group

Tổng ~7000–8000 topic, hoàn toàn ổn với Pulsar nếu bạn:
Sử dụng tiered storage (nếu cần log dài hạn).
Bật managedLedgerCacheEvictionWatermark hợp lý.
Dùng BookKeeper SSD disk (hoặc tiering S3).


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

#16 cilium and tunning linux stack
helm repo add cilium https://helm.cilium.io/
helm repo update
helm search repo cilium/cilium
helm install cilium cilium/cilium --version 1.17.3 \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$(minikube ip) \
  --set k8sServicePort=8443 \
  --set cni.exclusive=true
  --set bpf.masquerade=true \
  --set bpf.conntrack.gcInterval=30s \
  --set bpf.conntrack.maxStateSize=524288  

Chạy trên node server
1. ulimit -n
2. # /etc/systemd/system/containerd.service.d/override.conf
[Service]
LimitNOFILE=200000
3.  SYSCTL_CONF="/etc/sysctl.conf"
    TMP_CONF="/tmp/sysctl_custom.conf"
    cat <<EOF > "$TMP_CONF"
    # File/Connection limits
    fs.file-max = 2097152
    fs.nr_open = 2097152
    vm.max_map_count = 262144
    # TCP keepalive (duy trì kết nối sống)
    net.ipv4.tcp_keepalive_time = 30
    net.ipv4.tcp_keepalive_intvl = 10
    net.ipv4.tcp_keepalive_probes = 3
    # Port range mở rộng để nhiều kết nối outbound
    net.ipv4.ip_local_port_range = 10000 65535
    # TIME_WAIT reuse: tránh tốn slot
    net.ipv4.tcp_tw_reuse = 1
    net.ipv4.tcp_fin_timeout = 15
    # Backlog cho kết nối vào
    net.core.somaxconn = 65535
    net.ipv4.tcp_max_syn_backlog = 8192
    net.core.netdev_max_backlog = 65535
    # Syncookie (giảm SYN flood)
    net.ipv4.tcp_syncookies = 1
    # Tăng buffer TCP
    net.core.rmem_max = 16777216
    net.core.wmem_max = 16777216
    net.ipv4.tcp_rmem = 4096 87380 16777216
    net.ipv4.tcp_wmem = 4096 65536 16777216
    # Bypass reverse path filtering (tuỳ trường hợp)
    net.ipv4.conf.all.rp_filter = 0
    net.ipv4.conf.default.rp_filter = 0
    # Tăng connection tracking nếu có iptables/nftables
    net.netfilter.nf_conntrack_max = 2097152
    EOF
    for KEY in $(cut -d '=' -f 1 "$TMP_CONF" | xargs); do
      sed -i "/^$KEY\s*=/d" "$SYSCTL_CONF"
    done
    cat "$TMP_CONF" >> "$SYSCTL_CONF"
    sysctl -p "$SYSCTL_CONF"
    sudo systemctl daemon-reexec
    sudo systemctl daemon-reload
    sudo systemctl restart containerd    
  
#16 Tổ chức tunning hệ thống theo ai agent
ws-pulsar-aiops-platform/
├── helm/
│   ├── gateway/               # Chart cho WebSocket Gateway (Vert.x)
│   ├── pulsar/                # Apache Pulsar chart (bitnami hoặc streamnative)
│   ├── observability/         # Prometheus + Grafana
│   ├── kedascaler/            # KEDA setup + ScaledObjects
│   ├── robusta/               # Robusta automation
│   ├── keptn/                 # Keptn remediation workflow
│   └── opni/                  # Opni anomaly detection
├── langchain-agent/
│   ├── agent.py               # AI agent script
│   ├── tools/                 # Custom shell tools (scale pulsar, patch limit)
├── manifests/
│   ├── kustomize/             # Base + overlays for ArgoCD / FluxCD
├── dashboards/
│   ├── grafana/               # WS + Pulsar dashboards JSON
├── scripts/
│   └── bootstrap.sh           # Cài đặt nhanh toàn bộ stack
├── README.md

#17 haproxy
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm search repo bitnami/haproxy
helm pull bitnami/haproxy --version 2.2.21 
helm install haproxy ./haproxy --namespace haproxy

#18 GeoLite2-City
wget "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=&account_id=1172126&suffix=tar.gz" -O GeoLite2-City.tar.gz
tar -xzf GeoLite2-City.tar.gz


#100 echo Waiting for microservices to be installed... (Gradle 8.12.1, jdk 23, ndk;29.0.13113456)
flutter run -d chrome --web-port=59818
cd ./frontend
rm -rf android 
flutter create .
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

