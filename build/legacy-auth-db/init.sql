CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64) NOT NULL,
    password_md5 CHAR(32) NOT NULL
);

INSERT INTO users (username, password_md5) VALUES
    ('test_user1', MD5('summer2018')),
    ('test_user2', MD5('qwerty123')),
    ('demo', MD5('demo1234'));
