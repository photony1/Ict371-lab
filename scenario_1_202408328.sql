-- Scenario 1: University Library Book Loans
-- Student Number: 202408328

-- Clean start so the script can be re-run
DROP TABLE IF EXISTS book_loans;
DROP TABLE IF EXISTS books;
DROP PROCEDURE IF EXISTS borrow_book(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS return_book(INT);

-- 1. Tables and sample data
CREATE TABLE books (
    book_id          SERIAL PRIMARY KEY,
    title            VARCHAR(150) NOT NULL,
    available_copies INT NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE book_loans (
    loan_id        SERIAL PRIMARY KEY,
    book_id        INT NOT NULL REFERENCES books(book_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    loan_status    VARCHAR(10) NOT NULL DEFAULT 'BORROWED'
                   CHECK (loan_status IN ('BORROWED', 'RETURNED'))
);

INSERT INTO books (title, available_copies) VALUES
    ('Database System Concepts', 5),
    ('Introduction to Algorithms', 2),
    ('Operating System Concepts', 0),
    ('Computer Networks', 8);

SELECT * FROM books ORDER BY book_id;

-- 2. IF / ELSIF / ELSE : stock status of each book
DO $$
DECLARE
    rec    RECORD;
    v_msg  TEXT;
BEGIN
    FOR rec IN SELECT book_id, title, available_copies FROM books ORDER BY book_id LOOP
        IF rec.available_copies = 0 THEN
            v_msg := 'UNAVAILABLE';
        ELSIF rec.available_copies <= 2 THEN
            v_msg := 'LOW ON COPIES';
        ELSE
            v_msg := 'SUFFICIENTLY STOCKED';
        END IF;
        RAISE NOTICE 'Book % (%): % copies -> %', rec.book_id, rec.title, rec.available_copies, v_msg;
    END LOOP;
END $$;

-- 3. WHILE loop and numeric FOR loop
DO $$
DECLARE
    v_counter INT := 1;
BEGIN
    -- WHILE: three overdue reminder numbers
    WHILE v_counter <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number: %', v_counter;
        v_counter := v_counter + 1;
    END LOOP;

    -- Numeric FOR: three library shelf numbers
    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number: %', i;
    END LOOP;
END $$;

-- 4. borrow_book procedure
CREATE OR REPLACE PROCEDURE borrow_book(
    p_book_id        INT,
    p_student_number VARCHAR,
    p_quantity       INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    -- Validate quantity
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be greater than zero)', p_quantity
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- Check available copies (lock the row)
    SELECT available_copies INTO v_available
    FROM books
    WHERE book_id = p_book_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Book % does not exist', p_book_id;
    END IF;

    IF v_available < p_quantity THEN
        RAISE NOTICE 'Loan REJECTED for student %: requested %, only % available',
                     p_student_number, p_quantity, v_available;
        RETURN;
    END IF;

    -- Reduce stock and record the loan
    UPDATE books
    SET available_copies = available_copies - p_quantity
    WHERE book_id = p_book_id;

    INSERT INTO book_loans (book_id, student_number, quantity, loan_status)
    VALUES (p_book_id, p_student_number, p_quantity, 'BORROWED');

    RAISE NOTICE 'Loan RECORDED: student % borrowed % copy/copies of book %',
                 p_student_number, p_quantity, p_book_id;
END $$;

-- 5. Two valid loans and one request exceeding stock
CALL borrow_book(1, '202400001', 2);   -- valid
CALL borrow_book(2, '202400002', 1);   -- valid
CALL borrow_book(2, '202400003', 5);   -- exceeds available copies (rejected)

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- 6. return_book procedure (safe against double returns)
CREATE OR REPLACE PROCEDURE return_book(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_book_id  INT;
    v_quantity INT;
    v_status   VARCHAR(10);
BEGIN
    SELECT book_id, quantity, loan_status
    INTO v_book_id, v_quantity, v_status
    FROM book_loans
    WHERE loan_id = p_loan_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Loan % does not exist', p_loan_id;
        RETURN;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan % was already returned. No copies restored.', p_loan_id;
        RETURN;
    END IF;

    UPDATE book_loans SET loan_status = 'RETURNED' WHERE loan_id = p_loan_id;
    UPDATE books SET available_copies = available_copies + v_quantity WHERE book_id = v_book_id;

    RAISE NOTICE 'Loan % returned. % copy/copies restored to book %', p_loan_id, v_quantity, v_book_id;
END $$;

CALL return_book(1);   -- first call: restores copies
CALL return_book(1);   -- second call: must NOT restore copies again

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- 7. Explicit cursor: books with few copies remaining
DO $$
DECLARE
    cur_low_books CURSOR (p_threshold INT) FOR
        SELECT book_id, title, available_copies
        FROM books
        WHERE available_copies <= p_threshold
        ORDER BY available_copies, book_id;
    rec RECORD;
BEGIN
    OPEN cur_low_books(2);
    LOOP
        FETCH cur_low_books INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Low stock -> Book %: % (% copies left)', rec.book_id, rec.title, rec.available_copies;
    END LOOP;
    CLOSE cur_low_books;
END $$;

-- 8. Borrow zero copies: handled with an EXCEPTION block
DO $$
BEGIN
    CALL borrow_book(1, '202400004', 0);
EXCEPTION
    WHEN invalid_parameter_value THEN
        RAISE NOTICE 'Handled error: %', SQLERRM;
END $$;

-- 9. Final results
SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;
