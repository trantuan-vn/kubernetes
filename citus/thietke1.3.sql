CREATE SCHEMA IF NOT EXISTS today;
CREATE SCHEMA IF NOT EXISTS history;
CREATE SCHEMA IF NOT EXISTS system_parameters;
-- các bảng cơ sở
CREATE TABLE system_parameters.sqls (
    sql_id SERIAL PRIMARY KEY,
    sql_name VARCHAR(255) UNIQUE NOT NULL,
    sql_string TEXT  NOT NULL -- Câu SQL chứa các tham số dạng placeholder "?", ví dụ "insert into A(f1,f2,f3) values (?field_id,?field_id,?field_id)" , trong đó "?field_id" tương ứng với field_id trong bảng business_fields
);

CREATE TABLE system_parameters.actions (
    action_id SERIAL PRIMARY KEY,
    action_name VARCHAR(255) UNIQUE NOT NULL, 
    action_label VARCHAR(255) NOT NULL
);

CREATE TABLE system_parameters.actions_sqls (
    action_sql_id SERIAL PRIMARY KEY,
    action_id INT REFERENCES system_parameters.actions(action_id),
    sql_id INT REFERENCES system_parameters.sqls(sql_id),
    sql_order INT  NOT NULL
);


CREATE TABLE system_parameters.business_tables (
    table_id SERIAL PRIMARY KEY,
    table_name VARCHAR(255) UNIQUE NOT NULL, -- Tên bảng (users, groups, ...)
    table_label VARCHAR(255) NOT NULL,
    is_archive BOOLEAN DEFAULT FALSE,
    day_range INT DEFAULT 31,
    message_type VARCHAR(50) NOT NULL DEFAULT 'ISO20022',
    is_screen BOOLEAN DEFAULT TRUE,
    numPartitions INT DEFAULT 1,
    description VARCHAR(255)          -- Mô tả bảng
);

CREATE TABLE system_parameters.screen_actions (
    screen_action_id SERIAL PRIMARY KEY,
    table_id INT REFERENCES system_parameters.business_tables(table_id),
    action_id INT REFERENCES system_parameters.actions(action_id),
    action_label VARCHAR(255) NOT NULL,
    action_order INT NOT NULL -- thứ tự xuất hiện của action trên screen
);

CREATE TABLE system_parameters.business_fields (
    field_id SERIAL PRIMARY KEY,
    -- thông tin trường trong bảng
    table_id INT NOT NULL REFERENCES system_parameters.business_tables(table_id), -- Liên kết với bảng business_tables
    field_name VARCHAR(255) NOT NULL,                 -- Tên trường
    field_type VARCHAR(50) NOT NULL,                  -- Kiểu dữ liệu của trường (VARCHAR, INT, etc.)
    is_primary_key BOOLEAN DEFAULT FALSE,             -- Có phải khóa chính không
    is_nullable BOOLEAN DEFAULT TRUE,                 -- Có cho phép NULL không
    default_value VARCHAR(255),                        -- Giá trị mặc định
    description TEXT,
    -- flutter screen
    is_required BOOLEAN DEFAULT FALSE,-- Trường có bắt buộc nhập không
    options JSONB,                    -- Tùy chọn thêm (dành cho combo)
    is_hidden BOOLEAN DEFAULT FALSE,
    -- Thông tin về foreign key
    is_foreign_key BOOLEAN DEFAULT FALSE, -- Trường này có phải khóa ngoại không
    referenced_table_id INT REFERENCES system_parameters.business_tables(table_id), -- Bảng mà khóa ngoại tham chiếu đến
    referenced_field_id INT REFERENCES system_parameters.business_fields(field_id), -- Tên trường trong bảng được tham chiếu    
    -- Ràng buộc UNIQUE cho table_id và field_name
    CONSTRAINT business_fields_unique_table_id_field_name UNIQUE (table_id, field_name),
    -- Ràng buộc kiểm tra khi is_foreign_key = TRUE, referenced_table_id và referenced_field_id phải NOT NULL
    CONSTRAINT foreign_key_check CHECK (
        (is_foreign_key = FALSE) OR 
        (is_foreign_key = TRUE AND referenced_table_id IS NOT NULL AND referenced_field_id IS NOT NULL)
    )        
);

CREATE TABLE system_parameters.business_table_uniques (
    unique_id SERIAL PRIMARY KEY,
    table_id INT NOT NULL REFERENCES system_parameters.business_tables(table_id), -- Liên kết với bảng business_tables
    field_id INT NOT NULL REFERENCES system_parameters.business_fields(field_id)
);

