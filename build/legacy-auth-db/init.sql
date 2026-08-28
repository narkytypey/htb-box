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
