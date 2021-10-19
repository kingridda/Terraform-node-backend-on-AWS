CREATE DATABASE db_test;
USE db_test;

CREATE TABLE test_table(
    'id' int PRIMARY KEY NOT NULL AUTO_INCREMENT,
    'title' varchar
);


INSERT INTO test_table ('id', 'title') VALUES
(1, 'test title 1'),
(2, 'test title 2');