-- Example: Snowflake Alerts Demo
-- Description: MST example query from snowflake_alerts_demo.sql

-- 1. Set up Context
use role sysadmin;
use schema superset.public;
use warehouse s_wh;

-- 2. Get biggest discount
select
    max(l_discount)
from
    vw_sales_revenue;

-- Query to get two different Order keys
select distinct
    o_orderkey
from
    vw_sales_revenue
order by o_orderkey asc
limit 2;

-- 3. Update the Data to trigger the alert
-- !!! Execute this step after an alert is created !!!
update LINEITEM l
set l.L_DISCOUNT = 0.8
from ORDERS o 
join CUSTOMER r on o.o_custkey = r.c_custkey
where true
    and l.l_orderkey = o.o_orderkey
    and o.o_orderkey in (
        select distinct
            o_orderkey
        from
            vw_sales_revenue
        order by o_orderkey asc
        limit 2
    );

-- Validate the result
select
    max(l_discount)
from
    vw_sales_revenue;