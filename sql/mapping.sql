/*---------------------------------------------------------------------------------------------------------------------
 *
 * mapping.sql
 * 		Foreign-data wrapper for remote Hadoop servers
 *              To verify the CREATE SCHEMA, CREATE USER MAPPING and CREATE SERVER Functionality.
 *
 * Portions Copyright (c) 2012-2014, PostgreSQL Global Development Group
 *
 * Portions Copyright (c) 2004-2014, EnterpriseDB Corporation.
 *
 * IDENTIFICATION
 * 		mapping.sql
 *
 *---------------------------------------------------------------------------------------------------------------------
 */

-- Connection Settings.

\set HIVE_SERVER                '\'hive.server\''
\set HIVE_CLIENT_TYPE           '\'hiveserver2\''
\set HIVE_PORT                  '\'10000\''

CREATE DATABASE fdw_regression;
\c fdw_regression postgres

--create a non superuser
CREATE ROLE low_priv_user LOGIN;

--create a schema
CREATE SCHEMA test_ext_schema;

--- CREATE/ALTER/DROP EXTENSION ---

--Check the installed extensions in system and it should not list hdfs_fdw.
\dx+ hdfs_fdw

--switch to low privileged user
\c fdw_regression low_priv_user

--Try to create the hdfs_fdw extension with an unprivileged user. Should error out.
CREATE EXTENSION hdfs_fdw;

--switch back to superuser
\c fdw_regression postgres

-- Create the extension hdfs_fdw using the minimal syntax and it should create successfully. 
CREATE EXTENSION hdfs_fdw;

--Check the installed extensions in system and it should list hdfs_fdw and its properties.
\dx hdfs_fdw

--ReCreate the extension (while it already exists) and it should error out.
CREATE EXTENSION hdfs_fdw;

-- Create extension with IF NOT EXISTS syntax. It should show a notice message indicating 
-- the pre-existence of extension.
CREATE EXTENSION IF NOT EXISTS hdfs_fdw;

--switch to non superuser to ensure extension cannot be dropped
\c fdw_regression low_priv_user
DROP EXTENSION hdfs_fdw;

--switch back to postgres superuser
\c fdw_regression postgres

-- DROP EXTENSION with IF EXISTS clause
DROP EXTENSION IF EXISTS hdfs_fdw;

-- Attempt DROP EXTENSION with IF EXISTS clause when extension doesn't pre-exist
-- Ensure a NOTICE is raise
DROP EXTENSION IF EXISTS hdfs_fdw;

-- create extension WITH SCHEMA and IF NOT EXISTS and VERSION option to ensure extension 
-- objects are created in the schema
CREATE EXTENSION IF NOT EXISTS hdfs_fdw WITH SCHEMA test_ext_schema VERSION '1.0';

\dx hdfs_fdw
------------------------------------
----------ALTER EXTENSION ----------
-----------------------------------

-- UPDATE .. Since there is no update path available, it will display NOTICE
ALTER EXTENSION hdfs_fdw UPDATE;
\dx hdfs_fdw

-- Change schema
ALTER EXTENSION hdfs_fdw SET SCHEMA public;
\dx hdfs_fdw

-- Create a view to add as member to extension
CREATE VIEW ext_v1 AS SELECT * FROM DUAL;
ALTER EXTENSION hdfs_fdw ADD VIEW ext_v1; 
--should list the view in the members list
\dx+ hdfs_fdw

--remove the view member
ALTER EXTENSION hdfs_fdw DROP VIEW ext_v1;
\dx+ hdfs_fdw

------------------------------------
----------CREATE SERVER ----------
-----------------------------------


--Create a server without providing optional parameters using the hdfs_fdw wrapper.
-- host defaults to localhost, port to 10000, client_type to hiverserver2 (RM 37660)
-- 
CREATE SERVER hdfs_srv1 FOREIGN DATA WRAPPER hdfs_fdw OPTIONS (client_type :HIVE_CLIENT_TYPE);
\des+ hdfs_srv1

--test server
CREATE USER MAPPING FOR postgres SERVER hdfs_srv1;
\deu+
CREATE FOREIGN TABLE dept (
deptno INTEGER,
dname VARCHAR2(14),
loc VARCHAR2(13)
)
SERVER hdfs_srv1 OPTIONS (dbname 'fdw_db', table_name 'dept');
--should work successfully indicating host defaulted to localhost, port to 10000
SELECT * FROM dept;

--test ALTER SERVER OWNER TO, and RENAME to clauses
ALTER SERVER hdfs_srv1 RENAME TO hdfs_srv1_renamed;
\des+ hdfs_srv1
ALTER SERVER hdfs_srv1_renamed OWNER to low_priv_user;
\des+ hdfs_srv1_renamed

DROP FOREIGN TABLE dept;
DROP USER MAPPING FOR postgres SERVER hdfs_srv1_renamed;
--end test server


--Create a server providing TYPE and VERSION clauses. 
--Also check host parameter can take IP address and host a numeric port
--Also the named parameters to have mixed cased names e.g. host, PORT, Client_Type
CREATE SERVER hdfs_srv2 TYPE 'abc' VERSION '1.0' 
FOREIGN DATA WRAPPER hdfs_fdw 
OPTIONS (host '127.0.0.1', PORT:HIVE_PORT,Client_Type :HIVE_CLIENT_TYPE);
--verify that the supplied clauses TYPE, VERSION and host,port,client_type are
-- as specified
\des+ hdfs_srv2
--test server
CREATE USER MAPPING FOR postgres SERVER hdfs_srv2;
CREATE FOREIGN TABLE dept (
deptno INTEGER,
dname VARCHAR2(14),
loc VARCHAR2(13)
)
SERVER hdfs_srv2 OPTIONS (dbname 'fdw_db', table_name 'dept');
SELECT * FROM dept;
DROP FOREIGN TABLE dept;
DROP USER MAPPING FOR postgres SERVER hdfs_srv2;
--end test server