CREATE TABLE IF NOT EXISTS system_parameters.temp_execution_log (
    log_id SERIAL PRIMARY KEY,
    executed_query TEXT,
    error_message TEXT,
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION system_parameters.generate_table() RETURNS VOID AS $$
DECLARE
    record_a RECORD;
    field_record RECORD;
    create_sql TEXT;
    alter_sql TEXT;
    modify_sql TEXT;
    history_alter_sql TEXT;
    history_modify_sql TEXT;
    table_exists BOOLEAN;
    column_exists BOOLEAN;
    column_definition TEXT;
    table_name_var TEXT;
    field_name_var TEXT;
    primary_field_name TEXT;
    history_create_sql TEXT;
BEGIN
    FOR record_a IN (SELECT * FROM system_parameters.business_tables) LOOP
        -- Kiểm tra xem bảng đã tồn tại hay chưa
        SELECT EXISTS (
            SELECT 1 FROM information_schema.tables 
            WHERE table_schema = 'today' AND table_name = record_a.table_name
        ) INTO table_exists;

        IF NOT table_exists THEN
            -- Tạo câu lệnh CREATE TABLE nếu bảng chưa tồn tại
            create_sql := 'CREATE TABLE today.' || record_a.table_name || ' (';
            FOR field_record IN (SELECT * FROM system_parameters.business_fields WHERE table_id = record_a.table_id) LOOP
                create_sql := create_sql || field_record.field_name || ' ' || field_record.field_type;
                IF field_record.is_primary_key THEN
                    create_sql := create_sql || ' PRIMARY KEY';
                    primary_field_name := field_record.field_name;
                END IF;
                IF NOT field_record.is_nullable THEN
                    create_sql := create_sql || ' NOT NULL';
                END IF;
                IF field_record.default_value IS NOT NULL THEN
                    create_sql := create_sql || ' DEFAULT ' || field_record.default_value;
                END IF;
                IF field_record.is_foreign_key THEN
                    SELECT table_name INTO table_name_var FROM system_parameters.business_tables WHERE table_id = field_record.referenced_table_id;
                    SELECT field_name INTO field_name_var FROM system_parameters.business_fields WHERE field_id = field_record.referenced_field_id;
                    create_sql := create_sql || ' REFERENCES today.' || table_name_var || '(' || field_name_var || ')';
                END IF;
                create_sql := create_sql || ', ';
            END LOOP;

            -- Nếu bảng có is_archive = true, tạo bảng archive
            IF record_a.is_archive THEN
                -- Thêm cột business_date dùng cho phân vùng
                create_sql := create_sql || 'business_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP)';
                
                -- Tạo bảng phân vùng today cho ngày hiện tại
                -- Ghi log và thực thi câu lệnh
                INSERT INTO system_parameters.temp_execution_log (executed_query) VALUES (create_sql);
                BEGIN
                    EXECUTE create_sql;
                EXCEPTION WHEN OTHERS THEN
                    INSERT INTO system_parameters.temp_execution_log (executed_query, error_message)
                    VALUES (create_sql, SQLERRM);
                END;

                -- Tạo bảng phân vùng history cho n ngày trước đó
                history_create_sql := REPLACE(create_sql, 'CREATE TABLE IF NOT EXISTS today.', 'CREATE TABLE IF NOT EXISTS history.');

                -- Ghi log cho câu lệnh tạo bảng phân vùng history
                INSERT INTO system_parameters.temp_execution_log (executed_query) VALUES (history_create_sql);
                BEGIN
                    EXECUTE history_create_sql;
                    -- SELECT create_distributed_table('history.' || record_a.table_name, primary_field_name);
                EXCEPTION WHEN OTHERS THEN
                    INSERT INTO system_parameters.temp_execution_log (executed_query, error_message)
                    VALUES (history_create_sql, SQLERRM);
                END;
            ELSE
                -- Bỏ dấu phẩy cuối cùng và thêm dấu đóng ngoặc )
                create_sql := left(create_sql, length(create_sql) - 2) || ');';
                INSERT INTO system_parameters.temp_execution_log (executed_query) VALUES (create_sql);
                BEGIN
                    EXECUTE create_sql;
                EXCEPTION WHEN OTHERS THEN
                    INSERT INTO system_parameters.temp_execution_log (executed_query, error_message)
                    VALUES (create_sql, SQLERRM);
                END;
            END IF;
        ELSE
            -- Nếu bảng đã tồn tại, kiểm tra và ALTER TABLE khi cần
            FOR field_record IN (SELECT * FROM system_parameters.business_fields WHERE table_id = record_a.table_id) LOOP
                SELECT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'today' AND table_name = record_a.table_name AND column_name = field_record.field_name
                ) INTO column_exists;
                
                IF NOT column_exists THEN
                    alter_sql := 'ALTER TABLE today.' || record_a.table_name || ' ADD COLUMN ' || field_record.field_name || ' ' || field_record.field_type;
                    IF field_record.is_primary_key THEN
                        alter_sql := alter_sql || ' PRIMARY KEY';
                    END IF;
                    IF NOT field_record.is_nullable THEN
                        alter_sql := alter_sql || ' NOT NULL';
                    END IF;
                    IF field_record.default_value IS NOT NULL THEN
                        alter_sql := alter_sql || ' DEFAULT ' || field_record.default_value;
                    END IF;
                    IF field_record.is_foreign_key THEN
                        SELECT table_name INTO table_name_var FROM system_parameters.business_tables WHERE table_id = field_record.referenced_table_id;
                        SELECT field_name INTO field_name_var FROM system_parameters.business_fields WHERE field_id = field_record.referenced_field_id;
                        alter_sql := alter_sql || ' REFERENCES today.' || table_name_var || '(' || field_name_var || ')';
                    END IF;
                    INSERT INTO system_parameters.temp_execution_log (executed_query) VALUES (alter_sql);
                    BEGIN
                        EXECUTE alter_sql;
                    EXCEPTION WHEN OTHERS THEN
                        INSERT INTO system_parameters.temp_execution_log (executed_query, error_message) VALUES (alter_sql, SQLERRM);
                    END;
                    -- Nếu bảng có is_archive = true, tạo bảng archive
                    IF record_a.is_archive THEN
                        -- Tạo bảng phân vùng history cho n ngày trước đó
                        history_alter_sql := REPLACE(alter_sql, 'ALTER TABLE today.', 'ALTER TABLE history.');
                        -- Ghi log cho câu lệnh tạo bảng phân vùng history
                        INSERT INTO system_parameters.temp_execution_log (executed_query) VALUES (history_alter_sql);
                        BEGIN
                            EXECUTE history_alter_sql;
                        EXCEPTION WHEN OTHERS THEN
                            INSERT INTO system_parameters.temp_execution_log (executed_query, error_message)
                            VALUES (history_alter_sql, SQLERRM);
                        END;                    
                    END IF;
                ELSE
                    -- Kiểm tra và cập nhật nếu có thay đổi
                    SELECT data_type || ' ' || (CASE WHEN is_nullable = 'NO' THEN 'NOT NULL' ELSE '' END) ||
                        (CASE WHEN column_default IS NOT NULL THEN ' DEFAULT ' || column_default ELSE '' END)
                    INTO column_definition
                    FROM information_schema.columns
                    WHERE table_schema = 'today' AND table_name = record_a.table_name AND column_name = field_record.field_name;
                    
                    IF column_definition IS DISTINCT FROM (field_record.field_type || ' ' || (CASE WHEN NOT field_record.is_nullable THEN 'NOT NULL' ELSE '' END) ||
                        (CASE WHEN field_record.default_value IS NOT NULL THEN ' DEFAULT ' || field_record.default_value ELSE '' END)) THEN
                        modify_sql := 'ALTER TABLE today.' || record_a.table_name || ' ALTER COLUMN ' || field_record.field_name || ' TYPE ' || field_record.field_type;
                        INSERT INTO system_parameters.temp_execution_log (executed_query) VALUES (modify_sql);
                        BEGIN
                            EXECUTE modify_sql;
                        EXCEPTION WHEN OTHERS THEN
                            INSERT INTO system_parameters.temp_execution_log (executed_query, error_message) VALUES (modify_sql, SQLERRM);
                        END;
                        -- Nếu bảng có is_archive = true, tạo bảng archive
                        IF record_a.is_archive THEN
                            -- Tạo bảng phân vùng history cho n ngày trước đó
                            history_modify_sql := REPLACE(modify_sql, 'ALTER TABLE today.', 'ALTER TABLE history.');
                            -- Ghi log cho câu lệnh tạo bảng phân vùng history
                            INSERT INTO system_parameters.temp_execution_log (executed_query) VALUES (history_modify_sql);
                            BEGIN
                                EXECUTE history_modify_sql;
                            EXCEPTION WHEN OTHERS THEN
                                INSERT INTO system_parameters.temp_execution_log (executed_query, error_message)
                                VALUES (history_modify_sql, SQLERRM);
                            END;                    
                        END IF;
                    END IF;
                END IF;
            END LOOP;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION system_parameters.create_unique_index() RETURNS VOID AS $$
