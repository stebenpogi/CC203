PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS admins (
    admin_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    username        TEXT NOT NULL UNIQUE,
    password_hash   TEXT NOT NULL,
    full_name       TEXT NOT NULL,
    email           TEXT NOT NULL UNIQUE,
    status          TEXT NOT NULL DEFAULT 'ACTIVE'
                    CHECK (status IN ('ACTIVE', 'DISABLED')),
    created_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS blocked_emails (
    blocked_email_id INTEGER PRIMARY KEY AUTOINCREMENT,
    email            TEXT NOT NULL COLLATE NOCASE UNIQUE,
    reason           TEXT,
    blocked_by       INTEGER,
    blocked_at       TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (blocked_by) REFERENCES admins(admin_id)
);

CREATE TABLE IF NOT EXISTS registration_applications (
    registration_application_id INTEGER PRIMARY KEY AUTOINCREMENT,
    requested_account_type TEXT NOT NULL
        CHECK (requested_account_type IN ('BASIC', 'PREMIUM')),
    full_name       TEXT NOT NULL,
    address         TEXT NOT NULL,
    gender          TEXT,
    birth_date      TEXT NOT NULL,
    email           TEXT NOT NULL COLLATE NOCASE UNIQUE,
    contact_number  TEXT NOT NULL,
    tin_number      TEXT NOT NULL,
    application_status TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (application_status IN ('PENDING', 'APPROVED', 'REJECTED')),
    submitted_at   TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reviewed_at    TEXT,
    rejection_reason TEXT
);

CREATE TABLE IF NOT EXISTS employment_details (
    employment_id  INTEGER PRIMARY KEY AUTOINCREMENT,
    registration_application_id INTEGER NOT NULL UNIQUE,
    company_name   TEXT NOT NULL,
    company_address TEXT NOT NULL,
    company_phone  TEXT NOT NULL,
    hr_contact_number TEXT,
    position       TEXT NOT NULL,
    monthly_earnings NUMERIC NOT NULL CHECK (monthly_earnings >= 0),
    FOREIGN KEY (registration_application_id)
        REFERENCES registration_applications(registration_application_id)
        ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS bank_details (
    bank_detail_id INTEGER PRIMARY KEY AUTOINCREMENT,
    registration_application_id INTEGER NOT NULL UNIQUE,
    bank_name      TEXT NOT NULL,
    bank_account_number TEXT NOT NULL,
    card_holder_name TEXT NOT NULL,
    FOREIGN KEY (registration_application_id)
        REFERENCES registration_applications(registration_application_id)
        ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS registration_documents (
    document_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    registration_application_id INTEGER NOT NULL,
    document_type  TEXT NOT NULL
        CHECK (document_type IN ('PROOF_OF_BILLING', 'PRIMARY_VALID_ID', 'CERTIFICATE_OF_EMPLOYMENT')),
    file_reference TEXT NOT NULL,
    verification_status TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (verification_status IN ('PENDING', 'VERIFIED', 'INVALID')),
    uploaded_at    TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    verified_by    INTEGER,
    verified_at    TEXT,
    FOREIGN KEY (registration_application_id)
        REFERENCES registration_applications(registration_application_id)
        ON DELETE CASCADE,
    FOREIGN KEY (verified_by) REFERENCES admins(admin_id)
);

CREATE TABLE IF NOT EXISTS registration_reviews (
    review_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    registration_application_id INTEGER NOT NULL,
    admin_id       INTEGER NOT NULL,
    decision       TEXT NOT NULL CHECK (decision IN ('APPROVED', 'REJECTED')),
    remarks        TEXT,
    reviewed_at    TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (registration_application_id)
        REFERENCES registration_applications(registration_application_id),
    FOREIGN KEY (admin_id) REFERENCES admins(admin_id)
);

CREATE TABLE IF NOT EXISTS users (
    user_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    registration_application_id INTEGER NOT NULL UNIQUE,
    username       TEXT NOT NULL UNIQUE
        CHECK (length(username) >= 6),
    password_hash  TEXT NOT NULL,
    account_type   TEXT NOT NULL DEFAULT 'BASIC'
        CHECK (account_type IN ('BASIC', 'PREMIUM')),
    account_status TEXT NOT NULL DEFAULT 'ACTIVE'
        CHECK (account_status IN ('ACTIVE', 'DISABLED')),
    current_loan_limit NUMERIC NOT NULL DEFAULT 10000
        CHECK (current_loan_limit BETWEEN 10000 AND 50000),
    created_at     TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (registration_application_id)
        REFERENCES registration_applications(registration_application_id)
);

CREATE VIEW IF NOT EXISTS user_profile_view AS
SELECT
    u.user_id, u.username, u.account_type, u.account_status,
    r.full_name, r.address, r.gender, r.birth_date, r.email,
    r.contact_number, r.tin_number,
    e.company_name, e.company_address, e.company_phone,
    e.hr_contact_number, e.position, e.monthly_earnings,
    b.bank_name, b.bank_account_number, b.card_holder_name
FROM users u
JOIN registration_applications r
  ON r.registration_application_id = u.registration_application_id
LEFT JOIN employment_details e
  ON e.registration_application_id = r.registration_application_id
LEFT JOIN bank_details b
  ON b.registration_application_id = r.registration_application_id;

CREATE TRIGGER IF NOT EXISTS trg_limit_premium_members
BEFORE INSERT ON users
WHEN NEW.account_type = 'PREMIUM'
BEGIN
    SELECT CASE
        WHEN (SELECT COUNT(*) FROM users WHERE account_type = 'PREMIUM') >= 50
        THEN RAISE(ABORT, 'Premium membership limit of 50 has been reached.')
    END;
END;

CREATE TRIGGER IF NOT EXISTS trg_limit_premium_members_update
BEFORE UPDATE OF account_type ON users
WHEN NEW.account_type = 'PREMIUM' AND OLD.account_type <> 'PREMIUM'
BEGIN
    SELECT CASE
        WHEN (SELECT COUNT(*) FROM users WHERE account_type = 'PREMIUM') >= 50
        THEN RAISE(ABORT, 'Premium membership limit of 50 has been reached.')
    END;
END;

CREATE TABLE IF NOT EXISTS loan_applications (
    loan_application_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         INTEGER NOT NULL,
    requested_amount NUMERIC NOT NULL
        CHECK (requested_amount BETWEEN 5000 AND 50000),
    requested_months INTEGER NOT NULL
        CHECK (requested_months IN (1, 3, 6, 12, 15, 18, 21, 24, 27, 30, 32)),
    interest_rate   NUMERIC NOT NULL DEFAULT 0.03
        CHECK (interest_rate >= 0),
    application_status TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (application_status IN ('PENDING', 'APPROVED', 'REJECTED')),
    rejection_reason TEXT,
    applied_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reviewed_at     TEXT,
    reviewed_by     INTEGER,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (reviewed_by) REFERENCES admins(admin_id)
);

CREATE TRIGGER IF NOT EXISTS trg_check_loan_limit
BEFORE INSERT ON loan_applications
BEGIN
    SELECT CASE
        WHEN NEW.requested_amount >
             (SELECT current_loan_limit FROM users WHERE user_id = NEW.user_id)
        THEN RAISE(ABORT, 'Requested amount exceeds the user current loan limit.')
    END;
    SELECT CASE
        WHEN NEW.requested_amount % 1000 <> 0
        THEN RAISE(ABORT, 'Loan amount must be in increments of PHP 1,000.')
    END;
END;

CREATE TABLE IF NOT EXISTS loans (
    loan_id          INTEGER PRIMARY KEY AUTOINCREMENT,
    loan_application_id INTEGER NOT NULL UNIQUE,
    user_id          INTEGER NOT NULL,
    approved_amount  NUMERIC NOT NULL CHECK (approved_amount > 0),
    interest_rate    NUMERIC NOT NULL DEFAULT 0.03 CHECK (interest_rate >= 0),
    interest_amount  NUMERIC NOT NULL CHECK (interest_amount >= 0),
    net_amount_released NUMERIC NOT NULL CHECK (net_amount_released >= 0),
    repayment_months INTEGER NOT NULL CHECK (repayment_months > 0 AND repayment_months <= 32),
    release_date     TEXT NOT NULL,
    loan_status      TEXT NOT NULL DEFAULT 'ACTIVE'
        CHECK (loan_status IN ('ACTIVE', 'COMPLETED', 'OVERDUE', 'CANCELLED')),
    created_at       TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (loan_application_id) REFERENCES loan_applications(loan_application_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE TABLE IF NOT EXISTS loan_transactions (
    loan_transaction_id INTEGER PRIMARY KEY AUTOINCREMENT,
    transaction_code TEXT NOT NULL UNIQUE,
    loan_id          INTEGER NOT NULL,
    transaction_type TEXT NOT NULL
        CHECK (transaction_type IN ('LOAN_RELEASE', 'LOAN_INCREASE', 'TERM_INCREASE', 'ADJUSTMENT')),
    amount           NUMERIC NOT NULL DEFAULT 0,
    months_added     INTEGER NOT NULL DEFAULT 0,
    transaction_status TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (transaction_status IN ('PENDING', 'APPROVED', 'REJECTED')),
    rejection_reason TEXT,
    admin_id         INTEGER,
    transaction_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (loan_id) REFERENCES loans(loan_id),
    FOREIGN KEY (admin_id) REFERENCES admins(admin_id)
);

CREATE TABLE IF NOT EXISTS loan_payments (
    loan_payment_id INTEGER PRIMARY KEY AUTOINCREMENT,
    loan_id         INTEGER NOT NULL,
    payment_reference TEXT NOT NULL UNIQUE,
    amount_paid     NUMERIC NOT NULL CHECK (amount_paid > 0),
    payment_date    TEXT NOT NULL,
    payment_method  TEXT,
    payment_status  TEXT NOT NULL DEFAULT 'COMPLETED'
        CHECK (payment_status IN ('PENDING', 'COMPLETED', 'FAILED')),
    FOREIGN KEY (loan_id) REFERENCES loans(loan_id)
);

CREATE TABLE IF NOT EXISTS billing_statements (
    billing_statement_id INTEGER PRIMARY KEY AUTOINCREMENT,
    loan_id          INTEGER NOT NULL,
    statement_date   TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    billing_year     INTEGER NOT NULL,
    billing_month    INTEGER NOT NULL CHECK (billing_month BETWEEN 1 AND 12),
    principal_due    NUMERIC NOT NULL CHECK (principal_due >= 0),
    interest_amount  NUMERIC NOT NULL DEFAULT 0 CHECK (interest_amount >= 0),
    penalty_amount   NUMERIC NOT NULL DEFAULT 0 CHECK (penalty_amount >= 0),
    total_due        NUMERIC NOT NULL CHECK (total_due >= 0),
    due_date         TEXT NOT NULL,
    billing_status   TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (billing_status IN ('PENDING', 'COMPLETED', 'OVERDUE')),
    FOREIGN KEY (loan_id) REFERENCES loans(loan_id),
    UNIQUE (loan_id, billing_year, billing_month)
);

CREATE TABLE IF NOT EXISTS payment_schedules (
    payment_schedule_id INTEGER PRIMARY KEY AUTOINCREMENT,
    loan_id          INTEGER NOT NULL,
    installment_number INTEGER NOT NULL CHECK (installment_number > 0),
    due_date         TEXT NOT NULL,
    principal_due    NUMERIC NOT NULL CHECK (principal_due >= 0),
    interest_due     NUMERIC NOT NULL DEFAULT 0 CHECK (interest_due >= 0),
    penalty_due      NUMERIC NOT NULL DEFAULT 0 CHECK (penalty_due >= 0),
    schedule_status  TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (schedule_status IN ('PENDING', 'PAID', 'OVERDUE')),
    FOREIGN KEY (loan_id) REFERENCES loans(loan_id),
    UNIQUE (loan_id, installment_number)
);

CREATE TABLE IF NOT EXISTS savings_accounts (
    savings_account_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id          INTEGER NOT NULL UNIQUE,
    current_balance  NUMERIC NOT NULL DEFAULT 0
        CHECK (current_balance BETWEEN 0 AND 100000),
    account_status   TEXT NOT NULL DEFAULT 'ACTIVE'
        CHECK (account_status IN ('ACTIVE', 'DISABLED')),
    opened_at        TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE TABLE IF NOT EXISTS withdrawal_requests (
    withdrawal_request_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id          INTEGER NOT NULL,
    savings_account_id INTEGER NOT NULL,
    requested_amount NUMERIC NOT NULL CHECK (requested_amount >= 500),
    request_status   TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (request_status IN ('PENDING', 'APPROVED', 'REJECTED', 'COMPLETED')),
    request_date     TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reviewed_by      INTEGER,
    reviewed_at      TEXT,
    admin_remarks    TEXT,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (savings_account_id) REFERENCES savings_accounts(savings_account_id),
    FOREIGN KEY (reviewed_by) REFERENCES admins(admin_id)
);

CREATE TABLE IF NOT EXISTS savings_transactions (
    savings_transaction_id INTEGER PRIMARY KEY AUTOINCREMENT,
    transaction_code TEXT NOT NULL UNIQUE,
    savings_account_id INTEGER NOT NULL,
    withdrawal_request_id INTEGER,
    transaction_category TEXT NOT NULL
        CHECK (transaction_category IN ('DEPOSIT', 'WITHDRAWAL', 'MONEY_BACK')),
    amount           NUMERIC NOT NULL CHECK (amount > 0),
    transaction_status TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (transaction_status IN ('PENDING', 'FAILED', 'REJECTED', 'COMPLETED')),
    transaction_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    description      TEXT,
    FOREIGN KEY (savings_account_id) REFERENCES savings_accounts(savings_account_id),
    FOREIGN KEY (withdrawal_request_id) REFERENCES withdrawal_requests(withdrawal_request_id)
);

CREATE TRIGGER IF NOT EXISTS trg_validate_savings_deposit
BEFORE INSERT ON savings_transactions
WHEN NEW.transaction_category = 'DEPOSIT'
BEGIN
    SELECT CASE
        WHEN NEW.amount < 100 OR NEW.amount > 1000
        THEN RAISE(ABORT, 'Deposit must be between PHP 100 and PHP 1,000.')
    END;
END;

CREATE TRIGGER IF NOT EXISTS trg_savings_transaction_balance_insert
AFTER INSERT ON savings_transactions
WHEN NEW.transaction_status = 'COMPLETED'
BEGIN
    UPDATE savings_accounts
       SET current_balance =
           current_balance +
           CASE WHEN NEW.transaction_category IN ('DEPOSIT', 'MONEY_BACK')
                THEN NEW.amount ELSE -NEW.amount END
     WHERE savings_account_id = NEW.savings_account_id;
END;

CREATE TRIGGER IF NOT EXISTS trg_savings_transaction_balance_update
AFTER UPDATE OF transaction_status ON savings_transactions
WHEN OLD.transaction_status <> 'COMPLETED'
 AND NEW.transaction_status = 'COMPLETED'
BEGIN
    UPDATE savings_accounts
       SET current_balance =
           current_balance +
           CASE WHEN NEW.transaction_category IN ('DEPOSIT', 'MONEY_BACK')
                THEN NEW.amount ELSE -NEW.amount END
     WHERE savings_account_id = NEW.savings_account_id;
END;

CREATE TRIGGER IF NOT EXISTS trg_check_withdrawal_balance
BEFORE INSERT ON savings_transactions
WHEN NEW.transaction_category = 'WITHDRAWAL'
 AND NEW.transaction_status = 'COMPLETED'
BEGIN
    SELECT CASE
        WHEN NEW.amount >
             (SELECT current_balance FROM savings_accounts
              WHERE savings_account_id = NEW.savings_account_id)
        THEN RAISE(ABORT, 'Insufficient savings balance.')
    END;
END;

CREATE TABLE IF NOT EXISTS company_earnings (
    company_earning_id INTEGER PRIMARY KEY AUTOINCREMENT,
    earning_year     INTEGER NOT NULL UNIQUE,
    total_annual_income NUMERIC NOT NULL CHECK (total_annual_income >= 0),
    money_back_rate  NUMERIC NOT NULL DEFAULT 0.02
        CHECK (money_back_rate >= 0 AND money_back_rate <= 1),
    recorded_by      INTEGER,
    recorded_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (recorded_by) REFERENCES admins(admin_id)
);

CREATE TABLE IF NOT EXISTS money_back_allocations (
    allocation_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    company_earning_id INTEGER NOT NULL,
    user_id         INTEGER NOT NULL,
    premium_member_count INTEGER NOT NULL CHECK (premium_member_count > 0),
    allocation_amount NUMERIC NOT NULL CHECK (allocation_amount >= 0),
    allocation_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    allocation_status TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (allocation_status IN ('PENDING', 'COMPLETED', 'FAILED')),
    savings_transaction_id INTEGER UNIQUE,
    FOREIGN KEY (company_earning_id) REFERENCES company_earnings(company_earning_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (savings_transaction_id) REFERENCES savings_transactions(savings_transaction_id),
    UNIQUE (company_earning_id, user_id)
);

CREATE TABLE IF NOT EXISTS admin_activity_logs (
    activity_log_id INTEGER PRIMARY KEY AUTOINCREMENT,
    admin_id        INTEGER NOT NULL,
    action_type     TEXT NOT NULL,
    target_table    TEXT,
    target_record_id INTEGER,
    activity_details TEXT,
    activity_date   TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (admin_id) REFERENCES admins(admin_id)
);

CREATE TABLE IF NOT EXISTS notifications (
    notification_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         INTEGER NOT NULL,
    notification_type TEXT NOT NULL,
    message         TEXT NOT NULL,
    is_read         INTEGER NOT NULL DEFAULT 0 CHECK (is_read IN (0, 1)),
    created_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE INDEX IF NOT EXISTS idx_registration_status
    ON registration_applications(application_status);
CREATE INDEX IF NOT EXISTS idx_loan_user
    ON loan_applications(user_id);
CREATE INDEX IF NOT EXISTS idx_loan_status
    ON loan_applications(application_status);
CREATE INDEX IF NOT EXISTS idx_billing_due_date
    ON billing_statements(due_date);
CREATE INDEX IF NOT EXISTS idx_savings_account_date
    ON savings_transactions(savings_account_id, transaction_date);
CREATE INDEX IF NOT EXISTS idx_withdrawal_status
    ON withdrawal_requests(request_status);

INSERT OR IGNORE INTO admins
(admin_id, username, password_hash, full_name, email)
VALUES
(1, 'admin001', 'REPLACE_WITH_PASSWORD_HASH', 'System Administrator', 'admin@example.com');

INSERT OR IGNORE INTO registration_applications
(registration_application_id, requested_account_type, full_name, address, gender,
 birth_date, email, contact_number, tin_number, application_status, reviewed_at)
VALUES
(1, 'PREMIUM', 'Juan Dela Cruz', 'Minglanilla, Cebu', 'Male',
 '2000-01-15', 'juan@example.com', '09171234567', '123-456-789-000', 'APPROVED', CURRENT_TIMESTAMP),
(2, 'BASIC', 'Maria Santos', 'Cebu City, Cebu', 'Female',
 '1999-05-20', 'maria@example.com', '09181234567', '234-567-890-000', 'APPROVED', CURRENT_TIMESTAMP);

INSERT OR IGNORE INTO employment_details
(registration_application_id, company_name, company_address, company_phone,
 hr_contact_number, position, monthly_earnings)
VALUES
(1, 'ABC Company', 'Cebu City, Cebu', '0321234567', '09190000001', 'Staff', 25000),
(2, 'XYZ Corporation', 'Mandaue City, Cebu', '0327654321', '09190000002', 'Clerk', 20000);

INSERT OR IGNORE INTO bank_details
(registration_application_id, bank_name, bank_account_number, card_holder_name)
VALUES
(1, 'Sample Bank', '000123456789', 'JUAN DELA CRUZ'),
(2, 'Sample Bank', '000987654321', 'MARIA SANTOS');

INSERT OR IGNORE INTO registration_documents
(registration_application_id, document_type, file_reference, verification_status, verified_by, verified_at)
VALUES
(1, 'PROOF_OF_BILLING', 'sample/juan_billing.pdf', 'VERIFIED', 1, CURRENT_TIMESTAMP),
(1, 'PRIMARY_VALID_ID', 'sample/juan_id.pdf', 'VERIFIED', 1, CURRENT_TIMESTAMP),
(1, 'CERTIFICATE_OF_EMPLOYMENT', 'sample/juan_coe.pdf', 'VERIFIED', 1, CURRENT_TIMESTAMP),
(2, 'PROOF_OF_BILLING', 'sample/maria_billing.pdf', 'VERIFIED', 1, CURRENT_TIMESTAMP),
(2, 'PRIMARY_VALID_ID', 'sample/maria_id.pdf', 'VERIFIED', 1, CURRENT_TIMESTAMP),
(2, 'CERTIFICATE_OF_EMPLOYMENT', 'sample/maria_coe.pdf', 'VERIFIED', 1, CURRENT_TIMESTAMP);

INSERT OR IGNORE INTO registration_reviews
(registration_application_id, admin_id, decision, remarks)
VALUES
(1, 1, 'APPROVED', 'Documents verified.'),
(2, 1, 'APPROVED', 'Documents verified.');

INSERT OR IGNORE INTO users
(user_id, registration_application_id, username, password_hash, account_type, current_loan_limit)
VALUES
(1, 1, 'juan001', 'REPLACE_WITH_PASSWORD_HASH', 'PREMIUM', 10000),
(2, 2, 'maria001', 'REPLACE_WITH_PASSWORD_HASH', 'BASIC', 10000);

INSERT OR IGNORE INTO loan_applications
(loan_application_id, user_id, requested_amount, requested_months, application_status, reviewed_at, reviewed_by)
VALUES
(1, 1, 10000, 3, 'APPROVED', CURRENT_TIMESTAMP, 1);

INSERT OR IGNORE INTO loans
(loan_id, loan_application_id, user_id, approved_amount, interest_rate, interest_amount,
 net_amount_released, repayment_months, release_date, loan_status)
VALUES
(1, 1, 1, 10000, 0.03, 300, 9700, 3, date('now'), 'ACTIVE');

INSERT OR IGNORE INTO loan_transactions
(transaction_code, loan_id, transaction_type, amount, transaction_status, admin_id)
VALUES
('LTX-2026-0001', 1, 'LOAN_RELEASE', 10000, 'APPROVED', 1);

INSERT OR IGNORE INTO payment_schedules
(loan_id, installment_number, due_date, principal_due, interest_due)
VALUES
(1, 1, date('now', '+28 days'), 3333.33, 0),
(1, 2, date('now', '+56 days'), 3333.33, 0),
(1, 3, date('now', '+84 days'), 3333.34, 0);

INSERT OR IGNORE INTO billing_statements
(loan_id, billing_year, billing_month, principal_due, interest_amount,
 penalty_amount, total_due, due_date)
VALUES
(1, CAST(strftime('%Y', 'now') AS INTEGER),
     CAST(strftime('%m', 'now') AS INTEGER),
     3333.33, 0, 0, 3333.33, date('now', '+28 days'));

INSERT OR IGNORE INTO savings_accounts
(user_id, current_balance)
VALUES
(1, 500);

INSERT OR IGNORE INTO savings_transactions
(transaction_code, savings_account_id, transaction_category, amount,
 transaction_status, description)
VALUES
('STX-2026-0001', 1, 'DEPOSIT', 500, 'COMPLETED', 'Initial sample deposit');

INSERT OR IGNORE INTO withdrawal_requests
(withdrawal_request_id, user_id, savings_account_id, requested_amount, request_status)
VALUES
(1, 1, 1, 500, 'PENDING');

INSERT OR IGNORE INTO company_earnings
(company_earning_id, earning_year, total_annual_income, money_back_rate, recorded_by)
VALUES
(1, 2026, 1000000, 0.02, 1);

INSERT OR IGNORE INTO money_back_allocations
(company_earning_id, user_id, premium_member_count, allocation_amount, allocation_status)
VALUES
(1, 1, 1, 20000, 'PENDING');

INSERT OR IGNORE INTO admin_activity_logs
(admin_id, action_type, target_table, target_record_id, activity_details)
VALUES
(1, 'APPROVE_REGISTRATION', 'registration_applications', 1, 'Approved sample registration.');

INSERT OR IGNORE INTO notifications
(user_id, notification_type, message)
VALUES
(1, 'REGISTRATION_APPROVED', 'Your registration has been approved.');


