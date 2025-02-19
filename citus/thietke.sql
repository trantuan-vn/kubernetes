-- các bảng cơ sở

CREATE TABLE sqls (
    sql_id SERIAL PRIMARY KEY,
    sql_name VARCHAR(255) UNIQUE NOT NULL,
    sql_string TEXT  NOT NULL -- Câu SQL chứa các tham số dạng placeholder "?", ví dụ "insert into A(f1,f2,f3) values (?field_id,?field_id,?field_id)" , trong đó "?field_id" tương ứng với field_id trong bảng business_fields
);

CREATE TABLE actions (
    action_id SERIAL PRIMARY KEY,
    action_name VARCHAR(255) UNIQUE NOT NULL, 
    action_label VARCHAR(255) NOT NULL
);

CREATE TABLE actions_sqls (
    action_sql_id SERIAL PRIMARY KEY,
    action_id INT REFERENCES actions(action_id),
    sql_id INT REFERENCES sqls(sql_id),
    sql_order INT  NOT NULL
);
/*
-- các bảng màn hình
CREATE TABLE screens (
    screen_id SERIAL PRIMARY KEY,
    screen_name VARCHAR(255) UNIQUE NOT NULL,
    screen_label VARCHAR(255) NOT NULL,
    is_approved BOOLEAN DEFAULT FALSE, -- TRUE: cần duyệt
    microservice_name VARCHAR(255) NOT NULL -- tên microservice xử lý
);

CREATE TABLE screen_groups (
    group_id SERIAL PRIMARY KEY,
    screen_id INT REFERENCES screens(screen_id),
    group_name VARCHAR(255) UNIQUE NOT NULL,
    group_label VARCHAR(255),
    group_order INT NOT NULL -- thứ tự xuất hiện của group trên màn hình screen_id
);

CREATE TABLE screen_groups_fields (
    groups_fields_id SERIAL PRIMARY KEY,
    group_id INT REFERENCES screen_groups(group_id),
    field_id INT REFERENCES business_fields(field_id),
    field_order INT NOT NULL -- thứ tư trường trong group
);

CREATE TABLE screen_actions (
    screen_action_id SERIAL PRIMARY KEY,
    screen_id INT REFERENCES screens(screen_id),
    action_id INT REFERENCES actions(action_id),
    action_label VARCHAR(255) NOT NULL,
    action_order INT NOT NULL -- thứ tự xuất hiện của action trên screen
);
*/
CREATE TABLE screen_actions (
    screen_action_id SERIAL PRIMARY KEY,
    table_id INT REFERENCES business_tables(table_id),
    action_id INT REFERENCES actions(action_id),
    action_label VARCHAR(255) NOT NULL,
    action_order INT NOT NULL -- thứ tự xuất hiện của action trên screen
);

-- các bảng ghi log
-- log giao dịch trong ngày
-- CREATE TABLE transaction_logs (
--    log_id SERIAL PRIMARY KEY,
--    screen_action_id INT REFERENCES screen_actions(screen_action_id),
--    status VARCHAR(50) NOT NULL, -- Trạng thái của giao dịch ('pending', 'approved', 'rejected', etc.)
--    field_values JSONB -- Lưu trữ giá trị của các trường dưới dạng JSON
--);

CREATE TABLE business_tables (
    table_id SERIAL PRIMARY KEY,
    table_name VARCHAR(255) UNIQUE NOT NULL, -- Tên bảng (users, groups, ...)
    table_label VARCHAR(255) NOT NULL,
    is_archive BOOLEAN DEFAULT TRUE,
    description VARCHAR(255)          -- Mô tả bảng
);