DECLARE
    record_table RECORD;
    record_field RECORD;
    unique_field_names TEXT := '';
    index_name TEXT;
    archive_index_name TEXT;
    field_names TEXT;
    archive_field_names TEXT;
    isArchive BOOLEAN;
    executedQuery TEXT;
BEGIN
    -- Lặp qua các bảng có unique_order trong bảng business_table_uniques
    FOR record_table IN (
        select table_id, table_name from system_parameters.business_tables where table_id in 
		(SELECT table_id
        FROM system_parameters.business_table_uniques 
        GROUP BY table_id)
    ) LOOP
        -- Lấy tên bảng và kiểm tra is_archive
        SELECT table_name, is_archive INTO index_name, isArchive
        FROM system_parameters.business_tables 
        WHERE table_id = record_table.table_id;

        -- Tạo tên index cho bảng chính
        field_names:='';
        index_name := index_name || '_unique_idx_';
        archive_field_names:='business_date, ';
        archive_index_name := index_name || 'business_date_';
        -- Lấy các tên trường trong business_fields
        FOR record_field IN (
            SELECT bf.field_name 
            FROM system_parameters.business_fields bf
            JOIN system_parameters.business_table_uniques btu ON bf.field_id = btu.field_id
            WHERE bf.table_id = record_table.table_id
        ) LOOP
            field_names := field_names || record_field.field_name || ', ';
            archive_field_names := archive_field_names || record_field.field_name || ', ';
            index_name := index_name || record_field.field_name || '_';
            archive_index_name := archive_index_name || record_field.field_name || '_';
        END LOOP;

        -- Xóa dấu phẩy cuối cùng
        field_names := RTRIM(field_names, ', ');
        index_name := RTRIM(index_name, '_');
        archive_field_names :=  RTRIM(archive_field_names, ', ') ;
        archive_index_name := RTRIM(archive_index_name, '_'); -- Tạo tên index cho bảng archive
        BEGIN 
            IF isArchive then
                -- Tạo unique index cho bảng archive
                executedQuery := 'DROP INDEX IF EXISTS today.' || archive_index_name;
                EXECUTE executedQuery;
                executedQuery := 'CREATE UNIQUE INDEX ' || archive_index_name || ' ON today.' || record_table.table_name || ' (' || archive_field_names || ');';
                EXECUTE executedQuery;

                -- Tạo unique index cho bảng history
                executedQuery := 'DROP INDEX IF EXISTS history.' || archive_index_name;
                EXECUTE executedQuery;
                executedQuery := 'CREATE UNIQUE INDEX ' || archive_index_name || ' ON history.' || record_table.table_name || ' (' || archive_field_names || ');';
                EXECUTE executedQuery;
            else 
                -- Tạo unique index cho bảng chính
                executedQuery := 'DROP INDEX IF EXISTS today.' || index_name;
                EXECUTE executedQuery;
                executedQuery := 'CREATE UNIQUE INDEX ' || index_name || ' ON today.' || record_table.table_name || ' (' || field_names || ');';
                EXECUTE executedQuery;
            end if;
        EXCEPTION
            WHEN OTHERS THEN
                INSERT INTO system_parameters.temp_execution_log (executed_query, error_message)
                VALUES (executedQuery, SQLERRM);
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION system_parameters.generate_select_sql_statements() RETURNS VOID AS $$
DECLARE
    record_table RECORD;
    record_field RECORD;
    select_sql TEXT;
    unique_field_names TEXT := '';
