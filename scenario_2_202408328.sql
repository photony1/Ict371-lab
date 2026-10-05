-- Scenario 2: Computer Laboratory Reservations
-- Student Number: 202408328

DROP TABLE IF EXISTS reservations;
DROP TABLE IF EXISTS lab_sessions;
DROP PROCEDURE IF EXISTS reserve_workstations(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS cancel_reservation(INT);

-- 1. Tables and sample data
CREATE TABLE lab_sessions (
    session_id               SERIAL PRIMARY KEY,
    session_name             VARCHAR(100) NOT NULL,
    available_workstations   INT NOT NULL CHECK (available_workstations >= 0)
);

CREATE TABLE reservations (
    reservation_id   SERIAL PRIMARY KEY,
    session_id       INT NOT NULL REFERENCES lab_sessions(session_id),
    lecturer         VARCHAR(100) NOT NULL,
    workstations     INT NOT NULL CHECK (workstations > 0),
    status           VARCHAR(10) NOT NULL DEFAULT 'RESERVED'
                     CHECK (status IN ('RESERVED', 'CANCELLED'))
);

INSERT INTO lab_sessions (session_name, available_workstations) VALUES
    ('Monday 08:00 - Programming Lab', 30),
    ('Tuesday 10:00 - Networking Lab', 12),
    ('Wednesday 14:00 - Database Lab', 4),
    ('Thursday 09:00 - Systems Lab', 0);

SELECT * FROM lab_sessions ORDER BY session_id;

-- 2. IF / ELSIF / ELSE : session capacity report
DO $$
DECLARE
    rec   RECORD;
    v_msg TEXT;
BEGIN
    FOR rec IN SELECT session_id, session_name, available_workstations FROM lab_sessions ORDER BY session_id LOOP
        IF rec.available_workstations = 0 THEN
            v_msg := 'FULL';
        ELSIF rec.available_workstations <= 5 THEN
            v_msg := 'NEARLY FULL';
        ELSE
            v_msg := 'ENOUGH WORKSTATIONS';
        END IF;
        RAISE NOTICE 'Session % (%): % workstations -> %',
                     rec.session_id, rec.session_name, rec.available_workstations, v_msg;
    END LOOP;
END $$;

-- 3. WHILE loop and numeric FOR loop
DO $$
DECLARE
    v_counter INT := 1;
BEGIN
    -- WHILE: three session preparation reminders
    WHILE v_counter <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %: check projector, network and software', v_counter;
        v_counter := v_counter + 1;
    END LOOP;

    -- Numeric FOR: three workstation checks
    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Workstation check number %', i;
    END LOOP;
END $$;

-- 4. reserve_workstations procedure
CREATE OR REPLACE PROCEDURE reserve_workstations(
    p_session_id INT,
    p_lecturer   VARCHAR,
    p_quantity   INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid number of workstations: % (must be greater than zero)', p_quantity
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT available_workstations INTO v_available
    FROM lab_sessions
    WHERE session_id = p_session_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session % does not exist', p_session_id;
    END IF;

    IF v_available < p_quantity THEN
        RAISE NOTICE 'Reservation REJECTED for %: requested %, only % available',
                     p_lecturer, p_quantity, v_available;
        RETURN;
    END IF;

    UPDATE lab_sessions
    SET available_workstations = available_workstations - p_quantity
    WHERE session_id = p_session_id;

    INSERT INTO reservations (session_id, lecturer, workstations, status)
    VALUES (p_session_id, p_lecturer, p_quantity, 'RESERVED');

    RAISE NOTICE 'Reservation RECORDED: % reserved % workstation(s) in session %',
                 p_lecturer, p_quantity, p_session_id;
END $$;

-- 5. Two valid reservations and one exceeding capacity
CALL reserve_workstations(1, 'Dr. Banda', 10);   -- valid
CALL reserve_workstations(2, 'Mr. Phiri', 8);    -- valid
CALL reserve_workstations(2, 'Dr. Mwale', 9);    -- exceeds capacity (only 4 left)

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- 6. cancel_reservation procedure (safe against double cancel)
CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_id INT;
    v_quantity   INT;
    v_status     VARCHAR(10);
BEGIN
    SELECT session_id, workstations, status
    INTO v_session_id, v_quantity, v_status
    FROM reservations
    WHERE reservation_id = p_reservation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Reservation % does not exist', p_reservation_id;
        RETURN;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % is already cancelled. No workstations released.', p_reservation_id;
        RETURN;
    END IF;

    UPDATE reservations SET status = 'CANCELLED' WHERE reservation_id = p_reservation_id;
    UPDATE lab_sessions
    SET available_workstations = available_workstations + v_quantity
    WHERE session_id = v_session_id;

    RAISE NOTICE 'Reservation % cancelled. % workstation(s) released to session %',
                 p_reservation_id, v_quantity, v_session_id;
END $$;

CALL cancel_reservation(1);   -- first call: releases workstations
CALL cancel_reservation(1);   -- second call: must NOT release again

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- 7. Explicit cursor: sessions with few workstations left
DO $$
DECLARE
    cur_low_sessions CURSOR (p_threshold INT) FOR
        SELECT session_id, session_name, available_workstations
        FROM lab_sessions
        WHERE available_workstations <= p_threshold
        ORDER BY available_workstations, session_id;
    rec RECORD;
BEGIN
    OPEN cur_low_sessions(5);
    LOOP
        FETCH cur_low_sessions INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few workstations -> Session %: % (% left)',
                     rec.session_id, rec.session_name, rec.available_workstations;
    END LOOP;
    CLOSE cur_low_sessions;
END $$;

-- 8. Request zero workstations: handled with EXCEPTION block
DO $$
BEGIN
    CALL reserve_workstations(1, 'Dr. Zulu', 0);
EXCEPTION
    WHEN invalid_parameter_value THEN
        RAISE NOTICE 'Handled error: %', SQLERRM;
END $$;

-- 9. Final results
SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;
