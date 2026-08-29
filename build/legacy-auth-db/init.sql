-- Donerup Classic Till System -- legacy per-shop staff login.
-- Retired after the corporate LDAP rollout; kept online only for the
-- handful of legacy read-only shift reports noted in CHANGELOG.md.
-- Every row below is stale test data from before the migration.
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64) NOT NULL,
    password_md5 CHAR(32) NOT NULL
);

INSERT INTO users (username, password_md5) VALUES
    ('test_user1', MD5('pideci06')),
    ('test_user2', MD5('kokorec99')),
    ('demo', MD5('misir2020'));

-- Everything below is the read-only reporting remnant referenced in
-- CHANGELOG.md: shift and takings history the finance team still pulls
-- from occasionally. No authentication data -- that moved to the corporate
-- directory during the migration.
CREATE TABLE IF NOT EXISTS stores (
    code CHAR(7) PRIMARY KEY,
    city VARCHAR(40) NOT NULL,
    district VARCHAR(40) NOT NULL,
    region VARCHAR(10) NOT NULL,
    opened_on DATE NOT NULL
);

INSERT INTO stores (code, city, district, region, opened_on) VALUES
    ('DNR-001', 'Berlin', 'Mitte', 'DACH', '2011-04-18'),
    ('DNR-004', 'Hamburg', 'St Pauli', 'DACH', '2013-11-08'),
    ('DNR-014', 'Hamburg', 'Altona', 'DACH', '2017-12-01'),
    ('DNR-022', 'London', 'Dalston', 'UK&I', '2021-01-29'),
    ('DNR-027', 'London', 'Peckham', 'UK&I', '2024-03-15'),
    ('DNR-031', 'Rotterdam', 'Centrum', 'Benelux', '2023-12-08'),
    ('DNR-035', 'Amsterdam', 'Zuid', 'Benelux', '2025-02-14');

CREATE TABLE IF NOT EXISTS menu_items (
    sku VARCHAR(12) PRIMARY KEY,
    name VARCHAR(40) NOT NULL,
    category VARCHAR(20) NOT NULL,
    unit_price_cents INT NOT NULL
);

INSERT INTO menu_items (sku, name, category, unit_price_cents) VALUES
    ('DNR-WRAP-01', 'Doner Wrap', 'main', 850),
    ('DNR-PLAT-01', 'Doner Plate', 'main', 1250),
    ('DNR-PIDE-01', 'Pide', 'main', 990),
    ('DNR-LAHM-01', 'Lahmacun', 'main', 720),
    ('DNR-KOKO-01', 'Kokorec', 'main', 1150),
    ('DNR-SIDE-01', 'Fries', 'side', 390),
    ('DNR-SIDE-02', 'Mercimek Soup', 'side', 450),
    ('DNR-DRNK-01', 'Ayran', 'drink', 260),
    ('DNR-DRNK-02', 'Salgam', 'drink', 280),
    ('DNR-DSRT-01', 'Kunefe', 'dessert', 640);

CREATE TABLE IF NOT EXISTS shifts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    store_code CHAR(7) NOT NULL,
    shift_date DATE NOT NULL,
    shift_type VARCHAR(10) NOT NULL,
    staff_count TINYINT NOT NULL
);

INSERT INTO shifts (store_code, shift_date, shift_type, staff_count) VALUES
    ('DNR-001', '2026-05-11', 'day', 5),
    ('DNR-001', '2026-05-11', 'evening', 7),
    ('DNR-014', '2026-05-11', 'day', 4),
    ('DNR-014', '2026-05-11', 'evening', 6),
    ('DNR-022', '2026-05-12', 'day', 4),
    ('DNR-022', '2026-05-12', 'evening', 8),
    ('DNR-027', '2026-05-12', 'evening', 6),
    ('DNR-031', '2026-05-13', 'day', 3),
    ('DNR-035', '2026-05-13', 'evening', 5);

CREATE TABLE IF NOT EXISTS shift_reports (
    id INT AUTO_INCREMENT PRIMARY KEY,
    shift_id INT NOT NULL,
    covers SMALLINT NOT NULL,
    gross_cents INT NOT NULL,
    waste_pct DECIMAL(4,2) NOT NULL,
    note VARCHAR(120)
);

INSERT INTO shift_reports (shift_id, covers, gross_cents, waste_pct, note) VALUES
    (1, 118, 104300, 2.10, 'Quiet lunch, delivery platform outage 12:40-13:20'),
    (2, 241, 238900, 3.40, NULL),
    (3, 96, 81200, 1.80, NULL),
    (4, 187, 176400, 4.10, 'Grill 2 down from 19:00, single line service'),
    (5, 103, 99500, 2.60, NULL),
    (6, 262, 271800, 3.90, 'Match night, extended close'),
    (7, 174, 168300, 2.20, NULL),
    (8, 71, 64100, 1.40, 'Reduced hours, staff training afternoon'),
    (9, 149, 143600, 3.10, NULL);