CREATE TABLE business_fields (
    field_id SERIAL PRIMARY KEY,
    -- thông tin trường trong bảng
    table_id INT NOT NULL REFERENCES business_tables(table_id), -- Liên kết với bảng business_tables
    field_name VARCHAR(255) NOT NULL,                 -- Tên trường
    field_type VARCHAR(50) NOT NULL,                  -- Kiểu dữ liệu của trường (VARCHAR, INT, etc.)
    is_primary_key BOOLEAN DEFAULT FALSE,             -- Có phải khóa chính không
    is_nullable BOOLEAN DEFAULT TRUE,                 -- Có cho phép NULL không
    default_value VARCHAR(255),                        -- Giá trị mặc định
    -- flutter screen
    label VARCHAR(255) NOT NULL,      -- Nhãn của trường (hiển thị trên giao diện)
    is_required BOOLEAN DEFAULT FALSE,-- Trường có bắt buộc nhập không
    default_value TEXT,               -- Giá trị mặc định nếu có
    options JSONB,                    -- Tùy chọn thêm (dành cho combo)
    is_hidden BOOLEAN DEFAULT FALSE
    -- Thông tin về foreign key
    is_foreign_key BOOLEAN DEFAULT FALSE, -- Trường này có phải khóa ngoại không
    referenced_table_id INT REFERENCES business_tables(table_id), -- Bảng mà khóa ngoại tham chiếu đến
    referenced_field_id INT REFERENCES business_fields(field_id), -- Tên trường trong bảng được tham chiếu    
    -- Ràng buộc UNIQUE cho table_id và field_name
    CONSTRAINT business_fields_unique_table_id_field_name UNIQUE (table_id, field_name),
    -- Ràng buộc kiểm tra khi is_foreign_key = TRUE, referenced_table_id và referenced_field_id phải NOT NULL
    CONSTRAINT foreign_key_check CHECK (
        (is_foreign_key = FALSE) OR 
        (is_foreign_key = TRUE AND referenced_table_id IS NOT NULL AND referenced_field_id IS NOT NULL)
    )        
);

CREATE TABLE business_table_uniques (
    unique_id SERIAL PRIMARY KEY,
    table_id INT NOT NULL REFERENCES business_tables(table_id), -- Liên kết với bảng business_tables
    field_id INT NOT NULL REFERENCES business_fields(field_id)
);
# Cài đặt pg_partman extension
CREATE EXTENSION pg_partman;

CREATE OR REPLACE FUNCTION generate_table() RETURNS VOID AS $$
DECLARE
    record_a RECORD;
    field_record RECORD;
    create_sql TEXT;
    archive_sql TEXT;
    trigger_sql TEXT;
    table_name_var TEXT;
    field_name_var TEXT;
    primary_field_name TEXT;
    year_part INT;
