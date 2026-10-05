-- Scenario 3: Student Hostel Room Allocation
-- Student Number: 202408328

DROP TABLE IF EXISTS allocations;
DROP TABLE IF EXISTS hostel_rooms;
DROP PROCEDURE IF EXISTS allocate_room(VARCHAR, INT);
DROP PROCEDURE IF EXISTS check_out(INT);

-- 1. Tables and sample data
CREATE TABLE hostel_rooms (
    room_id          SERIAL PRIMARY KEY,
    room_name        VARCHAR(50) NOT NULL,
    available_spaces INT NOT NULL CHECK (available_spaces >= 0)
);

CREATE TABLE allocations (
    allocation_id  SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL,
    room_id        INT NOT NULL REFERENCES hostel_rooms(room_id),
    status         VARCHAR(10) NOT NULL DEFAULT 'ACTIVE'
                   CHECK (status IN ('ACTIVE', 'COMPLETE'))
);

INSERT INTO hostel_rooms (room_name, available_spaces) VALUES
    ('Room A101', 4),
    ('Room A102', 1),
    ('Room B201', 0),
    ('Room B202', 2);

SELECT * FROM hostel_rooms ORDER BY room_id;

-- 2. IF / ELSIF / ELSE : room status
DO $$
DECLARE
    rec   RECORD;
    v_msg TEXT;
BEGIN
    FOR rec IN SELECT room_id, room_name, available_spaces FROM hostel_rooms ORDER BY room_id LOOP
        IF rec.available_spaces = 0 THEN
            v_msg := 'FULL';
        ELSIF rec.available_spaces = 1 THEN
            v_msg := 'ONE SPACE LEFT';
        ELSE
            v_msg := 'SEVERAL SPACES';
        END IF;
        RAISE NOTICE '% : % space(s) -> %', rec.room_name, rec.available_spaces, v_msg;
    END LOOP;
END $$;

-- 3. WHILE loop and numeric FOR loop
DO $$
DECLARE
    v_day INT := 1;
BEGIN
    -- WHILE: three hostel inspection days
    WHILE v_day <= 3 LOOP
        RAISE NOTICE 'Hostel inspection day %', v_day;
        v_day := v_day + 1;
    END LOOP;

    -- Numeric FOR: three room checks
    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Room check number %', i;
    END LOOP;
END $$;

-- 4. allocate_room procedure
CREATE OR REPLACE PROCEDURE allocate_room(
    p_student_number VARCHAR,
    p_room_id        INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    -- Validate student number (blank or NULL is invalid)
    IF p_student_number IS NULL OR TRIM(p_student_number) = '' THEN
        RAISE EXCEPTION 'Invalid student number: it cannot be blank'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT available_spaces INTO v_available
    FROM hostel_rooms
    WHERE room_id = p_room_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Room % does not exist', p_room_id;
    END IF;

    IF v_available < 1 THEN
        RAISE NOTICE 'Allocation REJECTED for student %: room % is full', p_student_number, p_room_id;
        RETURN;
    END IF;

    UPDATE hostel_rooms
    SET available_spaces = available_spaces - 1
    WHERE room_id = p_room_id;

    INSERT INTO allocations (student_number, room_id, status)
    VALUES (TRIM(p_student_number), p_room_id, 'ACTIVE');

    RAISE NOTICE 'Allocation RECORDED: student % placed in room %', p_student_number, p_room_id;
END $$;

-- 5. Two valid allocations and one to a full room
CALL allocate_room('202400011', 1);   -- valid
CALL allocate_room('202400012', 2);   -- valid (room A102 becomes full)
CALL allocate_room('202400013', 3);   -- room B201 is full (rejected)

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- 6. check_out procedure (safe against double check-out)
CREATE OR REPLACE PROCEDURE check_out(p_allocation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_room_id INT;
    v_status  VARCHAR(10);
BEGIN
    SELECT room_id, status
    INTO v_room_id, v_status
    FROM allocations
    WHERE allocation_id = p_allocation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Allocation % does not exist', p_allocation_id;
        RETURN;
    END IF;

    IF v_status = 'COMPLETE' THEN
        RAISE NOTICE 'Allocation % is already complete. No space freed.', p_allocation_id;
        RETURN;
    END IF;

    UPDATE allocations SET status = 'COMPLETE' WHERE allocation_id = p_allocation_id;
    UPDATE hostel_rooms SET available_spaces = available_spaces + 1 WHERE room_id = v_room_id;

    RAISE NOTICE 'Allocation % checked out. One space freed in room %', p_allocation_id, v_room_id;
END $$;

CALL check_out(2);   -- first call: frees one space in room 2
CALL check_out(2);   -- second call: must NOT free another space

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- 7. Explicit cursor: full or nearly full rooms
DO $$
DECLARE
    cur_full_rooms CURSOR (p_threshold INT) FOR
        SELECT room_id, room_name, available_spaces
        FROM hostel_rooms
        WHERE available_spaces <= p_threshold
        ORDER BY available_spaces, room_id;
    rec RECORD;
BEGIN
    OPEN cur_full_rooms(1);
    LOOP
        FETCH cur_full_rooms INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Full / nearly full -> %: % space(s) left', rec.room_name, rec.available_spaces;
    END LOOP;
    CLOSE cur_full_rooms;
END $$;

-- 8. Blank student number: handled with an EXCEPTION block
DO $$
BEGIN
    CALL allocate_room('   ', 1);
EXCEPTION
    WHEN invalid_parameter_value THEN
        RAISE NOTICE 'Handled error: %', SQLERRM;
END $$;

-- 9. Final results
SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;
