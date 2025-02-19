-- master, all worker
psql -U postgres
CREATE USER smartconsultor WITH PASSWORD 'secret99';
ALTER USER smartconsultor SUPERUSER;
ALTER USER smartconsultor CREATEDB CREATEROLE;
CREATE DATABASE smartconsultor;
CREATE DATABASE superset;
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

--master
psql -U smartconsultor -d smartconsultor
SELECT schema_name
FROM information_schema.schemata;
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'standing' AND table_type = 'BASE TABLE';

CREATE TABLE standing.orders (
    order_id bigserial PRIMARY KEY,
    customer_id bigint,
    order_date date,
    amount numeric
);
SELECT create_distributed_table('standing.orders', 'order_id');

-- tao enduser chỉ có 1 số quyền cơ bản 
CREATE USER enduser WITH PASSWORD 'secret99';
ALTER ROLE enduser SET search_path TO standing, history, public;

GRANT USAGE ON SCHEMA standing TO enduser;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA standing TO enduser;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA standing TO enduser;


GRANT USAGE ON SCHEMA history TO enduser;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA history TO enduser;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA history TO enduser;