BEGIN
    FOR record_a IN (SELECT * FROM business_tables) LOOP
        -- Tạo câu lệnh CREATE TABLE cho bảng chính
        create_sql := 'CREATE TABLE IF NOT EXISTS ' || record_a.table_name || ' (';
        FOR field_record IN (SELECT * FROM business_fields WHERE table_id = record_a.table_id) LOOP
            create_sql := create_sql || field_record.field_name || ' ' || field_record.field_type;
            IF field_record.is_primary_key THEN
                create_sql := create_sql || ' PRIMARY KEY';
                primary_field_name := field_record.field_name;  -- Ghi lại tên khóa chính
            END IF;
            IF NOT field_record.is_nullable THEN
                create_sql := create_sql || ' NOT NULL';
            END IF;
            IF field_record.default_value IS NOT NULL THEN
                create_sql := create_sql || ' DEFAULT ' || field_record.default_value;
            END IF;
            IF field_record.is_foreign_key THEN
                SELECT table_name INTO table_name_var 
                FROM business_tables WHERE table_id = field_record.referenced_table_id; 
                SELECT field_name INTO field_name_var 
                FROM business_fields WHERE field_id = field_record.referenced_field_id; 
                create_sql := create_sql || ' REFERENCES ' || table_name_var || '(' || field_name_var || ')';
            END IF;
            create_sql := create_sql || ', ';
        END LOOP;
        create_sql := RTRIM(create_sql, ', ') || ');';
        -- Thực hiện tạo bảng chính
        EXECUTE create_sql;

        -- Nếu bảng có is_archive = true, tạo bảng archive
        IF record_a.is_archive THEN
            archive_sql := 'CREATE TABLE IF NOT EXISTS ' || record_a.table_name || '_archive (';
            archive_sql := archive_sql || record_a.table_name || '_archive_id SERIAL PRIMARY KEY, ';  -- Thêm trường khóa chính
            FOR field_record IN (SELECT * FROM business_fields WHERE table_id = record_a.table_id) LOOP
                archive_sql := archive_sql || field_record.field_name || ' ' || field_record.field_type || ', ';
            END LOOP;
            -- Thêm trường archived_at và tạo ràng buộc unique
            --archive_sql := archive_sql || 'archived_at TIMESTAMP NOT NULL DEFAULT NOW()) PARTITION BY RANGE (EXTRACT(YEAR FROM archived_at));';
            archive_sql := archive_sql || 'archived_at TIMESTAMP NOT NULL DEFAULT NOW());';
            -- Thực hiện tạo bảng archive
            EXECUTE archive_sql;

            -- Tạo partition dựa trên năm hiện tại
            --year_part := EXTRACT(YEAR FROM NOW());
            --partition_sql := 'CREATE TABLE IF NOT EXISTS ' || record_a.table_name || '_archive_' || year_part;
            --partition_sql := partition_sql || ' PARTITION OF ' || record_a.table_name || '_archive ';
            --partition_sql := partition_sql || 'FOR VALUES FROM (' || year_part || ') TO (' || (year_part + 1) || ');';
            --EXECUTE partition_sql;

            SELECT partman.create_parent(
                p_parent_table := record_a.table_name || '_archive',
                p_control := 'archived_at',
                p_type := 'time',
                p_interval := '3 months'
            );
            -- Chạy bảo trì pg_partman để tự động tạo partition mới
            SELECT run_maintenance(record_a.table_name || '_archive');

            -- Tạo trigger cho bảng chính để lưu dữ liệu vào bảng archive khi có thay đổi
            trigger_sql := 'CREATE TRIGGER trigger_' || record_a.table_name || '_archive ';
            trigger_sql := trigger_sql || 'BEFORE UPDATE OR DELETE ON ' || record_a.table_name || ' ';
            trigger_sql := trigger_sql || 'FOR EACH ROW EXECUTE FUNCTION archive_old_data(''' || record_a.table_name || ''');';
            
            -- Thực hiện tạo trigger
            EXECUTE trigger_sql;
        END IF; 
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION archive_old_data(table_name TEXT) RETURNS TRIGGER AS $$
DECLARE
    archive_sql TEXT;
    record_a RECORD;
BEGIN
    -- Xây dựng câu lệnh INSERT INTO cho bảng archive dựa trên table_name
    archive_sql := 'INSERT INTO ' || table_name || '_archive (';
    
    -- Lấy các tên cột từ bảng chính
    FOR record_a IN (SELECT column_name 
                    FROM information_schema.columns 
                    WHERE table_name = table_name 
                    AND column_name != 'archived_at' 
                    AND column_name != (table_name || '_archive_id')) LOOP  -- Bỏ qua cột archived_at và _archive_id
        archive_sql := archive_sql || record_a.column_name || ', ';
    END LOOP;
    
    -- Loại bỏ dấu phẩy cuối cùng và thêm cột archived_at
    archive_sql := RTRIM(archive_sql, ', ') || ') VALUES (';
    
    -- Thêm giá trị tương ứng từ OLD (dữ liệu cũ trước khi UPDATE/DELETE)
    FOR record_a IN (SELECT column_name 
                    FROM information_schema.columns 
                    WHERE table_name = table_name 
                    AND column_name != 'archived_at' 
                    AND column_name != (table_name || '_archive_id')) LOOP  -- Bỏ qua cột archived_at và _archive_id
        archive_sql := archive_sql || 'OLD.' || record_a.column_name || ', ';
    END LOOP;
    
    -- Thêm giá trị archived_at là thời gian hiện tại
    archive_sql := RTRIM(archive_sql, ', ') || ');';

    -- Thực hiện câu lệnh INSERT INTO để lưu trữ dữ liệu cũ vào bảng archive
    EXECUTE archive_sql;
    
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_unique_constraint() RETURNS VOID AS $$
DECLARE
    record_table RECORD;
    record_field RECORD;
    unique_field_names TEXT := '';
    constraint_name TEXT;
    archive_constraint_name TEXT;
    field_names TEXT;
    archive_field_names TEXT;
    is_archive BOOLEAN;
BEGIN
    -- Lặp qua các bảng có unique_order trong bảng business_table_uniques
    FOR record_table IN (
        SELECT table_id
        FROM business_table_uniques 
        GROUP BY table_id
    ) LOOP
        -- Lấy tên bảng và kiểm tra is_archive
        SELECT table_name, is_archive INTO constraint_name, is_archive
        FROM business_tables 
        WHERE table_id = record_table.table_id;

        -- Tạo tên constraint cho bảng chính
        field_names:='';
        constraint_name := constraint_name || '_unique_';
        archive_field_names:='archived_at, ';
        archive_constraint_name := constraint_name || 'archived_at_'
        -- Lấy các tên trường trong business_fields
        FOR record_field IN (
            SELECT bf.field_name 
            FROM business_fields bf
            JOIN business_table_uniques btu ON bf.field_id = btu.field_id
            WHERE btu.table_id = record_table.table_id
        ) LOOP
            field_names := field_names || record_field.field_name || ', ';
            archive_field_names := archive_field_names || record_field.field_name || ', ';
            constraint_name := constraint_name || record_field.field_name || '_';
            archive_constraint_name := archive_constraint_name || record_field.field_name || '_';
        END LOOP;

        -- Xóa dấu phẩy cuối cùng
        field_names := RTRIM(field_names, ', ');
        constraint_name := RTRIM(constraint_name, '_')
        archive_field_names :=  RTRIM(archive_field_names, ', ') ;
        archive_constraint_name := RTRIM(archive_constraint_name, '_'); -- Tạo tên constraint cho bảng archive

        -- Tạo unique constraint cho bảng chính
        EXECUTE 'ALTER TABLE ' || constraint_name || ' DROP CONSTRAINT IF EXISTS ' || constraint_name;
        EXECUTE 'ALTER TABLE ' || constraint_name || ' ADD CONSTRAINT ' || constraint_name || ' UNIQUE (' || field_names || ');';

        -- Chỉ tạo unique constraint cho bảng archive nếu is_archive=true
        IF is_archive THEN
            EXECUTE 'ALTER TABLE ' || constraint_name || '_archive DROP CONSTRAINT IF EXISTS ' || archive_constraint_name;
            EXECUTE 'ALTER TABLE ' || constraint_name || '_archive ADD CONSTRAINT ' || archive_constraint_name || ' UNIQUE (' || archive_field_names || ');';
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

/*
CREATE OR REPLACE FUNCTION create_yearly_partitions() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    r RECORD;
    archive_table_name TEXT;
    partition_name TEXT;
    partition_sql TEXT;
    year_part INT;
BEGIN
    -- Lấy tất cả các bảng có is_archive = true
    FOR r IN (SELECT table_name FROM business_tables WHERE is_archive = TRUE) LOOP
        -- Xây dựng tên bảng archive
        archive_table_name := r.table_name || '_archive';
        -- Lấy năm hiện tại
        year_part := EXTRACT(YEAR FROM NOW());

        -- Xây dựng tên partition dựa vào năm hiện tại
        partition_name := archive_table_name || '_' || year_part;

        -- Tạo partition dựa trên năm hiện tại
        partition_sql := 'CREATE TABLE IF NOT EXISTS ' || partition_name;
        partition_sql := partition_sql || ' PARTITION OF ' || archive_table_name;
        partition_sql := partition_sql || ' FOR VALUES FROM (' || year_part || ') TO (' || (year_part + 1) || ');';

        -- Thực hiện tạo partition
        EXECUTE partition_sql;
    END LOOP;
END $$;

-- Tạo pg_cron nếu chưa có
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Đặt lịch tự động chạy hàm mỗi năm vào ngày 1 tháng 1
SELECT cron.schedule('Create Yearly Partitions', '0 0 1 1 *', 'CALL create_yearly_partitions()');
*/


CREATE OR REPLACE FUNCTION generate_select_sql_statements() RETURNS VOID AS $$
DECLARE
    record_table RECORD;
    record_field RECORD;
    select_sql TEXT;
    unique_field_names TEXT := '';
BEGIN
    -- Lặp qua các bảng
    FOR record_table IN (
        SELECT table_id, table_name 
        FROM business_tables
    ) LOOP
        -- Tạo câu lệnh SELECT
        select_sql := 'SELECT * FROM ' || record_table.table_name || ' WHERE ';

        -- Lấy các trường có ràng buộc UNIQUE cho bảng đó
        FOR record_field IN (
            SELECT bf.field_name, bf.field_id
            FROM business_fields bf
            JOIN business_table_uniques btu ON bf.field_id = btu.field_id
            WHERE btu.table_id = record_table.table_id
        ) LOOP
            select_sql := select_sql || record_field.field_name || ' = ?' || record_field.field_id || ' AND ';
        END LOOP;

        -- Xóa điều kiện AND cuối cùng
        select_sql := RTRIM(select_sql, ' AND ');

        -- Nếu không có trường nào có unique, không tạo câu lệnh
        IF select_sql LIKE '% WHERE %' THEN
            -- delete
            delete from sqls where sql_name=record_a.table_name || '.SELECT_BY_UNIQUE';
            -- Thêm câu lệnh vào bảng sqls
            INSERT INTO sqls (sql_name, sql_string)
            VALUES (record_table.table_name || '.SELECT_BY_UNIQUE', select_sql);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION generate_insert_sql_statements() RETURNS VOID AS $$
DECLARE
    record_a RECORD;
    field_record RECORD;
    insert_sql TEXT;
BEGIN
    FOR record_a IN (SELECT * FROM business_tables) LOOP
        -- Tạo câu lệnh INSERT
        insert_sql := 'INSERT INTO ' || record_a.table_name || ' (';
        FOR field_record IN (SELECT field_name FROM business_fields WHERE table_id = record_a.table_id) LOOP
            insert_sql := insert_sql || field_record.field_name || ', ';
        END LOOP;
        insert_sql := RTRIM(insert_sql, ', ') || ') VALUES (';
        FOR field_record IN (SELECT field_id FROM business_fields WHERE table_id = record_a.table_id) LOOP
            insert_sql := insert_sql || '?' || field_record.field_id ||', '; -- Placeholder cho giá trị
        END LOOP;
        insert_sql := RTRIM(insert_sql, ', ') || ');';
        -- delete
        delete from sqls where sql_name=record_a.table_name || '.INSERT';
        -- Thêm câu lệnh vào bảng sqls
        INSERT INTO sqls (sql_name, sql_string)
        VALUES (record_a.table_name || '.INSERT', insert_sql);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION generate_update_sql_statements() RETURNS VOID AS $$
DECLARE
    record_a RECORD;
    field_record RECORD;
    update_sql TEXT;
    primary_key_field_name TEXT;
    primary_key_field_id TEXT;
BEGIN
    FOR record_a IN SELECT * FROM business_tables LOOP
        -- Tạo câu lệnh UPDATE
        update_sql := 'UPDATE ' || record_a.table_name || ' SET ';
        primary_key_field_name := record_a.table_name || '_id';
        -- Tạo phần SET cho câu lệnh UPDATE
        FOR field_record IN SELECT * FROM business_fields WHERE table_id = record_a.table_id LOOP
            update_sql := update_sql || field_record.field_name || ' = ?' || field_record.field_id || ', '; -- Placeholder cho giá trị
            IF field_record.is_primary_key THEN
                primary_key_field_name := field_record.field_name;
                primary_key_field_id :=  field_record.field_id;
            END IF;            
        END LOOP;
        update_sql := RTRIM(update_sql, ', '); -- Xóa dấu phẩy cuối cùng
        
        -- Thêm điều kiện WHERE để chỉ cập nhật dòng có id tương ứng
        update_sql := update_sql || ' WHERE ' || primary_key_field_name || ' = ?' || primary_key_field_id || ';'; -- Điều kiện WHERE dựa trên cột id
        -- delete
        delete from sqls where sql_name=record_a.table_name || '.UPDATE';
        -- Thêm câu lệnh vào bảng sqls
        INSERT INTO sqls (sql_name, sql_string)
        VALUES (record_a.table_name || '.UPDATE', update_sql);
            
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION generate_delete_sql_statements() RETURNS VOID AS $$
DECLARE
    record_a RECORD;
    field_record RECORD;
    delete_sql TEXT;
    primary_key_field_name TEXT;
    primary_key_field_id TEXT;
BEGIN
    FOR record_a IN SELECT * FROM business_tables LOOP
        -- Tìm khóa chính
        primary_key_field_name := record_a.table_name || '_id';
        
        FOR field_record IN SELECT * FROM business_fields WHERE table_id = record_a.table_id LOOP
            IF field_record.is_primary_key THEN
                primary_key_field_name := field_record.field_name;
                primary_key_field_id :=  field_record.field_id;
            END IF;
        END LOOP;

        -- Tạo câu lệnh DELETE
        delete_sql := 'DELETE FROM ' || record_a.table_name || ' WHERE ' || primary_key_field_name || ' = ?' || primary_key_field_id || ';'; -- Điều kiện WHERE dựa trên cột id
        -- delete
        delete from sqls where sql_name=record_a.table_name || '.UPDATE';
        -- Thêm câu lệnh DELETE mới vào bảng sqls
        INSERT INTO sqls (sql_name, sql_string)
        VALUES (record_a.table_name || '.DELETE', delete_sql);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

