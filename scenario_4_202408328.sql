-- Scenario 4: Campus Clinic Medicine Dispensing
-- Student Number: 202408328

DROP TABLE IF EXISTS dispensing_records;
DROP TABLE IF EXISTS medicines;
DROP PROCEDURE IF EXISTS dispense_medicine(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS reverse_dispensing(INT);

-- 1. Tables and sample data
CREATE TABLE medicines (
    medicine_id    SERIAL PRIMARY KEY,
    medicine_name  VARCHAR(100) NOT NULL,
    stock_quantity INT NOT NULL CHECK (stock_quantity >= 0)
);

CREATE TABLE dispensing_records (
    record_id      SERIAL PRIMARY KEY,
    medicine_id    INT NOT NULL REFERENCES medicines(medicine_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    status         VARCHAR(10) NOT NULL DEFAULT 'DISPENSED'
                   CHECK (status IN ('DISPENSED', 'REVERSED'))
);

INSERT INTO medicines (medicine_name, stock_quantity) VALUES
    ('Paracetamol 500mg', 200),
    ('Amoxicillin 250mg', 15),
    ('Ibuprofen 200mg', 0),
    ('Oral Rehydration Salts', 50);

SELECT * FROM medicines ORDER BY medicine_id;

-- 2. IF / ELSIF / ELSE : stock status of each medicine
DO $$
DECLARE
    rec   RECORD;
    v_msg TEXT;
BEGIN
    FOR rec IN SELECT medicine_id, medicine_name, stock_quantity FROM medicines ORDER BY medicine_id LOOP
        IF rec.stock_quantity = 0 THEN
            v_msg := 'OUT OF STOCK';
        ELSIF rec.stock_quantity <= 20 THEN
            v_msg := 'LOW ON STOCK';
        ELSE
            v_msg := 'SUFFICIENTLY STOCKED';
        END IF;
        RAISE NOTICE '% : % unit(s) -> %', rec.medicine_name, rec.stock_quantity, v_msg;
    END LOOP;
END $$;

-- 3. WHILE loop and numeric FOR loop
DO $$
DECLARE
    v_day INT := 1;
BEGIN
    -- WHILE: three stock review days
    WHILE v_day <= 3 LOOP
        RAISE NOTICE 'Stock review day %', v_day;
        v_day := v_day + 1;
    END LOOP;

    -- Numeric FOR: three shelf inspections
    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Shelf inspection number %', i;
    END LOOP;
END $$;

-- 4. dispense_medicine procedure
CREATE OR REPLACE PROCEDURE dispense_medicine(
    p_medicine_id    INT,
    p_student_number VARCHAR,
    p_quantity       INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid dispensing quantity: % (must be greater than zero)', p_quantity
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT stock_quantity INTO v_stock
    FROM medicines
    WHERE medicine_id = p_medicine_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Medicine % does not exist', p_medicine_id;
    END IF;

    IF v_stock < p_quantity THEN
        RAISE NOTICE 'Dispensing REJECTED for student %: requested %, only % in stock',
                     p_student_number, p_quantity, v_stock;
        RETURN;
    END IF;

    UPDATE medicines
    SET stock_quantity = stock_quantity - p_quantity
    WHERE medicine_id = p_medicine_id;

    INSERT INTO dispensing_records (medicine_id, student_number, quantity, status)
    VALUES (p_medicine_id, p_student_number, p_quantity, 'DISPENSED');

    RAISE NOTICE 'Dispensing RECORDED: % unit(s) of medicine % given to student %',
                 p_quantity, p_medicine_id, p_student_number;
END $$;

-- 5. Two valid quantities and one exceeding stock
CALL dispense_medicine(1, '202400021', 10);   -- valid
CALL dispense_medicine(2, '202400022', 5);    -- valid
CALL dispense_medicine(2, '202400023', 50);   -- exceeds stock (rejected)

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- 6. reverse_dispensing procedure (stock restored only once)
CREATE OR REPLACE PROCEDURE reverse_dispensing(p_record_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_medicine_id INT;
    v_quantity    INT;
    v_status      VARCHAR(10);
BEGIN
    SELECT medicine_id, quantity, status
    INTO v_medicine_id, v_quantity, v_status
    FROM dispensing_records
    WHERE record_id = p_record_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Dispensing record % does not exist', p_record_id;
        RETURN;
    END IF;

    IF v_status = 'REVERSED' THEN
        RAISE NOTICE 'Record % is already reversed. Stock not restored again.', p_record_id;
        RETURN;
    END IF;

    UPDATE dispensing_records SET status = 'REVERSED' WHERE record_id = p_record_id;
    UPDATE medicines SET stock_quantity = stock_quantity + v_quantity WHERE medicine_id = v_medicine_id;

    RAISE NOTICE 'Record % reversed. % unit(s) restored to medicine %', p_record_id, v_quantity, v_medicine_id;
END $$;

CALL reverse_dispensing(2);   -- first call: restores stock
CALL reverse_dispensing(2);   -- second call: must NOT restore stock again

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- 7. Explicit cursor: medicines below a low-stock threshold
DO $$
DECLARE
    cur_low_stock CURSOR (p_threshold INT) FOR
        SELECT medicine_id, medicine_name, stock_quantity
        FROM medicines
        WHERE stock_quantity < p_threshold
        ORDER BY stock_quantity, medicine_id;
    rec RECORD;
BEGIN
    OPEN cur_low_stock(20);
    LOOP
        FETCH cur_low_stock INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Below threshold -> %: % unit(s) left', rec.medicine_name, rec.stock_quantity;
    END LOOP;
    CLOSE cur_low_stock;
END $$;

-- 8. Negative dispensing quantity: handled with EXCEPTION block
DO $$
BEGIN
    CALL dispense_medicine(1, '202400024', -5);
EXCEPTION
    WHEN invalid_parameter_value THEN
        RAISE NOTICE 'Handled error: %', SQLERRM;
END $$;

-- 9. Final results
SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;