BEGIN
    -- Lặp qua các bảng
    FOR record_table IN (
        SELECT table_id, table_name 
        FROM system_parameters.business_tables
    ) LOOP
        -- Tạo câu lệnh SELECT
        select_sql := 'SELECT * FROM today.' || record_table.table_name || ' WHERE ';

        -- Lấy các trường có ràng buộc UNIQUE cho bảng đó
        FOR record_field IN (
            SELECT bf.field_name, bf.field_id
            FROM system_parameters.business_fields bf
            JOIN system_parameters.business_table_uniques btu ON bf.field_id = btu.field_id
            WHERE btu.table_id = record_table.table_id
        ) LOOP
            select_sql := select_sql || record_field.field_name || ' = ?' || record_field.field_id || ' AND ';
        END LOOP;

        -- Xóa điều kiện AND cuối cùng
        select_sql := RTRIM(select_sql, ' AND ');

        -- Nếu không có trường nào có unique, không tạo câu lệnh
        IF select_sql LIKE '% WHERE %' THEN
            -- delete
            delete from system_parameters.sqls where sql_name=record_table.table_name || '.SELECT_BY_UNIQUE';
            -- Thêm câu lệnh vào bảng sqls
            INSERT INTO system_parameters.sqls (sql_name, sql_string)
            VALUES (record_table.table_name || '.SELECT_BY_UNIQUE', select_sql);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION system_parameters.generate_insert_sql_statements() RETURNS VOID AS $$