--Create a server providing valid OPTIONS (HOST,PORT,CLIENT_TYPE,connect_timeout,query_timeout)

CREATE SERVER hdfs_srv3a FOREIGN DATA WRAPPER hdfs_fdw 
 OPTIONS (host :HIVE_SERVER, port :HIVE_PORT, client_type :HIVE_CLIENT_TYPE, connect_timeout '4000',query_timeout '4000');
\des+ hdfs_srv3a

--test server
CREATE USER MAPPING FOR postgres SERVER hdfs_srv3a;
CREATE FOREIGN TABLE dept (
deptno INTEGER,
dname VARCHAR2(14),
loc VARCHAR2(13)
)
SERVER hdfs_srv3a OPTIONS (dbname 'fdw_db', table_name 'dept');
SELECT * FROM dept; 

--test port
--negative, raise error
ALTER SERVER hdfs_srv3a OPTIONS (SET port '-1');
\des+ hdfs_srv3a
SELECT * FROM dept;
--zero, raise error
ALTER SERVER hdfs_srv3a OPTIONS (SET port '0');
SELECT * FROM dept;
-- very large number, raise error
ALTER SERVER hdfs_srv3a OPTIONS (SET port '12345678');
SELECT * FROM dept;
-- empty string, raise error (RM37655)
ALTER SERVER hdfs_srv3a OPTIONS (SET port '');
SELECT * FROM dept;
-- non numeric, raise error (RM37655)
ALTER SERVER hdfs_srv3a OPTIONS (SET port 'abc');
SELECT * FROM dept;
-- drop port to see it goes back to default 10000, should succeed
ALTER SERVER hdfs_srv3a OPTIONS (DROP port );
SELECT * FROM dept;


--test host
--valid IP address, should succeed
ALTER SERVER hdfs_srv3a OPTIONS (SET host '127.0.0.1');
\des+ hdfs_srv3a
SELECT * FROM dept;

--invalid IP address, should fail (RM37672)
ALTER SERVER hdfs_srv3a OPTIONS (SET host '127.0.0.2');
SELECT * FROM dept;

--invalid domain, should fail
ALTER SERVER hdfs_srv3a OPTIONS (SET host 'invalid.domain');
SELECT * FROM dept;

--empty string, should fail
ALTER SERVER hdfs_srv3a OPTIONS (SET host '');
SELECT * FROM dept;

--drop host to see it defaults to localhost
ALTER SERVER hdfs_srv3a OPTIONS (DROP host);
SELECT * FROM dept;

--test cient_type
--check case insensitivity, should pass (but fails RM 37640)
ALTER SERVER hdfs_srv3a OPTIONS (SET client_type 'HIVEserver2');
\des+ hdfs_srv3a
SELECT * FROM dept;

--set to hiveserver1, should error when querying 
--since the target is hiveserver2
ALTER SERVER hdfs_srv3a OPTIONS (SET client_type 'hiverserver1');
SELECT * FROM dept;

--set to invalid value, should error when querying 
ALTER SERVER hdfs_srv3a OPTIONS (SET client_type 'invalidserver');
SELECT * FROM dept;

--set to invalid value, should error when querying 
ALTER SERVER hdfs_srv3a OPTIONS (SET client_type 'invalidserver');
SELECT * FROM dept;

--drop client_type and then add back again, success
ALTER SERVER hdfs_srv3a OPTIONS (DROP client_type);
ALTER SERVER hdfs_srv3a OPTIONS (ADD client_type 'hiveserver2');
SELECT * FROM dept;


--test connect_timeout and query_timeout

-- set connect_timeout and query_timeout to 0, should disable timeout
--and bring results from foreign server (and not mean 0ms to fail every query)
ALTER SERVER hdfs_srv3a OPTIONS (SET connect_timeout '0', SET query_timeout '0');
\des+ hdfs_srv3a
SELECT * FROM dept;

-- set to 10ms each and see they should timeout
ALTER SERVER hdfs_srv3a OPTIONS (SET connect_timeout '10', SET query_timeout '10');
SELECT * FROM dept;

--success
ALTER SERVER hdfs_srv3a OPTIONS (SET connect_timeout '-1', SET query_timeout '-1');
SELECT * FROM dept;

--success
ALTER SERVER hdfs_srv3a OPTIONS (SET connect_timeout '2000', SET query_timeout '-1');
SELECT * FROM dept;

ALTER SERVER hdfs_srv3a OPTIONS (SET connect_timeout '-1', SET query_timeout '4000');
SELECT * FROM dept;


--test DROP SERVER
--should fail, RESTRICT enforced
DROP SERVER hdfs_srv3a;

--should fail, RESTRICT enforced
DROP SERVER hdfs_srv3a RESTRICT;

--CASCADE, should pass and drop FOREIGN TABLE and USER MAPPING
DROP SERVER hdfs_srv3a CASCADE;
\d dept
\deu+

--end test server


DROP SERVER IF EXISTS hdfs_srv1_renamed;
DROP SERVER hdfs_srv2;

-- DROP EXTENSION
DROP EXTENSION hdfs_fdw;
DROP SCHEMA test_ext_schema;
DROP ROLE low_priv_user;
DROP VIEW ext_v1;
\c postgres postgres
DROP DATABASE fdw_regression;