DECLARE
    record_a RECORD;
    field_record RECORD;
    insert_sql TEXT;
BEGIN
    FOR record_a IN (SELECT * FROM system_parameters.business_tables) LOOP
        -- Tạo câu lệnh INSERT
        insert_sql := 'INSERT INTO today.' || record_a.table_name || ' (';
        FOR field_record IN (SELECT field_name FROM system_parameters.business_fields WHERE table_id = record_a.table_id) LOOP
            insert_sql := insert_sql || field_record.field_name || ', ';
        END LOOP;
        insert_sql := RTRIM(insert_sql, ', ') || ') VALUES (';
        FOR field_record IN (SELECT field_id FROM system_parameters.business_fields WHERE table_id = record_a.table_id) LOOP
            insert_sql := insert_sql || '?' || field_record.field_id ||', '; -- Placeholder cho giá trị
        END LOOP;
        insert_sql := RTRIM(insert_sql, ', ') || ');';
        -- delete
        delete from system_parameters.sqls where sql_name=record_a.table_name || '.INSERT';
        -- Thêm câu lệnh vào bảng sqls
        INSERT INTO system_parameters.sqls (sql_name, sql_string)
        VALUES (record_a.table_name || '.INSERT', insert_sql);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION system_parameters.generate_update_sql_statements() RETURNS VOID AS $$
DECLARE
    record_a RECORD;
    field_record RECORD;
    update_sql TEXT;
    primary_key_field_name TEXT;
    primary_key_field_id TEXT;
BEGIN
    FOR record_a IN (SELECT * FROM system_parameters.business_tables) LOOP
        -- Tạo câu lệnh UPDATE
        update_sql := 'UPDATE today.' || record_a.table_name || ' SET ';
        primary_key_field_name := record_a.table_name || '_id';
        -- Tạo phần SET cho câu lệnh UPDATE
        FOR field_record IN (SELECT * FROM system_parameters.business_fields WHERE table_id = record_a.table_id) LOOP
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
        delete from system_parameters.sqls where sql_name=record_a.table_name || '.UPDATE';
        -- Thêm câu lệnh vào bảng sqls
        INSERT INTO system_parameters.sqls (sql_name, sql_string)
        VALUES (record_a.table_name || '.UPDATE', update_sql);
            
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION system_parameters.generate_delete_sql_statements() RETURNS VOID AS $$
DECLARE
    record_a RECORD;
    field_record RECORD;
    delete_sql TEXT;
    primary_key_field_name TEXT;
    primary_key_field_id TEXT;
BEGIN
    FOR record_a IN (SELECT * FROM system_parameters.business_tables) LOOP
        -- Tìm khóa chính
        primary_key_field_name := record_a.table_name || '_id';
        
        FOR field_record IN (SELECT * FROM system_parameters.business_fields WHERE table_id = record_a.table_id) LOOP
            IF field_record.is_primary_key THEN
                primary_key_field_name := field_record.field_name;
                primary_key_field_id :=  field_record.field_id;
            END IF;
        END LOOP;

        -- Tạo câu lệnh DELETE
        delete_sql := 'DELETE FROM today.' || record_a.table_name || ' WHERE ' || primary_key_field_name || ' = ?' || primary_key_field_id || ';'; -- Điều kiện WHERE dựa trên cột id
        -- delete
        delete from system_parameters.sqls where sql_name=record_a.table_name || '.DELETE';
        -- Thêm câu lệnh DELETE mới vào bảng sqls
        INSERT INTO system_parameters.sqls (sql_name, sql_string)
        VALUES (record_a.table_name || '.DELETE', delete_sql);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

